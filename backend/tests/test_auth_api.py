"""Auth and account surface, exercised over real HTTP.

Registration, OTP verification, login and refresh rotation are reachable by an
attacker before they hold any credentials, so they are tested through the API
rather than by calling services directly.
"""

from __future__ import annotations

import pytest
from django.db import models
from django.utils import timezone
from datetime import timedelta
from rest_framework.test import APIClient

from apps.accounts.models import User, VerificationCode
from apps.accounts.services import issue_verification

pytestmark = pytest.mark.django_db

PASSWORD = "Str0ng-Passw0rd!23"


@pytest.fixture(autouse=True)
def _clear_throttles():
    """Throttle counters live in the cache; tests must not inherit each other's."""
    from django.core.cache import cache

    cache.clear()
    yield
    cache.clear()


@pytest.fixture
def api():
    return APIClient()


def _register(api, email="new@example.com", password=PASSWORD):
    return api.post(
        "/api/v1/auth/register/",
        {"email": email, "password": password, "full_name": "New Member"},
        format="json",
    )


def _login(api, email, password=PASSWORD):
    return api.post("/api/v1/auth/login/", {"identifier": email, "password": password}, format="json")


def _code_for(user):
    """Read the live code straight from the console provider's outbox.

    The plaintext is never stored — only its hash — so a test that wants a code
    generates a fresh one and captures what was sent.
    """
    from apps.accounts import services as accounts_services

    captured = {}

    original = accounts_services.send_otp
    try:
        accounts_services.send_otp = lambda message: captured.setdefault("code", message.code)
        # Registration already sent one. Waiting out the cooldown is the honest
        # way to get a second code, so emulate it by ageing the last one.
        VerificationCode.objects.filter(user=user, channel="email").update(
            created_at=models.F("created_at") - timedelta(minutes=5)
        )
        issue_verification(user=user, channel="email", purpose=VerificationCode.Purpose.SIGNUP)
    finally:
        accounts_services.send_otp = original
    return captured["code"]


def test_registration_creates_an_unverified_account(api):
    response = _register(api)
    assert response.status_code == 201

    user = User.objects.get(email="new@example.com")
    assert user.is_email_verified is False, "an account is not usable until verified"
    assert user.has_usable_password()
    assert "password" not in response.content.decode().lower()


def test_registration_response_carries_no_tokens(api):
    """Registering must not hand out a session: the address is unproven."""
    body = _register(api).json()["data"]
    assert "access" not in body and "refresh" not in body


def test_verification_activates_the_account(api):
    _register(api)
    user = User.objects.get(email="new@example.com")
    code = _code_for(user)

    api.force_authenticate(user=user)
    response = api.post(
        "/api/v1/auth/verify/", {"code": code, "purpose": VerificationCode.Purpose.SIGNUP}, format="json"
    )
    assert response.status_code == 200
    user.refresh_from_db()
    assert user.is_email_verified is True


def test_a_wrong_code_is_rejected(api):
    _register(api)
    user = User.objects.get(email="new@example.com")
    _code_for(user)

    api.force_authenticate(user=user)
    response = api.post(
        "/api/v1/auth/verify/", {"code": "000000", "purpose": VerificationCode.Purpose.SIGNUP}, format="json"
    )
    assert response.status_code in {400, 422}
    user.refresh_from_db()
    assert user.is_email_verified is False


def test_a_code_cannot_be_reused(api):
    _register(api)
    user = User.objects.get(email="new@example.com")
    code = _code_for(user)
    api.force_authenticate(user=user)

    first = api.post("/api/v1/auth/verify/", {"code": code, "purpose": "signup"}, format="json")
    second = api.post("/api/v1/auth/verify/", {"code": code, "purpose": "signup"}, format="json")
    assert first.status_code == 200
    assert second.status_code in {400, 422}, "a one-time code is used once"


def test_codes_are_stored_only_as_hashes(api):
    _register(api)
    user = User.objects.get(email="new@example.com")
    code = _code_for(user)
    record = VerificationCode.objects.filter(user=user).order_by("-created_at").first()
    assert code not in (record.code_hash or ""), "the plaintext code must not be recoverable"


def test_login_returns_tokens_and_rejects_bad_passwords(api, member_a):
    ok = _login(api, member_a.email)
    assert ok.status_code == 200
    data = ok.json()["data"]
    assert data.get("access") and data.get("refresh")

    bad = _login(api, member_a.email, password="wrong-password")
    assert bad.status_code in {400, 401, 403}


