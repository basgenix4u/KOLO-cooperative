"""Tests that only mean something outside a wrapping transaction.

Every other test module runs on `TestCase`/`pytest.mark.django_db`, which wraps
each test in a transaction. That convenience hid two production-only defects and
let a full green suite ship them:

1. `select_for_update()` in autocommit raises `TransactionManagementError`, so
   `POST /auth/verify/` and `POST /auth/refresh/` returned HTTP 500 on the real
   server while every test passed.
2. Worse, once those paths *were* wrapped, a refusal raised inside the same
   `atomic()` block rolled back the security write that justified the refusal:
   `attempts_left` never moved, so a six-digit code could be brute-forced with
   unlimited attempts, and replaying a rotated refresh token failed to revoke the
   family, so a stolen session stayed alive.

`TransactionTestCase` truncates and commits for real, so these assertions are
about committed database state rather than a rollback we cannot see. Each test
also pins the observable HTTP contract, because that is what the client sees.
"""

from __future__ import annotations

import pytest
from django.test import TransactionTestCase
from rest_framework.test import APIClient

from apps.accounts import services as accounts
from apps.accounts.models import RefreshToken, User, VerificationCode
from apps.common.exceptions import DomainError, PermissionDeniedError

PASSWORD = "Str0ng-Passw0rd!23"


@pytest.fixture
def otp_capture(monkeypatch):
    """Intercept the outgoing OTP so a test can submit the real code.

    The database deliberately stores only a hash, so the plaintext is only ever
    visible at the moment it is dispatched.
    """
    sent: list[str] = []

    def fake_send(message):
        sent.append(message.code)

    monkeypatch.setattr(accounts, "send_otp", fake_send)
    return sent


def _user(email: str, *, verified: bool = True) -> User:
    user = User.objects.create_user(email=email, password=PASSWORD, full_name="Auto Commit")
    if verified:
        user.is_email_verified = True
        user.verification_level = "basic"
        user.save(update_fields=["is_email_verified", "verification_level"])
    return user


class RefreshRotationWithoutAmbientTransaction(TransactionTestCase):
    """Autocommit semantics: no test-managed outer transaction to lean on."""

    reset_sequences = True

    def setUp(self):
        self.user = _user("rotate@example.com")

    def _issue(self) -> str:
        raw, _ = accounts.issue_refresh_token(user=self.user, device=None)
        return raw

    def test_rotation_actually_works_in_autocommit(self):
        """The original 500: locking the row must not need a caller's transaction."""
        old = self._issue()
        user, new_raw, record = accounts.rotate_refresh_token(raw_token=old)

        self.assertEqual(user.pk, self.user.pk)
        self.assertNotEqual(new_raw, old)
        self.assertIsNotNone(record.revoked_at is None)
        self.assertTrue(RefreshToken.objects.filter(token_hash=accounts.hash_token(old)).get().revoked_at)

    def test_replay_revokes_the_family_and_it_sticks(self):
        """Reuse detection must survive the exception that reports it.

        The refusal is raised on purpose. If the revocation were written inside
        the block that raises, the rollback would leave the stolen session alive.
        """
        a = self._issue()
        _, b, _ = accounts.rotate_refresh_token(raw_token=a)
        _, c, _ = accounts.rotate_refresh_token(raw_token=b)

        with self.assertRaises(PermissionDeniedError) as caught:
            accounts.rotate_refresh_token(raw_token=a)
        self.assertEqual(caught.exception.code, "refresh_revoked")

        # The live token the honest member is holding must now be dead too.
        with self.assertRaises(PermissionDeniedError) as caught:
            accounts.rotate_refresh_token(raw_token=c)
        self.assertEqual(caught.exception.code, "refresh_revoked")

        live = RefreshToken.objects.filter(user=self.user, revoked_at__isnull=True)
        self.assertEqual(live.count(), 0, "every token in the family must be revoked after reuse")

    def test_expired_refresh_is_refused_and_leaves_state_alone(self):
        from datetime import timedelta

        from django.utils import timezone

        raw = self._issue()
        RefreshToken.objects.filter(token_hash=accounts.hash_token(raw)).update(
            expires_at=timezone.now() - timedelta(seconds=1)
        )
        with self.assertRaises(PermissionDeniedError) as caught:
            accounts.rotate_refresh_token(raw_token=raw)
        self.assertEqual(caught.exception.code, "refresh_expired")
        self.assertIsNone(RefreshToken.objects.get(token_hash=accounts.hash_token(raw)).revoked_at)

    def test_unknown_refresh_is_refused(self):
        with self.assertRaises(PermissionDeniedError) as caught:
            accounts.rotate_refresh_token(raw_token="not-a-real-token")
        self.assertEqual(caught.exception.code, "refresh_invalid")


