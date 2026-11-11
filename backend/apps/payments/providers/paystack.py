"""Paystack adapter.

Only selected when credentials exist. Every method maps Paystack's wording onto
KOLO's contract so no domain code learns a vendor's field names.
"""

from __future__ import annotations

import hashlib
import hmac
import json
from datetime import date

import requests
from django.conf import settings

from apps.common.models import to_minor

from .base import (
    InitiationRequest,
    InitiationResult,
    PaymentProvider,
    ProviderNotConfigured,
    TransferRequest,
    TransferResult,
    VerificationResult,
    WebhookParseResult,
)

API = "https://api.paystack.co"


class PaystackProvider(PaymentProvider):
    name = "paystack"
    supports_disbursement = True

    def __init__(self) -> None:
        self.secret = getattr(settings, "PAYSTACK_SECRET_KEY", "")
        if not self.secret:
            raise ProviderNotConfigured("PAYSTACK_SECRET_KEY is not set")
        self.headers = {"Authorization": f"Bearer {self.secret}", "Content-Type": "application/json"}

    def initiate(self, request: InitiationRequest) -> InitiationResult:
        body = {
            "email": request.customer_email or f"{request.reference}@kolo.invalid",
            "amount": request.amount_minor,
            "currency": request.currency,
            "reference": request.reference,
            "callback_url": request.callback_url,
            "metadata": request.metadata,
        }
        response = requests.post(f"{API}/transaction/initialize", json=body, headers=self.headers, timeout=20)
        data = response.json()
        if not data.get("status"):
            raise RuntimeError(data.get("message", "payment could not be started"))
        return InitiationResult(
            provider_reference=data["data"]["reference"],
            checkout_url=data["data"]["authorization_url"],
            raw=data["data"],
        )

    def verify(self, provider_reference: str) -> VerificationResult:
        response = requests.get(f"{API}/transaction/verify/{provider_reference}", headers=self.headers, timeout=20)
        data = response.json()
        payload = data.get("data", {})
        return VerificationResult(
            paid=bool(data.get("status")) and payload.get("status") == "success",
            amount_minor=int(payload.get("amount") or 0),
            currency=(payload.get("currency") or "").upper(),
            provider_reference=provider_reference,
            status=payload.get("status", "unknown"),
            failure_reason=payload.get("gateway_response", ""),
            raw=payload,
        )

    def verify_webhook_signature(self, *, headers: dict, body: bytes) -> bool:
        sent = {k.lower(): v for k, v in headers.items()}.get("x-paystack-signature", "")
        if not sent:
            return False
        expected = hmac.new(self.secret.encode(), body, hashlib.sha512).hexdigest()
        return hmac.compare_digest(sent, expected)

    def parse_webhook(self, *, headers: dict, body: bytes) -> WebhookParseResult | None:
        payload = json.loads(body.decode() or "{}")
        event = payload.get("event", "")
        data = payload.get("data", {}) or {}
        succeeded = None
        if event in {"charge.success", "transfer.success"}:
            succeeded = True
        elif event in {"charge.failed", "transfer.failed", "transfer.reversed"}:
            succeeded = False
        return WebhookParseResult(
            # Paystack sends no event id, so one is derived from the body: the
            # same delivery retried hashes identically and is caught by the
            # unique constraint.
            event_id=payload.get("id") and str(payload["id"]) or f"ps_{hashlib.sha256(body).hexdigest()[:28]}",
            event_type=event,
            provider_reference=str(data.get("reference", "")),
            amount_minor=data.get("amount"),
            currency=(data.get("currency") or "").upper(),
            succeeded=succeeded,
            raw=payload,
        )

    def transfer(self, request: TransferRequest) -> TransferResult:
        # A recipient must exist before a transfer; creating one per payout is
        # wasteful and duplicates recipients in the partner's records.
        recipient = requests.post(
            f"{API}/transferrecipient",
            json={"type": "nuban", "name": request.account_name, "account_number": request.account_number,
                  "bank_code": request.bank_code, "currency": request.currency},
            headers=self.headers, timeout=20,
        ).json()
        if not recipient.get("status"):
            return TransferResult(accepted=False, provider_reference="", status="rejected",
                                  failure_reason=recipient.get("message", "recipient rejected"))
        body = {
            "source": "balance",
            "amount": request.amount_minor,
            "recipient": recipient["data"]["recipient_code"],
            "reason": request.narration,
            "reference": request.reference,
        }
        data = requests.post(f"{API}/transfer", json=body, headers=self.headers, timeout=20).json()
        if not data.get("status"):
            return TransferResult(accepted=False, provider_reference="", status="rejected",
                                  failure_reason=data.get("message", "transfer rejected"))
        return TransferResult(
            accepted=True, provider_reference=data["data"].get("reference", request.reference),
            status=data["data"].get("status", "queued"), raw=data["data"],
        )

    def fetch_settlements(self, *, period_start: date, period_end: date, currency: str) -> list[dict]:
        params = {
            "from": period_start.isoformat(),
            "to": period_end.isoformat(),
            "currency": currency,
            "perPage": 200,
        }
        response = requests.get(f"{API}/settlement", params=params, headers=self.headers, timeout=30)
        data = response.json()
        return data.get("data", [])
