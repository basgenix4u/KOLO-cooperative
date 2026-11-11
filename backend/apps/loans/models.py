"""Loans: cooperative-funded, and member-to-member under agreed rules.

Activation guard: disbursement is refused unless the deployment is marked
production *and* an operator has explicitly enabled lending, because lending is
a regulated activity that needs a partner agreement behind it.
"""

from __future__ import annotations

from django.conf import settings
from django.db import models

from apps.common.models import AuditModel, UUIDModel


class LoanProduct(AuditModel):
    """Terms a group offers. Rates are configuration, never hard-coded."""

    class Category(models.TextChoices):
        COOPERATIVE = "cooperative", "Cooperative-funded"
        MEMBER_TO_MEMBER = "member_to_member", "Member to member"

    group = models.ForeignKey("groups.Group", on_delete=models.CASCADE, related_name="loan_products")
    name = models.CharField(max_length=140)
    category = models.CharField(max_length=20, choices=Category.choices, default=Category.COOPERATIVE)
    currency = models.CharField(max_length=3)
    min_amount_minor = models.BigIntegerField()
    max_amount_minor = models.BigIntegerField()
    # Basis points per annum, e.g. 1200 = 12%. Integer, so no float drift.
    interest_bps = models.PositiveIntegerField(default=0)
    term_months_min = models.PositiveSmallIntegerField(default=1)
    term_months_max = models.PositiveSmallIntegerField(default=12)
    requires_guarantors = models.PositiveSmallIntegerField(default=0)
    requires_member_vote = models.BooleanField(default=False)
    min_membership_days = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ("name",)
        constraints = [
            models.CheckConstraint(condition=models.Q(max_amount_minor__gte=models.F("min_amount_minor")),
                                   name="loan_product_amount_range"),
            models.CheckConstraint(condition=models.Q(interest_bps__lte=10000), name="loan_interest_sane"),
        ]

    def __str__(self) -> str:
        return f"{self.name} ({self.group.name})"


class LoanApplication(AuditModel):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        SUBMITTED = "submitted", "Submitted"
        UNDER_REVIEW = "under_review", "Under review"
        AWAITING_VOTE = "awaiting_vote", "Awaiting member vote"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"
        WITHDRAWN = "withdrawn", "Withdrawn"
        DISBURSED = "disbursed", "Disbursed"

    product = models.ForeignKey(LoanProduct, on_delete=models.PROTECT, related_name="applications")
    borrower = models.ForeignKey("groups.Membership", on_delete=models.PROTECT, related_name="loan_applications")
    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    term_months = models.PositiveSmallIntegerField()
    purpose = models.CharField(max_length=300)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.DRAFT, db_index=True)
    submitted_at = models.DateTimeField(null=True, blank=True)
    decided_at = models.DateTimeField(null=True, blank=True)
    decided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL)
    decision_note = models.CharField(max_length=500, blank=True)
    risk_flags = models.JSONField(default=list, blank=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.CheckConstraint(condition=models.Q(amount_minor__gt=0), name="loan_application_positive"),
        ]
        indexes = [models.Index(fields=["status", "-created_at"])]

    def __str__(self) -> str:
        return f"application {self.amount_minor} {self.currency} [{self.status}]"


class Guarantor(UUIDModel):
    """A member standing behind a loan. Must agree; silence is not consent."""

    class Status(models.TextChoices):
        INVITED = "invited", "Invited"
        ACCEPTED = "accepted", "Accepted"
        DECLINED = "declined", "Declined"

    application = models.ForeignKey(LoanApplication, on_delete=models.CASCADE, related_name="guarantors")
    membership = models.ForeignKey("groups.Membership", on_delete=models.CASCADE, related_name="guarantees")
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.INVITED, db_index=True)
    responded_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["application", "membership"], name="uniq_guarantor_per_loan")]


class Loan(AuditModel):
    class Status(models.TextChoices):
        PENDING_DISBURSEMENT = "pending_disbursement", "Approved, awaiting disbursement"
        ACTIVE = "active", "Active"
        OVERDUE = "overdue", "Overdue"
        REPAID = "repaid", "Fully repaid"
        DEFAULTED = "defaulted", "Defaulted"
        CANCELLED = "cancelled", "Cancelled"

    application = models.OneToOneField(LoanApplication, on_delete=models.PROTECT, related_name="loan")
    reference = models.CharField(max_length=40, unique=True)
    group = models.ForeignKey("groups.Group", on_delete=models.PROTECT, related_name="loans")
    borrower = models.ForeignKey("groups.Membership", on_delete=models.PROTECT, related_name="loans")
    principal_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    interest_bps = models.PositiveIntegerField()
    term_months = models.PositiveSmallIntegerField()
    total_repayable_minor = models.BigIntegerField()
    outstanding_minor = models.BigIntegerField()
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.PENDING_DISBURSEMENT, db_index=True)
    disbursed_at = models.DateTimeField(null=True, blank=True)
    due_date = models.DateField(null=True, blank=True)
    ledger_reference = models.CharField(max_length=40, blank=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.CheckConstraint(condition=models.Q(principal_minor__gt=0), name="loan_principal_positive"),
            models.CheckConstraint(condition=models.Q(outstanding_minor__gte=0), name="loan_outstanding_non_negative"),
        ]
        indexes = [models.Index(fields=["group", "status"]), models.Index(fields=["borrower", "status"])]

    def __str__(self) -> str:
        return f"{self.reference} [{self.status}]"


class RepaymentSchedule(UUIDModel):
    installment_no = models.PositiveSmallIntegerField()
    loan = models.ForeignKey(Loan, on_delete=models.CASCADE, related_name="schedule")
    due_date = models.DateField(db_index=True)
    amount_minor = models.BigIntegerField()
    principal_minor = models.BigIntegerField()
    interest_minor = models.BigIntegerField()
    paid_minor = models.BigIntegerField(default=0)
    paid_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("loan", "installment_no")
        constraints = [
            models.UniqueConstraint(fields=["loan", "installment_no"], name="uniq_installment_no"),
            models.CheckConstraint(condition=models.Q(paid_minor__lte=models.F("amount_minor")),
                                   name="installment_paid_within_due"),
        ]

    @property
    def is_overdue(self):
        from django.utils import timezone

        return self.paid_minor < self.amount_minor and self.due_date < timezone.localdate()


class Repayment(AuditModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        PROCESSING = "processing", "Processing"
        SETTLED = "settled", "Settled"
        FAILED = "failed", "Failed"

    loan = models.ForeignKey(Loan, on_delete=models.PROTECT, related_name="repayments")
    schedule_item = models.ForeignKey(RepaymentSchedule, null=True, blank=True, on_delete=models.SET_NULL,
                                      related_name="repayments")
    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.PENDING, db_index=True)
    reference = models.CharField(max_length=40, unique=True)
    payment_intent = models.ForeignKey("payments.PaymentIntent", null=True, blank=True, on_delete=models.SET_NULL)
    ledger_reference = models.CharField(max_length=40, blank=True)
    paid_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [models.CheckConstraint(condition=models.Q(amount_minor__gt=0), name="repayment_positive")]


class LoanVote(UUIDModel):
    """A member's vote on a loan application. One vote each, enforced by constraint."""

    application = models.ForeignKey(LoanApplication, on_delete=models.CASCADE, related_name="votes")
    membership = models.ForeignKey("groups.Membership", on_delete=models.CASCADE, related_name="loan_votes")
    in_favour = models.BooleanField()
    comment = models.CharField(max_length=300, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["application", "membership"], name="uniq_loan_vote")]
