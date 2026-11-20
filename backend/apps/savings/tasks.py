import logging
from datetime import timedelta

from celery import shared_task
from django.db import transaction
from django.utils import timezone

from apps.savings import services
from apps.savings.models import FREQUENCY_DAYS, Obligation, Programme, ProgrammeType, RotationCycle

logger = logging.getLogger("kolo.savings")


def _system_actor(group):
    from apps.accounts.models import User

    officer = group.memberships.filter(is_active=True).select_related("user").order_by("-created_at").first()
    if officer is None:
        return None
    return officer.user


@shared_task
def advance_due_rotations():
    """Open the next cycle wherever the current one has finished and the period has ended."""
    today = timezone.localdate()
    opened = 0
    programmes = Programme.objects.filter(
        type=ProgrammeType.ROTATIONAL, status=Programme.Status.ACTIVE
    ).select_related("group")
    for programme in programmes:
        current = programme.cycles.order_by("-sequence").first()
        if current is None or current.period_end > today:
            continue
        if current.status not in {
            RotationCycle.Status.PAID,
            RotationCycle.Status.SHORTFALL,
            RotationCycle.Status.CANCELLED,
        }:
            continue
        actor = _system_actor(programme.group)
        if actor is None:
            continue
        try:
            with transaction.atomic():
                services.open_next_cycle(actor=actor, programme=programme)
            opened += 1
        except Exception:
            logger.exception("cycle advance failed", extra={"programme_id": str(programme.pk)})
    return opened


@shared_task
def remind_upcoming_obligations():
    """Tell members about obligations due in the next two days, once each."""
    today = timezone.localdate()
    horizon = today + timedelta(days=2)
    sent = 0
    due = Obligation.objects.filter(
        status__in=[Obligation.Status.PENDING, Obligation.Status.PARTIALLY_PAID],
        due_date__gte=today,
        due_date__lte=horizon,
        reminded_at__isnull=True,
    ).select_related("participation__membership", "programme")
    for obligation in due:
        services.publish(
            "obligation.reminder",
            {
                "obligation_id": str(obligation.pk),
                "programme_id": str(obligation.programme_id),
                "group_id": str(obligation.programme.group_id),
                "user_id": str(obligation.participation.membership.user_id),
                "outstanding_minor": obligation.outstanding_minor,
                "currency": obligation.programme.currency,
                "due_date": str(obligation.due_date),
            },
        )
        obligation.reminded_at = timezone.now()
        obligation.save(update_fields=["reminded_at"])
        sent += 1
    return sent


@shared_task
def mark_overdue_obligations():
    """Flag every obligation that has passed its grace period, programme by programme."""
    total = 0
    for programme in Programme.objects.filter(status=Programme.Status.ACTIVE).select_related("group"):
        total += services.mark_missed_obligations(programme=programme)
    return total


@shared_task
def sweep_expired_requests():
    """Cancel withdrawal requests nobody decided within a week."""
    from apps.savings.models import WithdrawalRequest

    now = timezone.now()
    stale = WithdrawalRequest.objects.filter(
        status=WithdrawalRequest.Status.PENDING_APPROVAL,
        created_at__lt=now - timedelta(days=7),
    )
    count = stale.update(status=WithdrawalRequest.Status.CANCELLED, updated_at=now)
    return count


@shared_task
def send_cycle_digest():
    """A per-group summary of what is collected, owed and overdue."""
    today = timezone.localdate()
    digests = 0
    for programme in Programme.objects.filter(status=Programme.Status.ACTIVE).select_related("group"):
        interval = programme.custom_interval_days or FREQUENCY_DAYS.get(programme.frequency, 30)
        recent = programme.obligations.filter(due_date__gte=today - timedelta(days=interval))
        if not recent.exists():
            continue
        services.publish(
            "programme.digest",
            {
                "programme_id": str(programme.pk),
                "group_id": str(programme.group_id),
                "collected_minor": sum(o.paid_minor for o in recent),
                "outstanding_minor": sum(o.outstanding_minor for o in recent),
                "overdue_count": sum(1 for o in recent if o.status == Obligation.Status.OVERDUE),
                "currency": programme.currency,
            },
        )
        digests += 1
    return digests