def test_unknown_user_and_wrong_password_look_identical(api, member_a):
    """Different answers here would tell an attacker which emails exist."""
    unknown = _login(api, "nobody@example.com", password="whatever-123")
    wrong = _login(api, member_a.email, password="whatever-123")
    assert unknown.status_code == wrong.status_code
    assert unknown.json().get("error", {}).get("code") == wrong.json().get("error", {}).get("code")


def test_repeated_failures_lock_the_identifier(api, member_a):
    for _ in range(6):
        _login(api, member_a.email, password="wrong-password")
    locked = _login(api, member_a.email)
    assert locked.status_code in {400, 401, 403, 423, 429}


def test_refresh_rotates_and_the_old_token_stops_working(api, member_a):
    first_refresh = _login(api, member_a.email).json()["data"]["refresh"]

    rotated = api.post("/api/v1/auth/refresh/", {"refresh": first_refresh}, format="json")
    assert rotated.status_code == 200
    new_refresh = rotated.json()["data"]["refresh"]
    assert new_refresh != first_refresh, "refresh tokens rotate"

    reused = api.post("/api/v1/auth/refresh/", {"refresh": first_refresh}, format="json")
    assert reused.status_code in {400, 401, 403}, "an old refresh token must not work again"


def test_me_requires_authentication_and_returns_no_secrets(api, member_a):
    assert api.get("/api/v1/auth/me/").status_code == 401

    access = _login(api, member_a.email).json()["data"]["access"]
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    me = api.get("/api/v1/auth/me/")
    assert me.status_code == 200
    body = me.content.decode().lower()
    for forbidden in ("password_hash", "token_hash", "code_hash", "secret"):
        assert forbidden not in body


def test_logout_revokes_the_refresh_token(api, member_a):
    tokens = _login(api, member_a.email).json()["data"]
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")

    out = api.post("/api/v1/auth/logout/", {"all_devices": True}, format="json")
    assert out.status_code in {200, 204}

    again = api.post("/api/v1/auth/refresh/", {"refresh": tokens["refresh"]}, format="json")
    assert again.status_code in {400, 401, 403}


def test_password_reset_request_is_a_neutral_success(api):
    """Whether the address exists must not be observable from this endpoint."""
    unknown = api.post("/api/v1/auth/password/reset/", {"identifier": "nobody@example.com"}, format="json")
    assert unknown.status_code in {200, 202}
    assert "not found" not in unknown.content.decode().lower()


def test_a_short_password_is_refused(api):
    response = _register(api, email="weak@example.com", password="short")
    assert response.status_code == 400
    assert not User.objects.filter(email="weak@example.com").exists()


# ---------------------------------------------------------------------------
# Push token registration
# ---------------------------------------------------------------------------
#
# Push is how an officer learns that a payout is waiting for their signature.
# Registering the token is part of the security path, not a convenience: an
# officer who never receives the notification cannot approve, and the group's
# money sits still.


def _login_with_device(api, email):
    _register(api, email=email)
    response = _login(api, email)
    assert response.status_code == 200
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {response.json()['data']['access']}")
    return response.json()["data"]["device_id"]


def test_registering_a_push_token_actually_stores_it(api):
    from apps.accounts.models import DeviceSession

    device_id = _login_with_device(api, "push-1@example.com")

    response = api.post(
        "/api/v1/auth/push-token/",
        {"device_id": device_id, "push_token": "fcm-token-abc"},
        format="json",
    )

    assert response.status_code == 200
    assert response.json()["data"]["registered"] is True
    assert DeviceSession.objects.get(pk=device_id).push_token == "fcm-token-abc"


def test_a_push_token_for_an_unknown_device_is_refused_not_claimed(api):
    """The endpoint used to answer `registered: true` for any device id.

    A stale id after a reinstall produced a success response and stored no token,
    so the member quietly stopped receiving notifications with no error anywhere
    for anyone to notice.
    """
    _login_with_device(api, "push-2@example.com")

    response = api.post(
        "/api/v1/auth/push-token/",
        {"device_id": "00000000-0000-0000-0000-000000000000", "push_token": "fcm-token-xyz"},
        format="json",
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "device_not_found"


def test_a_member_cannot_attach_a_push_token_to_someone_else_device(api):
    from apps.accounts.models import DeviceSession

    first = APIClient()
    other_device = _login_with_device(first, "push-3@example.com")

    _login_with_device(api, "push-4@example.com")
    response = api.post(
        "/api/v1/auth/push-token/",
        {"device_id": other_device, "push_token": "hijack"},
        format="json",
    )

    assert response.status_code == 404
    assert DeviceSession.objects.get(pk=other_device).push_token == ""
