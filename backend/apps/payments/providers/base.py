"""The payment provider interface.

Business logic depends on this Protocol, never on a vendor SDK. Adding a
provider means implementing this file and registering it; it does not mean
touching the savings or ledger code.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable


@dataclass(frozen=True)
class InitiationRequest:
    reference: str
    amount_minor: int
    currency: str
    customer_email: str = ""
    customer_phone: str = ""
    description: str = ""
    callback_url: str = ""
    metadata: dict = field(default_factory=dict)


@dataclass(frozen=True)
class InitiationResult:
    provider_reference: str
    checkout_url: str
    raw: dict = field(default_factory=dict)


@dataclass(frozen=True)
class VerificationResult:
    """What the provider says about one payment attempt.

    `paid` is the only field business logic may trust, and it must come from a
    server-to-server call or a signature-verified webhook — never from the app.
    """

    paid: bool
    amount_minor: int
    currency: str
    provider_reference: str
    status: str
    failure_reason: str = ""
    raw: dict = field(default_factory=dict)


@dataclass(frozen=True)
class TransferRequest:
    reference: str
    amount_minor: int
    currency: str
    account_number: str
    account_name: str = ""
    bank_code: str = ""
    narration: str = ""


@dataclass(frozen=True)
class TransferResult:
    accepted: bool
    provider_reference: str
    status: str
    failure_reason: str = ""
    raw: dict = field(default_factory=dict)


@dataclass(frozen=True)
class WebhookParseResult:
    """A provider payload, normalised."""

    event_id: str
    event_type: str
    provider_reference: str = ""
    amount_minor: int | None = None
    currency: str = ""
    succeeded: bool | None = None
    raw: dict = field(default_factory=dict)


@runtime_checkable
class PaymentProvider(Protocol):
    """Everything KOLO needs from a financial partner."""

    name: str
    supports_disbursement: bool

    def initiate(self, request: InitiationRequest) -> InitiationResult: ...

    def verify(self, provider_reference: str) -> VerificationResult: ...

    def parse_webhook(self, *, headers: dict, body: bytes) -> WebhookParseResult | None: ...

    def verify_webhook_signature(self, *, headers: dict, body: bytes) -> bool: ...

    def transfer(self, request: TransferRequest) -> TransferResult: ...

    def fetch_settlements(self, *, period_start, period_end, currency: str) -> list[dict]: ...


class ProviderNotConfigured(RuntimeError):
    """Raised when an integration is selected but its credentials are absent.

    This is deliberately loud: pretending a missing integration works is how a
    member pays and nothing happens.
    """
