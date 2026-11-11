"""Group operations, each one authorised at the point of change."""

from __future__ import annotations

import logging
import secrets
from datetime import timedelta

from django.db import transaction
from django.utils import timezone
from django.utils.text import slugify

from apps.common.audit import AuditLog
from apps.common.exceptions import ConflictError, DomainError, InvalidStateError, NotFoundError, PermissionDeniedError
from apps.common.outbox import publish

from .models import (
    Announcement, Group, GroupRole, Invitation, Membership, MembershipPermission, MembershipRequest,
    Permission as GroupPermission,
)
from .permissions import membership_for, require_membership, require_permission

logger = logging.getLogger("kolo.audit")


def unique_slug(name: str) -> str:
    base = slugify(name)[:110] or "group"
    candidate = base
    counter = 1
    while Group.objects.filter(slug=candidate).exists():
        counter += 1
        candidate = f"{base}-{counter}"
    return candidate


def create_group(*, actor, **fields) -> Group:
    """The creator becomes the founder — the only role that can hand out ownership."""
    with transaction.atomic():
        group = Group.objects.create(slug=unique_slug(fields["name"]), created_by=actor, **fields)
        Membership.objects.create(
            group=group, user=actor, role=GroupRole.FOUNDER, status=Membership.Status.ACTIVE,
            joined_at=timezone.now(), display_name=actor.full_name or "",
        )
        AuditLog.record(action="group.created", actor=actor, group_id=group.pk, target_type="group",
                        target_id=group.pk, summary=f"{group.name} created")
    return group


def update_group(*, actor, group: Group, **fields) -> Group:
    require_permission(actor, group, GroupPermission.GROUP_EDIT)
    protected = {"currency", "visibility"}
    for key, value in fields.items():
        setattr(group, key, value)
    if "currency" in fields and group.programmes.exists():
        raise InvalidStateError(
            "The group currency cannot change after a programme exists.", code="currency_locked"
        )
    group.save()
    AuditLog.record(action="group.updated", actor=actor, group_id=group.pk, target_type="group",
                    target_id=group.pk, summary=", ".join(fields.keys()))
    return group


def archive_group(*, actor, group: Group) -> Group:
    require_permission(actor, group, GroupPermission.GROUP_ARCHIVE)
    active_programmes = group.programmes.exclude(status__in=["completed", "cancelled", "closed"]).count()
    if active_programmes:
        raise ConflictError(
            "Close the group's active programmes before archiving it.",
            code="group_has_active_programmes",
            details={"active_programmes": active_programmes},
        )
    group.is_archived = True
    group.archived_at = timezone.now()
    group.save(update_fields=["is_archived", "archived_at", "updated_at"])
    AuditLog.record(action="group.archived", actor=actor, group_id=group.pk, severity=AuditLog.Severity.NOTICE,
                    target_type="group", target_id=group.pk, summary="Group archived")
    return group


def request_to_join(*, actor, group: Group, message: str = "") -> MembershipRequest:
    if group.is_archived:
        raise InvalidStateError("This group is archived.", code="group_archived")
    existing = Membership.objects.filter(group=group, user=actor).first()
    if existing and existing.status == Membership.Status.ACTIVE:
        raise ConflictError("You are already a member of this group.", code="already_member")
    if group.member_count() >= group.max_members:
        raise ConflictError("This group is full.", code="group_full")

    if group.visibility == Group.Visibility.PRIVATE:
        # Private groups are invitation-only; ask for an invite rather than
        # silently queueing a request the group never sees.
        raise PermissionDeniedError("This group is invite-only. Ask a member to invite you.",
                                    code="invite_required")

    with transaction.atomic():
        if group.visibility == Group.Visibility.PUBLIC and not group.requires_approval:
            membership, _ = Membership.objects.get_or_create(
                group=group, user=actor,
                defaults={"status": Membership.Status.ACTIVE, "joined_at": timezone.now(),
                          "display_name": actor.full_name or ""},
            )
            membership.status = Membership.Status.ACTIVE
            membership.joined_at = timezone.now()
            membership.save(update_fields=["status", "joined_at"])
            AuditLog.record(action="group.joined", actor=actor, group_id=group.pk, target_type="membership",
                            target_id=membership.pk, summary="Joined an open group")
            publish("membership.joined", {"group_id": str(group.pk), "user_id": str(actor.pk),
                                         "group_name": group.name})
            return membership  # type: ignore[return-value]

        request_obj, _ = MembershipRequest.objects.get_or_create(
            group=group, user=actor, status=MembershipRequest.Status.PENDING,
            defaults={"message": message[:500]},
        )
    AuditLog.record(action="membership.requested", actor=actor, group_id=group.pk,
                    target_type="membership_request", target_id=request_obj.pk, summary="Asked to join")
    return request_obj