class OtpAttemptsPersistAcrossRefusals(TransactionTestCase):
    """A wrong code must leave a mark. Unlimited attempts is a real vulnerability."""

    reset_sequences = True

    def setUp(self):
        self.user = _user("otp@example.com", verified=False)
        self.sent: list[str] = []
        patcher = pytest.MonkeyPatch()
        patcher.setattr(accounts, "send_otp", lambda message: self.sent.append(message.code))
        self.addCleanup(patcher.undo)

    def _dispatch(self, record: VerificationCode) -> str:
        """The plaintext code captured when `issue_verification` dispatched it."""
        return self.sent[-1]

    def _issue(self, *, purpose: str = "signup", channel: str = "email") -> VerificationCode:
        return accounts.issue_verification(user=self.user, purpose=purpose, channel=channel)

    def test_each_wrong_guess_decrements_the_counter(self):
        self._issue()
        seen = []
        for _ in range(4):
            with self.assertRaises(DomainError) as caught:
                accounts.verify_code(user=self.user, code="000000", purpose="signup")
            self.assertEqual(caught.exception.code, "otp_invalid")
            seen.append(caught.exception.details["attempts_left"])
        self.assertEqual(seen, [4, 3, 2, 1])

    def test_counter_is_persisted_not_just_reported(self):
        record = self._issue()
        with self.assertRaises(DomainError):
            accounts.verify_code(user=self.user, code="000000", purpose="signup")
        # Re-read from the database: the decrement has to be committed.
        self.assertEqual(VerificationCode.objects.get(pk=record.pk).attempts_left, record.attempts_left - 1)

    def test_brute_force_is_cut_off_at_zero(self):
        record = self._issue()
        real_code = self._dispatch(record)
        for _ in range(record.attempts_left):
            with self.assertRaises(DomainError):
                accounts.verify_code(user=self.user, code="000000", purpose="signup")
        with self.assertRaises(DomainError) as caught:
            accounts.verify_code(user=self.user, code="000000", purpose="signup")
        self.assertEqual(caught.exception.code, "otp_locked")

        # And the correct code is no longer accepted either — the code is burnt.
        with self.assertRaises(DomainError) as caught:
            accounts.verify_code(user=self.user, code=real_code, purpose="signup")
        self.assertEqual(caught.exception.code, "otp_locked")
        self.user.refresh_from_db()
        self.assertFalse(self.user.is_email_verified)

    def test_correct_code_consumes_and_verifies(self):
        record = self._issue()
        accounts.verify_code(user=self.user, code=self._dispatch(record), purpose="signup")

        self.user.refresh_from_db()
        self.assertTrue(self.user.is_email_verified)
        self.assertIsNotNone(VerificationCode.objects.get(pk=record.pk).consumed_at)

    def test_used_code_cannot_be_replayed(self):
        record = self._issue()
        code = self._dispatch(record)
        accounts.verify_code(user=self.user, code=code, purpose="signup")
        with self.assertRaises(DomainError) as caught:
            accounts.verify_code(user=self.user, code=code, purpose="signup")
        self.assertEqual(caught.exception.code, "otp_missing")

    def test_no_pending_code_is_refused(self):
        with self.assertRaises(DomainError) as caught:
            accounts.verify_code(user=self.user, code="123456", purpose="signup")
        self.assertEqual(caught.exception.code, "otp_missing")


@pytest.mark.django_db(transaction=True)
def test_refresh_endpoint_never_returns_500(client):
    """The HTTP contract the Flutter client depends on, exercised in autocommit."""
    user = _user("http-refresh@example.com")
    raw, _ = accounts.issue_refresh_token(user=user, device=None)

    response = client.post("/api/v1/auth/refresh/", {"refresh": raw}, content_type="application/json")
    assert response.status_code == 200, response.content
    body = response.json()["data"]
    assert body["access"] and body["refresh"] and body["refresh"] != raw

    # Replaying the now-rotated token is a 403, never a 500.
    replay = client.post("/api/v1/auth/refresh/", {"refresh": raw}, content_type="application/json")
    assert replay.status_code == 403, replay.content
    assert replay.json()["error"]["code"] == "refresh_revoked"


@pytest.mark.django_db(transaction=True)
def test_verify_endpoint_returns_400_not_500(client, otp_capture):
    user = _user("http-verify@example.com", verified=False)
    record = accounts.issue_verification(user=user, purpose="signup", channel="email")
    real_code = otp_capture[-1]

    api = APIClient()
    api.force_authenticate(user=user)
    response = api.post("/api/v1/auth/verify/", {"code": "000000", "purpose": "signup"}, format="json")
    assert response.status_code == 400, response.content
    assert response.json()["error"]["code"] == "otp_invalid"
    assert response.json()["error"]["details"]["attempts_left"] == record.attempts_left - 1

    ok = api.post("/api/v1/auth/verify/", {"code": real_code, "purpose": "signup"}, format="json")
    assert ok.status_code == 200, ok.content
    user.refresh_from_db()
    assert user.is_email_verified
