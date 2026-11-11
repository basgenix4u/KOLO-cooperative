"""Provider registry.

Selection is one environment variable. Business logic asks for "the provider"
and receives whichever partner is configured.
"""

from __future__ import annotations

from django.conf import settings

from .base import (  # noqa: F401 - re-exported for callers
    InitiationRequest,
    InitiationResult,
    PaymentProvider,
    ProviderNotConfigured,
    TransferRequest,
    TransferResult,
    VerificationResult,
    WebhookParseResult,
)
from .mock import MockProvider
from .paystack import PaystackProvider

_INSTANCES: dict[str, PaymentProvider] = {}


def get_provider(name: str | None = None) -> PaymentProvider:
    key = (name or settings.PAYMENT_PROVIDER or "mock").lower()
    if key not in _INSTANCES:
        if key == "mock":
            _INSTANCES[key] = MockProvider()
        elif key == "paystack":
            _INSTANCES[key] = PaystackProvider()
        else:
            raise ProviderNotConfigured(f"Unknown payment provider: {key}")
    return _INSTANCES[key]


def reset_provider_cache() -> None:
    """Tests swap providers mid-run; this keeps that honest."""
    _INSTANCES.clear()
