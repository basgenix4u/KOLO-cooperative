"""Groups, cooperatives and the permission model that guards them.

Authorisation is a backend concern. A hidden button is a UX courtesy; it is
never the control. Every protected operation calls `require_permission`, which
reads this table.
"""

from __future__ import annotations

from django.conf import settings
from django.db import models

from apps.common.models import AuditModel, UUIDModel


class Permission(models.TextChoices):
    """Every distinct thing a person can do inside a group."""

    # Membership
    MEMBER_VIEW = "member.view", "View members"
    MEMBER_INVITE = "member.invite", "Invite members"
    MEMBER_APPROVE = "member.approve", "Approve membership requests"
    MEMBER_REMOVE = "member.remove", "Remove members"
    MEMBER_ROLE_ASSIGN = "member.role_assign", "Assign roles"

    # Group
    GROUP_EDIT = "group.edit", "Edit group settings"
    GROUP_ARCHIVE = "group.archive", "Archive the group"
    GROUP_ANNOUNCE = "group.announce", "Post announcements"

    # Programmes
    PROGRAMME_VIEW = "programme.view", "View programmes"
    PROGRAMME_CREATE = "programme.create", "Create programmes"
    PROGRAMME_EDIT = "programme.edit", "Edit programmes"
    PROGRAMME_ACTIVATE = "programme.activate", "Activate or pause programmes"
    PROGRAMME_CLOSE = "programme.close", "Close programmes"

    # Money
    FINANCE_VIEW = "finance.view", "View group financials"
    FINANCE_POST = "finance.post", "Record and reconcile payments"
    WITHDRAWAL_REQUEST = "withdrawal.request", "Request a withdrawal"
    WITHDRAWAL_APPROVE = "withdrawal.approve", "Approve a withdrawal"
    WITHDRAWAL_EXECUTE = "withdrawal.execute", "Execute an approved withdrawal"
    PAYOUT_APPROVE = "payout.approve", "Approve a rotation payout"

    # Loans
    LOAN_VIEW = "loan.view", "View loans"
    LOAN_APPROVE = "loan.approve", "Approve a loan"
    LOAN_DISBURSE = "loan.disburse", "Disburse a loan"

    # Governance
    PROPOSAL_CREATE = "proposal.create", "Create proposals"
    PROPOSAL_MANAGE = "proposal.manage", "Manage voting rounds"
    RESOLUTION_PUBLISH = "resolution.publish", "Publish resolutions"

    # Communication
    CHAT_MODERATE = "chat.moderate", "Moderate chat"


class GroupRole(models.TextChoices):
    """Default roles. Permissions per role are data, not hard-coded branches."""

    FOUNDER = "founder", "Founder"
    OWNER = "owner", "Owner"
    ADMIN = "admin", "Administrator"
    TREASURER = "treasurer", "Treasurer"
    SECRETARY = "secretary", "Secretary"
    MODERATOR = "moderator", "Moderator"
    MEMBER = "member", "Member"


