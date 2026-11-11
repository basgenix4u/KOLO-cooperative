"""The single entry point for group-scoped authorisation."""

from __future__ import annotations

from django.db.models import Q

from apps.common.exceptions import NotFoundError, PermissionDeniedError

from .models import Group, Membership, Permission, ROLE_PERMISSIONS

MEMBER_PERMISSION_FIELDS = ("member.view",)


def membership_for(user, group) -> Membership | None:
    """The user's active membership, or None. Never trusts a client-sent id."""
    if not user or not user.is_authenticated:
        return None
    return (
        Membership.objects.select_related("group", "user")
        .filter(group=group, user=user, status=Membership.Status.ACTIVE)
        .first()
    )


def require_membership(user, group) -> Membership:
    membership = membership_for(user, group)
    if not membership:
        # 404 rather than 403 for a group the caller cannot see: a 403 confirms
        # that a private group with that id exists.
        if group.visibility == Group.Visibility.PRIVATE:
            raise NotFoundError("That group is not available to you.", code="group_not_found")
        raise PermissionDeniedError("You are not a member of this group.", code="not_a_member")
    return membership


def require_permission(user, group, permission: str) -> Membership:
    """Enforce one permission, and return the membership it was checked against."""
    membership = require_membership(user, group)
    if permission not in membership.permissions:
        raise PermissionDeniedError(
            "Your role in this group does not allow that.",
            code="missing_permission",
            details={"required_permission": permission, "your_role": membership.role},
        )
    return membership


def visible_groups(user):
    """Groups a user may see in listings: their own, plus discoverable ones."""
    return Group.objects.filter(is_archived=False).filter(
        Q(visibility=Group.Visibility.PUBLIC)
        | Q(visibility=Group.Visibility.RESTRICTED)
        | Q(memberships__user=user, memberships__status=Membership.Status.ACTIVE)
    ).distinct()


def assert_not_self_approving(actor_membership: Membership, *, beneficiary_membership: Membership, action: str) -> None:
    """Separation of duties for money.

    An officer may not approve a payment that benefits themselves. This is the
    check that stops a single compromised treasurer from draining a group, and
    it lives in the backend so no client can skip it.
    """
    if actor_membership.pk == beneficiary_membership.pk:
        from apps.common.exceptions import PermissionDeniedError as Denied

        raise Denied(
            "This payment benefits you, so someone else has to approve it.",
            code="self_approval_blocked",
            details={"action": action},
        )
