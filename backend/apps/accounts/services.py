"""Authentication services: registration, OTP, login, rotation, sessions."""

from __future__ import annotations

import hashlib
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.db.models import F
from django.utils import timezone

from apps.common.audit import AuditLog
from apps.common.exceptions import (
    ConflictError,
    DomainError,
    InvalidStateError,
    NotFoundError,
    PermissionDeniedError,
)
from apps.common.outbox import publish

from .models import (
    DeviceSession,
    LoginAttempt,
    RefreshToken,
    User,
    VerificationCode,
    generate_code,
    hash_code,
)
from .otp import OtpMessage, send_otp

logger = logging.getLogger("kolo.security")

# Lockout policy, expressed in one place so it can be reasoned about.
MAX_FAILURES_15MIN = 5
MAX_FAILURES_DAY = 25
LOCKOUT_15MIN = timedelta(minutes=15)
LOCKOUT_DAY = timedelta(hours=1)


def hash_token(token: str) -> str:
    return hashlib.sha256(f"{token}:{settings.SECRET_KEY}".encode()).hexdigest()


# ---------------------------------------------------------------------------
# Registration & verification
# ---------------------------------------------------------------------------

def register(*, email: str | None = None, phone: str | None = None, password: str, full_name: str = "",
             country: str = "", preferred_currency: str = "NGN", timezone_name: str = "UTC", request=None) -> User:
    """Create an account and send the first verification code.

    Registration never reveals whether an identifier is already in use in the
    response body for the *existing* case — it raises a conflict, which is
    unavoidable for a good sign-up UX, but the code path is audited so support
    can see probing.
    """
    email = (email or "").strip().lower() or None
    phone = (phone or "").strip() or None
    if not email and not phone:
        raise DomainError("Provide an email address or a phone number", code="identifier_required")

    if email and User.objects.filter(email=email).exists():
        raise ConflictError("An account already uses this email address", code="email_taken")
    if phone and User.objects.filter(phone=phone).exists():
        raise ConflictError("An account already uses this phone number", code="phone_taken")

    with transaction.atomic():
        user = User.objects.create_user(
            email=email,
            phone=phone,
            password=password,
            full_name=full_name.strip(),
            country=(country or "").upper()[:2],
            preferred_currency=(preferred_currency or "NGN").upper(),
            timezone=timezone_name or "UTC",
        )
        AuditLog.record(action="account.registered", actor=user, target_type="user", target_id=user.pk,
                        summary="Account created", request=request)
        if email:
            issue_verification(user=user, channel="email", purpose=VerificationCode.Purpose.SIGNUP, request=request)
        if phone:
            issue_verification(user=user, channel="phone", purpose=VerificationCode.Purpose.SIGNUP, request=request)
    return user


def issue_verification(*, user: User, channel: str, purpose: str, request=None) -> VerificationCode:
    """Create and send one code. Resends are rate-limited, not free."""
    destination = user.email if channel == "email" else user.phone
    if not destination:
        raise InvalidStateError("No address on file for that channel")

    cooldown = settings.KOLO["OTP_RESEND_COOLDOWN_SECONDS"]
    latest = VerificationCode.objects.filter(user=user, channel=channel, purpose=purpose).first()
    if latest and (timezone.now() - latest.created_at).total_seconds() < cooldown:
        raise DomainError(
            "A code was just sent. Wait before requesting another.",
            code="otp_cooldown",
            details={"retry_after_seconds": int(cooldown - (timezone.now() - latest.created_at).total_seconds())},
        )

    code = generate_code()
    record = VerificationCode.objects.create(
        user=user,
        channel=channel,
        destination=destination,
        purpose=purpose,
        code_hash=hash_code(code),
        attempts_left=settings.KOLO["OTP_MAX_ATTEMPTS"],
        expires_at=timezone.now() + timedelta(seconds=settings.KOLO["OTP_TTL_SECONDS"]),
    )
    # Invalidate older outstanding codes for the same purpose: two valid codes
    # at once doubles an attacker's odds for no product benefit.
    VerificationCode.objects.filter(
        user=user, channel=channel, purpose=purpose, consumed_at__isnull=True
    ).exclude(pk=record.pk).update(consumed_at=timezone.now())

    send_otp(OtpMessage(destination=destination, channel=channel, code=code, purpose=purpose))
    AuditLog.record(action="otp.issued", actor=user, target_type="verification", target_id=record.pk,
                    summary=f"{purpose} code sent via {channel}", request=request)
    return record


