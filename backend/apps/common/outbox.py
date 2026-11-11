"""Publishing domain events without losing them.

Usage inside a transaction:

    with transaction.atomic():
        ...change state...
        publish("contribution.succeeded", {"contribution_id": str(c.id)})

The row commits with the change, or not at all. A Celery beat task sweeps
anything still pending, so a broker outage delays delivery instead of losing it.
"""

from __future__ import annotations

import logging

from django.db import transaction
from django.utils import timezone

from .models import OutboxEvent

logger = logging.getLogger("kolo.audit")


def publish(topic: str, payload: dict, *, delay_seconds: int = 0) -> OutboxEvent:
    """Queue an event for delivery after the current transaction commits."""
    event = OutboxEvent.objects.create(topic=topic, payload=payload)
    if delay_seconds:
        event.available_at = timezone.now() + timezone.timedelta(seconds=delay_seconds)
        event.save(update_fields=["available_at"])
    # Scheduling after commit keeps a rolled-back transaction from shipping an
    # event about work that never happened.
    transaction.on_commit(lambda: _nudge(event.pk))
    return event


def _nudge(event_pk) -> None:
    """Best-effort immediate delivery; the sweeper is the safety net."""
    try:
        from apps.common.tasks import deliver_outbox_event

        deliver_outbox_event.delay(str(event_pk))
    except Exception as exc:  # broker down, no workers, eager mode in tests
        logger.info('{"event":"outbox_deferred","reason":%r}', str(exc))
