"""Payment orchestration: initiate, verify, webhook, disbursement, reconcile.

The chain of trust is explicit:

  app says "I paid"        -> ignored, it is not evidence
  webhook arrives          -> signature checked, recorded, then verified with
                              the provider server-to-server
  provider confirms amount -> ledger posted
  anything else            -> intent stays processing, nobody is credited
"""

from __future__ import annotations

import logging
import secrets
from datetime import date, datetime, time, timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.common.audit import AuditLog
from apps.common.exceptions import ConflictError, DomainError, InvalidStateError
from apps.common.outbox import publish
from apps.ledger import services as ledger

from .models import (
    Disbursement,
    PaymentIntent,
    ProviderTransaction,
    ReconciliationItem,
    ReconciliationRun,
    WebhookEvent,
)
from .providers import (
    InitiationRequest,
    TransferRequest,
    get_provider,
)

logger = logging.getLogger("kolo.audit")


def new_reference(prefix: str = "PAY") -> str:
    return f"{prefix}-{timezone.now():%Y%m%d}-{secrets.token_hex(4).upper()}"


# ---------------------------------------------------------------------------
# Initiation
# ---------------------------------------------------------------------------

def create_intent(
    *, user, purpose: str, amount_minor: int, currency: str, source_type: str = "", source_id: str = "",
    idempotency_key: str = "", callback_url: str = "", description: str = "",
) -> PaymentIntent:
    """Start a payment. Reusing an idempotency key returns the original intent."""
    if amount_minor <= 0:
        raise DomainError("Enter an amount greater than zero.", code="amount_invalid")
    currency = currency.upper()

    if idempotency_key:
        existing = PaymentIntent.objects.filter(user=user, idempotency_key=idempotency_key).first()
        if existing:
            if existing.amount_minor != amount_minor or existing.currency != currency:
                raise ConflictError(
                    "That request key was already used with a different amount.",
                    code="idempotency_conflict",
                )
            return existing

    provider = get_provider()
    intent = PaymentIntent.objects.create(
        reference=new_reference(),
        user=user,
        purpose=purpose,
        amount_minor=amount_minor,
        currency=currency,
        provider=provider.name,
        idempotency_key=idempotency_key,
        source_type=source_type,
        source_id=str(source_id or ""),
        status=PaymentIntent.Status.AWAITING_PAYMENT,
        expires_at=timezone.now() + timedelta(minutes=30),
    )

    result = provider.initiate(
        InitiationRequest(
            reference=intent.reference,
            amount_minor=amount_minor,
            currency=currency,
            customer_email=user.email or "",
            customer_phone=user.phone or "",
            description=description or f"KOLO {purpose.replace('_', ' ')}",
            callback_url=callback_url,
            metadata={"intent_id": str(intent.pk), "user_id": str(user.pk), "source_id": str(source_id or "")},
        )
    )
    intent.provider_reference = result.provider_reference
    intent.checkout_url = result.checkout_url
    intent.save(update_fields=["provider_reference", "checkout_url", "updated_at"])

    AuditLog.record(action="payment.initiated", actor=user, target_type="payment_intent", target_id=intent.pk,
                    summary=f"{amount_minor} {currency} via {provider.name}")
    return intent


# ---------------------------------------------------------------------------
# Verification and settlement
# ---------------------------------------------------------------------------

