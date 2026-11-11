"""Savings programmes: pooled, rotational (esusu/ajo/adashe), and target-based.

The rule that shapes every model here: **an expected contribution is not
money.** A schedule row says what should arrive and when. Only a verified,
ledger-posted contribution is a balance. No code path may derive an available
payout from a schedule.
"""

from __future__ import annotations

from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.common.models import AuditModel, UUIDModel


class ProgrammeType(models.TextChoices):
    ROTATIONAL = "rotational", "Rotational (esusu / ajo / adashe)"
    ACCUMULATED = "accumulated", "Accumulated savings"
    TARGET = "target", "Target savings"
    FUNDRAISING = "fundraising", "Fundraising / donations"


class Frequency(models.TextChoices):
    DAILY = "daily", "Daily"
    WEEKLY = "weekly", "Weekly"
    BIWEEKLY = "biweekly", "Every two weeks"
    MONTHLY = "monthly", "Monthly"
    QUARTERLY = "quarterly", "Quarterly"
    CUSTOM = "custom", "Custom"


FREQUENCY_DAYS = {
    Frequency.DAILY: 1,
    Frequency.WEEKLY: 7,
    Frequency.BIWEEKLY: 14,
    Frequency.MONTHLY: 30,
    Frequency.QUARTERLY: 91,
}


class Programme(AuditModel):
    """A savings programme inside one group.

    Each programme has its own accounting scope: its pool is a distinct ledger
    account, so a group with a land fund and an emergency fund never blends them,
    and consolidated reporting sums programme balances without double counting.
    """

    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        PENDING_APPROVAL = "pending_approval", "Awaiting approval"
        SCHEDULED = "scheduled", "Scheduled"
        ACTIVE = "active", "Active"
        PAUSED = "paused", "Paused"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"
        CLOSED = "closed", "Closed"

    class Visibility(models.TextChoices):
        MEMBERS = "members", "Members of this group"
        OFFICERS = "officers", "Officers only"

    group = models.ForeignKey("groups.Group", on_delete=models.CASCADE, related_name="programmes")
    name = models.CharField(max_length=140)
    description = models.TextField(blank=True, max_length=2000)
    type = models.CharField(max_length=20, choices=ProgrammeType.choices, db_index=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.DRAFT, db_index=True)
    visibility = models.CharField(max_length=12, choices=Visibility.choices, default=Visibility.MEMBERS)

    currency = models.CharField(max_length=3)
    # Minor units. Zero means "members choose their own amount" (target/open
    # savings); a rotational programme requires a fixed amount.
    contribution_amount_minor = models.BigIntegerField(default=0)
    frequency = models.CharField(max_length=12, choices=Frequency.choices, default=Frequency.MONTHLY)
    custom_interval_days = models.PositiveSmallIntegerField(null=True, blank=True)

    target_amount_minor = models.BigIntegerField(default=0)
    start_date = models.DateField(db_index=True)
    end_date = models.DateField(null=True, blank=True)
    contribution_day = models.PositiveSmallIntegerField(
        null=True, blank=True, help_text="Day of month / week the obligation falls due"
    )

    # Rotational specifics
    rotation_order_locked = models.BooleanField(default=False)
    cycle_length = models.PositiveSmallIntegerField(
        null=True, blank=True, help_text="Number of contribution periods per payout"
    )

    # Governance
    requires_dual_approval = models.BooleanField(default=True)
    allow_late_contributions = models.BooleanField(default=True)
    late_fee_minor = models.BigIntegerField(default=0)
    grace_period_days = models.PositiveSmallIntegerField(default=3)

    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="created_programmes"
    )
    activated_at = models.DateTimeField(null=True, blank=True)
    closed_at = models.DateTimeField(null=True, blank=True)
    completion_summary = models.JSONField(default=dict, blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True, db_index=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.CheckConstraint(condition=models.Q(currency__regex=r"^[A-Z]{3}$"), name="programme_currency_iso4217"),
            models.CheckConstraint(
                condition=models.Q(contribution_amount_minor__gte=0), name="programme_amount_non_negative"
            ),
            models.CheckConstraint(
                condition=models.Q(end_date__isnull=True) | models.Q(end_date__gte=models.F("start_date")),
                name="programme_end_after_start",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(type="rotational", contribution_amount_minor__gt=0)
                    | ~models.Q(type="rotational")
                ),
                name="rotational_needs_fixed_amount",
            ),
        ]
        indexes = [
            models.Index(fields=["group", "status"]),
            models.Index(fields=["status", "start_date"]),
        ]

    def __str__(self) -> str:
        return f"{self.name} ({self.get_type_display()})"

    @property
    def is_active(self) -> bool:
        return self.status == self.Status.ACTIVE

    def expected_total_minor(self) -> int:
        """What the schedule *expects*. Never a balance, never a payout basis."""
        active = self.participants.filter(status=Participation.Status.ACTIVE).count()
        if not self.contribution_amount_minor:
            return 0
        return active * self.contribution_amount_minor

    def collected_total_minor(self) -> int:
        """Verified money only."""
        from django.db.models import Sum

        total = self.contributions.filter(
            status__in=[Contribution.Status.CONFIRMED, Contribution.Status.SETTLED]
        ).aggregate(total=Sum("amount_minor"))["total"]
        return total or 0

    def next_due_date(self, *, after=None):
        after = after or timezone.localdate()
        interval = self.custom_interval_days or FREQUENCY_DAYS.get(self.frequency, 30)
        return after + timedelta(days=interval)


