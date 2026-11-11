"""Payments: the webhook is the only thing that makes money real.

Webhooks are unauthenticated, retried, and replayed by providers by design. The
tests below are what stops a replayed callback from crediting an account twice,
and a forged one from crediting it at all.
"""

from __future__ import annotations

import hashlib
import hmac
import json

import pytest
from django.conf import settings

from apps.common.exceptions import ConflictError
from apps.ledger import services as ledger
from apps.payments import services
from apps.payments.models import PaymentIntent, WebhookEvent
from apps.payments.providers import store

pytestmark = pytest.mark.django_db


@pytest.fixture(autouse=True)
def _clean_mock_store(tmp_path, monkeypatch):
    """Each test gets its own provider-side state file."""
    monkeypatch.setenv("MOCK_PROVIDER_STATE", str(tmp_path / "mock_provider.json"))
    import importlib

    from apps.payments.providers import store as store_module

    importlib.reload(store_module)
    from apps.payments.providers import mock as mock_module

    importlib.reload(mock_module)
    yield
    monkeypatch.undo()


def _sign(body: bytes) -> str:
    secret = settings.KOLO_WEBHOOK_SECRET.encode()
    return hmac.new(secret, body, hashlib.sha256).hexdigest()


def _webhook_body(intent, *, event_id="evt_1", paid=True):
    payload = {
        "event_id": event_id,
        "event": "payment.completed" if paid else "payment.failed",
        "provider_reference": intent.provider_reference,
        "amount_minor": intent.amount_minor,
        "currency": intent.currency,
        "paid": paid,
    }
    return json.dumps(payload).encode()


def _intent(user, amount_minor=10_000, currency="NGN"):
    return services.create_intent(
        user=user, purpose="contribution", amount_minor=amount_minor, currency=currency,
    )


def _provider_accepts(intent):
    """The member actually paid: the provider now has a record of it.

    The webhook body is never trusted for this — the server re-verifies — so a
    test that only sent a body would prove nothing.
    """
    from apps.payments.providers import store as provider_store

    provider_store.record(
        intent.provider_reference, amount_minor=intent.amount_minor,
        currency=intent.currency, paid=True,
    )


def _provider_declines(intent):
    from apps.payments.providers import store as provider_store

    provider_store.record(
        intent.provider_reference, amount_minor=intent.amount_minor,
        currency=intent.currency, paid=False, failure="declined",
    )


def _deliver(intent, *, event_id="evt_1", paid=True, sign=True):
    body = _webhook_body(intent, event_id=event_id, paid=paid)
    headers = {"X-Kolo-Mock-Signature": _sign(body)} if sign else {}
    return services.handle_webhook(provider_name="mock", headers=headers, body=body)


def test_a_valid_webhook_confirms_the_intent(member_a):
    intent = _intent(member_a)
    _provider_accepts(intent)
    event = _deliver(intent)
    assert event.status == WebhookEvent.Status.PROCESSED

    intent.refresh_from_db()
    assert intent.status == PaymentIntent.Status.SUCCEEDED


def test_a_replayed_webhook_is_ignored(member_a):
    intent = _intent(member_a)
    _provider_accepts(intent)
    first = _deliver(intent, event_id="evt_replay")
    second = _deliver(intent, event_id="evt_replay")

    assert first.pk == second.pk, "the same event id resolves to the same record"
    assert WebhookEvent.objects.filter(event_id="evt_replay").count() == 1
    intent.refresh_from_db()
    assert intent.status == PaymentIntent.Status.SUCCEEDED


def test_a_replayed_webhook_processes_once(memberships):
    """Provider retries must be idempotent at every layer.

    Three deliveries of one event produce one event record, one provider
    transaction, and one intent transition. Note what does *not* happen: an
    intent that is not attached to a contribution or repayment posts nothing to
    the ledger. Money enters the books when it is owed for something, not merely
    because a provider said a charge succeeded.
    """
    from apps.payments.models import ProviderTransaction

    intent = _intent(memberships["a"].user, amount_minor=10_000)
    _provider_accepts(intent)
    _deliver(intent, event_id="evt_dup")
    _deliver(intent, event_id="evt_dup")
    _deliver(intent, event_id="evt_dup")

    assert WebhookEvent.objects.filter(event_id="evt_dup").count() == 1
    assert ProviderTransaction.objects.filter(intent=intent).count() == 1
    intent.refresh_from_db()
    assert intent.status == PaymentIntent.Status.SUCCEEDED
    settlement = ledger.provider_settlement("NGN")
    assert ledger.balance_of(settlement) == 0, "an unattached intent posts no ledger entry"


