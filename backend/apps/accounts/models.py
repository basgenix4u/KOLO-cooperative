"""Identity: one human, one account, many groups."""

from __future__ import annotations

import secrets
from datetime import timedelta

from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin
from django.core.validators import RegexValidator
from django.db import models
from django.utils import timezone

from apps.common.models import AuditModel, UUIDModel

from .managers import UserManager

E164 = RegexValidator(r"^\+[1-9]\d{7,14}$", "Enter a phone number in international format, e.g. +2348012345678")


class User(AbstractBaseUser, PermissionsMixin, UUIDModel):
    """A KOLO member or operator.

    Phone and email are both optional at creation but at least one verified
    identifier is required before an account can hold money — enforced in the
    verification flow, not only in the UI.
    """

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        SUSPENDED = "suspended", "Suspended"
        DEACTIVATED = "deactivated", "Deactivated"

    email = models.EmailField(unique=True, null=True, blank=True)
    phone = models.CharField(max_length=20, unique=True, null=True, blank=True, validators=[E164])

    full_name = models.CharField(max_length=150, blank=True)
    avatar_url = models.URLField(blank=True)

    country = models.CharField(max_length=2, blank=True, help_text="ISO 3166-1 alpha-2")
    preferred_currency = models.CharField(max_length=3, default="NGN")
    timezone = models.CharField(max_length=64, default="UTC")
    locale = models.CharField(max_length=10, default="en")

    is_email_verified = models.BooleanField(default=False)
    is_phone_verified = models.BooleanField(default=False)
    # Progressive verification: only ask for what the feature actually needs.
    verification_level = models.CharField(max_length=20, default="unverified")
    identity_verified_at = models.DateTimeField(null=True, blank=True)

    status = models.CharField(max_length=20, choices=Status.choices, default=Status.ACTIVE, db_index=True)
    is_staff = models.BooleanField(default=False)
    is_superuser = models.BooleanField(default=False)
    # Operators can be required to use MFA; members may opt in.
    mfa_enabled = models.BooleanField(default=False)

    last_login_ip = models.GenericIPAddressField(null=True, blank=True)
    deactivated_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: list[str] = []

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.CheckConstraint(
                condition=~models.Q(email__isnull=True) | ~models.Q(phone__isnull=True),
                name="user_needs_email_or_phone",
            ),
            models.CheckConstraint(
                condition=models.Q(preferred_currency__regex=r"^[A-Z]{3}$"),
                name="user_currency_iso4217",
            ),
        ]
        indexes = [models.Index(fields=["status", "created_at"])]

    def __str__(self) -> str:
        return self.full_name or self.email or self.phone or str(self.pk)

    @property
    def is_active(self) -> bool:
        return self.status == self.Status.ACTIVE

    @property
    def display_name(self) -> str:
        if self.full_name:
            return self.full_name.split(" ")[0]
        if self.email:
            return self.email.split("@")[0]
        return "there"

    def mark_deactivated(self) -> None:
        """Deactivation is reversible by support, but sessions are not."""
        self.status = self.Status.DEACTIVATED
        self.deactivated_at = timezone.now()
        self.save(update_fields=["status", "deactivated_at", "updated_at"])
        RefreshToken.objects.filter(user=self, revoked_at__isnull=True).update(revoked_at=timezone.now())
        DeviceSession.objects.filter(user=self, revoked_at__isnull=True).update(revoked_at=timezone.now())


class VerificationCode(UUIDModel):
    """A one-time code for phone or email proof.

    Only a hash of the code is stored. Brute force is bounded by
    `attempts_left`, and a resend is rate-limited by `can_resend`.
    """

    class Purpose(models.TextChoices):
        SIGNUP = "signup", "Sign up"
        LOGIN = "login", "Log in"
        RESET = "reset", "Reset password"
        CHANGE = "change", "Change contact"
        MFA = "mfa", "Multi-factor"

    class Channel(models.TextChoices):
        PHONE = "phone", "Phone"
        EMAIL = "email", "Email"

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="verification_codes")
    channel = models.CharField(max_length=10, choices=Channel.choices)
    destination = models.CharField(max_length=254)
    purpose = models.CharField(max_length=12, choices=Purpose.choices)
    code_hash = models.CharField(max_length=128)
    attempts_left = models.PositiveSmallIntegerField(default=5)
    expires_at = models.DateTimeField(db_index=True)
    consumed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["user", "purpose", "consumed_at"])]

    @property
    def is_expired(self) -> bool:
        return timezone.now() >= self.expires_at

    @property
    def is_usable(self) -> bool:
        return self.consumed_at is None and not self.is_expired and self.attempts_left > 0


class RefreshToken(UUIDModel):
    """Refresh tokens are stored as hashes and rotated on every use.

    Reuse of a rotated token revokes the whole family — that is the signal of a
    stolen token, and pretending otherwise leaves an attacker with a session.
    """

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="refresh_tokens")
    token_hash = models.CharField(max_length=128, unique=True)
    family = models.UUIDField(db_index=True)
    parent = models.ForeignKey("self", null=True, blank=True, on_delete=models.SET_NULL)
    device = models.ForeignKey("DeviceSession", null=True, blank=True, on_delete=models.SET_NULL)
    expires_at = models.DateTimeField(db_index=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    rotated_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)

    @property
    def is_active(self) -> bool:
        return self.revoked_at is None and self.expires_at > timezone.now()


class DeviceSession(AuditModel):
    """A signed-in device, so a member can see and revoke it."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="sessions")
    device_name = models.CharField(max_length=120, blank=True)
    platform = models.CharField(max_length=20, blank=True)  # ios | android | web
    app_version = models.CharField(max_length=20, blank=True)
    push_token = models.CharField(max_length=255, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.CharField(max_length=255, blank=True)
    last_seen_at = models.DateTimeField(default=timezone.now)
    revoked_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-last_seen_at",)
        indexes = [models.Index(fields=["user", "revoked_at"])]

    def __str__(self) -> str:
        return f"{self.device_name or self.platform or 'device'} ({self.user_id})"


class LoginAttempt(models.Model):
    """Failed sign-ins, counted per identifier to blunt password spraying.

    A per-IP throttle is not enough: a spray from many addresses stays politely
    under each address's limit while one account absorbs the guesses.
    """

    identifier = models.CharField(max_length=254, db_index=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    succeeded = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["identifier", "-created_at"])]

    @classmethod
    def recent_failures(cls, identifier: str, window: timedelta) -> int:
        return cls.objects.filter(
            identifier=identifier.lower(), succeeded=False, created_at__gte=timezone.now() - window
        ).count()


def hash_code(code: str) -> str:
    """Codes are short, so they are hashed with the secret key as pepper.

    A fast hash is deliberate: the value space is tiny and the real defence is
    expiry plus a hard attempt limit, not computational cost.
    """
    import hashlib

    from django.conf import settings

    return hashlib.sha256(f"{code}:{settings.SECRET_KEY}".encode()).hexdigest()


def generate_code(digits: int = 6) -> str:
    return "".join(str(secrets.randbelow(10)) for _ in range(digits))
