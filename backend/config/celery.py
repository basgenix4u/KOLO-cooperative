import os

from celery import Celery
from celery.schedules import schedule

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.deploy")

app = Celery("kolo")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()

app.conf.beat_schedule = {
    "sweep-expired-authorisations": {
        "task": "apps.savings.tasks.sweep_expired_requests",
        "schedule": schedule(run_every=300.0),
    },
    "remind-upcoming-contributions": {
        "task": "apps.savings.tasks.remind_upcoming_obligations",
        "schedule": schedule(run_every=3600.0),
    },
    "advance-due-rotations": {
        "task": "apps.savings.tasks.advance_due_rotations",
        "schedule": schedule(run_every=900.0),
    },
    "mark-overdue-loans": {
        "task": "apps.loans.tasks.mark_overdue_installments",
        "schedule": schedule(run_every=3600.0),
    },
    "deliver-outbox": {
        "task": "apps.common.tasks.dispatch_pending_outbox",
        "schedule": schedule(run_every=120.0),
    },
}