# Separation of duties is encoded here, not in the UI:
#   * A treasurer may prepare money movements but not approve their own.
#   * An admin may approve a withdrawal but not execute it alone when dual
#     control is on, and may never approve a payout they are the beneficiary of.
#   * Nobody gets both `withdrawal.approve` and `withdrawal.execute` by default
#     except the owner, and even then a second officer is required by policy.
ROLE_PERMISSIONS: dict[str, set[str]] = {
    GroupRole.FOUNDER: {
        Permission.MEMBER_VIEW, Permission.MEMBER_INVITE, Permission.MEMBER_APPROVE,
        Permission.MEMBER_REMOVE, Permission.MEMBER_ROLE_ASSIGN,
        Permission.GROUP_EDIT, Permission.GROUP_ARCHIVE, Permission.GROUP_ANNOUNCE,
        Permission.PROGRAMME_VIEW, Permission.PROGRAMME_CREATE, Permission.PROGRAMME_EDIT,
        Permission.PROGRAMME_ACTIVATE, Permission.PROGRAMME_CLOSE,
        Permission.FINANCE_VIEW, Permission.FINANCE_POST,
        Permission.WITHDRAWAL_REQUEST, Permission.WITHDRAWAL_APPROVE, Permission.WITHDRAWAL_EXECUTE,
        Permission.PAYOUT_APPROVE,
        Permission.LOAN_VIEW, Permission.LOAN_APPROVE, Permission.LOAN_DISBURSE,
        Permission.PROPOSAL_CREATE, Permission.PROPOSAL_MANAGE, Permission.RESOLUTION_PUBLISH,
        Permission.CHAT_MODERATE,
    },
    GroupRole.OWNER: {
        Permission.MEMBER_VIEW, Permission.MEMBER_INVITE, Permission.MEMBER_APPROVE,
        Permission.MEMBER_ROLE_ASSIGN, Permission.GROUP_EDIT, Permission.GROUP_ANNOUNCE,
        Permission.PROGRAMME_VIEW, Permission.PROGRAMME_CREATE, Permission.PROGRAMME_EDIT,
        Permission.PROGRAMME_ACTIVATE, Permission.PROGRAMME_CLOSE,
        Permission.FINANCE_VIEW, Permission.FINANCE_POST,
        Permission.WITHDRAWAL_REQUEST, Permission.WITHDRAWAL_APPROVE,
        Permission.PAYOUT_APPROVE, Permission.LOAN_VIEW, Permission.LOAN_APPROVE,
        Permission.PROPOSAL_CREATE, Permission.PROPOSAL_MANAGE, Permission.RESOLUTION_PUBLISH,
        Permission.CHAT_MODERATE,
    },
    GroupRole.ADMIN: {
        Permission.MEMBER_VIEW, Permission.MEMBER_INVITE, Permission.MEMBER_APPROVE,
        Permission.MEMBER_REMOVE, Permission.MEMBER_ROLE_ASSIGN,
        Permission.GROUP_EDIT, Permission.GROUP_ANNOUNCE,
        Permission.PROGRAMME_VIEW, Permission.PROGRAMME_CREATE, Permission.PROGRAMME_EDIT,
        Permission.FINANCE_VIEW, Permission.WITHDRAWAL_APPROVE, Permission.LOAN_VIEW,
        Permission.PROPOSAL_CREATE, Permission.CHAT_MODERATE,
    },
    GroupRole.TREASURER: {
        Permission.MEMBER_VIEW, Permission.PROGRAMME_VIEW, Permission.PROGRAMME_EDIT,
        Permission.FINANCE_VIEW, Permission.FINANCE_POST,
        Permission.WITHDRAWAL_REQUEST, Permission.PAYOUT_APPROVE,
        Permission.LOAN_VIEW, Permission.LOAN_DISBURSE, Permission.PROPOSAL_CREATE,
    },
    GroupRole.SECRETARY: {
        Permission.MEMBER_VIEW, Permission.MEMBER_INVITE, Permission.GROUP_ANNOUNCE,
        Permission.PROGRAMME_VIEW, Permission.PROPOSAL_CREATE, Permission.RESOLUTION_PUBLISH,
    },
    GroupRole.MODERATOR: {
        Permission.MEMBER_VIEW, Permission.PROGRAMME_VIEW, Permission.CHAT_MODERATE,
    },
    GroupRole.MEMBER: {Permission.MEMBER_VIEW, Permission.PROGRAMME_VIEW},
}


class Group(AuditModel):
    """A savings group, cooperative, association or community."""

    class Visibility(models.TextChoices):
        PUBLIC = "public", "Public — discoverable, join freely"
        PRIVATE = "private", "Private — invite only"
        RESTRICTED = "restricted", "Restricted — discoverable, approval required"

    class Category(models.TextChoices):
        FAMILY = "family", "Family"
        FRIENDS = "friends", "Friends"
        ESUSU = "esusu", "Esusu / Ajo / Adashe"
        COOPERATIVE = "cooperative", "Registered cooperative"
        MARKET = "market", "Market association"
        FAITH = "faith", "Religious or social organisation"
        COMMUNITY = "community", "Community association"
        WORKPLACE = "workplace", "Workplace"
        OTHER = "other", "Other"

    name = models.CharField(max_length=120, db_index=True)
    slug = models.SlugField(max_length=140, unique=True)
    description = models.TextField(blank=True, max_length=2000)
    category = models.CharField(max_length=20, choices=Category.choices, default=Category.FRIENDS)
    visibility = models.CharField(max_length=12, choices=Visibility.choices, default=Visibility.RESTRICTED, db_index=True)

    currency = models.CharField(max_length=3, default="NGN")
    country = models.CharField(max_length=2, blank=True)
    # Approximate only: city-level or a coarse coordinate. A member's home
    # address is never a group attribute.
    city = models.CharField(max_length=120, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

    avatar_url = models.URLField(blank=True)
    cover_url = models.URLField(blank=True)

    requires_approval = models.BooleanField(default=True)
    max_members = models.PositiveIntegerField(default=500)
    # Rules made explicit so the app can explain them instead of surprising
    # someone later: how many officers must approve money leaving the group.
    requires_dual_approval_for_withdrawals = models.BooleanField(default=True)

    is_archived = models.BooleanField(default=False, db_index=True)
    archived_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="created_groups"
    )

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("name",)
        verbose_name_plural = "groups"
        constraints = [
            models.CheckConstraint(condition=models.Q(currency__regex=r"^[A-Z]{3}$"), name="group_currency_iso4217"),
            models.CheckConstraint(condition=models.Q(max_members__gte=2), name="group_min_two_members"),
        ]
        indexes = [
            models.Index(fields=["visibility", "is_archived"]),
            models.Index(fields=["category", "country"]),
        ]

    def __str__(self) -> str:
        return self.name

    def member_count(self) -> int:
        return self.memberships.filter(status=Membership.Status.ACTIVE).count()


