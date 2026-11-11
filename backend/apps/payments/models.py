"""Payment intents, provider transactions, webhooks and reconciliation.

Two invariants:

1. A `PaymentIntent` in `processing` is not money. Only a server-verified
   provider result moves it to `succeeded`.
2. Every webhook is recorded before it is acted on, keyed by a provider event
   id, so a replayed delivery cannot cause a second credit.
"""

from __future__ import annotations

from django.conf import settings
from django.db import models

from apps.common.models import AuditModel, UUIDModel


class PaymentIntent(AuditModel):
    """What the member is paying for, and the state of that attempt."""

    class Status(models.TextChoices):
        CREATED = "created", "Created"
        AWAITING_PAYMENT = "awaiting_payment", "Awaiting payment"
        PROCESSING = "processing", "Processing with provider"
        SUCCEEDED = "succeeded", "Succeeded"
        FAILED = "failed", "Failed"
        CANCELLED = "cancelled", "Cancelled"
        EXPIRED = "expired", "Expired"
        REVERSED = "reversed", "Reversed"
        REFUNDED = "refunded", "Refunded"

    class Purpose(models.TextChoices):
        CONTRIBUTION = "contribution", "Savings contribution"
        DONATION = "donation", "Campaign donation"
        LOAN_REPAYMENT = "loan_repayment", "Loan repayment"
        WALLET_TOPUP = "wallet_topup", "Wallet top-up"

    reference = models.CharField(max_length=40, unique=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="payment_intents")
    purpose = models.CharField(max_length=20, choices=Purpose.choices, db_index=True)
    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.CREATED, db_index=True)

    provider = models.CharField(max_length=30)
    provider_reference = models.CharField(max_length=120, blank=True, db_index=True)
    # Client-supplied idempotency key: pressing "pay" twice must not create two
    # intents, and a retried request must return the original.
    idempotency_key = models.CharField(max_length=120, blank=True)
    checkout_url = models.URLField(blank=True)

    # The domain object this pays for.
    source_type = models.CharField(max_length=40, blank=True)
    source_id = models.CharField(max_length=64, blank=True, db_index=True)

    expires_at = models.DateTimeField(null=True, blank=True)
    confirmed_at = models.DateTimeField(null=True, blank=True)
    failure_code = models.CharField(max_length=60, blank=True)
    failure_message = models.CharField(max_length=300, blank=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.CheckConstraint(condition=models.Q(amount_minor__gt=0), name="intent_amount_positive"),
            models.CheckConstraint(condition=models.Q(currency__regex=r"^[A-Z]{3}$"), name="intent_currency_iso4217"),
            models.UniqueConstraint(
                fields=["user", "idempotency_key"], condition=~models.Q(idempotency_key=""),
                name="uniq_intent_idempotency_per_user",
            ),
        ]
        indexes = [models.Index(fields=["status", "-created_at"]), models.Index(fields=["source_type", "source_id"])]

    def __str__(self) -> str:
        return f"{self.reference} {self.amount_minor} {self.currency} [{self.status}]"

    @property
    def is_settled(self) -> bool:
        return self.status == self.Status.SUCCEEDED


class ProviderTransaction(UUIDModel):
    """What the provider says happened — kept verbatim for reconciliation."""

    provider = models.CharField(max_length=30, db_index=True)
    provider_reference = models.CharField(max_length=120, db_index=True)
    intent = models.ForeignKey(PaymentIntent, null=True, blank=True, on_delete=models.SET_NULL, related_name="transactions")
    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    status = models.CharField(max_length=30, db_index=True)
    raw_payload = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(fields=["provider", "provider_reference"], name="uniq_provider_txn_reference"),
        ]


class WebhookEvent(UUIDModel):
    """Every inbound webhook, recorded before processing.

    `unique(provider, event_id)` is the replay guard: a duplicate delivery hits
    the constraint, not the business logic.
    """

    class Status(models.TextChoices):
        RECEIVED = "received", "Received"
        PROCESSED = "processed", "Processed"
        IGNORED = "ignored", "Ignored (duplicate or irrelevant)"
        FAILED = "failed", "Failed"

    provider = models.CharField(max_length=30, db_index=True)
    event_id = models.CharField(max_length=160)
    event_type = models.CharField(max_length=80, blank=True)
    signature_valid = models.BooleanField(default=False)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.RECEIVED, db_index=True)
    payload = models.JSONField(default=dict)
    error = models.CharField(max_length=400, blank=True)
    processed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [models.UniqueConstraint(fields=["provider", "event_id"], name="uniq_webhook_event")]
        indexes = [models.Index(fields=["provider", "status"])]


