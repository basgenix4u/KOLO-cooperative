"""Ledger invariants. These are the tests that matter most: if any of them
fails, the product must not ship.
"""

from __future__ import annotations

import pytest
from django.db import transaction
from django.db.utils import IntegrityError

from apps.common.exceptions import FinancialSafetyError, InsufficientFundsError
from apps.groups.models import Group, Membership
from apps.ledger import services as ledger
from apps.ledger.models import Account, JournalTransaction

pytestmark = pytest.mark.django_db


def _account(currency="NGN", code="MEMBER_HOLDING", scope_type="member", scope_id=None):
    import uuid

    if scope_id is None:
        scope_id = uuid.uuid4()
    elif isinstance(scope_id, str):
        scope_id = uuid.uuid5(uuid.NAMESPACE_URL, scope_id)
    return ledger.get_or_create_account(
        code=code, name=code.title(), type="liability", currency=currency,
        scope_type=scope_type, scope_id=scope_id,
    )


def test_posting_that_does_not_balance_is_refused(group):
    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with pytest.raises(FinancialSafetyError) as caught:
        with transaction.atomic():
            ledger.post(
                kind="contribution", currency="NGN",
                legs=[ledger.Leg(account=a, amount_minor=1000), ledger.Leg(account=b, amount_minor=-999)],
            )
    assert caught.value.code == "ledger_unbalanced"
    assert caught.value.details["imbalance_minor"] == 1
    assert JournalTransaction.objects.count() == 0


def test_zero_leg_is_refused(group):
    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with pytest.raises(FinancialSafetyError) as caught:
        with transaction.atomic():
            ledger.post(kind="transfer", currency="NGN",
                        legs=[ledger.Leg(account=a, amount_minor=0), ledger.Leg(account=b, amount_minor=0)])
    assert caught.value.code == "ledger_zero_leg"


def test_currency_mismatch_is_refused(group):
    ngn = _account(currency="NGN", scope_id="a")
    usd = _account(currency="USD", scope_id="b")
    with pytest.raises(FinancialSafetyError) as caught:
        with transaction.atomic():
            ledger.post(kind="transfer", currency="NGN",
                        legs=[ledger.Leg(account=ngn, amount_minor=500), ledger.Leg(account=usd, amount_minor=-500)])
    assert caught.value.code == "ledger_currency_mismatch"


@pytest.mark.django_db(transaction=True)
def test_posting_outside_a_transaction_is_refused(group):
    """Without an enclosing atomic block the guard must refuse.

    Autocommit is the real condition here, so this test opts out of pytest's
    transaction wrapper rather than weakening the guard for tests.
    """
    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with pytest.raises(FinancialSafetyError) as caught:
        ledger.post(kind="transfer", currency="NGN",
                    legs=[ledger.Leg(account=a, amount_minor=100), ledger.Leg(account=b, amount_minor=-100)])
    assert caught.value.code == "ledger_no_transaction"


def test_balance_is_derived_from_entries(group):
    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with transaction.atomic():
        ledger.post(kind="contribution", currency="NGN",
                    legs=[ledger.Leg(account=a, amount_minor=2500), ledger.Leg(account=b, amount_minor=-2500)])
    a.refresh_from_db()
    assert ledger.balance_of(a) == 2500
    # The cached column must agree with the entries it summarises.
    assert a.cached_balance_minor == 2500


def test_idempotency_key_prevents_double_posting(group):
    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with transaction.atomic():
        first = ledger.post(kind="contribution", currency="NGN", idempotency_key="pay-123",
                            legs=[ledger.Leg(account=a, amount_minor=1000), ledger.Leg(account=b, amount_minor=-1000)])
        second = ledger.post(kind="contribution", currency="NGN", idempotency_key="pay-123",
                             legs=[ledger.Leg(account=a, amount_minor=1000), ledger.Leg(account=b, amount_minor=-1000)])
    assert first.pk == second.pk
    a.refresh_from_db()
    assert ledger.balance_of(a) == 1000, "a replayed webhook must not double the balance"


