"""Payment-domain reactions to events from other domains."""

from __future__ import annotations

import logging

from apps.common.handlers import handler

logger = logging.getLogger("kolo.audit")


@handler("contribution.succeeded")
def note_contribution(payload: dict) -> None:
    """Nothing financial happens here — settlement already posted the ledger.

    This handler exists to demonstrate the intended split: the money path is
    synchronous and transactional; everything downstream of it (notifications,
    receipts, analytics) is asynchronous and safe to retry.
    """
    logger.info('{"event":"handler.contribution_succeeded","contribution":"%s"}', payload.get("contribution_id"))
