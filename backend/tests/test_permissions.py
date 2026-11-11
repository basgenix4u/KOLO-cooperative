"""Who is allowed to do what, inside a group.

These tests pin the role matrix and the separation-of-duties rules that make an
officer a job rather than a key to the safe. They will fail loudly if someone
later "simplifies" a permission set.
"""

from __future__ import annotations

import pytest
from rest_framework.test import APIClient

from apps.common.exceptions import NotFoundError, PermissionDeniedError
from apps.groups.models import Group, GroupRole, Membership, Permission
from apps.groups.permissions import (
    assert_not_self_approving, membership_for, require_membership, require_permission, visible_groups,
)

pytestmark = pytest.mark.django_db


def test_membership_is_resolved_from_the_group_not_the_client(group, memberships):
    assert membership_for(memberships["a"].user, group).pk == memberships["a"].pk
    assert membership_for(memberships["a"].user, group).user_id == memberships["a"].user_id


def test_a_pending_member_is_not_a_member(group, outsider):
    """An unapproved join request grants nothing, and in a private group the
    refusal is a 404 so the group's existence is not confirmed."""
    Membership.objects.create(
        group=group, user=outsider, role=GroupRole.MEMBER, status=Membership.Status.PENDING
    )
    assert membership_for(outsider, group) is None
    with pytest.raises(NotFoundError):
        require_membership(outsider, group)


def test_a_private_group_answers_not_found_to_a_stranger(group, outsider):
    """403 would confirm a private group with that id exists; 404 does not."""
    with pytest.raises(NotFoundError) as caught:
        require_membership(outsider, group)
    assert caught.value.code == "group_not_found"


def test_a_public_group_answers_permission_denied(group, outsider):
    Group.objects.filter(pk=group.pk).update(visibility=Group.Visibility.PUBLIC)
    group.refresh_from_db()
    with pytest.raises(PermissionDeniedError) as caught:
        require_membership(outsider, group)
    assert caught.value.code == "not_a_member"


def test_an_ordinary_member_cannot_create_a_programme(group, memberships):
    with pytest.raises(PermissionDeniedError) as caught:
        require_permission(memberships["a"].user, group, Permission.PROGRAMME_CREATE)
    assert caught.value.code == "missing_permission"
    assert caught.value.details["required_permission"] == Permission.PROGRAMME_CREATE


def test_the_treasurer_cannot_activate_a_programme(group, officers):
    """Treasurers handle money; starting a programme is a chair's decision."""
    with pytest.raises(PermissionDeniedError):
        require_permission(officers["treasurer"].user, group, Permission.PROGRAMME_ACTIVATE)


def test_the_treasurer_can_record_payments(group, officers):
    membership = require_permission(officers["treasurer"].user, group, Permission.FINANCE_POST)
    assert membership.role == GroupRole.TREASURER


def test_a_treasurer_cannot_approve_their_own_withdrawal(group, officers, memberships):
    """The separation-of-duties check, exercised directly."""
    from apps.groups.permissions import assert_not_self_approving

    with pytest.raises(Exception) as caught:
        assert_not_self_approving(
            officers["treasurer"], beneficiary_membership=officers["treasurer"], action="withdraw"
        )
    assert getattr(caught.value, "code", "") == "self_approval_blocked"


def test_a_second_officer_can_approve_it(group, officers, memberships):
    # Different memberships: allowed.
    assert_not_self_approving(
        officers["chair"], beneficiary_membership=officers["treasurer"], action="withdraw"
    )


def test_only_visible_groups_are_listed(group, memberships, outsider):
    public_group = Group.objects.create(
        name="Open Ajo", slug="open-ajo", visibility=Group.Visibility.PUBLIC, created_by=outsider
    )
    private_group, _ = Group.objects.get_or_create(
        slug="hidden-ajo", defaults={"name": "Hidden", "visibility": Group.Visibility.PRIVATE,
                                     "created_by": outsider}
    )
    seen = set(visible_groups(outsider).values_list("pk", flat=True))
    assert public_group.pk in seen
    assert private_group.pk not in seen
    assert group.pk not in seen


def test_public_group_endpoints_hide_a_members_only_group():
    """The listing endpoint must not leak a private group to a stranger."""
    group = Group.objects.create(
        name="Secret Ajo", slug="secret-ajo", visibility=Group.Visibility.PRIVATE,
        created_by=None,
    )
    client = APIClient()
    from tests.conftest import make_user

    stranger = make_user("stranger@example.com")
    client.force_authenticate(user=stranger)
    response = client.get("/api/v1/groups/")
    body = response.content.decode()
    assert "Secret Ajo" not in body


def test_role_permissions_are_what_the_matrix_says(group, officers):
    """Spot-check the matrix rather than trusting it by eye."""
    chair = officers["chair"].permissions
    treasurer = officers["treasurer"].permissions

    assert Permission.PROGRAMME_ACTIVATE in chair
    assert Permission.PROGRAMME_ACTIVATE not in treasurer

    assert Permission.FINANCE_POST in treasurer
    assert Permission.WITHDRAWAL_REQUEST in treasurer
    assert Permission.WITHDRAWAL_APPROVE not in treasurer, "the requester cannot also be the approver"

    # Nobody can approve their own payout without a second signature.
    assert Permission.PAYOUT_APPROVE in treasurer