def test_entries_are_immutable(group):
    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with transaction.atomic():
        txn = ledger.post(kind="contribution", currency="NGN",
                          legs=[ledger.Leg(account=a, amount_minor=700), ledger.Leg(account=b, amount_minor=-700)])
    entry = txn.entries.first()
    entry.amount_minor = 999_999
    with pytest.raises(Exception):
        entry.save()


def test_reversal_is_a_new_equal_opposite_posting(group):
    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with transaction.atomic():
        txn = ledger.post(kind="contribution", currency="NGN",
                          legs=[ledger.Leg(account=a, amount_minor=5000), ledger.Leg(account=b, amount_minor=-5000)])
    reversal = ledger.reverse(txn, reason="provider refunded")

    txn.refresh_from_db()
    a.refresh_from_db()
    assert txn.status == JournalTransaction.Status.REVERSED
    assert reversal.kind == JournalTransaction.Kind.REVERSAL
    assert ledger.balance_of(a) == 0, "the pair nets to zero, the history stays"
    assert txn.entries.count() == 2, "the original's entries are untouched"

    with pytest.raises(FinancialSafetyError) as caught:
        ledger.reverse(txn, reason="again")
    assert caught.value.code == "ledger_not_reversible"


def test_availability_subtracts_held_funds(group):
    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with transaction.atomic():
        ledger.post(kind="contribution", currency="NGN",
                    legs=[ledger.Leg(account=a, amount_minor=10_000), ledger.Leg(account=b, amount_minor=-10_000)])
    reservation = ledger.reserve(a, 4_000, reason="payout", ttl_seconds=600)
    a.refresh_from_db()
    assert ledger.balance_of(a) == 10_000
    assert ledger.held_of(a) == 4_000
    assert ledger.available_of(a) == 6_000

    ledger.capture_reservation(reservation)
    a.refresh_from_db()
    assert ledger.held_of(a) == 0
    assert ledger.available_of(a) == 10_000


def test_reservation_beyond_availability_is_refused(group):
    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with transaction.atomic():
        ledger.post(kind="contribution", currency="NGN",
                    legs=[ledger.Leg(account=a, amount_minor=3_000), ledger.Leg(account=b, amount_minor=-3_000)])
    with pytest.raises(InsufficientFundsError) as caught:
        ledger.reserve(a, 3_001, reason="payout")
    assert caught.value.code == "insufficient_funds"
    assert caught.value.details["available_minor"] == 3_000


def test_two_reservations_cannot_both_take_the_same_money(group):
    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with transaction.atomic():
        ledger.post(kind="contribution", currency="NGN",
                    legs=[ledger.Leg(account=a, amount_minor=5_000), ledger.Leg(account=b, amount_minor=-5_000)])

    ledger.reserve(a, 5_000, reason="first payout")
    with pytest.raises(InsufficientFundsError):
        ledger.reserve(a, 5_000, reason="second payout")
    a.refresh_from_db()
    assert ledger.held_of(a) == 5_000, "the second hold must not exist"


def test_expired_reservations_return_to_availability(group):
    from datetime import timedelta

    from django.utils import timezone

    a = _account(scope_id="a")
    b = _account(scope_id="b")
    with transaction.atomic():
        ledger.post(kind="contribution", currency="NGN",
                    legs=[ledger.Leg(account=a, amount_minor=2_000), ledger.Leg(account=b, amount_minor=-2_000)])
    reservation = ledger.reserve(a, 2_000, reason="pending", ttl_seconds=1)
    reservation.expires_at = timezone.now() - timedelta(seconds=5)
    reservation.save(update_fields=["expires_at"])

    a.refresh_from_db()
    assert ledger.held_of(a) == 0, "an expired hold no longer reserves anything"
    assert ledger.expire_reservations() == 1


def test_account_permissions_are_scoped_by_uniqueness(group):
    """Two calls for the same scope must resolve to one account, not two."""
    first = _account(scope_id="scope-1")
    second = _account(scope_id="scope-1")
    assert first.pk == second.pk
    assert Account.objects.filter(scope_id=first.scope_id).count() == 1