def verify_code(*, user: User, code: str, purpose: str) -> VerificationCode:
    """Consume a code or refuse. Attempts decrement on every wrong guess.

    Two things must both hold, and they pull in opposite directions:

    * the row is locked while it is read and judged, so two simultaneous
      submissions of the same code cannot both consume it (PostgreSQL refuses
      `FOR UPDATE` in autocommit, which is why the lock lives in its own
      transaction);
    * the attempt counter and the consumed marker survive a refusal — and an
      exception raised inside `transaction.atomic()` rolls that block back.

    So the lock, the penalty and the consumption are each committed in their own
    short transaction, and the refusal is raised afterwards, outside all of them.
    Nesting a second `atomic()` inside an outer one would not have helped: it is
    only a savepoint, and the outer rollback would still have taken the write
    with it.

    Before this was split up, a wrong code left `attempts_left` at 5 forever:
    an attacker could try a six-digit code without limit.
    """
    with transaction.atomic():
        record = (
            VerificationCode.objects.select_for_update()
            .filter(user=user, purpose=purpose, consumed_at__isnull=True)
            .order_by("-created_at")
            .first()
        )
        if not record:
            raise DomainError("No code is pending for this action. Request a new one.", code="otp_missing")
        if record.is_expired:
            raise DomainError("That code has expired. Request a new one.", code="otp_expired")
        if record.attempts_left <= 0:
            raise DomainError("Too many incorrect attempts. Request a new code.", code="otp_locked")
        matches = secrets.compare_digest(record.code_hash, hash_code(code.strip()))
        attempts_left = record.attempts_left
        record_pk = record.pk

    if not matches:
        # Committed in its own transaction so the penalty outlives the refusal.
        with transaction.atomic():
            VerificationCode.objects.filter(pk=record_pk).update(attempts_left=F("attempts_left") - 1)
            fresh = VerificationCode.objects.only("attempts_left").get(pk=record_pk)
            AuditLog.record(
                action="otp.failed", actor=user, severity=AuditLog.Severity.WARNING,
                target_type="verification", target_id=record_pk,
                summary=f"Incorrect code, {fresh.attempts_left} attempts left",
            )
        raise DomainError(
            "That code is not correct.",
            code="otp_invalid",
            details={"attempts_left": fresh.attempts_left},
        )

    with transaction.atomic():
        # Conditional update: if another request consumed the same code in the
        # meantime, nothing is written and the caller is told the code is gone.
        consumed = VerificationCode.objects.filter(pk=record_pk, consumed_at__isnull=True).update(
            consumed_at=timezone.now()
        )
        if not consumed:
            raise DomainError("No code is pending for this action. Request a new one.", code="otp_missing")
        record = VerificationCode.objects.get(pk=record_pk)

        if record.channel == "email":
            user.is_email_verified = True
        else:
            user.is_phone_verified = True
        if (user.is_email_verified or user.is_phone_verified) and user.verification_level == "unverified":
            user.verification_level = "contact"
        user.save(update_fields=["is_email_verified", "is_phone_verified", "verification_level", "updated_at"])
        publish("account.verified", {"user_id": str(user.pk), "channel": record.channel})
    return record


# ---------------------------------------------------------------------------
# Login, lockout, tokens
# ---------------------------------------------------------------------------

def assert_not_locked(identifier: str) -> None:
    ident = identifier.strip().lower()
    burst = LoginAttempt.recent_failures(ident, LOCKOUT_15MIN)
    if burst >= MAX_FAILURES_15MIN:
        raise PermissionDeniedError(
            "Too many failed attempts. Try again in a few minutes.",
            code="account_temporarily_locked",
            details={"retry_after_seconds": int(LOCKOUT_15MIN.total_seconds())},
        )
    daily = LoginAttempt.recent_failures(ident, timedelta(days=1))
    if daily >= MAX_FAILURES_DAY:
        raise PermissionDeniedError(
            "This account is locked for an hour after repeated failed sign-ins.",
            code="account_locked",
            details={"retry_after_seconds": int(LOCKOUT_DAY.total_seconds())},
        )


def record_attempt(identifier: str, *, succeeded: bool, ip: str | None = None) -> None:
    LoginAttempt.objects.create(identifier=identifier.strip().lower(), ip_address=ip, succeeded=succeeded)


def register_device(*, user: User, device_name: str = "", platform: str = "", app_version: str = "",
                    push_token: str = "", ip: str | None = None, user_agent: str = "") -> DeviceSession:
    return DeviceSession.objects.create(
        user=user,
        device_name=device_name[:120],
        platform=platform[:20],
        app_version=app_version[:20],
        push_token=push_token[:255],
        ip_address=ip,
        user_agent=user_agent[:255],
    )


