"""A deterministic mock provider for development, tests and demos.

It is a real implementation of the interface — signature verification, webhook
parsing, verification — so the whole payment path can be exercised end to end
without a live financial partner. It never touches real money, and production
refuses to boot while it is selected.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import secrets
from datetime import date

from django.conf import settings

from .base import (
    InitiationRequest,
    InitiationResult,
    PaymentProvider,
    TransferRequest,
    TransferResult,
    VerificationResult,
    WebhookParseResult,
)

SIGNATURE_HEADER = "X-Kolo-Mock-Signature"


class MockProvider(PaymentProvider):
    name = "mock"
    supports_disbursement = True

    # Outcomes are controllable so tests and the demo can reproduce failures
    # without a network. Prefix the description with `FAIL:` to force a decline.
    def initiate(self, request: InitiationRequest) -> InitiationResult:
        provider_reference = f"mock_{request.reference}_{secrets.token_hex(4)}"
        base = settings.MOCK_CHECKOUT_BASE.rstrip("/")
        return InitiationResult(
            provider_reference=provider_reference,
            checkout_url=f"{base}/{provider_reference}",
            raw={"reference": request.reference, "amount_minor": request.amount_minor},
        )

    def verify(self, provider_reference: str) -> VerificationResult:
        # The mock keeps its own tiny ledger of what it "accepted".
        from .store import load

        record = load(provider_reference)
        if record is None:
            return VerificationResult(
                paid=False, amount_minor=0, currency="NGN", provider_reference=provider_reference,
                status="not_found",
            )
        return VerificationResult(
            paid=record["paid"],
            amount_minor=record["amount_minor"],
            currency=record["currency"],
            provider_reference=provider_reference,
            status="success" if record["paid"] else record.get("failure", "failed"),
            failure_reason=record.get("failure_reason", ""),
            raw=record,
        )

    def _sign(self, body: bytes) -> str:
        secret = settings.KOLO_WEBHOOK_SECRET.encode()
        return hmac.new(secret, body, hashlib.sha256).hexdigest()

    def verify_webhook_signature(self, *, headers: dict, body: bytes) -> bool:
        sent = {k.lower(): v for k, v in headers.items()}.get(SIGNATURE_HEADER.lower(), "")
        if not sent:
            return False
        return hmac.compare_digest(sent, self._sign(body))

    def parse_webhook(self, *, headers: dict, body: bytes) -> WebhookParseResult | None:
        try:
            payload = json.loads(body.decode() or "{}")
        except (ValueError, UnicodeDecodeError):
            return None
        reference = payload.get("provider_reference", "")
        if not reference:
            return None
        event_id = payload.get("event_id") or f"evt_{hashlib.sha256(body).hexdigest()[:24]}"
        return WebhookParseResult(
            event_id=event_id,
            event_type=payload.get("event", "payment.completed"),
            provider_reference=reference,
            amount_minor=payload.get("amount_minor"),
            currency=payload.get("currency", ""),
            succeeded=payload.get("paid"),
            raw=payload,
        )

    def transfer(self, request: TransferRequest) -> TransferResult:
        if request.amount_minor <= 0:
            return TransferResult(accepted=False, provider_reference="", status="rejected",
                                  failure_reason="amount must be positive")
        reference = f"mocktrf_{request.reference}_{secrets.token_hex(3)}"
        return TransferResult(accepted=True, provider_reference=reference, status="queued",
                              raw={"narration": request.narration})

    def fetch_settlements(self, *, period_start: date, period_end: date, currency: str) -> list[dict]:
        from .store import all_records

        return [r for r in all_records() if r.get("currency") == currency]