def test_an_unsigned_webhook_is_rejected(member_a):
    intent = _intent(member_a)
    event = _deliver(intent, sign=False)

    assert event.status == WebhookEvent.Status.FAILED
    assert event.signature_valid is False
    intent.refresh_from_db()
    assert intent.status == PaymentIntent.Status.AWAITING_PAYMENT, "a forged callback moves nothing"


def test_a_badly_signed_webhook_is_rejected(member_a):
    intent = _intent(member_a)
    _provider_accepts(intent)
    body = _webhook_body(intent)
    headers = {"X-Kolo-Mock-Signature": "deadbeef" * 8}
    event = services.handle_webhook(provider_name="mock", headers=headers, body=body)

    assert event.status == WebhookEvent.Status.FAILED
    intent.refresh_from_db()
    assert intent.status == PaymentIntent.Status.AWAITING_PAYMENT


def test_an_unparseable_payload_is_recorded_not_crashed(member_a):
    event = services.handle_webhook(
        provider_name="mock", headers={"X-Kolo-Mock-Signature": _sign(b"not json")}, body=b"not json",
    )
    assert event.status == WebhookEvent.Status.FAILED


def test_a_webhook_for_an_unknown_reference_is_ignored(member_a):
    intent = _intent(member_a)
    payload = {
        "event_id": "evt_unknown", "event": "payment.completed",
        "provider_reference": "mock_does_not_exist", "amount_minor": 99, "currency": "NGN", "paid": True,
    }
    body = json.dumps(payload).encode()
    event = services.handle_webhook(
        provider_name="mock", headers={"X-Kolo-Mock-Signature": _sign(body)}, body=body,
    )
    assert event.status == WebhookEvent.Status.IGNORED
    settlement = ledger.provider_settlement("NGN")
    assert ledger.balance_of(settlement) == 0


def test_a_failed_payment_does_not_mark_the_intent_paid(member_a):
    intent = _intent(member_a)
    _provider_declines(intent)
    event = _deliver(intent, paid=False)
    intent.refresh_from_db()
    assert intent.status == PaymentIntent.Status.FAILED
    assert event.status == WebhookEvent.Status.PROCESSED


def test_idempotency_key_returns_the_same_intent(member_a):
    first = services.create_intent(
        user=member_a, purpose="contribution", amount_minor=5_000, currency="NGN",
        idempotency_key="order-1",
    )
    second = services.create_intent(
        user=member_a, purpose="contribution", amount_minor=5_000, currency="NGN",
        idempotency_key="order-1",
    )
    assert first.pk == second.pk
    assert PaymentIntent.objects.filter(user=member_a).count() == 1


def test_idempotency_key_cannot_be_reused_with_a_different_amount(member_a):
    services.create_intent(
        user=member_a, purpose="contribution", amount_minor=5_000, currency="NGN",
        idempotency_key="order-2",
    )
    with pytest.raises(ConflictError) as caught:
        services.create_intent(
            user=member_a, purpose="contribution", amount_minor=9_000, currency="NGN",
            idempotency_key="order-2",
        )
    assert caught.value.code == "idempotency_conflict"


def test_zero_amount_is_refused(member_a):
    from apps.common.exceptions import DomainError

    with pytest.raises(DomainError):
        services.create_intent(user=member_a, purpose="contribution", amount_minor=0, currency="NGN")


def test_verify_trusts_the_provider_not_the_client(member_a):
    """The client says "I paid"; the provider says otherwise."""
    intent = _intent(member_a)
    # Nothing recorded at the provider yet.
    result = services.verify_and_settle(intent, actor=member_a, source="client")
    result.refresh_from_db()
    assert result.status in {PaymentIntent.Status.AWAITING_PAYMENT, PaymentIntent.Status.PROCESSING}
    assert result.status != PaymentIntent.Status.SUCCEEDED
    settlement = ledger.provider_settlement("NGN")
    assert ledger.balance_of(settlement) == 0
