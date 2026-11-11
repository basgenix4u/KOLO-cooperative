"""Notification creation and push delivery."""

from __future__ import annotations

import logging

from django.conf import settings
from django.utils import timezone

from apps.accounts.models import DeviceSession

from .models import Notification, NotificationPreference

logger = logging.getLogger("kolo.audit")

KIND_TO_PREFERENCE = {
    "payment_confirmed": "contributions",
    "payment_failed": "contributions",
    "contribution_due": "contributions",
    "contribution_overdue": "contributions",
    "payout_paid": "payouts",
    "withdrawal_update": "payouts",
    "loan_update": "loans",
    "vote_open": "governance",
    "announcement": "announcements",
    "membership": "announcements",
    "programme": "announcements",
    "security": "security",
}


def notify_user(*, user_id, kind: str, title: str, body: str, dedupe_key: str = "", data: dict | None = None) -> Notification | None:
    """Create a notification unless the member opted out or it already exists."""
    preference_field = KIND_TO_PREFERENCE.get(kind, "announcements")
    prefs = NotificationPreference.objects.filter(user_id=user_id).first()
    if prefs and not getattr(prefs, preference_field, True):
        return None
    if prefs and kind != "security" and not prefs.push_enabled and not prefs.email_enabled:
        return None

    if dedupe_key and Notification.objects.filter(user_id=user_id, dedupe_key=dedupe_key).exists():
        return None

    notification = Notification.objects.create(
        user_id=user_id, kind=kind, title=title[:140], body=body[:400],
        data=data or {}, dedupe_key=dedupe_key,
    )
    try:
        send_push(notification)
    except Exception as exc:  # noqa: BLE001 - push must never break the caller
        logger.warning('{"event":"push_failed","notification":"%s","error":%r}', notification.pk, str(exc))
    return notification


def send_push(notification: Notification) -> bool:
    """Deliver via FCM to every live device of the member.

    Absent credentials mean push is simply off — never a crash, never a claim
    that it was delivered.
    """
    tokens = list(
        DeviceSession.objects.filter(
            user_id=notification.user_id, revoked_at__isnull=True
        ).exclude(push_token="").values_list("push_token", flat=True)
    )
    if not tokens:
        return False

    credential_path = getattr(settings, "FCM_CREDENTIALS_PATH", "")
    if not credential_path:
        logger.info('{"event":"push_skipped","reason":"FCM credentials not configured","count":%d}', len(tokens))
        notification.push_error = "Push is not configured in this environment"
        notification.save(update_fields=["push_error"])
        return False

    import firebase_admin
    from firebase_admin import credentials, messaging

    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate(credential_path))

    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=notification.title, body=notification.body),
        data={k: str(v) for k, v in (notification.data or {}).items()},
    )
    response = messaging.send_each_for_multicast(message)
    notification.push_sent_at = timezone.now()
    notification.push_error = "" if response.failure_count == 0 else f"{response.failure_count} device(s) failed"
    notification.save(update_fields=["push_sent_at", "push_error"])
    return response.success_count > 0


def mark_all_read(*, user) -> int:
    return Notification.objects.filter(user=user, read_at__isnull=True).update(read_at=timezone.now())
