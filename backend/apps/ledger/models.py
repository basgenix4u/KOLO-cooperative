"""Double-entry ledger — the financial source of truth.

Design decisions that matter:

* Every amount is an integer in minor units, scoped to exactly one currency.
  A journal transaction never spans currencies; FX is two transactions.
* Posted journal entries are immutable. Corrections are reversals, never edits.
* An account's balance is *derived* from its entries. There is no mutable
  `balance` column to drift, and nothing in Redis or the app is authoritative.
* `Account.balance` is cached and rebuilt from entries, guarded by a database
  constraint on entry count so a stale cache is detectable.
"""

from __future__ import annotations

from django.conf import settings
from django.db import models
from django.db.models import Q, Sum

from apps.common.models import AuditModel, UUIDModel


class AccountType(models.TextChoices):
    ASSET = "asset", "Asset"
    LIABILITY = "liability", "Liability"
    EQUITY = "equity", "Equity"
    INCOME = "income", "Income"
    EXPENSE = "expense", "Expense"


class AccountScope(models.TextChoices):
    """What the money in an account belongs to."""

    PLATFORM = "platform", "Platform"
    GROUP = "group", "Group"
    PROGRAMME = "programme", "Programme"
    MEMBER = "member", "Member"


class Account(UUIDModel):
    """One line in the chart of accounts.

    `scope_type` + `scope_id` say who owns it. A group's savings pool and a
    programme's ring-fenced fund are different accounts on purpose: consolidated
    group reporting must be able to read programme accounts without the parent's
    own account double-counting the same money.
    """

    code = models.CharField(max_length=40, db_index=True)
    name = models.CharField(max_length=120)
    type = models.CharField(max_length=16, choices=AccountType.choices, db_index=True)
    currency = models.CharField(max_length=3, db_index=True)

    scope_type = models.CharField(max_length=16, choices=AccountScope.choices, db_index=True)
    scope_id = models.UUIDField(null=True, blank=True, db_index=True)

    is_platform_account = models.BooleanField(default=False)
    # Money in a member-owned wallet can be withdrawn; programme pools are
    # spendable only through an approved withdrawal.
    is_withdrawable = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)

    # Cached projection of the entries. Rebuildable, never authoritative.
    cached_balance_minor = models.BigIntegerField(default=0)
    cached_entry_count = models.BigIntegerField(default=0)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("code",)
        constraints = [
            models.UniqueConstraint(
                fields=["code", "currency", "scope_type", "scope_id"],
                name="uniq_account_per_scope",
            ),
            models.CheckConstraint(
                condition=Q(currency__regex=r"^[A-Z]{3}$"), name="account_currency_iso4217"
            ),
            models.CheckConstraint(
                condition=(
                    Q(scope_type="platform", scope_id__isnull=True)
                    | (~Q(scope_type="platform") & Q(scope_id__isnull=False))
                ),
                name="account_scope_consistency",
            ),
        ]
        indexes = [models.Index(fields=["scope_type", "scope_id", "currency"])]

    def __str__(self) -> str:
        return f"{self.code} ({self.currency})"

    def balance_minor(self) -> int:
        """Live balance straight from the entries."""
        total = self.entries.aggregate(total=Sum("amount_minor"))["total"]
        return total or 0

    def refresh_cache(self) -> int:
        from django.db.models import Count

        agg = self.entries.aggregate(total=Sum("amount_minor"), count=Count("id"))
        self.cached_balance_minor = agg["total"] or 0
        self.cached_entry_count = agg["count"] or 0
        self.save(update_fields=["cached_balance_minor", "cached_entry_count"])
        return self.cached_balance_minor