def review_join_request(*, actor, request_obj: MembershipRequest, approve: bool) -> MembershipRequest:
    group = request_obj.group
    require_permission(actor, group, GroupPermission.MEMBER_APPROVE)
    if request_obj.status != MembershipRequest.Status.PENDING:
        raise InvalidStateError("This request has already been reviewed.", code="request_decided")

    with transaction.atomic():
        request_obj.status = MembershipRequest.Status.APPROVED if approve else MembershipRequest.Status.REJECTED
        request_obj.reviewed_by = actor
        request_obj.reviewed_at = timezone.now()
        request_obj.save(update_fields=["status", "reviewed_by", "reviewed_at", "updated_at"])
        if approve:
            membership, _ = Membership.objects.get_or_create(
                group=group, user=request_obj.user,
                defaults={"display_name": request_obj.user.full_name or ""},
            )
            membership.status = Membership.Status.ACTIVE
            membership.joined_at = timezone.now()
            membership.save(update_fields=["status", "joined_at"])
        publish("membership.reviewed", {"group_id": str(group.pk), "user_id": str(request_obj.user_id),
                                        "approved": approve, "group_name": group.name})
    AuditLog.record(action="membership.reviewed", actor=actor, group_id=group.pk,
                    target_type="membership_request", target_id=request_obj.pk,
                    summary="approved" if approve else "rejected")
    return request_obj


def invite(*, actor, group: Group, email: str = "", phone: str = "", expires_in_days: int = 7) -> Invitation:
    require_permission(actor, group, GroupPermission.MEMBER_INVITE)
    if group.member_count() >= group.max_members:
        raise ConflictError("This group is full.", code="group_full")
    invitation = Invitation.objects.create(
        group=group,
        invited_email=email.lower()[:254],
        invited_phone=phone[:20],
        token=secrets.token_urlsafe(24),
        invited_by=actor,
        expires_at=timezone.now() + timedelta(days=expires_in_days),
    )
    AuditLog.record(action="membership.invited", actor=actor, group_id=group.pk, target_type="invitation",
                    target_id=invitation.pk, summary=f"Invitation for {email or phone}")
    publish("membership.invited", {"group_id": str(group.pk), "group_name": group.name,
                                    "email": email, "phone": phone, "token": invitation.token})
    return invitation


def accept_invitation(*, actor, token: str) -> Membership:
    invitation = Invitation.objects.filter(token=token).first()
    if not invitation or not invitation.is_open:
        raise NotFoundError("That invitation is no longer valid.", code="invite_invalid")
    existing = Membership.objects.filter(group=invitation.group, user=actor).first()
    if existing and existing.status == Membership.Status.ACTIVE:
        raise ConflictError("You are already a member of this group.", code="already_member")

    with transaction.atomic():
        membership, _ = Membership.objects.get_or_create(
            group=invitation.group, user=actor, defaults={"display_name": actor.full_name or ""}
        )
        membership.status = Membership.Status.ACTIVE
        membership.joined_at = timezone.now()
        membership.save(update_fields=["status", "joined_at"])
        invitation.accepted_by = actor
        invitation.accepted_at = timezone.now()
        invitation.save(update_fields=["accepted_by", "accepted_at"])
    AuditLog.record(action="membership.joined", actor=actor, group_id=invitation.group_id,
                    target_type="membership", target_id=membership.pk, summary="Accepted an invitation")
    return membership


