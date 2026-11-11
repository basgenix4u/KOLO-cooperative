"""Shared primitives used across every domain.

The rules encoded here are product rules, not conveniences:

* Money is never a float. Amounts are integer minor units plus an ISO currency.
* Public identifiers are UUIDs; sequential integers stay internal.
* Every state change that matters to money or access is auditable.
"""

from __future__ import annotations

import uuid
from typing import NamedTuple

from django.db import models


class UUIDModel(models.Model):
    """Base model with a UUID primary key that is safe to expose in APIs."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    class Meta:
        abstract = True


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class AuditModel(UUIDModel, TimeStampedModel):
    """UUID identity plus timestamps — the default base for domain models."""

    class Meta:
        abstract = True


CURRENCY_DECIMALS = {
    "NGN": 2,
    "USD": 2,
    "GBP": 2,
    "EUR": 2,
    "KES": 2,
    "GHS": 2,
    "ZAR": 2,
    "XOF": 0,
    "JPY": 0,
}


class Money(NamedTuple):
    """An exact amount of money.

    `minor` is the smallest indivisible unit (kobo, cents, ...). Two decimal
    places is right for every currency KOLO currently supports, but the exponent
    lives in one table so a zero-decimal currency is a data change, not a
    rewrite of arithmetic that was silently assuming 100.
    """

    minor: int
    currency: str

    def __post_init__(self):
        if not isinstance(self.minor, int):
            raise TypeError("Money.minor must be an int (minor units), got %r" % type(self.minor))

    @property
    def exponent(self) -> int:
        return CURRENCY_DECIMALS[self.currency.upper()]

    @property
    def major(self) -> str:
        """Human-readable amount, e.g. '2000.00'. Display only, never arithmetic."""
        scale = 10 ** self.exponent
        sign = "-" if self.minor < 0 else ""
        whole, frac = divmod(abs(self.minor), scale)
        if self.exponent == 0:
            return f"{sign}{whole}"
        return f"{sign}{whole}.{str(frac).zfill(self.exponent)}"

    def __add__(self, other: "Money") -> "Money":
        self._assert_same_currency(other)
        return Money(self.minor + other.minor, self.currency)

    def __sub__(self, other: "Money") -> "Money":
        self._assert_same_currency(other)
        return Money(self.minor - other.minor, self.currency)

    def _assert_same_currency(self, other: "Money") -> None:
        if self.currency.upper() != other.currency.upper():
            raise ValueError(f"currency mismatch: {self.currency} vs {other.currency}")

    def __str__(self) -> str:
        return f"{self.major} {self.currency.upper()}"

    @classmethod
    def zero(cls, currency: str) -> "Money":
        return cls(0, currency)


def to_minor(major_amount: str, currency: str) -> int:
    """Parse a decimal string into minor units without float error.

    Providers occasionally hand back "2000.5" or "2000.50"; both must land on
    the same integer.
    """
    from decimal import Decimal, InvalidOperation

    try:
        value = Decimal(str(major_amount).strip())
    except (InvalidOperation, AttributeError) as exc:
        raise ValueError(f"invalid amount: {major_amount!r}") from exc
    exponent = CURRENCY_DECIMALS[currency.upper()]
    scaled = value.scaleb(exponent)
    if scaled != scaled.to_integral_value():
        raise ValueError(f"amount {major_amount!r} has more precision than {currency} allows")
    return int(scaled)


# Re-exported so `apps.common.models` is the single import surface for this
# app's tables (Django's migration discovery reads models from here).
from .audit import AuditLog, OutboxEvent  # noqa: E402,F401

__all__ = ["UUIDModel", "TimeStampedModel", "AuditModel", "Money", "to_minor", "CURRENCY_DECIMALS",
           "AuditLog", "OutboxEvent"]