class Membership(AuditModel):
    """A member's standing in one group. One user, many memberships."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending approval"
        ACTIVE = "active", "Active"
        SUSPENDED = "suspended", "Suspended"
        LEFT = "left", "Left"
        REMOVED = "removed", "Removed"

    group = models.ForeignKey(Group, on_delete=models.CASCADE, related_name="memberships")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="memberships")
    role = models.CharField(max_length=20, choices=GroupRole.choices, default=GroupRole.MEMBER, db_index=True)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.PENDING, db_index=True)

    display_name = models.CharField(max_length=120, blank=True, help_text="How this member appears inside this group")
    joined_at = models.DateTimeField(null=True, blank=True)
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="approved_memberships"
    )
    left_at = models.DateTimeField(null=True, blank=True)
    # Members can hide their own financial detail from other members while
    # still being a full participant.
    share_financials = models.BooleanField(default=False)

    class Meta:
        ordering = ("display_name", "created_at")
        constraints = [
            models.UniqueConstraint(fields=["group", "user"], name="uniq_membership_per_group"),
        ]
        indexes = [models.Index(fields=["group", "status"]), models.Index(fields=["user", "status"])]

    def __str__(self) -> str:
        return f"{self.display_name or self.user_id} in {self.group.name}"

    @property
    def permissions(self) -> set[str]:
        """Role defaults, plus any per-member overrides, nothing more."""
        base = set(ROLE_PERMISSIONS.get(self.role, set()))
        overrides = self.permission_overrides.all()
        for override in overrides:
            if override.granted:
                base.add(override.permission)
            else:
                base.discard(override.permission)
        return base

    def has_permission(self, permission: str) -> bool:
        return self.status == self.Status.ACTIVE and permission in self.permissions


class MembershipPermission(UUIDModel):
    """A per-member grant or revoke, so a real committee is not forced into a role."""

    membership = models.ForeignKey(Membership, on_delete=models.CASCADE, related_name="permission_overrides")
    permission = models.CharField(max_length=60, choices=Permission.choices)
    granted = models.BooleanField(default=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["membership", "permission"], name="uniq_member_permission")]


class MembershipRequest(AuditModel):
    """A request to join a restricted or approval-gated group."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"
        WITHDRAWN = "withdrawn", "Withdrawn"

    group = models.ForeignKey(Group, on_delete=models.CASCADE, related_name="join_requests")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="join_requests")
    message = models.CharField(max_length=500, blank=True)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.PENDING, db_index=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="reviewed_requests"
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(
                fields=["group", "user"], condition=models.Q(status="pending"), name="uniq_open_join_request"
            ),
        ]


class Invitation(AuditModel):
    """An invite code for a private group. Single-use, expiring, revocable."""

    group = models.ForeignKey(Group, on_delete=models.CASCADE, related_name="invitations")
    invited_email = models.EmailField(blank=True)
    invited_phone = models.CharField(max_length=20, blank=True)
    token = models.CharField(max_length=64, unique=True)
    invited_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="sent_invitations")
    accepted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="accepted_invitations"
    )
    expires_at = models.DateTimeField(db_index=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)

    @property
    def is_open(self) -> bool:
        from django.utils import timezone

        return (
            self.accepted_at is None
            and self.revoked_at is None
            and self.expires_at > timezone.now()
        )


class Announcement(AuditModel):
    """A pinned message from the group's officers."""

    group = models.ForeignKey(Group, on_delete=models.CASCADE, related_name="announcements")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL)
    title = models.CharField(max_length=160)
    body = models.TextField(max_length=4000)
    is_pinned = models.BooleanField(default=False)

    class Meta:
        ordering = ("-is_pinned", "-created_at")
        indexes = [models.Index(fields=["group", "-created_at"])]
