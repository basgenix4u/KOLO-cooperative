"""Notification fan-out driven by domain events.

Deliberately idempotent: notifications are created with a dedupe key derived
from the event, so a retried outbox delivery cannot double-notify.
"""

from __future__ import annotations

import logging

from apps.common.handlers import handler

logger = logging.getLogger("kolo.audit")


@handler("contribution.succeeded")
def notify_contribution(payload: dict) -> None:
    from .services import notify_user

    notify_user(
        user_id=payload["payer_id"],
        kind="payment_confirmed",
        title="Contribution received",
        body="Your contribution was confirmed and added to the programme.",
        dedupe_key=f"contribution:{payload['contribution_id']}",
        data={"programme_id": payload.get("programme_id", "")},
    )


@handler("payment.failed")
def notify_payment_failure(payload: dict) -> None:
    from .services import notify_user

    notify_user(
        user_id=payload["user_id"],
        kind="payment_failed",
        title="Payment did not complete",
        body="The payment was not completed. You can try again from the programme.",
        dedupe_key=f"payment-failed:{payload['intent_id']}",
    )


@handler("rotation.payout_paid")
def notify_payout(payload: dict) -> None:
    from .services import notify_user

    notify_user(
        user_id=payload["beneficiary_user_id"],
        kind="payout_paid",
        title="Payout completed",
        body="Your rotation payout has been recorded in your programme.",
        dedupe_key=f"payout:{payload['cycle_id']}",
        data={"programme_id": payload.get("programme_id", "")},
    )


@handler("obligation.overdue")
def notify_overdue(payload: dict) -> None:
    from .services import notify_user

    notify_user(
        user_id=payload["user_id"],
        kind="contribution_overdue",
        title="Contribution outstanding",
        body=f"A contribution due on {payload.get('due_date')} is still outstanding.",
        dedupe_key=f"overdue:{payload['obligation_id']}",
    )


@handler("account.verified")
def notify_verified(payload: dict) -> None:
    from .services import notify_user

    notify_user(
        user_id=payload["user_id"],
        kind="security",
        title="Account verified",
        body="Your contact details are verified. You can now join and create groups.",
        dedupe_key=f"verified:{payload['user_id']}:{payload['channel']}",
    )
