import logging

from celery import shared_task
from django.db import transaction
from django.utils import timezone

from .models import OutboxEvent

logger = logging.getLogger("kolo.audit")

MAX_ATTEMPTS = 8


@shared_task(bind=True, max_retries=3)
def deliver_outbox_event(self, event_id: str):
    """Deliver one event to its handlers, exactly once in practice.

    Handlers must be idempotent: the sweeper may retry an event whose delivery
    succeeded but whose commit did not record that fact.
    """
    from .handlers import HANDLERS

    try:
        event = OutboxEvent.objects.get(pk=event_id)
    except OutboxEvent.DoesNotExist:
        return "missing"

    if event.status == OutboxEvent.Status.DELIVERED:
        return "already-delivered"

    handlers = HANDLERS.get(event.topic, [])
    try:
        for handler in handlers:
            handler(event.payload)
    except Exception as exc:
        event.attempts += 1
        event.last_error = str(exc)[:400]
        # Exponential backoff, capped: 2, 4, 8 ... 300 seconds.
        backoff = min(2 ** event.attempts, 300)
        event.available_at = timezone.now() + timezone.timedelta(seconds=backoff)
        if event.attempts >= MAX_ATTEMPTS:
            event.status = OutboxEvent.Status.FAILED
            logger.error('{"event":"outbox_failed","topic":"%s","id":"%s","error":%r}',
                         event.topic, event.id, str(exc))
        event.save(update_fields=["attempts", "last_error", "available_at", "status"])
        raise self.retry(exc=exc, countdown=backoff)

    event.status = OutboxEvent.Status.DELIVERED
    event.delivered_at = timezone.now()
    event.save(update_fields=["status", "delivered_at"])
    return "delivered"


@shared_task
def dispatch_pending_outbox():
    """Safety net for events whose immediate nudge was lost."""
    pending = OutboxEvent.objects.filter(
        status=OutboxEvent.Status.PENDING, available_at__lte=timezone.now()
    ).order_by("created_at")[:200]
    for event in pending:
        deliver_outbox_event.delay(str(event.pk))
    return len(pending)