class Participation(AuditModel):
    """A member taking part in one programme — participation is opt-in per programme."""

    class Status(models.TextChoices):
        INVITED = "invited", "Invited"
        ACTIVE = "active", "Active"
        PAUSED = "paused", "Paused"
        EXITED = "exited", "Exited"
        REMOVED = "removed", "Removed"
        COMPLETED = "completed", "Completed"

    programme = models.ForeignKey(Programme, on_delete=models.CASCADE, related_name="participants")
    membership = models.ForeignKey("groups.Membership", on_delete=models.CASCADE, related_name="participations")
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.ACTIVE, db_index=True)
    amount_minor = models.BigIntegerField(default=0, help_text="This member's agreed contribution, if it varies")
    joined_at = models.DateTimeField(default=timezone.now)
    exited_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("joined_at",)
        constraints = [
            models.UniqueConstraint(fields=["programme", "membership"], name="uniq_participation"),
            models.CheckConstraint(condition=models.Q(amount_minor__gte=0), name="participation_amount_non_negative"),
        ]

    def __str__(self) -> str:
        return f"{self.membership_id} in {self.programme_id}"


class RotationPosition(UUIDModel):
    """Where a member sits in a rotational payout order."""

    programme = models.ForeignKey(Programme, on_delete=models.CASCADE, related_name="rotation_positions")
    participation = models.ForeignKey(Participation, on_delete=models.CASCADE, related_name="rotation_positions")
    position = models.PositiveSmallIntegerField()
    assigned_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("position",)
        constraints = [
            models.UniqueConstraint(fields=["programme", "position"], name="uniq_rotation_position"),
            models.UniqueConstraint(fields=["programme", "participation"], name="uniq_rotation_participant"),
            models.CheckConstraint(condition=models.Q(position__gte=1), name="rotation_position_positive"),
        ]