class Disbursement(AuditModel):
    """Money leaving KOLO for a member's bank or wallet.

    Kept separate from `WithdrawalRequest`: the request is a decision, the
    disbursement is an attempt to move funds with a provider, and they fail
    independently.
    """

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        QUEUED = "queued", "Queued with provider"
        PROCESSING = "processing", "Processing"
        COMPLETED = "completed", "Completed"
        FAILED = "failed", "Failed"
        REVERSED = "reversed", "Reversed"

    reference = models.CharField(max_length=40, unique=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="disbursements")
    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.PENDING, db_index=True)

    provider = models.CharField(max_length=30)
    provider_reference = models.CharField(max_length=120, blank=True, db_index=True)
    destination_bank_code = models.CharField(max_length=20, blank=True)
    destination_account_number = models.CharField(max_length=34, blank=True)
    destination_account_name = models.CharField(max_length=120, blank=True)

    failure_code = models.CharField(max_length=60, blank=True)
    failure_message = models.CharField(max_length=300, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.CheckConstraint(condition=models.Q(amount_minor__gt=0), name="disbursement_positive"),
            models.CheckConstraint(condition=models.Q(currency__regex=r"^[A-Z]{3}$"), name="disbursement_currency_iso4217"),
        ]
        indexes = [models.Index(fields=["status", "-created_at"])]

    def __str__(self) -> str:
        return f"{self.reference} {self.amount_minor} {self.currency} [{self.status}]"


class ReconciliationRun(AuditModel):
    """A comparison of our records with a provider's, and what disagreed."""

    class Status(models.TextChoices):
        RUNNING = "running", "Running"
        COMPLETED = "completed", "Completed"
        FAILED = "failed", "Failed"

    provider = models.CharField(max_length=30)
    currency = models.CharField(max_length=3)
    period_start = models.DateField()
    period_end = models.DateField()
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.RUNNING, db_index=True)
    matched_count = models.PositiveIntegerField(default=0)
    mismatch_count = models.PositiveIntegerField(default=0)
    missing_count = models.PositiveIntegerField(default=0)
    notes = models.TextField(blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)


class ReconciliationItem(UUIDModel):
    """One disagreement. Never auto-corrected — a human decides."""

    class Kind(models.TextChoices):
        AMOUNT_MISMATCH = "amount_mismatch", "Amount mismatch"
        MISSING_INTERNAL = "missing_internal", "Provider has it, we do not"
        MISSING_PROVIDER = "missing_provider", "We have it, provider does not"
        DUPLICATE = "duplicate", "Duplicate"
        DELAYED = "delayed", "Delayed settlement"
        FAILED_DISBURSEMENT = "failed_disbursement", "Failed disbursement"
        UNMATCHED_REVERSAL = "unmatched_reversal", "Unmatched reversal"

    class Resolution(models.TextChoices):
        OPEN = "open", "Open"
        ACCEPTED = "accepted", "Accepted as correct"
        INVESTIGATING = "investigating", "Investigating"
        RESOLVED = "resolved", "Resolved"

    run = models.ForeignKey(ReconciliationRun, on_delete=models.CASCADE, related_name="items")
    kind = models.CharField(max_length=24, choices=Kind.choices)
    provider_reference = models.CharField(max_length=120, blank=True, db_index=True)
    internal_reference = models.CharField(max_length=120, blank=True)
    internal_amount_minor = models.BigIntegerField(null=True, blank=True)
    provider_amount_minor = models.BigIntegerField(null=True, blank=True)
    currency = models.CharField(max_length=3, blank=True)
    detail = models.CharField(max_length=400, blank=True)
    resolution = models.CharField(max_length=16, choices=Resolution.choices, default=Resolution.OPEN, db_index=True)
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL
    )
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("kind", "provider_reference")
