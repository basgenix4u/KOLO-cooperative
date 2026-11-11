"""The only sanctioned way to move money.

Everything here runs inside a database transaction and takes a lock before it
reads a balance, because the alternative — read, check, write — is how two
simultaneous withdrawals both succeed against one balance.

Rules enforced:
  1. A posting must balance to exactly zero, per currency.
  2. An account is used only in its own currency.
  3. Posted transactions never change. Corrections are reversals.
  4. Availability = balance − held reservations, computed under lock.
"""

from __future__ import annotations

import logging
import secrets
from dataclasses import dataclass
from datetime import timedelta
from typing import Iterable, Sequence

from django.db import transaction as db_transaction
from django.db.models import Sum
from django.utils import timezone

from apps.common.exceptions import FinancialSafetyError, InsufficientFundsError

from .models import Account, AccountScope, AccountType, FundReservation, JournalEntry, JournalTransaction

logger = logging.getLogger("kolo.audit")


@dataclass(frozen=True)
class Leg:
    """One side of a posting. Positive debits, negative credits."""

    account: Account
    amount_minor: int
    memo: str = ""


class LedgerError(FinancialSafetyError):
    default_code = "ledger_error"


def new_reference(prefix: str = "JNL") -> str:
    """Human-quotable reference. Not a security token, just an identifier."""
    stamp = timezone.now().strftime("%Y%m%d")
    return f"{prefix}-{stamp}-{secrets.token_hex(4).upper()}"


def balance_of(account: Account) -> int:
    total = account.entries.aggregate(total=Sum("amount_minor"))["total"]
    return total or 0


def held_of(account: Account, *, at=None) -> int:
    """Funds promised to unsettled operations."""
    at = at or timezone.now()
    total = account.reservations.filter(
        status=FundReservation.Status.HELD, expires_at__gt=at
    ).aggregate(total=Sum("amount_minor"))["total"]
    return total or 0


def available_of(account: Account, *, at=None) -> int:
    return balance_of(account) - held_of(account, at=at)


def natural_balance(account: Account) -> int:
    """The balance as a person would say it out loud.

    The ledger stores everything double-entry style — positive debits, negative
    credits — so an asset (a pool, a bank account) reads positive and a
    liability (what we owe a member) reads negative. Correct for accounting,
    confusing in a member's statement: "your balance is -40,000" is not a
    sentence anyone should read. This flips the sign for credit-normal accounts
    and leaves the underlying entries untouched.
    """
    raw = balance_of(account)
    credit_normal = {AccountType.LIABILITY, AccountType.EQUITY, AccountType.INCOME}
    return -raw if account.type in credit_normal else raw


def lock_account(account_id) -> Account:
    """Fetch an account FOR UPDATE.

    Every money path calls this first. The row lock serialises concurrent
    operations on the same account, which is what makes the availability check
    immediately below trustworthy.
    """
    return Account.objects.select_for_update().get(pk=account_id)


def lock_accounts(accounts: Iterable[Account]) -> dict:
    """Lock several accounts in a stable order to avoid deadlocks.

    Sorting by primary key means two concurrent postings that touch the same
    pair of accounts always acquire locks in the same sequence.
    """
    ids = sorted({a.pk for a in accounts}, key=str)
    locked = Account.objects.select_for_update().filter(pk__in=ids)
    return {a.pk: a for a in locked}


