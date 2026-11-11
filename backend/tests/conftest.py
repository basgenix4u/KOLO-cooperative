"""Shared fixtures: real users, a real group, real officers.

Nothing here mocks the ledger or the database. If these tests pass, the money
rules hold against PostgreSQL with its real locking and constraints.
"""

from __future__ import annotations

import pytest
from django.utils import timezone

from apps.groups.models import Group, GroupRole, Membership


@pytest.fixture(autouse=True)
def _fast_otp(settings):
    settings.KOLO["OTP_PROVIDER"] = "console"
    settings.PAYMENT_PROVIDER = "mock"
    settings.FINANCIAL_ENV = "sandbox"
    return settings


def make_user(email: str, *, full_name: str = "Test Member", verified: bool = True):
    from apps.accounts.models import User

    user = User.objects.create_user(
        email=email, password="Str0ng-Passw0rd!23", full_name=full_name,
    )
    if verified:
        user.is_email_verified = True
        user.verification_level = "basic"
        user.save(update_fields=["is_email_verified", "verification_level"])
    return user


@pytest.fixture
def treasurer():
    return make_user("treasurer@example.com", full_name="Tess Okonkwo")


@pytest.fixture
def chairperson():
    return make_user("chair@example.com", full_name="Chidi Balogun")


@pytest.fixture
def member_a():
    return make_user("member-a@example.com", full_name="Amaka Eze")


@pytest.fixture
def member_b():
    return make_user("member-b@example.com", full_name="Bola Ade")


@pytest.fixture
def outsider():
    return make_user("outsider@example.com", full_name="Uche Nwosu")


@pytest.fixture
def group(chairperson):
    group = Group.objects.create(
        name="Abuja Friends Ajo", slug="abuja-friends-ajo", currency="NGN",
        created_by=chairperson, visibility=Group.Visibility.PRIVATE,
    )
    return group


def _join(group, user, role, *, approved_by=None):
    membership = Membership.objects.create(
        group=group, user=user, role=role, status=Membership.Status.ACTIVE,
        joined_at=timezone.now(), approved_by=approved_by, share_financials=True,
    )
    return membership


@pytest.fixture
def officers(group, chairperson, treasurer):
    """A group with a chairperson and a treasurer, both active members."""
    chair = _join(group, chairperson, GroupRole.OWNER)
    tres = _join(group, treasurer, GroupRole.TREASURER)
    return {"chair": chair, "treasurer": tres}


@pytest.fixture
def memberships(group, officers, member_a, member_b):
    return {
        "a": _join(group, member_a, GroupRole.MEMBER),
        "b": _join(group, member_b, GroupRole.MEMBER),
    }