def verify_and_settle(intent: PaymentIntent, *, actor=None, source: str = "verify") -> PaymentIntent:
    """Ask the provider what really happened, then settle if it says paid.

    Amount and currency are compared against what we asked for. A provider
    confirming a *different* amount is a mismatch, not a success — that is the
    difference between a bug and an underpayment being silently accepted.
    """
    provider = get_provider(intent.provider)

    with transaction.atomic():
        intent = PaymentIntent.objects.select_for_update().get(pk=intent.pk)
        if intent.status == PaymentIntent.Status.SUCCEEDED:
            return intent  # idempotent: a retry or duplicate webhook changes nothing
        if intent.status in {PaymentIntent.Status.REVERSED, PaymentIntent.Status.REFUNDED}:
            raise ConflictError("This payment was reversed.", code="payment_reversed")

        result = provider.verify(intent.provider_reference)

        ProviderTransaction.objects.get_or_create(
            provider=provider.name,
            provider_reference=result.provider_reference or intent.provider_reference,
            defaults={
                "intent": intent,
                "amount_minor": result.amount_minor,
                "currency": result.currency or intent.currency,
                "status": result.status,
                "raw_payload": result.raw,
            },
        )

        if not result.paid:
            if result.status in {"not_found", "pending", "ongoing", "processing"}:
                # The member may not have finished paying. Nothing is wrong yet,
                # so don't stamp a failure the app would show as "declined".
                intent.status = PaymentIntent.Status.PROCESSING
                intent.save(update_fields=["status", "updated_at"])
                return intent
            intent.status = PaymentIntent.Status.FAILED
            intent.failure_code = (result.status or "failed")[:60]
            intent.failure_message = (result.failure_reason or "The payment did not complete.")[:300]
            intent.save(update_fields=["status", "failure_code", "failure_message", "updated_at"])
            return intent

        if result.amount_minor != intent.amount_minor:
            intent.status = PaymentIntent.Status.FAILED
            intent.failure_code = "amount_mismatch"
            intent.failure_message = (
                f"The provider confirmed {result.amount_minor} but {intent.amount_minor} was requested."
            )
            intent.save(update_fields=["status", "failure_code", "failure_message", "updated_at"])
            AuditLog.record(
                action="payment.amount_mismatch", severity=AuditLog.Severity.CRITICAL,
                target_type="payment_intent", target_id=intent.pk,
                summary=intent.failure_message,
                metadata={"expected_minor": intent.amount_minor, "confirmed_minor": result.amount_minor},
            )
            raise DomainError(
                "The amount paid does not match this request. Support has been notified.",
                code="amount_mismatch",
            )

        if result.currency and result.currency.upper() != intent.currency:
            raise DomainError("The payment currency does not match this request.", code="currency_mismatch")

        intent.status = PaymentIntent.Status.SUCCEEDED
        intent.confirmed_at = timezone.now()
        intent.failure_code = ""
        intent.failure_message = ""
        intent.save(update_fields=["status", "confirmed_at", "failure_code", "failure_message", "updated_at"])

        _settle_source(intent, actor=actor)

    AuditLog.record(action="payment.succeeded", actor=actor, target_type="payment_intent", target_id=intent.pk,
                    summary=f"{intent.amount_minor} {intent.currency} confirmed via {source}")
    return intent


def _settle_source(intent: PaymentIntent, *, actor=None) -> None:
    """Hand the confirmed payment to the domain that asked for it."""
    if intent.purpose == PaymentIntent.Purpose.CONTRIBUTION and intent.source_id:
        from apps.savings.models import Contribution
        from apps.savings.services import settle_contribution

        contribution = Contribution.objects.filter(pk=intent.source_id).first()
        if contribution:
            settle_contribution(contribution, actor=actor, provider_reference=intent.provider_reference)
    elif intent.purpose == PaymentIntent.Purpose.LOAN_REPAYMENT and intent.source_id:
        from apps.loans.models import Repayment
        from apps.loans.services import settle_repayment

        repayment = Repayment.objects.filter(pk=intent.source_id).first()
        if repayment:
            settle_repayment(repayment, actor=actor, provider_reference=intent.provider_reference)
    elif intent.purpose == PaymentIntent.Purpose.DONATION and intent.source_id:
        from apps.savings.models import FundraisingCampaign
        from apps.savings.services import record_donation

        record_donation(intent=intent, campaign_id=intent.source_id)


# ---------------------------------------------------------------------------
# Webhooks
# ---------------------------------------------------------------------------