class RotationCycle(AuditModel):
    """One turn of a rotational programme: collect, then pay one member.

    Status reflects reality: a cycle is only `ready_for_payout` once the money
    that was actually collected covers the payout. `expected` and `collected`
    are separate fields on purpose.
    """

    class Status(models.TextChoices):
        SCHEDULED = "scheduled", "Scheduled"
        COLLECTING = "collecting", "Collecting"
        READY_FOR_PAYOUT = "ready_for_payout", "Ready for payout"
        PAYOUT_PENDING_APPROVAL = "payout_pending_approval", "Payout awaiting approval"
        PAID = "paid", "Paid out"
        SHORTFALL = "shortfall", "Collected short of target"
        CANCELLED = "cancelled", "Cancelled"

    programme = models.ForeignKey(Programme, on_delete=models.CASCADE, related_name="cycles")
    sequence = models.PositiveSmallIntegerField()
    beneficiary = models.ForeignKey(
        Participation, null=True, blank=True, on_delete=models.PROTECT, related_name="payout_cycles"
    )
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.SCHEDULED, db_index=True)

    period_start = models.DateField()
    period_end = models.DateField()
    expected_total_minor = models.BigIntegerField(default=0, help_text="What the schedule says should arrive")
    collected_total_minor = models.BigIntegerField(default=0, help_text="Verified contributions only")
    payout_amount_minor = models.BigIntegerField(default=0)

    payout_approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="approved_cycles"
    )
    payout_approved_at = models.DateTimeField(null=True, blank=True)
    paid_at = models.DateTimeField(null=True, blank=True)
    ledger_reference = models.CharField(max_length=40, blank=True)

    class Meta:
        ordering = ("programme", "sequence")
        constraints = [
            models.UniqueConstraint(fields=["programme", "sequence"], name="uniq_cycle_sequence"),
            models.CheckConstraint(
                condition=models.Q(collected_total_minor__gte=0)
                & models.Q(expected_total_minor__gte=0)
                & models.Q(payout_amount_minor__gte=0),
                name="cycle_totals_non_negative",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.programme.name} cycle {self.sequence}"

    @property
    def shortfall_minor(self) -> int:
        return max(0, self.payout_amount_minor - self.collected_total_minor)


class Obligation(AuditModel):
    """One member's expected contribution for one period.

    Created ahead of time by a scheduled job. It is a *request for money*, and
    stays `pending` until a contribution is verified.
    """

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        PARTIALLY_PAID = "partially_paid", "Partially paid"
        SETTLED = "settled", "Settled"
        OVERDUE = "overdue", "Overdue"
        WAIVED = "waived", "Waived"
        CANCELLED = "cancelled", "Cancelled"

    programme = models.ForeignKey(Programme, on_delete=models.CASCADE, related_name="obligations")
    participation = models.ForeignKey(Participation, on_delete=models.CASCADE, related_name="obligations")
    cycle = models.ForeignKey(RotationCycle, null=True, blank=True, on_delete=models.SET_NULL, related_name="obligations")
    due_date = models.DateField(db_index=True)
    amount_minor = models.BigIntegerField()
    paid_minor = models.BigIntegerField(default=0)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING, db_index=True)
    reminded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("due_date",)
        constraints = [
            models.UniqueConstraint(fields=["programme", "participation", "due_date"], name="uniq_obligation_per_period"),
            models.CheckConstraint(condition=models.Q(amount_minor__gt=0), name="obligation_positive"),
            models.CheckConstraint(condition=models.Q(paid_minor__gte=0), name="obligation_paid_non_negative"),
            models.CheckConstraint(condition=models.Q(paid_minor__lte=models.F("amount_minor")), name="obligation_paid_within_due"),
        ]
        indexes = [
            models.Index(fields=["status", "due_date"]),
            models.Index(fields=["programme", "status"]),
        ]

    def __str__(self) -> str:
        return f"{self.participation_id} {self.amount_minor} due {self.due_date}"

    @property
    def outstanding_minor(self) -> int:
        return max(0, self.amount_minor - self.paid_minor)