class JournalTransaction(AuditModel):
    """The header of a balanced set of entries.

    Status:
      * `posted`   — final, immutable, affects balances.
      * `reversed` — superseded by a reversal transaction (kept for the trail).
      * `pending`  — created but not yet posted (e.g. awaiting provider confirm).
    """

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        POSTED = "posted", "Posted"
        REVERSED = "reversed", "Reversed"

    class Kind(models.TextChoices):
        CONTRIBUTION = "contribution", "Contribution"
        PAYOUT = "payout", "Payout"
        WITHDRAWAL = "withdrawal", "Withdrawal"
        TRANSFER = "transfer", "Transfer"
        LOAN_DISBURSEMENT = "loan_disbursement", "Loan disbursement"
        LOAN_REPAYMENT = "loan_repayment", "Loan repayment"
        DONATION = "donation", "Donation"
        FEE = "fee", "Fee"
        ADJUSTMENT = "adjustment", "Adjustment"
        REVERSAL = "reversal", "Reversal"

    reference = models.CharField(max_length=40, unique=True)
    kind = models.CharField(max_length=24, choices=Kind.choices, db_index=True)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.PENDING, db_index=True)
    currency = models.CharField(max_length=3, db_index=True)

    description = models.CharField(max_length=240, blank=True)
    memo = models.JSONField(default=dict, blank=True)

    # Linkage to the domain record that caused this posting.
    source_type = models.CharField(max_length=60, blank=True, db_index=True)
    source_id = models.CharField(max_length=64, blank=True, db_index=True)

    # Idempotency: two requests carrying the same external reference must not
    # post twice.
    external_reference = models.CharField(max_length=120, blank=True)
    idempotency_key = models.CharField(max_length=120, blank=True)

    posted_at = models.DateTimeField(null=True, blank=True, db_index=True)
    posted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="journal_postings"
    )
    reversal_of = models.OneToOneField(
        "self", null=True, blank=True, on_delete=models.PROTECT, related_name="reversed_by"
    )

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(
                fields=["idempotency_key"],
                condition=~Q(idempotency_key=""),
                name="uniq_journal_idempotency_key",
            ),
            models.UniqueConstraint(
                fields=["external_reference"],
                condition=~Q(external_reference=""),
                name="uniq_journal_external_reference",
            ),
            models.CheckConstraint(
                condition=Q(status__in=["pending", "posted", "reversed"]), name="journal_status_valid"
            ),
        ]

    def __str__(self) -> str:
        return f"{self.reference} [{self.status}]"

    def delete(self, *args, **kwargs):
        if self.status != self.Status.PENDING:
            raise ValueError("Posted journal transactions cannot be deleted; reverse them instead")
        return super().delete(*args, **kwargs)


class JournalEntry(models.Model):
    """One side of a transaction: a signed amount against one account.

    Positive = debit, negative = credit, in the account's own currency and
    sign convention. The sum of every entry in a transaction is always zero.
    """

    id = models.BigAutoField(primary_key=True)
    transaction = models.ForeignKey(JournalTransaction, on_delete=models.PROTECT, related_name="entries")
    account = models.ForeignKey(Account, on_delete=models.PROTECT, related_name="entries")
    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    memo = models.CharField(max_length=240, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("id",)
        constraints = [
            models.CheckConstraint(condition=~Q(amount_minor=0), name="entry_amount_non_zero"),
            models.CheckConstraint(
                condition=Q(currency__regex=r"^[A-Z]{3}$"), name="entry_currency_iso4217"
            ),
        ]
        indexes = [models.Index(fields=["account", "transaction"])]

    def __str__(self) -> str:
        return f"{self.account.code} {self.amount_minor:+d}"

    def save(self, *args, **kwargs):
        if not self._state.adding:
            raise ValueError("Journal entries are immutable once written")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError("Journal entries cannot be deleted; reverse the transaction instead")


class FundReservation(UUIDModel):
    """Money promised to an operation that has not settled yet.

    Withdrawals and payouts reserve funds so two concurrent requests cannot both
    pass an availability check and then both spend the same balance.
    """

    class Status(models.TextChoices):
        HELD = "held", "Held"
        CAPTURED = "captured", "Captured"
        RELEASED = "released", "Released"
        EXPIRED = "expired", "Expired"

    account = models.ForeignKey(Account, on_delete=models.PROTECT, related_name="reservations")
    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.HELD, db_index=True)
    reason = models.CharField(max_length=80)
    source_type = models.CharField(max_length=60, blank=True)
    source_id = models.CharField(max_length=64, blank=True, db_index=True)
    expires_at = models.DateTimeField(db_index=True)
    released_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.CheckConstraint(condition=Q(amount_minor__gt=0), name="reservation_positive"),
        ]
        indexes = [models.Index(fields=["account", "status"])]

    def __str__(self) -> str:
        return f"reserve {self.amount_minor} on {self.account.code} ({self.status})"