def post(
    *,
    kind: str,
    legs: Sequence[Leg],
    currency: str,
    description: str = "",
    source_type: str = "",
    source_id: str = "",
    external_reference: str = "",
    idempotency_key: str = "",
    memo: dict | None = None,
    posted_by=None,
    reference: str | None = None,
) -> JournalTransaction:
    """Post a balanced set of entries. Must be called inside a transaction.

    Returns the existing transaction when `idempotency_key` or
    `external_reference` has been seen before, which is what makes retries safe.
    """
    if not db_transaction.get_connection().in_atomic_block:
        raise LedgerError(
            "post() must run inside transaction.atomic() so the balance check and the write commit together",
            code="ledger_no_transaction",
        )

    if idempotency_key:
        existing = JournalTransaction.objects.filter(
            idempotency_key=idempotency_key, status__in=["pending", "posted"]
        ).first()
        if existing:
            return existing
    if external_reference:
        existing = JournalTransaction.objects.filter(
            external_reference=external_reference, status__in=["pending", "posted"]
        ).first()
        if existing:
            return existing

    if not legs:
        raise LedgerError("a posting needs at least two legs", code="ledger_empty")
    for leg in legs:
        if leg.amount_minor == 0:
            raise LedgerError("a leg cannot be zero", code="ledger_zero_leg")
        if leg.account.currency.upper() != currency.upper():
            raise LedgerError(
                f"account {leg.account.code} is {leg.account.currency}, posting is {currency}",
                code="ledger_currency_mismatch",
            )

    total = sum(leg.amount_minor for leg in legs)
    if total != 0:
        raise LedgerError(
            f"posting does not balance: legs sum to {total} in {currency}",
            code="ledger_unbalanced",
            details={"imbalance_minor": total, "currency": currency},
        )

    # Lock every account touched, in a deterministic order, before writing.
    locked = lock_accounts(leg.account for leg in legs)

    txn = JournalTransaction.objects.create(
        reference=reference or new_reference(),
        kind=kind,
        currency=currency.upper(),
        description=description[:240],
        source_type=source_type,
        source_id=str(source_id or ""),
        external_reference=external_reference,
        idempotency_key=idempotency_key,
        memo=memo or {},
        posted_by=posted_by if getattr(posted_by, "pk", None) else None,
    )

    JournalEntry.objects.bulk_create(
        [
            JournalEntry(
                transaction=txn,
                account=locked[leg.account.pk],
                amount_minor=leg.amount_minor,
                currency=currency.upper(),
                memo=leg.memo[:240],
            )
            for leg in legs
        ]
    )

    txn.status = JournalTransaction.Status.POSTED
    txn.posted_at = timezone.now()
    txn.save(update_fields=["status", "posted_at"])

    for leg in legs:
        locked[leg.account.pk].refresh_cache()

    logger.info(
        '{"event":"ledger_posted","reference":"%s","kind":"%s","currency":"%s","amount_minor":%d,"source":"%s:%s"}',
        txn.reference,
        kind,
        currency,
        abs(legs[0].amount_minor),
        source_type,
        source_id,
    )
    return txn


def reverse(
    original: JournalTransaction, *, reason: str, posted_by=None, reference: str | None = None
) -> JournalTransaction:
    """Undo a posted transaction with an equal and opposite one.

    Never deletes or edits: the original stays, its entries stay, and the pair
    tells the true story.
    """
    if original.status != JournalTransaction.Status.POSTED:
        raise LedgerError("only a posted transaction can be reversed", code="ledger_not_reversible")
    if hasattr(original, "reversed_by"):
        raise LedgerError("this transaction was already reversed", code="ledger_already_reversed")

    with db_transaction.atomic():
        original = JournalTransaction.objects.select_for_update().get(pk=original.pk)
        if original.status != JournalTransaction.Status.POSTED:
            raise LedgerError("only a posted transaction can be reversed", code="ledger_not_reversible")

        entries = list(original.entries.select_related("account"))
        legs = [Leg(account=e.account, amount_minor=-e.amount_minor, memo=f"reversal: {reason}"[:240]) for e in entries]
        txn = post(
            kind=JournalTransaction.Kind.REVERSAL,
            legs=legs,
            currency=original.currency,
            description=f"Reversal of {original.reference}: {reason}"[:240],
            source_type=original.source_type,
            source_id=original.source_id,
            memo={"reversal_of": str(original.pk), "reason": reason},
            posted_by=posted_by,
            reference=reference,
        )
        txn.reversal_of = original
        txn.save(update_fields=["reversal_of"])
        original.status = JournalTransaction.Status.REVERSED
        original.save(update_fields=["status"])

    logger.warning('{"event":"ledger_reversed","original":"%s","reversal":"%s","reason":%r}',
                   original.reference, txn.reference, reason)
    return txn


def reserve(
    account: Account, amount_minor: int, *, reason: str, source_type: str = "", source_id: str = "", ttl_seconds: int = 900
) -> FundReservation:
    """Hold funds for a pending operation. Fails if availability is short."""
    if amount_minor <= 0:
        raise LedgerError("reservation must be positive", code="reservation_invalid")
    with db_transaction.atomic():
        locked = lock_account(account.pk)
        available = available_of(locked)
        if available < amount_minor:
            raise InsufficientFundsError(
                details={"available_minor": available, "required_minor": amount_minor, "currency": locked.currency}
            )
        return FundReservation.objects.create(
            account=locked,
            amount_minor=amount_minor,
            currency=locked.currency,
            reason=reason[:80],
            source_type=source_type,
            source_id=str(source_id or ""),
            expires_at=timezone.now() + timedelta(seconds=ttl_seconds),
        )


def capture_reservation(reservation: FundReservation) -> None:
    """The operation settled; the hold is consumed by the posting itself."""
    FundReservation.objects.filter(pk=reservation.pk, status=FundReservation.Status.HELD).update(
        status=FundReservation.Status.CAPTURED, released_at=timezone.now()
    )