def issue_refresh_token(*, user: User, device: DeviceSession | None, family=None, parent=None) -> tuple[str, RefreshToken]:
    """Mint a refresh token; the raw value is shown once and never stored."""
    raw = secrets.token_urlsafe(48)
    record = RefreshToken.objects.create(
        user=user,
        token_hash=hash_token(raw),
        family=family or secrets.token_hex(16),
        parent=parent,
        device=device,
        expires_at=timezone.now() + timedelta(days=settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"].days),
    )
    return raw, record


def rotate_refresh_token(*, raw_token: str) -> tuple[User, str, RefreshToken]:
    """Exchange a refresh token for a new one, revoking the old.

    Reuse of an already-rotated token means someone else has a copy: the entire
    family is revoked and the member must sign in again.

    The refusal paths commit before they raise. A revoked-family write made
    inside a block that then rolls back leaves the stolen session alive, which
    defeats the whole point of reuse detection — so the revocation happens in
    its own transaction and the caller is refused afterwards.
    """
    digest = hash_token(raw_token)
    with transaction.atomic():
        record = RefreshToken.objects.select_for_update().filter(token_hash=digest).first()
        if not record:
            raise PermissionDeniedError("This session is no longer valid. Sign in again.", code="refresh_invalid")

        if record.revoked_at:
            reuse_of_family = record.family
            record_pk = record.pk
        else:
            reuse_of_family = None
            if record.expires_at <= timezone.now():
                raise PermissionDeniedError("Your session expired. Sign in again.", code="refresh_expired")
            user = record.user
            if not user.is_active:
                raise PermissionDeniedError("This account is not active.", code="account_inactive")

            record.revoked_at = timezone.now()
            record.rotated_at = timezone.now()
            record.save(update_fields=["revoked_at", "rotated_at"])
            raw, new_record = issue_refresh_token(
                user=user, device=record.device, family=record.family, parent=record
            )
            if record.device:
                DeviceSession.objects.filter(pk=record.device.pk).update(last_seen_at=timezone.now())
            return user, raw, new_record

    # Reuse detected: kill the family in its own committed transaction, then refuse.
    with transaction.atomic():
        revoked = RefreshToken.objects.filter(family=reuse_of_family, revoked_at__isnull=True).update(
            revoked_at=timezone.now()
        )
        AuditLog.record(
            action="auth.refresh_reuse", severity=AuditLog.Severity.CRITICAL,
            target_type="refresh_token", target_id=record_pk,
            summary=f"Rotated refresh token replayed; {revoked} token(s) in the family revoked",
        )
    raise PermissionDeniedError("This session is no longer valid. Sign in again.", code="refresh_revoked")


def revoke_all_sessions(user: User, *, reason: str = "") -> int:
    count = RefreshToken.objects.filter(user=user, revoked_at__isnull=True).update(revoked_at=timezone.now())
    DeviceSession.objects.filter(user=user, revoked_at__isnull=True).update(revoked_at=timezone.now())
    AuditLog.record(action="auth.all_sessions_revoked", actor=user, severity=AuditLog.Severity.NOTICE,
                    target_type="user", target_id=user.pk, summary=reason or "All sessions revoked")
    return count


def change_password(*, user: User, current_password: str, new_password: str, request=None) -> None:
    if not user.check_password(current_password):
        record_attempt(user.email or user.phone, succeeded=False)
        raise PermissionDeniedError("Your current password is not correct.", code="password_incorrect")
    user.set_password(new_password)
    user.save(update_fields=["password", "updated_at"])
    revoke_all_sessions(user, reason="Password changed")
    AuditLog.record(action="account.password_changed", actor=user, severity=AuditLog.Severity.NOTICE,
                    target_type="user", target_id=user.pk, summary="Password changed", request=request)
    publish("account.password_changed", {"user_id": str(user.pk)})


def request_password_reset(identifier: str, *, request=None) -> None:
    """Always succeeds, whether or not the identifier exists.

    A different response for a known account turns this endpoint into an
    account-enumeration oracle.
    """
    user = User.objects.filter(email=identifier.strip().lower()).first() or User.objects.filter(
        phone=identifier.strip()
    ).first()
    if not user or not user.is_active:
        return
    channel = "email" if user.email else "phone"
    issue_verification(user=user, channel=channel, purpose=VerificationCode.Purpose.RESET, request=request)


def reset_password(*, identifier: str, code: str, new_password: str, request=None) -> User:
    user = User.objects.filter(email=identifier.strip().lower()).first() or User.objects.filter(
        phone=identifier.strip()
    ).first()
    if not user:
        raise NotFoundError("That reset request is not valid.", code="reset_invalid")
    verify_code(user=user, code=code, purpose=VerificationCode.Purpose.RESET)
    user.set_password(new_password)
    user.save(update_fields=["password", "updated_at"])
    revoke_all_sessions(user, reason="Password reset")
    AuditLog.record(action="account.password_reset", actor=user, severity=AuditLog.Severity.NOTICE,
                    target_type="user", target_id=user.pk, summary="Password reset completed", request=request)
    return user
