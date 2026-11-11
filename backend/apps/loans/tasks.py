from celery import shared_task


@shared_task
def mark_overdue_installments():
    from .services import mark_overdue_installments as run

    return run()
