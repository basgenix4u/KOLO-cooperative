"""Savings reactions: keep cycle totals authoritative without blocking payment."""

from __future__ import annotations

import logging

from apps.common.handlers import handler

logger = logging.getLogger("kolo.audit")


@handler("programme.status_changed")
def log_programme_transition(payload: dict) -> None:
    logger.info('{"event":"handler.programme_status","programme":"%s","status":"%s"}',
                payload.get("programme_id"), payload.get("status"))