class Contribution(AuditModel):
    """An attempt to satisfy an obligation, and its verified outcome.

    Only `confirmed`/`settled` count towards balances. The split between
    `processing` and `confirmed` is what stops "user came back from the payment
    screen" from being treated as payment.
    """

    class Status(models.TextChoices):
        INITIATED = "initiated", "Initiated"
        PENDING = "pending", "Pending"
        PROCESSING = "processing", "Processing"
        CONFIRMED = "confirmed", "Confirmed"
        SETTLED = "settled", "Settled"
        FAILED = "failed", "Failed"
        REVERSED = "reversed", "Reversed"
        REFUNDED = "refunded", "Refunded"

    class Source(models.TextChoices):
        MEMBER = "member", "Paid by a member"
        GROUP = "group", "Funded from group balance"
        OFFLINE = "offline", "Recorded by an officer"

    programme = models.ForeignKey(Programme, on_delete=models.PROTECT, related_name="contributions")
    obligation = models.ForeignKey(Obligation, null=True, blank=True, on_delete=models.SET_NULL, related_name="contributions")
    participation = models.ForeignKey(Participation, on_delete=models.PROTECT, related_name="contributions")
    payer = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="contributions")

    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.INITIATED, db_index=True)
    source = models.CharField(max_length=12, choices=Source.choices, default=Source.MEMBER)

    reference = models.CharField(max_length=40, unique=True)
    ledger_reference = models.CharField(max_length=40, blank=True)
    payment_intent = models.ForeignKey(
        "payments.PaymentIntent", null=True, blank=True, on_delete=models.SET_NULL, related_name="contributions"
    )
    confirmed_at = models.DateTimeField(null=True, blank=True)
    failure_reason = models.CharField(max_length=240, blank=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.CheckConstraint(condition=models.Q(amount_minor__gt=0), name="contribution_positive"),
            models.CheckConstraint(condition=models.Q(currency__regex=r"^[A-Z]{3}$"), name="contribution_currency_iso4217"),
        ]
        indexes = [
            models.Index(fields=["programme", "status"]),
            models.Index(fields=["participation", "-created_at"]),
            models.Index(fields=["payer", "-created_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.reference} {self.amount_minor} {self.status}"

    @property
    def counts_towards_balance(self) -> bool:
        return self.status in {self.Status.CONFIRMED, self.Status.SETTLED}


class WithdrawalRequest(AuditModel):
    """Money leaving a programme. Two officers, one beneficiary rule."""

    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        PENDING_APPROVAL = "pending_approval", "Awaiting approval"
        APPROVED = "approved", "Approved"
        PROCESSING = "processing", "Processing"
        PAID = "paid", "Paid"
        REJECTED = "rejected", "Rejected"
        CANCELLED = "cancelled", "Cancelled"
        FAILED = "failed", "Failed"

    class Reason(models.TextChoices):
        MEMBER_EXIT = "member_exit", "Member exit"
        PROGRAMME_GOAL_REACHED = "goal_reached", "Programme goal reached"
        EMERGENCY = "emergency", "Emergency"
        ROTATION_PAYOUT = "rotation_payout", "Rotation payout"
        LOAN_DISBURSEMENT = "loan_disbursement", "Loan disbursement"
        OTHER = "other", "Other"

    programme = models.ForeignKey(Programme, on_delete=models.PROTECT, related_name="withdrawals")
    beneficiary = models.ForeignKey(
        Participation, null=True, blank=True, on_delete=models.PROTECT, related_name="withdrawals"
    )
    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    reason = models.CharField(max_length=24, choices=Reason.choices, default=Reason.OTHER)
    note = models.CharField(max_length=500, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.DRAFT, db_index=True)

    requested_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="withdrawal_requests"
    )
    approvals = models.ManyToManyField(
        settings.AUTH_USER_MODEL, through="WithdrawalApproval", related_name="withdrawal_approvals_given"
    )
    reservation = models.ForeignKey(
        "ledger.FundReservation", null=True, blank=True, on_delete=models.SET_NULL, related_name="withdrawals"
    )
    disbursement = models.ForeignKey(
        "payments.Disbursement", null=True, blank=True, on_delete=models.SET_NULL, related_name="withdrawals"
    )
    ledger_reference = models.CharField(max_length=40, blank=True)
    executed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.CheckConstraint(condition=models.Q(amount_minor__gt=0), name="withdrawal_positive"),
            models.CheckConstraint(condition=models.Q(currency__regex=r"^[A-Z]{3}$"), name="withdrawal_currency_iso4217"),
        ]
        indexes = [models.Index(fields=["programme", "status"]), models.Index(fields=["status", "-created_at"])]

    def __str__(self) -> str:
        return f"withdrawal {self.amount_minor} {self.currency} ({self.status})"


class WithdrawalApproval(UUIDModel):
    """One officer's approval. A person approves a request at most once."""

    withdrawal = models.ForeignKey(WithdrawalRequest, on_delete=models.CASCADE, related_name="approval_records")
    approver = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    approved = models.BooleanField(default=True)
    comment = models.CharField(max_length=400, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["withdrawal", "approver"], name="uniq_withdrawal_approval")]


class FundraisingCampaign(AuditModel):
    """A public or private appeal for a defined purpose."""

    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        ACTIVE = "active", "Active"
        COMPLETED = "completed", "Completed"
        CLOSED = "closed", "Closed"
        CANCELLED = "cancelled", "Cancelled"

    group = models.ForeignKey("groups.Group", on_delete=models.CASCADE, related_name="campaigns")
    title = models.CharField(max_length=160)
    description = models.TextField(max_length=4000)
    beneficiary_name = models.CharField(max_length=160)
    beneficiary_note = models.CharField(max_length=500, blank=True)
    target_amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    deadline = models.DateField(null=True, blank=True)
    is_public = models.BooleanField(default=False)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.DRAFT, db_index=True)
    collected_minor = models.BigIntegerField(default=0, help_text="Denormalised for display; reconciles to the ledger")
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.CheckConstraint(condition=models.Q(target_amount_minor__gt=0), name="campaign_target_positive"),
            models.CheckConstraint(condition=models.Q(collected_minor__gte=0), name="campaign_collected_non_negative"),
        ]

    def __str__(self) -> str:
        return self.title


class ContributionTarget(AuditModel):
    """A personal or group target: 'save 500,000 by December'."""

    class Scope(models.TextChoices):
        MEMBER = "member", "Member"
        PROGRAMME = "programme", "Programme"

    scope = models.CharField(max_length=12, choices=Scope.choices)
    programme = models.ForeignKey(Programme, null=True, blank=True, on_delete=models.CASCADE, related_name="targets")
    participation = models.ForeignKey(Participation, null=True, blank=True, on_delete=models.CASCADE, related_name="targets")
    name = models.CharField(max_length=140)
    target_amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    target_date = models.DateField()
    achieved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [models.CheckConstraint(condition=models.Q(target_amount_minor__gt=0), name="target_positive")]
