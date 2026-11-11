"""Tiny JSON store used by the mock provider only.

Deliberately not the database: it stands in for a *third party's* records, so
keeping it outside KOLO's tables is the honest representation of the boundary.
"""

from __future__ import annotations

import json
import os
import tempfile
import threading
from pathlib import Path

_LOCK = threading.Lock()
_PATH = Path(os.environ.get("MOCK_PROVIDER_STATE", "/tmp/kolo_mock_provider.json"))


def _read() -> dict:
    try:
        return json.loads(_PATH.read_text())
    except (FileNotFoundError, ValueError):
        return {}


def _write(data: dict) -> None:
    tmp = tempfile.NamedTemporaryFile("w", delete=False, dir=str(_PATH.parent))
    json.dump(data, tmp)
    tmp.close()
    os.replace(tmp.name, _PATH)


def record(reference: str, *, amount_minor: int, currency: str, paid: bool, failure: str = "",
           failure_reason: str = "") -> None:
    with _LOCK:
        data = _read()
        data[reference] = {
            "amount_minor": amount_minor, "currency": currency, "paid": paid,
            "failure": failure, "failure_reason": failure_reason,
        }
        _write(data)


def load(reference: str) -> dict | None:
    return _read().get(reference)


def all_records() -> list[dict]:
    return list(_read().values())


def clear() -> None:
    with _LOCK:
        _write({})
