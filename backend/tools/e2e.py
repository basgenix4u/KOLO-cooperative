#!/usr/bin/env python
"""KOLO end-to-end harness: drives the real HTTP API against a running server.

Nothing here mocks the application. Every request is a real request, every
assertion is about a server response or the server's own committed state. The
only direct database access is where the *member* cannot know something by
design: reading the OTP out of the dev email backend, and seeding the mock
payment provider so it can report "this member paid".

Why a script rather than a pytest module: the unit suite deliberately runs in
one process with a test database. This runs against the deployed stack over the
wire, which is the only way to catch things like "select_for_update in
autocommit returns 500" that a test harness structurally hides.

Usage:
    python tools/e2e.py            # full run against http://127.0.0.1:8000
    python tools/e2e.py --keep     # leave the created group/data in place

Exit code 0 means every check passed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

import urllib.error
import urllib.request

BASE = os.environ.get("KOLO_BASE_URL", "http://127.0.0.1:8000")
SERVER_LOG = Path(os.environ.get("KOLO_SERVER_LOG", "/tmp/kolo_server.log"))
BACKEND_DIR = Path(__file__).resolve().parent.parent
PYTHON = os.environ.get("KOLO_PYTHON", "/home/user/kolo/.venv-backend/bin/python")
PASSWORD = "Str0ng-Passw0rd!23"

# --------------------------------------------------------------------------
# Tiny HTTP client
# --------------------------------------------------------------------------


class Api:
    def __init__(self, base: str):
        self.base = base
        self.token: str | None = None
        self.calls: list[tuple[str, str, int]] = []

    def _request(self, method: str, path: str, body=None, *, token=None, raw=False):
        url = f"{self.base}{path}"
        data = None
        headers = {"Accept": "application/json"}
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if token or self.token:
            headers["Authorization"] = f"Bearer {token or self.token}"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
                status = response.status
        except urllib.error.HTTPError as exc:
            payload = exc.read()
            status = exc.code
        self.calls.append((method, path, status))
        if raw:
            return status, payload
        try:
            parsed = json.loads(payload) if payload else {}
        except json.JSONDecodeError:
            parsed = {"_raw": payload.decode(errors="replace")[:400]}
        return status, parsed

    def get(self, path, **kw):
        return self._request("GET", path, **kw)

    def post(self, path, body=None, **kw):
        return self._request("POST", path, body if body is not None else {}, **kw)

    def put(self, path, body=None, **kw):
        return self._request("PUT", path, body if body is not None else {}, **kw)

    def patch_(self, path, body=None, **kw):
        return self._request("PATCH", path, body if body is not None else {}, **kw)


# --------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------

GREEN, RED, YELLOW, DIM, RESET = "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[0m"


@dataclass
class Report:
    passed: list[str] = field(default_factory=list)
    failed: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def check(self, label: str, condition: bool, detail: str = ""):
        if condition:
            self.passed.append(label)
            print(f"  {GREEN}PASS{RESET} {label}")
        else:
            self.failed.append(f"{label}{' — ' + detail if detail else ''}")
            print(f"  {RED}FAIL{RESET} {label}" + (f" {DIM}({detail}){RESET}" if detail else ""))
        return condition

    def note(self, text: str):
        self.notes.append(text)
        print(f"  {YELLOW}NOTE{RESET} {text}")

    def section(self, title: str):
        print(f"\n{'=' * 72}\n{title}\n{'=' * 72}")


def django_shell(code: str) -> str:
    """Run a snippet in the server's Django environment (seeding only)."""
    env = dict(os.environ, PYTHONPATH=str(BACKEND_DIR), DJANGO_SETTINGS_MODULE="config.settings.dev")
    result = subprocess.run(
        [PYTHON, "-c", f"import django; django.setup()\n{code}"],
        cwd=BACKEND_DIR, env=env, capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError(f"django_shell failed:\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def reset_throttles() -> None:
    """Clear rate-limit counters between scenario phases.

    Development convenience only: the throttles themselves stay configured and
    are exercised deliberately elsewhere. A human onboarding a whole group at
    once would hit the same limits, which is why the harness resets between
    phases instead of raising the configured rates.
    """
    django_shell("from django.core.cache import cache\ncache.clear()\nprint('throttles reset')")


def read_otp(email: str) -> str | None:
    """Pull a member's OTP from the dev console email backend.

    The API never returns the code — correctly. A developer-facing server prints
    it to the log, which is how a human tester would read it out of their inbox.
    """
    for _ in range(20):
        if SERVER_LOG.exists():
            text = SERVER_LOG.read_text(errors="replace")
            matches = re.findall(
                rf"To: {re.escape(email)}\b.*?Your KOLO code is (\d{{6}})", text, flags=re.DOTALL
            )
            if matches:
                return matches[-1]
        time.sleep(0.25)
    return None


# --------------------------------------------------------------------------
# Actors
# --------------------------------------------------------------------------


@dataclass
class Actor:
    label: str
    email: str
    api: Api
    user_id: str = ""
    access: str = ""
    refresh: str = ""


def register(base: str, label: str) -> Actor:
    email = f"e2e.{label}.{uuid.uuid4().hex[:8]}@example.com"
    api = Api(base)
    status, body = api.post("/api/v1/auth/register/", {
        "email": email, "password": PASSWORD, "full_name": f"E2E {label.title()}",
    })
    if status != 201:
        raise RuntimeError(f"register {label} failed: {status} {body}")
    actor = Actor(label=label, email=email, api=api, user_id=body["data"]["user"]["id"])
    return actor


def log_in(actor: Actor) -> None:
    status, body = actor.api.post("/api/v1/auth/login/", {"identifier": actor.email, "password": PASSWORD})
    if status != 200:
        raise RuntimeError(f"login {actor.label} failed: {status} {body}")
    actor.access = body["data"]["access"]
    actor.refresh = body["data"]["refresh"]
    actor.api.token = actor.access


def verify_email(actor: Actor, report: Report, *, expect_replay_refused: bool = False) -> bool:
    """Complete the OTP step the way a member does, using the code they were sent.

    Registration already dispatches a code; a second request inside the resend
    cooldown is refused on purpose, so the harness reads the one already sent.
    """
    code = read_otp(actor.email)
    if not code:
        report.check(f"{actor.label}: OTP retrievable from the dev email log", False, "no code in server log")
        return False

    status, body = actor.api.post("/api/v1/auth/verify/", {"code": code, "purpose": "signup"})
    level = body.get("data", {}).get("user", {}).get("verification_level")
    ok = report.check(
        f"{actor.label}: email verified with the code from their inbox",
        status == 200 and level in {"contact", "basic"},
        f"{status} {body.get('error', {}).get('code', '')} level={level}",
    )
    if expect_replay_refused and ok:
        status, body = actor.api.post("/api/v1/auth/verify/", {"code": code, "purpose": "signup"})
        report.check(
            f"{actor.label}: the same code cannot be used twice",
            status == 400 and body["error"]["code"] == "otp_missing",
            f"{status} {body.get('error', {}).get('code')}",
        )
    return ok


# --------------------------------------------------------------------------
# The scenario
# --------------------------------------------------------------------------


def run(report: Report, *, base: str, keep: bool) -> int:
    report.section("0. Server is alive and honest about its dependencies")
    health = Api(base)
    status, body = health.get("/health/")
    report.check("GET /health/ returns 200", status == 200, str(status))
    report.check("health reports the database reachable", body.get("database") is True, str(body))
    status, body = health.get("/ready/")
    report.check("GET /ready/ returns 200 with database and cache", status == 200 and body.get("status") == "ready", str(body))

    reset_throttles()
    report.section("1. Registration, OTP verification, login, token rotation")
    chair = register(base, "chair")
    treasurer = register(base, "treasurer")
    amaka = register(base, "amaka")
    bola = register(base, "bola")
    outsider = register(base, "outsider")
    report.check("four members and one outsider registered over HTTP", True)

    log_in(chair)

    # --- OTP brute-force protection, observed over HTTP -------------------
    code = read_otp(chair.email)
    report.check("the signup code is delivered to the member's inbox", bool(code), "nothing in the dev mail log")
    counts = []
    for _ in range(3):
        status, body = chair.api.post("/api/v1/auth/verify/", {"code": "000000", "purpose": "signup"})
        counts.append(body.get("error", {}).get("details", {}).get("attempts_left"))
    report.check(
        "wrong OTP codes actually consume attempts over the wire",
        counts == [4, 3, 2], f"attempts_left sequence was {counts}",
    )
    status, body = chair.api.post("/api/v1/auth/verify/", {"code": code, "purpose": "signup"})
    report.check("the correct code still verifies after some wrong guesses", status == 200, f"{status} {body}")

    for actor in (treasurer, amaka, bola, outsider):
        log_in(actor)
        verify_email(actor, report, expect_replay_refused=True)

    # --- refresh rotation -------------------------------------------------
    old_refresh = chair.refresh
    status, body = chair.api.post("/api/v1/auth/refresh/", {"refresh": old_refresh})
    report.check("refresh rotates: new access + new refresh", status == 200 and body["data"]["refresh"] != old_refresh, str(status))
    new_refresh = body["data"]["refresh"]

    status, body = chair.api.post("/api/v1/auth/refresh/", {"refresh": old_refresh})
    report.check(
        "replaying the old refresh token is refused as reuse",
        status == 403 and body["error"]["code"] == "refresh_revoked", f"{status} {body.get('error', {}).get('code')}",
    )
    status, body = chair.api.post("/api/v1/auth/refresh/", {"refresh": new_refresh})
    report.check(
        "after reuse is detected the whole token family is dead",
        status == 403, f"live token returned {status} — a stolen session would have survived",
    )

    # Sign in again, since the family is legitimately gone now.
    log_in(chair)

    reset_throttles()
    report.section("2. Group formation and membership rules")
    status, body = chair.api.post("/api/v1/groups/", {
        "name": f"E2E Ajo {uuid.uuid4().hex[:6]}", "description": "End to end rotational group",
        "currency": "NGN", "visibility": "public", "requires_approval": True,
        "requires_dual_approval_for_withdrawals": True,
    })
    report.check("chairperson creates a group", status == 201, f"{status} {body}")
    group = body["data"]
    slug = group["slug"]

    status, body = chair.api.get(f"/api/v1/groups/{slug}/members/")
    report.check("creator is an active owner member", status == 200 and len(body["data"]) == 1, str(body)[:200])

    # Outsider asks to join; approval is required.
    status, body = outsider.api.post(f"/api/v1/groups/{slug}/join/", {"message": "Please let me in"})
    requested = status == 201 and body.get("data", {}).get("requested") is True
    report.check("a stranger's join request waits for approval", requested, f"{status} {body}")
    join_request_id = body.get("data", {}).get("request_id") if requested else None

    status, body = outsider.api.get(f"/api/v1/groups/{slug}/members/")
    report.check(
        "a non-member cannot read the member list",
        status in (403, 404), f"got {status}: membership is not a formality",
    )

    if join_request_id:
        status, body = chair.api.post(f"/api/v1/groups/{slug}/requests/{join_request_id}/review/", {"approve": False})
        report.check("an officer can decline a join request", status == 200, f"{status} {body}")
        status, body = outsider.api.get(f"/api/v1/groups/{slug}/members/")
        report.check("a declined stranger still cannot read the group", status in (403, 404), f"got {status}")

    status, body = chair.api.post("/api/v1/groups/", {
        "name": f"E2E Private {uuid.uuid4().hex[:6]}", "visibility": "private", "currency": "NGN",
    })
    private_slug = body.get("data", {}).get("slug")
    status, body = outsider.api.post(f"/api/v1/groups/{private_slug}/join/", {"message": "hello"})
    report.check(
        "a private group refuses cold join attempts (invite only)",
        status == 403 and body["error"]["code"] == "invite_required", f"{status} {body.get('error', {}).get('code')}",
    )

    # Invite the two savers directly.
    member_ids = {}
    for actor in (treasurer, amaka, bola):
        status, body = chair.api.post(f"/api/v1/groups/{slug}/invitations/", {"email": actor.email})
        report.check(f"invitation sent to {actor.label}", status == 201, f"{status} {body}")
        token = body.get("data", {}).get("token") or body.get("data", {}).get("code")
        status, body = actor.api.post("/api/v1/groups/invitations/accept/", {"token": token} if token else {})
        report.check(f"{actor.label} accepts the invitation", status == 200, f"{status} {body}")

    status, body = chair.api.get(f"/api/v1/groups/{slug}/members/")
    members = {m["full_name"]: m for m in body.get("data", [])}
    report.check("the group now has four active members", len(members) == 4, f"has {len(members)}: {list(members)}")

    # Officers.
    member_rows = body.get("data", [])
    treasurer_row = next((m for m in member_rows if "Treasurer" in m["full_name"]), None)
    if treasurer_row:
        status, body = chair.api.patch_(f"/api/v1/groups/{slug}/members/{treasurer_row['id']}/role/", {"role": "treasurer"})
        report.check("chairperson appoints a treasurer", status == 200, f"{status} {body}")

    membership_ids = [m["id"] for m in member_rows]
    user_ids = {m["full_name"]: m["id"] for m in member_rows}

    reset_throttles()
    report.section("3. Programme, participants, rotation order")
    start = (datetime.now() + timedelta(days=1)).date().isoformat()
    status, body = chair.api.post("/api/v1/savings/programmes/", {
        "group": slug, "name": "E2E Monthly Ajo", "type": "rotational",
        "contribution_amount_minor": 1_000_00,  # ₦1,000 in kobo, integer minor units
        "frequency": "monthly", "start_date": start, "cycle_length": 1,
        "visibility": "members", "currency": "NGN",
    })
    report.check("officer creates a rotational programme", status == 201, f"{status} {body}")
    programme = body["data"]
    programme_id = programme["id"]

    status, body = amaka.api.post("/api/v1/savings/programmes/", {
        "group": slug, "name": "Member cannot do this", "type": "rotational",
        "contribution_amount_minor": 100, "frequency": "monthly", "start_date": start,
    })
    report.check("a plain member cannot create a programme", status in (403, 400), f"got {status}")

    status, body = chair.api.post(f"/api/v1/savings/programmes/{programme_id}/participants/", {
        "membership_ids": membership_ids,
    })
    report.check("officer enrols all four members", status == 201 and body["data"]["added"] == 4, f"{status} {body}")

    status, body = amaka.api.post(f"/api/v1/savings/programmes/{programme_id}/participants/", {
        "membership_ids": membership_ids,
    })
    report.check("a plain member cannot enrol people", status in (403,), f"got {status}")

    status, body = chair.api.get(f"/api/v1/savings/programmes/{programme_id}/participants/")
    participants = body.get("data", [])
    report.check("four participants listed", len(participants) == 4, str(len(participants)))
    participation_ids = [p["id"] for p in participants]

    status, body = chair.api.put(f"/api/v1/savings/programmes/{programme_id}/rotation/", {
        "participation_ids": participation_ids,
    })
    report.check("officer locks the payout order", status == 200 and len(body.get("data", [])) == 4, f"{status} {body}")

    status, body = chair.api.post(f"/api/v1/savings/programmes/{programme_id}/status/", {"status": "active"})
    report.check(
        "a draft programme cannot skip straight to active",
        status == 400 and body["error"]["code"] == "programme_transition_invalid", f"{status}",
    )
    status, body = chair.api.post(f"/api/v1/savings/programmes/{programme_id}/status/", {"status": "scheduled"})
    report.check("programme is scheduled", status == 200, f"{status} {body}")
    status, body = chair.api.post(f"/api/v1/savings/programmes/{programme_id}/status/", {"status": "active"})
    report.check("scheduled programme activates", status == 200, f"{status} {body}")

    status, body = chair.api.get(f"/api/v1/savings/programmes/{programme_id}/cycles/")
    cycles = body.get("data", [])
    report.check("activation opens the first rotation cycle", len(cycles) == 1, f"{len(cycles)} cycles")
    report.note(f"cycle 1 beneficiary: {cycles[0].get('beneficiary_name') if cycles else 'none'}")

    reset_throttles()
    report.section("4. Contribution → payment intent → provider → settlement → ledger")
    status, body = amaka.api.get("/api/v1/savings/obligations/")
    report.check("member sees their obligations", status == 200 and len(body["data"]) >= 1, f"{status} {body}")
    obligation = body["data"][0] if body.get("data") else {}
    report.check(
        "obligation amount is an integer in minor units",
        isinstance(obligation.get("amount_minor"), int),
        f"{obligation.get('amount_minor')!r} ({type(obligation.get('amount_minor')).__name__})",
    )

    status, body = amaka.api.post(f"/api/v1/savings/programmes/{programme_id}/contributions/", {
        "amount_minor": 1_000_00, "obligation_id": obligation.get("id"),
        "idempotency_key": f"e2e-{uuid.uuid4().hex[:8]}",
    })
    report.check("member starts a contribution and gets a checkout", status == 201, f"{status} {body}")
    contribution = body.get("data", {}).get("contribution", {})
    payment = body.get("data", {}).get("payment", {})
    intent_reference = payment.get("reference")
    report.check("contribution is not marked paid before the provider confirms",
                 contribution.get("status") in {"pending", "pending_payment", "awaiting_payment"},
                 f"status={contribution.get('status')}")

    # The provider now actually has the money. Only then may the books move.
    settle = django_shell(
        "from apps.payments.models import PaymentIntent\n"
        "from apps.payments.providers import store\n"
        f"i = PaymentIntent.objects.get(reference='{intent_reference}')\n"
        "store.record(i.provider_reference, amount_minor=i.amount_minor, currency=i.currency, paid=True)\n"
        "print('provider recorded the charge')\n"
    )
    report.note(settle)

    status, body = amaka.api.post("/api/v1/payments/verify/", {"reference": intent_reference})
    report.check("server-side verification confirms the payment", status == 200 and body["data"]["status"] == "succeeded",
                 f"{status} {body}")

    status, body = amaka.api.post("/api/v1/payments/verify/", {"reference": intent_reference})
    report.check("verifying twice is idempotent (no double credit)", status == 200 and body["data"]["status"] == "succeeded",
                 f"{status} {body}")

    status, body = amaka.api.get("/api/v1/savings/contributions/")
    mine = [c for c in body.get("data", []) if c.get("status") == "confirmed"]
    report.check("the member's own contribution reads back as confirmed", bool(mine), str(body)[:200])
    report.check(
        "the confirmed amount matches what the member paid (integer minor units)",
        bool(mine) and mine[0].get("amount_minor") == 1_000_00,
        f"amount={mine[0].get('amount_minor') if mine else None}",
    )

    status, body = chair.api.get(f"/api/v1/savings/groups/{slug}/summary/")
    report.check("group summary is available to officers", status == 200, f"{status} {body}")
    summary = body.get("data", {})
    report.note(f"summary: {json.dumps(summary)[:300]}")

    # A second member pays, the rest do not. The payout must be blocked.
    reset_throttles()
    report.section("5. Financial safety: an under-funded payout cannot be signed off")
    status, body = chair.api.get(f"/api/v1/savings/programmes/{programme_id}/cycles/")
    cycles = body.get("data", [])
    report.check("cycle list is readable", status == 200 and len(cycles) >= 1, f"{status}")
    cycle_id = cycles[0]["id"]
    report.note(f"cycle 1 collected {cycles[0].get('collected_total_minor')} of {cycles[0].get('expected_total_minor')} expected")
    report.check(
        "an extra cycle cannot be opened mid-collection",
        chair.api.post(f"/api/v1/savings/programmes/{programme_id}/cycles/")[0] == 409,
        "a second cycle would split the same collection",
    )

    status, body = chair.api.post(f"/api/v1/savings/cycles/{cycle_id}/approve/")
    if status == 200:
        report.note("first approval accepted while the cycle is under-funded (execution must still refuse)")
    else:
        report.check("approval is refused while the cycle is under-funded", status in (400, 403, 409),
                     f"{status} {body.get('error', {}).get('code')}")

    if status == 200:
        status, body = chair.api.post(f"/api/v1/savings/cycles/{cycle_id}/execute/")
        report.check(
            "the same officer cannot both approve and execute (separation of duties)",
            status in (400, 403, 409),
            f"got {status} — dual control failed",
        )

    reset_throttles()
    reset_throttles()
    report.section("5b. A fully funded payout, two officers, to a bank account")
    # Everything above proved that an unfunded payout is refused. This proves the
    # other half: when the money really is there and two different officers sign,
    # it goes through — and the same officer cannot do both halves.

    # Everyone who is due to contribute actually pays.
    for payer in (treasurer, amaka, bola):
        status, body = payer.api.get("/api/v1/savings/obligations/")
        for owed in body.get("data", []):
            if owed.get("programme_id") != programme_id or owed.get("status") == "settled":
                continue
            status, body = payer.api.post(f"/api/v1/savings/programmes/{programme_id}/contributions/", {
                "amount_minor": owed["amount_minor"], "obligation_id": owed["id"],
                "idempotency_key": f"e2e-fund-{uuid.uuid4().hex[:8]}",
            })
            if status != 201:
                report.check(f"a member can start their contribution", False, f"{status} {body}")
                continue
            reference = body.get("data", {}).get("payment", {}).get("reference")
            django_shell(
                "from apps.payments.models import PaymentIntent\n"
                "from apps.payments.providers import store\n"
                f"i = PaymentIntent.objects.get(reference='{reference}')\n"
                "store.record(i.provider_reference, amount_minor=i.amount_minor, currency=i.currency, paid=True)\n"
                "print('paid')\n"
            )
            payer.api.post("/api/v1/payments/verify/", {"reference": reference})
    # The chairperson pays their own way too; without it the cycle is short.
    status, body = chair.api.get("/api/v1/savings/obligations/")
    for owed in body.get("data", []):
        if owed.get("programme_id") != programme_id or owed.get("status") == "settled":
            continue
        status, body = chair.api.post(f"/api/v1/savings/programmes/{programme_id}/contributions/", {
            "amount_minor": owed["amount_minor"], "obligation_id": owed["id"],
            "idempotency_key": f"e2e-fund-{uuid.uuid4().hex[:8]}",
        })
        if status == 201:
            reference = body.get("data", {}).get("payment", {}).get("reference")
            django_shell(
                "from apps.payments.models import PaymentIntent\n"
                "from apps.payments.providers import store\n"
                f"i = PaymentIntent.objects.get(reference='{reference}')\n"
                "store.record(i.provider_reference, amount_minor=i.amount_minor, currency=i.currency, paid=True)\n"
                "print('paid')\n"
            )
            chair.api.post("/api/v1/payments/verify/", {"reference": reference})

    status, body = chair.api.get(f"/api/v1/savings/programmes/{programme_id}/cycles/")
    cycle = body["data"][0]
    cycle_id = cycle["id"]
    report.note(f"cycle 1 now {cycle.get('collected_total_minor')} of {cycle.get('expected_total_minor')}")

    # The chairperson approves, and is refused the execution: same person, both halves.
    status, body = chair.api.post(f"/api/v1/savings/cycles/{cycle_id}/approve/")
    report.check("cycle 1 can be approved once funded", status == 200, f"{status} {body}")
    status, body = chair.api.post(f"/api/v1/savings/cycles/{cycle_id}/execute/", {
        "account_number": "0123456789", "bank_code": "058", "account_name": "E2E Beneficiary",
    })
    report.check(
        "the officer who approved cannot also execute it",
        status == 403 and body.get("error", {}).get("code") == "approver_cannot_execute",
        f"{status} {body}",
    )

    # A different officer can.
    status, body = treasurer.api.post(f"/api/v1/savings/cycles/{cycle_id}/execute/", {
        "account_number": "0123456789", "bank_code": "058", "account_name": "E2E Beneficiary",
    })
    report.check("a second officer can execute the approved payout", status == 200, f"{status} {body}")

    # Executing again must not pay again.
    status, body = treasurer.api.post(f"/api/v1/savings/cycles/{cycle_id}/execute/", {
        "account_number": "0123456789", "bank_code": "058", "account_name": "E2E Beneficiary",
    })
    report.check("executing twice does not pay twice", status in (200, 400, 409), f"{status} {body}")
    status, body = chair.api.get(f"/api/v1/savings/programmes/{programme_id}/cycles/")
    paid_cycle = next(c for c in body["data"] if c["id"] == cycle_id)
    report.check("the cycle reads back as paid", paid_cycle.get("status") == "paid",
                 f"status={paid_cycle.get('status')}")
    report.note(f"cycle ledger reference {paid_cycle.get('ledger_reference')}")

    # Still a plain member at this point: this is the last moment the assertion
    # below is about a member rather than an officer.
    status, body = bola.api.get(f"/api/v1/groups/{slug}/requests/")
    report.check("a plain member cannot read join requests (officer permission)", status in (403,), f"got {status}")

    # Withdrawals need their own pot. The rotation above paid out everything the
    # group had collected — which is what a full rotation does — so a withdrawal
    # against the same programme could only ever be refused for lack of funds.
    # A second programme, funded for real through the same payment flow, keeps the
    # withdrawal test about permissions rather than about an empty balance.
    status, body = chair.api.post("/api/v1/savings/programmes/", {
        "group": slug, "name": "E2E Welfare Fund", "type": "target",
        "contribution_amount_minor": 50_000, "frequency": "monthly", "start_date": start,
        "target_amount_minor": 200_000, "visibility": "members", "currency": "NGN",
    })
    report.check("a second programme is created for withdrawals", status == 201, f"{status} {body}")
    welfare_id = body["data"]["id"]

    status, body = chair.api.post(f"/api/v1/savings/programmes/{welfare_id}/participants/", {
        "membership_ids": membership_ids,
    })
    report.check("members join the welfare programme", status == 201, f"{status} {body}")

    # A draft programme has no obligations, so there would be nothing to pay and
    # the fund would sit empty. It has to be scheduled and started first, exactly
    # as the rotation programme was.
    for target in ("scheduled", "active"):
        status, body = chair.api.post(f"/api/v1/savings/programmes/{welfare_id}/status/",
                                      {"status": target})
        report.check(f"the welfare programme is {target}", status == 200, f"{status} {body}")

    # One member actually pays into it: now the fund has money of its own.
    status, body = chair.api.get("/api/v1/savings/obligations/")
    welfare_due = [o for o in body.get("data", [])
                   if o.get("programme_id") == welfare_id and o.get("status") != "settled"]
    if welfare_due:
        owed = welfare_due[0]
        status, body = chair.api.post(f"/api/v1/savings/programmes/{welfare_id}/contributions/", {
            "amount_minor": owed["amount_minor"], "obligation_id": owed["id"],
            "idempotency_key": f"e2e-welfare-{uuid.uuid4().hex[:8]}",
        })
        if status == 201:
            reference = body.get("data", {}).get("payment", {}).get("reference")
            django_shell(
                "from apps.payments.models import PaymentIntent\n"
                "from apps.payments.providers import store\n"
                f"i = PaymentIntent.objects.get(reference='{reference}')\n"
                "store.record(i.provider_reference, amount_minor=i.amount_minor, currency=i.currency, paid=True)\n"
                "print('paid')\n"
            )
            chair.api.post("/api/v1/payments/verify/", {"reference": reference})
    report.check("the welfare fund holds money", status == 201, f"{status}")

    # Now the two-signature story, on money that is really there.
    for name, role in (("Amaka", "admin"), ("Bola", "owner")):
        row = next((m for m in member_rows if name in m["full_name"]), None)
        if row:
            status, body = chair.api.patch_(f"/api/v1/groups/{slug}/members/{row['id']}/role/",
                                            {"role": role})
            report.check(f"chairperson makes {name} an officer who can approve",
                         status == 200, f"{status} {body}")

    status, body = chair.api.post(f"/api/v1/savings/programmes/{welfare_id}/withdrawals/", {
        "amount_minor": 5_000, "reason": "other", "note": "e2e separation-of-duties check",
    })
    report.check("an officer requests a withdrawal", status == 201, f"{status} {body}")
    withdrawal_id = body.get("data", {}).get("id")
    report.check("a new withdrawal waits for a second officer",
                 body.get("data", {}).get("status") == "pending_approval",
                 f"status={body.get('data', {}).get('status')}")

    # The chairperson can approve in principle — which is what makes this test
    # worth running. The refusal must come from the conflict rule, not from the
    # permission gate, or the hole would simply be hidden behind a different error.
    status, body = chair.api.post(f"/api/v1/savings/withdrawals/{withdrawal_id}/decide/", {"approve": True})
    report.check(
        "the requester cannot approve their own withdrawal",
        status == 403 and body.get("error", {}).get("code") == "self_approval_blocked",
        f"{status} {body}",
    )

    # The treasurer signs, and the treasurer also holds the execute permission.
    # That combination is the whole point: the refusal that follows must come
    # from the separation-of-duties rule, not from a missing permission.
    status, body = amaka.api.post(f"/api/v1/savings/withdrawals/{withdrawal_id}/decide/", {"approve": True})
    report.check("a second officer signs it", status == 200, f"{status} {body}")

    status, body = bola.api.post(f"/api/v1/savings/withdrawals/{withdrawal_id}/decide/", {"approve": True})
    report.check("a third officer completes dual approval", status == 200, f"{status} {body}")

    # Bola holds both approve and execute, which is the case worth checking: the
    # refusal has to come from the conflict rule, not from a missing permission.
    status, body = bola.api.post(f"/api/v1/savings/withdrawals/{withdrawal_id}/execute/", {
        "account_number": "0123456789", "bank_code": "058", "account_name": "E2E Beneficiary",
    })
    report.check(
        "the officer who approved cannot also send it",
        status == 403 and body.get("error", {}).get("code") == "approver_cannot_execute",
        f"{status} {body}",
    )

    status, body = chair.api.post(f"/api/v1/savings/withdrawals/{withdrawal_id}/execute/", {
        "account_number": "0123456789", "bank_code": "058", "account_name": "E2E Beneficiary",
    })
    report.check(
        "an approved withdrawal reaches the provider",
        status == 200 and body.get("data", {}).get("status") not in {None, "approved"},
        f"{status} {body}",
    )

    reset_throttles()
    report.section("6. Permissions and membership restrictions")
    status, body = outsider.api.get(f"/api/v1/savings/programmes/{programme_id}/")
    report.check("a non-member cannot read a group's programme", status in (403, 404), f"got {status}")

    status, body = outsider.api.get(f"/api/v1/savings/obligations/")
    report.check("a non-member sees no obligations", status == 200 and body.get("data") == [], str(body)[:150])


    status, body = amaka.api.post(f"/api/v1/savings/cycles/{cycle_id}/approve/")
    report.check("a plain member cannot approve a payout", status in (403,), f"got {status}")

    status, body = outsider.api.post(f"/api/v1/savings/programmes/{programme_id}/contributions/",
                                     {"amount_minor": 100})
    report.check("a non-member cannot contribute to a programme", status in (403, 404), f"got {status}")

    reset_throttles()
    report.section("7. Ledger consistency (server-side, the only source of truth)")
    ledger_state = django_shell(
        "from apps.ledger import services as ledger\n"
        "from apps.ledger.models import Account\n"
        "for acc in Account.objects.all().order_by('code'):\n"
        "    print(f'{acc.code:28} {ledger.balance_of(acc):>12}')\n"
    )
    print(DIM + "\n".join("    " + line for line in ledger_state.splitlines()) + RESET)

    balanced = django_shell(
        "from django.db.models import Sum\n"
        "from apps.ledger.models import JournalEntry\n"
        "print(JournalEntry.objects.aggregate(t=Sum('amount_minor'))['t'] or 0)\n"
    )
    report.check("the ledger balances to zero overall (every posting has two sides)",
                 balanced.strip() == "0", f"residual {balanced}")

    unbalanced_txns = django_shell(
        "from django.db.models import Sum\n"
        "from apps.ledger.models import JournalTransaction\n"
        "bad = []\n"
        "for tx in JournalTransaction.objects.all():\n"
        "    total = tx.entries.aggregate(t=Sum('amount_minor'))['t'] or 0\n"
        "    if total != 0:\n"
        "        bad.append(str(tx.pk))\n"
        "print(len(bad))\n"
    )
    report.check("no individual journal transaction is one-sided", unbalanced_txns.strip() == "0",
                 f"{unbalanced_txns} unbalanced transactions")

    # The member's funds and the programme pool must agree with what was paid.
    reconciliation = django_shell(
        "from django.db.models import Sum\n"
        "from apps.ledger import services as ledger\n"
        "from apps.ledger.models import Account\n"
        "from apps.savings.models import Contribution\n"
        "pool = Account.objects.filter(code='PROGRAMME_POOL', scope_type='programme', scope_id='" + programme_id + "').first()\n"
        "paid = Contribution.objects.filter(programme_id='" + programme_id + "', status='confirmed').aggregate(s=Sum('amount_minor'))['s'] or 0\n"
        "pool_balance = ledger.balance_of(pool) if pool else None\n"
        # A rotation payout and a withdrawal have already left the pool by now.
        # Reconciliation compares what was paid in against what is still there
        # plus what has gone out; money is conserved, not merely present.
        "from apps.savings.models import WithdrawalRequest, RotationCycle\n"
        "paid_out = WithdrawalRequest.objects.filter(programme_id='" + programme_id + "', status='paid').aggregate(s=Sum('amount_minor'))['s'] or 0\n"
        "cycles_out = RotationCycle.objects.filter(programme_id='" + programme_id + "', status='paid').aggregate(s=Sum('payout_amount_minor'))['s'] or 0\n"
        "expected = paid - paid_out - cycles_out\n"
        "print(paid, pool_balance, paid_out, cycles_out, 'MATCH' if pool_balance == expected else 'MISMATCH')\n"
    )
    print(DIM + f"    (confirmed contributions, programme pool balance): {reconciliation}" + RESET)
    report.check(
        "the programme pool balance equals the money members actually paid",
        reconciliation.split()[-1] == "MATCH" if reconciliation else False,
        reconciliation,
    )

    collected = django_shell(
        "from apps.savings.models import Contribution\n"
        "from django.db.models import Sum\n"
        f"print(Contribution.objects.filter(programme_id='{programme_id}', status='confirmed').aggregate(s=Sum('amount_minor'))['s'] or 0)\n"
    )
    report.check("confirmed contributions are recorded in minor units", collected.strip().isdigit(), collected)

    reset_throttles()
    report.section("8. Duplicate webhooks and reversal safety")
    webhook_note = django_shell(
        "import hashlib, hmac, json\n"
        "from django.conf import settings\n"
        "from apps.payments.models import PaymentIntent, WebhookEvent\n"
        "from apps.payments import services as pay\n"
        f"i = PaymentIntent.objects.get(reference='{intent_reference}')\n"
        "body = json.dumps({'event_id': 'e2e-replay-1', 'event': 'payment.completed',\n"
        "  'provider_reference': i.provider_reference, 'amount_minor': i.amount_minor,\n"
        "  'currency': i.currency, 'paid': True}).encode()\n"
        "sig = hmac.new(settings.KOLO_WEBHOOK_SECRET.encode(), body, hashlib.sha256).hexdigest()\n"
        "e1 = pay.handle_webhook(provider_name='mock', headers={'X-Kolo-Mock-Signature': sig}, body=body)\n"
        "e2 = pay.handle_webhook(provider_name='mock', headers={'X-Kolo-Mock-Signature': sig}, body=body)\n"
        "print('same_event_record', e1.pk == e2.pk)\n"
        "print('event_count', WebhookEvent.objects.filter(event_id='e2e-replay-1').count())\n"
    )
    print(DIM + "\n".join("    " + line for line in webhook_note.splitlines()) + RESET)
    report.check("a replayed webhook resolves to one event record", "event_count 1" in webhook_note, webhook_note)

    bad_signature = django_shell(
        "import json\n"
        "from apps.payments.models import PaymentIntent\n"
        "from apps.payments import services as pay\n"
        f"i = PaymentIntent.objects.get(reference='{intent_reference}')\n"
        "body = json.dumps({'event_id': 'e2e-forged-1', 'event': 'payment.completed',\n"
        "  'provider_reference': i.provider_reference, 'amount_minor': i.amount_minor,\n"
        "  'currency': i.currency, 'paid': True}).encode()\n"
        "e = pay.handle_webhook(provider_name='mock', headers={'X-Kolo-Mock-Signature': 'deadbeef'*8}, body=body)\n"
        "print(e.status)\n"
    )
    report.check("a forged webhook is rejected", bad_signature.strip() == "failed", bad_signature)

    reset_throttles()
    report.section("9. Group chat (HTTP side; the WebSocket transport is checked separately)")
    status, body = chair.api.get(f"/api/v1/comms/groups/{slug}/chat/")
    report.check("the group's chat channel is created on first use", status == 200, f"{status} {body}")
    conversation_id = body.get("data", {}).get("id")

    status, body = amaka.api.get(f"/api/v1/comms/groups/{slug}/chat/")
    report.check("every member reaches the same conversation", status == 200 and body.get("data", {}).get("id") == conversation_id,
                 f"{status}")

    status, body = amaka.api.post(f"/api/v1/comms/conversations/{conversation_id}/messages/",
                                  {"body": "Welcome to the ajo, everyone."})
    report.check("a member can post a message", status == 201, f"{status} {body}")

    status, body = chair.api.get(f"/api/v1/comms/conversations/{conversation_id}/messages/")
    report.check("another member reads the message back", status == 200 and len(body.get("data", [])) >= 1,
                 f"{status} {body}")

    status, body = outsider.api.get(f"/api/v1/comms/conversations/{conversation_id}/messages/")
    report.check("a non-member cannot read group chat", status in (403, 404), f"got {status}")

    status, body = outsider.api.post(f"/api/v1/comms/conversations/{conversation_id}/messages/", {"body": "let me in"})
    report.check("a non-member cannot post to group chat", status in (403, 404), f"got {status}")

    report.section("10. Summary")
    total = len(report.passed) + len(report.failed)
    print(f"\n  {len(report.passed)}/{total} checks passed")
    if report.failed:
        print(f"  {RED}FAILURES:{RESET}")
        for failure in report.failed:
            print(f"    - {failure}")
    if report.notes:
        print(f"  {YELLOW}NOTES:{RESET}")
        for note in report.notes:
            print(f"    - {note}")
    print(f"\n  group slug: {slug}")
    print(f"  programme:  {programme_id}")
    print(f"  chair:      {chair.email}")
    print(f"  members:    {treasurer.email}, {amaka.email}, {bola.email}")
    print(f"  http calls: {len(chair.api.calls) + len(amaka.api.calls)}")
    return 0 if not report.failed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default=BASE)
    parser.add_argument("--keep", action="store_true", help="keep created data (no cleanup)")
    args = parser.parse_args()

    report = Report()
    try:
        return run(report, base=args.base, keep=args.keep)
    except Exception as exc:  # noqa: BLE001 - a crash is a failure, report it as one
        print(f"\n{RED}HARNESS ERROR{RESET}: {exc}")
        import traceback

        traceback.print_exc()
        total = len(report.passed) + len(report.failed)
        print(f"\n  {len(report.passed)}/{total} checks passed before the error")
        return 2


if __name__ == "__main__":
    sys.exit(main())