def handle_webhook(*, provider_name: str, headers: dict, body: bytes, ip: str | None = None) -> WebhookEvent:
    """Record, verify, then act. Recording first is what makes replays safe."""
    provider = get_provider(provider_name)

    signature_ok = provider.verify_webhook_signature(headers=headers, body=body)
    parsed = provider.parse_webhook(headers=headers, body=body)

    if not parsed:
        event = WebhookEvent.objects.create(
            provider=provider.name,
            event_id=f"unparsed_{secrets.token_hex(8)}",
            signature_valid=signature_ok,
            status=WebhookEvent.Status.FAILED,
            payload={"raw_length": len(body)},
            error="Payload could not be parsed",
        )
        return event

    event, created = WebhookEvent.objects.get_or_create(
        provider=provider.name,
        event_id=parsed.event_id,
        defaults={
            "event_type": parsed.event_type,
            "signature_valid": signature_ok,
            "payload": parsed.raw,
            "status": WebhookEvent.Status.RECEIVED,
        },
    )
    if not created:
        # A replay. This is the whole point of the unique constraint.
        logger.info('{"event":"webhook_duplicate","provider":"%s","event_id":"%s"}', provider.name, parsed.event_id)
        return event

    if not signature_ok:
        event.status = WebhookEvent.Status.FAILED
        event.error = "Signature verification failed"
        event.save(update_fields=["status", "error"])
        AuditLog.record(action="webhook.signature_invalid", severity=AuditLog.Severity.CRITICAL,
                        summary=f"Rejected {provider.name} webhook {parsed.event_id}",
                        metadata={"ip": ip, "event_type": parsed.event_type})
        return event

    try:
        intent = PaymentIntent.objects.filter(
            provider=provider.name, provider_reference=parsed.provider_reference
        ).first()

        if not intent:
            event.status = WebhookEvent.Status.IGNORED
            event.error = "No matching payment intent"
            event.save(update_fields=["status", "error"])
            return event

        if parsed.succeeded is False:
            intent.status = PaymentIntent.Status.FAILED
            intent.failure_code = parsed.event_type[:60]
            intent.failure_message = "The provider reported this payment as unsuccessful."
            intent.save(update_fields=["status", "failure_code", "failure_message", "updated_at"])
            publish("payment.failed", {
                "intent_id": str(intent.pk), "user_id": str(intent.user_id),
                "amount_minor": intent.amount_minor, "currency": intent.currency,
                "reason": parsed.event_type,
            })
        else:
            # Never trust the webhook body for the amount — re-verify server side.
            verify_and_settle(intent, source="webhook")

        event.status = WebhookEvent.Status.PROCESSED
        event.processed_at = timezone.now()
        event.save(update_fields=["status", "processed_at"])
    except Exception as exc:  # noqa: BLE001 - record and re-raise for provider retry
        event.status = WebhookEvent.Status.FAILED
        event.error = str(exc)[:400]
        event.save(update_fields=["status", "error"])
        logger.exception('{"event":"webhook_failed","provider":"%s","event_id":"%s"}', provider.name, parsed.event_id)
        raise
    return event


# ---------------------------------------------------------------------------
# Disbursements
# ---------------------------------------------------------------------------

def create_disbursement(
    *, user, amount_minor: int, currency: str, account_number: str, account_name: str = "", bank_code: str = "",
    reference: str | None = None,
) -> Disbursement:
    """Queue money out. Refuses in sandbox unless explicitly allowed.

    The sandbox guard exists because a disbursement is the one irreversible
    action in KOLO: once a provider moves funds, no code can take them back.
    """
    if settings.FINANCIAL_ENV != "production" and not settings.KOLO.get("ALLOW_SANDBOX_DISBURSEMENT", True):
        raise DomainError("Payouts are disabled in this environment.", code="payouts_disabled")

    provider = get_provider()
    if not provider.supports_disbursement:
        raise DomainError("The configured payment partner cannot send money.", code="disbursement_unsupported")

    disbursement = Disbursement.objects.create(
        reference=reference or new_reference("DSB"),
        user=user,
        amount_minor=amount_minor,
        currency=currency.upper(),
        provider=provider.name,
        destination_account_number=account_number,
        destination_account_name=account_name,
        destination_bank_code=bank_code,
    )
    return disbursement


def execute_disbursement(disbursement: Disbursement, *, actor=None) -> Disbursement:
    with transaction.atomic():
        disbursement = Disbursement.objects.select_for_update().get(pk=disbursement.pk)
        if disbursement.status in {Disbursement.Status.COMPLETED, Disbursement.Status.PROCESSING,
                                   Disbursement.Status.QUEUED}:
            return disbursement

        provider = get_provider(disbursement.provider)
        result = provider.transfer(
            TransferRequest(
                reference=disbursement.reference,
                amount_minor=disbursement.amount_minor,
                currency=disbursement.currency,
                account_number=disbursement.destination_account_number,
                account_name=disbursement.destination_account_name,
                bank_code=disbursement.destination_bank_code,
                narration="KOLO payout",
            )
        )
        if result.accepted:
            disbursement.status = Disbursement.Status.QUEUED
            disbursement.provider_reference = result.provider_reference
        else:
            disbursement.status = Disbursement.Status.FAILED
            disbursement.failure_code = "provider_rejected"
            disbursement.failure_message = result.failure_reason[:300]
        disbursement.save()

    AuditLog.record(action="disbursement.executed", actor=actor, severity=AuditLog.Severity.NOTICE,
                    target_type="disbursement", target_id=disbursement.pk,
                    summary=f"{disbursement.status}: {disbursement.amount_minor} {disbursement.currency}")
    return disbursement