def release_reservation(reservation: FundReservation, *, reason: str = "") -> None:
    FundReservation.objects.filter(pk=reservation.pk, status=FundReservation.Status.HELD).update(
        status=FundReservation.Status.RELEASED, released_at=timezone.now()
    )
    logger.info('{"event":"reservation_released","id":"%s","reason":%r}', reservation.pk, reason)


def expire_reservations() -> int:
    """Release holds whose operation never happened."""
    return FundReservation.objects.filter(
        status=FundReservation.Status.HELD, expires_at__lte=timezone.now()
    ).update(status=FundReservation.Status.EXPIRED, released_at=timezone.now())


# ---------------------------------------------------------------------------
# Chart of accounts helpers
# ---------------------------------------------------------------------------

def get_or_create_account(
    *,
    code: str,
    name: str,
    type: str,
    currency: str,
    scope_type: str,
    scope_id=None,
    is_withdrawable: bool = False,
    is_platform_account: bool = False,
) -> Account:
    """Idempotent account creation.

    Safe to call from any code path: the unique constraint decides, so two
    concurrent first-contributions cannot create two pools for one programme.
    """
    account, _ = Account.objects.get_or_create(
        code=code,
        currency=currency.upper(),
        scope_type=scope_type,
        scope_id=scope_id,
        defaults={
            "name": name,
            "type": type,
            "is_withdrawable": is_withdrawable,
            "is_platform_account": is_platform_account,
        },
    )
    return account


def programme_pool(programme) -> Account:
    """The ring-fenced account a programme's contributions land in."""
    return get_or_create_account(
        code="PROGRAMME_POOL",
        name=f"{programme.name} pool",
        type=AccountType.ASSET,
        currency=programme.currency,
        scope_type=AccountScope.PROGRAMME,
        scope_id=programme.pk,
    )


def programme_liability(programme) -> Account:
    """What the programme owes its members — the mirror of the pool."""
    return get_or_create_account(
        code="PROGRAMME_MEMBER_FUNDS",
        name=f"{programme.name} member funds",
        type=AccountType.LIABILITY,
        currency=programme.currency,
        scope_type=AccountScope.PROGRAMME,
        scope_id=programme.pk,
    )


def member_holding(group, member, currency: str) -> Account:
    """A member's balance inside one group.

    Accepts a Membership or a membership id: callers legitimately have one or
    the other, and silently assuming a model instance turned into an
    AttributeError on the overpayment path.
    """
    membership_id = getattr(member, "pk", member)
    return get_or_create_account(
        code="MEMBER_HOLDING",
        name="Member holding",
        type=AccountType.LIABILITY,
        currency=currency,
        scope_type=AccountScope.MEMBER,
        scope_id=membership_id,
    )


def group_pool(group) -> Account:
    return get_or_create_account(
        code="GROUP_POOL",
        name=f"{group.name} pool",
        type=AccountType.ASSET,
        currency=group.currency,
        scope_type=AccountScope.GROUP,
        scope_id=group.pk,
    )


def group_loan_receivable(group) -> Account:
    """Money the group has lent out and expects back.

    Without this account a disbursement looks like the pool simply shrank, and a
    repayment looks like money appeared from nowhere. Lending needs both sides.
    """
    return get_or_create_account(
        code="LOAN_RECEIVABLE",
        name=f"{group.name} loans receivable",
        type=AccountType.ASSET,
        currency=group.currency,
        scope_type=AccountScope.GROUP,
        scope_id=group.pk,
    )


def interest_income(currency: str) -> Account:
    """Interest the group has earned. Income is credit-normal."""
    return platform_account("INTEREST_INCOME", "Interest income", AccountType.INCOME, currency)


def platform_account(code: str, name: str, type: str, currency: str) -> Account:
    return get_or_create_account(
        code=code,
        name=name,
        type=type,
        currency=currency,
        scope_type=AccountScope.PLATFORM,
        scope_id=None,
        is_platform_account=True,
    )


def provider_settlement(currency: str) -> Account:
    """Money received from a payment provider but not yet swept to its owner."""
    return platform_account("PROVIDER_SETTLEMENT", "Provider settlement", AccountType.ASSET, currency)


def provider_payable(currency: str) -> Account:
    """The counterpart liability while funds sit in settlement."""
    return platform_account("PROVIDER_PAYABLE", "Provider payable", AccountType.LIABILITY, currency)


def platform_revenue(currency: str) -> Account:
    return platform_account("PLATFORM_REVENUE", "Platform fees", AccountType.INCOME, currency)


def platform_expense(currency: str) -> Account:
    return platform_account("PLATFORM_EXPENSE", "Platform costs", AccountType.EXPENSE, currency)
