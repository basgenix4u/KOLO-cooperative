"""Outbox topic -> handler wiring.

Kept in one table so it is obvious, at a glance, what reacts to a domain event.
Handlers are imported lazily to avoid circular imports at app-load time.
"""

from __future__ import annotations

from typing import Callable

HANDLERS: dict[str, list[Callable[[dict], None]]] = {}


def handler(topic: str):
    def register(fn):
        HANDLERS.setdefault(topic, []).append(fn)
        return fn

    return register


def load_handlers() -> None:
    """Import handler modules so their decorators run."""
    from apps.notifications import outbox_handlers  # noqa: F401
    from apps.savings import outbox_handlers as savings_handlers  # noqa: F401
    from apps.payments import outbox_handlers as payment_handlers  # noqa: F401