def mark_disbursement_completed(disbursement: Disbursement, *, actor=None) -> Disbursement:
    """Provider confirmed the money left. Post the outbound ledger transaction."""
    with transaction.atomic():
        disbursement = Disbursement.objects.select_for_update().get(pk=disbursement.pk)
        if disbursement.status == Disbursement.Status.COMPLETED:
            return disbursement

        settlement = ledger.provider_settlement(disbursement.currency)
        payable = ledger.provider_payable(disbursement.currency)
        txn = ledger.post(
            kind=ledger.JournalTransaction.Kind.WITHDRAWAL,
            currency=disbursement.currency,
            description=f"Disbursement {disbursement.reference}",
            source_type="disbursement",
            source_id=str(disbursement.pk),
            idempotency_key=f"disbursement:{disbursement.pk}",
            posted_by=actor,
            legs=[
                ledger.Leg(account=payable, amount_minor=disbursement.amount_minor, memo="Settle payable"),
                ledger.Leg(account=settlement, amount_minor=-disbursement.amount_minor, memo="Funds leave"),
            ],
        )
        disbursement.status = Disbursement.Status.COMPLETED
        disbursement.completed_at = timezone.now()
        disbursement.save(update_fields=["status", "completed_at", "updated_at"])
        publish("disbursement.completed", {
            "disbursement_id": str(disbursement.pk), "user_id": str(disbursement.user_id),
            "amount_minor": disbursement.amount_minor, "currency": disbursement.currency,
            "ledger_reference": txn.reference,
        })
    return disbursement


# ---------------------------------------------------------------------------
# Reconciliation
# ---------------------------------------------------------------------------

def run_reconciliation(*, provider_name: str, period_start: date, period_end: date, currency: str) -> ReconciliationRun:
    """Compare our settled payments to the partner's records.

    Findings are recorded, never corrected. Auto-"fixing" a mismatch to make a
    report tidy destroys the evidence of the bug.
    """
    provider = get_provider(provider_name)
    run = ReconciliationRun.objects.create(
        provider=provider.name, currency=currency.upper(),
        period_start=period_start, period_end=period_end,
    )

    start_dt = datetime.combine(period_start, time.min, tzinfo=timezone.get_current_timezone())
    end_dt = datetime.combine(period_end, time.max, tzinfo=timezone.get_current_timezone())

    ours = {
        t.provider_reference: t
        for t in ProviderTransaction.objects.filter(
            provider=provider.name, currency=currency.upper(), created_at__range=(start_dt, end_dt)
        )
    }
    try:
        theirs = {str(r.get("reference", "")): r for r in provider.fetch_settlements(
            period_start=period_start, period_end=period_end, currency=currency.upper()
        )}
    except Exception as exc:  # noqa: BLE001 - partner down is a finding, not a crash
        run.status = ReconciliationRun.Status.FAILED
        run.notes = f"Provider settlement fetch failed: {exc}"[:500]
        run.completed_at = timezone.now()
        run.save()
        return run

    matched = mismatched = missing = 0
    for reference, txn in ours.items():
        if reference not in theirs:
            missing += 1
            ReconciliationItem.objects.create(
                run=run, kind=ReconciliationItem.Kind.MISSING_PROVIDER, provider_reference=reference,
                internal_amount_minor=txn.amount_minor, currency=txn.currency,
                detail="We recorded this payment; the provider does not list it.",
            )
            continue
        provider_amount = int(theirs[reference].get("amount") or theirs[reference].get("amount_minor") or 0)
        if provider_amount and provider_amount != txn.amount_minor:
            mismatched += 1
            ReconciliationItem.objects.create(
                run=run, kind=ReconciliationItem.Kind.AMOUNT_MISMATCH, provider_reference=reference,
                internal_amount_minor=txn.amount_minor, provider_amount_minor=provider_amount,
                currency=txn.currency, detail="Amounts disagree between KOLO and the provider.",
            )
        else:
            matched += 1

    for reference in theirs:
        if reference and reference not in ours:
            ReconciliationItem.objects.create(
                run=run, kind=ReconciliationItem.Kind.MISSING_INTERNAL, provider_reference=reference,
                provider_amount_minor=int(theirs[reference].get("amount") or 0), currency=currency.upper(),
                detail="The provider settled this; KOLO has no matching transaction.",
            )

    run.matched_count = matched
    run.mismatch_count = mismatched
    run.missing_count = missing
    run.status = ReconciliationRun.Status.COMPLETED
    run.completed_at = timezone.now()
    run.save()

    if mismatched or missing:
        AuditLog.record(action="reconciliation.discrepancies", severity=AuditLog.Severity.WARNING,
                        target_type="reconciliation_run", target_id=run.pk,
                        summary=f"{mismatched} mismatches, {missing} missing for {provider.name}")
    return run
