"""Real concurrent access, against real PostgreSQL.

Every other test in this suite runs one thing at a time. The failure mode that
actually loses members' money is two operations racing: read the balance, both
decide there is enough, both write. These tests use real threads and real row
locks — they are the reason `lock_account` exists.
"""

from __future__ import annotations

import threading
from datetime import date, timedelta

import pytest
from django.db import connections, transaction
from django.utils import timezone

from apps.common.exceptions import InsufficientFundsError
from apps.ledger import services as ledger

pytestmark = pytest.mark.django_db(transaction=True)


def _run_concurrently(target, count=2):
    """Run `target` in `count` threads and collect (result, exception) pairs."""
    barrier = threading.Barrier(count)
    results: list = [None] * count
    errors: list = [None] * count

    def worker(index):
        try:
            barrier.wait(timeout=10)
            results[index] = target(index)
        except Exception as exc:  # noqa: BLE001 - the test asserts on these
            errors[index] = exc
        finally:
            # Each thread gets its own connection; leaking it keeps the lock.
            connections.close_all()

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(count)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=20)
    return results, errors


def _funded_account(group, amount=10_000):
    account = ledger.get_or_create_account(
        code="CONCURRENCY_TEST", name="Concurrency test", type="asset",
        currency="NGN", scope_type="group", scope_id=group.pk,
    )
    counterpart = ledger.get_or_create_account(
        code="CONCURRENCY_TEST_COUNTERPART", name="Counterpart", type="liability",
        currency="NGN", scope_type="group", scope_id=group.pk,
    )
    with transaction.atomic():
        ledger.post(
            kind="contribution", currency="NGN",
            legs=[ledger.Leg(account=account, amount_minor=amount),
                  ledger.Leg(account=counterpart, amount_minor=-amount)],
        )
    return account


def test_two_withdrawals_cannot_both_take_the_same_balance(group):
    """10,000 in the account, two 10,000 requests at the same instant."""
    account = _funded_account(group, 10_000)

    def take(_index):
        with transaction.atomic():
            return ledger.reserve(account, 10_000, reason="withdrawal", ttl_seconds=300)

    results, errors = _run_concurrently(take, count=2)
    successes = [r for r in results if r is not None]
    refusals = [e for e in errors if isinstance(e, InsufficientFundsError)]

    assert len(successes) == 1, f"exactly one reservation may succeed, got {len(successes)}"
    assert len(refusals) == 1, "the second attempt must be refused, not silently accepted"

    account.refresh_from_db()
    assert ledger.held_of(account) == 10_000, "the balance is not doubly promised"


def test_concurrent_postings_still_balance(group):
    """Parallel postings to the same pair of accounts must not lose an entry."""
    account = _funded_account(group, 1_000)
    counterpart = ledger.Account.objects.get(code="CONCURRENCY_TEST_COUNTERPART", scope_id=group.pk)

    def post_one(_index):
        with transaction.atomic():
            return ledger.post(
                kind="transfer", currency="NGN",
                legs=[ledger.Leg(account=account, amount_minor=100),
                      ledger.Leg(account=counterpart, amount_minor=-100)],
            )

    results, errors = _run_concurrently(post_one, count=4)
    assert all(e is None for e in errors), f"none of the postings should fail: {errors}"
    assert len({r.pk for r in results if r}) == 4

    account.refresh_from_db()
    counterpart.refresh_from_db()
    assert ledger.balance_of(account) == 1_400
    assert ledger.balance_of(counterpart) == -1_400
    assert ledger.balance_of(account) + ledger.balance_of(counterpart) == 0


def test_the_same_idempotency_key_across_threads_posts_once(group):
    """Two simultaneous retries of one provider callback."""
    account = _funded_account(group, 5_000)
    counterpart = ledger.Account.objects.get(code="CONCURRENCY_TEST_COUNTERPART", scope_id=group.pk)

    def post_once(_index):
        with transaction.atomic():
            return ledger.post(
                kind="contribution", currency="NGN", idempotency_key="race-key-1",
                legs=[ledger.Leg(account=account, amount_minor=500),
                      ledger.Leg(account=counterpart, amount_minor=-500)],
            )

    results, errors = _run_concurrently(post_once, count=2)
    references = {r.pk for r in results if r is not None}

    account.refresh_from_db()
    balance = ledger.balance_of(account)

    # Two acceptable outcomes: the loser's insertion tripped the unique
    # constraint (one committed transfer, one IntegrityError), or both saw the
    # row and shared it (also one transfer). What must never happen is two
    # transfers of 500.
    assert balance in {5_000, 5_500}, f"a replayed key must not double the money, got {balance}"
    assert len(references) <= 1, "one key means one transaction, even under a race"