def change_role(*, actor, group: Group, membership: Membership, role: str,
                overrides: dict[str, bool] | None = None) -> Membership:
    require_permission(actor, group, GroupPermission.MEMBER_ROLE_ASSIGN)
    actor_membership = require_membership(actor, group)

    if membership.pk == actor_membership.pk and role != actor_membership.role:
        raise PermissionDeniedError("You cannot change your own role.", code="self_role_change")
    if membership.role == GroupRole.FOUNDER and actor_membership.role != GroupRole.FOUNDER:
        raise PermissionDeniedError("Only the founder can change the founder's role.", code="founder_protected")
    if role == GroupRole.FOUNDER and actor_membership.role != GroupRole.FOUNDER:
        raise PermissionDeniedError("Only the founder can hand over the founder role.", code="founder_protected")

    with transaction.atomic():
        membership.role = role
        membership.save(update_fields=["role", "updated_at"])
        if overrides is not None:
            for permission, granted in overrides.items():
                if permission not in GroupPermission.values:
                    raise DomainError(f"Unknown permission: {permission}", code="permission_unknown")
                MembershipPermission.objects.update_or_create(
                    membership=membership, permission=permission,
                    defaults={"granted": granted, "created_by": actor},
                )
    AuditLog.record(action="membership.role_changed", actor=actor, group_id=group.pk,
                    target_type="membership", target_id=membership.pk,
                    summary=f"{membership.user_id} -> {role}", severity=AuditLog.Severity.NOTICE)
    return membership


def remove_member(*, actor, group: Group, membership: Membership, reason: str = "") -> Membership:
    require_permission(actor, group, GroupPermission.MEMBER_REMOVE)
    if membership.role == GroupRole.FOUNDER:
        raise PermissionDeniedError("The founder cannot be removed.", code="founder_protected")
    if membership.pk == require_membership(actor, group).pk:
        raise PermissionDeniedError("Use 'leave group' to remove yourself.", code="self_removal")

    # A member in an active programme with money in it cannot simply vanish:
    # their obligations and holdings still exist.
    from apps.savings.models import Obligation, Participation

    active = Participation.objects.filter(
        membership=membership, status=Participation.Status.ACTIVE,
        programme__status__in=["active", "paused"],
    )
    if active.exists():
        outstanding = Obligation.objects.filter(
            participation__in=active,
            status__in=[Obligation.Status.PENDING, Obligation.Status.PARTIALLY_PAID, Obligation.Status.OVERDUE],
        ).count()
        raise ConflictError(
            "This member is in an active programme. Exit or settle their participation first.",
            code="member_has_active_participation",
            details={"programmes": active.count(), "outstanding_obligations": outstanding},
        )

    with transaction.atomic():
        membership.status = Membership.Status.REMOVED
        membership.left_at = timezone.now()
        membership.save(update_fields=["status", "left_at", "updated_at"])
    AuditLog.record(action="membership.removed", actor=actor, group_id=group.pk, severity=AuditLog.Severity.NOTICE,
                    target_type="membership", target_id=membership.pk, summary=reason or "Removed by an officer")
    publish("membership.removed", {"group_id": str(group.pk), "user_id": str(membership.user_id),
                                    "group_name": group.name})
    return membership


def leave_group(*, actor, group: Group) -> Membership:
    membership = require_membership(actor, group)
    if membership.role == GroupRole.FOUNDER and group.memberships.filter(
        status=Membership.Status.ACTIVE, role=GroupRole.FOUNDER
    ).count() == 1:
        raise ConflictError(
            "Hand over the founder role before leaving.", code="last_founder"
        )
    from apps.savings.models import Participation

    if Participation.objects.filter(membership=membership, status=Participation.Status.ACTIVE,
                                    programme__status__in=["active", "paused"]).exists():
        raise ConflictError("Leave your active programmes before leaving the group.",
                            code="member_has_active_participation")

    membership.status = Membership.Status.LEFT
    membership.left_at = timezone.now()
    membership.save(update_fields=["status", "left_at", "updated_at"])
    AuditLog.record(action="membership.left", actor=actor, group_id=group.pk, target_type="membership",
                    target_id=membership.pk, summary="Left the group")
    return membership


def post_announcement(*, actor, group: Group, title: str, body: str, pinned: bool = False) -> Announcement:
    require_permission(actor, group, GroupPermission.GROUP_ANNOUNCE)
    announcement = Announcement.objects.create(group=group, author=actor, title=title[:160],
                                               body=body[:4000], is_pinned=pinned)
    member_ids = list(
        Membership.objects.filter(group=group, status=Membership.Status.ACTIVE).values_list("user_id", flat=True)
    )
    publish("group.announcement", {"group_id": str(group.pk), "group_name": group.name,
                                    "title": announcement.title, "member_ids": [str(m) for m in member_ids]})
    return announcement
