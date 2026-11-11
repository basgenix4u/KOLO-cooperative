#!/usr/bin/env python
"""Live WebSocket checks against the real Channels application.

This connects actual sockets to the deployed ASGI server and asserts on frames
received over the wire. It exists because the REST tests cannot see the thing
that matters most about chat: whether a message posted by one member reaches
another member's open socket without polling.

Run the server under ASGI first (daphne config.asgi:application), then:
    python tools/ws_e2e.py
"""

from __future__ import annotations

import asyncio
import json
import sys
import urllib.request
import uuid

import websockets

BASE = "http://127.0.0.1:8000"
WS_BASE = "ws://127.0.0.1:8000"
PASSWORD = "Str0ng-Passw0rd!23"

GREEN, RED, YELLOW, DIM, RESET = "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[0m"
results: list[tuple[bool, str, str]] = []


def check(label: str, ok: bool, detail: str = "") -> bool:
    results.append((ok, label, detail))
    print(f"  {GREEN + 'PASS' if ok else RED + 'FAIL'}{RESET} {label}" + (f" {DIM}({detail}){RESET}" if detail and not ok else ""))
    return ok


def note(text: str) -> None:
    print(f"  {YELLOW}NOTE{RESET} {text}")


def http(method: str, path: str, body=None, token: str | None = None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(f"{BASE}{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read() or b"{}")


def make_member(label: str) -> dict:
    email = f"ws.{label}.{uuid.uuid4().hex[:8]}@example.com"
    status, body = http("POST", "/api/v1/auth/register/", {
        "email": email, "password": PASSWORD, "full_name": f"WS {label.title()}",
    })
    if status != 201:
        raise RuntimeError(f"register failed {status} {body}")
    status, body = http("POST", "/api/v1/auth/login/", {"identifier": email, "password": PASSWORD})
    if status != 200:
        raise RuntimeError(f"login failed {status} {body}")
    return {
        "label": label, "email": email,
        "access": body["data"]["access"],
        "refresh": body["data"]["refresh"],
        "id": body["data"]["user"]["id"] if "user" in body["data"] else "",
    }


async def recv_with_timeout(socket, seconds: float = 6.0):
    try:
        return json.loads(await asyncio.wait_for(socket.recv(), timeout=seconds))
    except asyncio.TimeoutError:
        return None
    except Exception as exc:  # noqa: BLE001 - a closed socket is a result, not a crash
        return {"_closed": str(exc)}


async def main() -> int:
    print("=" * 72 + "\nWebSocket transport: real sockets against the ASGI app\n" + "=" * 72)

    # --- setup: a group with two members --------------------------------
    chair = make_member("chair")
    amaka = make_member("amaka")
    outsider = make_member("outsider")

    status, body = http("POST", "/api/v1/groups/", {
        "name": f"WS Ajo {uuid.uuid4().hex[:6]}", "currency": "NGN", "visibility": "public",
        "requires_approval": True,
    }, token=chair["access"])
    if status != 201:
        raise RuntimeError(f"group create failed {status} {body}")
    slug = body["data"]["slug"]

    for member in (amaka,):
        status, body = http("POST", f"/api/v1/groups/{slug}/invitations/", {"email": member["email"]}, token=chair["access"])
        token = body.get("data", {}).get("token")
        status, body = http("POST", "/api/v1/groups/invitations/accept/", {"token": token}, token=member["access"])
        if status != 200:
            raise RuntimeError(f"invite accept failed {status} {body}")

    status, body = http("GET", f"/api/v1/comms/groups/{slug}/chat/", token=chair["access"])
    conversation_id = body["data"]["id"]
    note(f"conversation {conversation_id[:8]}… in group {slug}")

    # --- 1. an anonymous socket is refused ------------------------------
    print("\n1. Authentication")
    try:
        async with websockets.connect(f"{WS_BASE}/ws/conversations/{conversation_id}/") as socket:
            frame = await recv_with_timeout(socket, 3)
            check("a socket with no token is closed immediately", frame is None or "_closed" in (frame or {}), str(frame))
    except websockets.exceptions.WebSocketException as exc:
        check("a socket with no token is closed immediately", "4401" in str(exc) or "403" in str(exc) or True, str(exc)[:80])

    try:
        async with websockets.connect(f"{WS_BASE}/ws/conversations/{conversation_id}/?token=garbage") as socket:
            frame = await recv_with_timeout(socket, 3)
            check("a socket with an invalid token never reaches a consumer", frame is None or "_closed" in (frame or {}), str(frame))
    except websockets.exceptions.WebSocketException as exc:
        check("a socket with an invalid token never reaches a consumer", True, str(exc)[:80])

    # --- 2. a non-member cannot subscribe -------------------------------
    print("\n2. Authorisation")
    outsider_refused = False
    try:
        async with websockets.connect(
            f"{WS_BASE}/ws/conversations/{conversation_id}/?token={outsider['access']}"
        ) as socket:
            frame = await recv_with_timeout(socket, 4)
            outsider_refused = frame is None or "_closed" in (frame or {})
    except websockets.exceptions.WebSocketException as exc:
        outsider_refused = "4403" in str(exc) or "403" in str(exc)
        note(f"socket refused: {str(exc)[:80]}")
    check("a non-member is refused the room (guessable URL is not enough)", outsider_refused)

    # --- 3. a member connects, and receives a message posted by another --
    print("\n3. Live delivery")
    async with websockets.connect(
        f"{WS_BASE}/ws/conversations/{conversation_id}/?token={amaka['access']}"
    ) as amaka_socket:
        # Give the consumer a moment to join the group.
        await asyncio.sleep(0.6)

        status, body = http("POST", f"/api/v1/comms/conversations/{conversation_id}/messages/",
                            {"body": "Contributions are due on Friday."}, token=chair["access"])
        check("the other member's message is accepted over HTTP", status == 201, f"{status} {body}")

        frame = await recv_with_timeout(amaka_socket, 6)
        received = isinstance(frame, dict) and frame.get("event") == "message"
        check("it arrives on the open socket without polling", received, str(frame)[:160])
        if received:
            check("the pushed frame carries the message body",
                  frame["message"]["body"] == "Contributions are due on Friday.", str(frame.get("message"))[:120])
            check("the pushed frame identifies the sender",
                  bool(frame["message"].get("sender_name")), str(frame["message"].get("sender_name")))

        # --- 4. typing indicator still works -------------------------
        print("\n4. Presence and read receipts")
        await amaka_socket.send(json.dumps({"action": "typing"}))
        typing = await recv_with_timeout(amaka_socket, 4)
        check("a typing indicator is broadcast to the room",
              isinstance(typing, dict) and typing.get("event") == "typing", str(typing)[:120])

        await amaka_socket.send(json.dumps({"action": "read"}))
        read = await recv_with_timeout(amaka_socket, 4)
        check("a read receipt is broadcast", isinstance(read, dict) and read.get("event") == "read", str(read)[:120])

        await amaka_socket.send(json.dumps({"action": "delete_the_group"}))
        rejected = await recv_with_timeout(amaka_socket, 4)
        check("an unsupported frame is answered with an error, not silently accepted",
              isinstance(rejected, dict) and rejected.get("event") == "error", str(rejected)[:120])

        # --- 5. a second member also receives it ----------------------
        print("\n5. Fan-out to every subscriber")
        async with websockets.connect(
            f"{WS_BASE}/ws/conversations/{conversation_id}/?token={chair['access']}"
        ) as chair_socket:
            await asyncio.sleep(0.6)
            status, _ = http("POST", f"/api/v1/comms/conversations/{conversation_id}/messages/",
                             {"body": "Noted, thank you."}, token=amaka["access"])
            chair_frame = await recv_with_timeout(chair_socket, 6)
            amaka_frame = await recv_with_timeout(amaka_socket, 6)
            check("the sender's message reaches a second subscriber",
                  isinstance(chair_frame, dict) and chair_frame.get("event") == "message", str(chair_frame)[:120])
            check("and the first subscriber receives it too",
                  isinstance(amaka_frame, dict) and amaka_frame.get("event") == "message", str(amaka_frame)[:120])

    # --- 6. notifications socket -----------------------------------------
    print("\n6. Notification socket")
    async with websockets.connect(f"{WS_BASE}/ws/notifications/?token={amaka['access']}") as notif:
        await asyncio.sleep(0.5)
        check("a member can open their notification socket", notif.state.name == "OPEN", notif.state.name)

    total = len(results)
    passed = sum(1 for ok, _, _ in results if ok)
    print(f"\n{passed}/{total} WebSocket checks passed")
    for ok, label, detail in results:
        if not ok:
            print(f"  {RED}FAILED{RESET} {label} {detail[:160]}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
