"""Group chat over WebSockets.

Authorisation happens in `connect` by calling the same service the REST history
endpoint uses. A member of group A cannot join group B's room by guessing a URL.
"""

from __future__ import annotations

import json
import logging

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer

logger = logging.getLogger("kolo.security")


class ConversationConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        user = self.scope.get("user")
        if not user or not user.is_authenticated:
            await self.close(code=4401)
            return

        self.conversation_id = str(self.scope["url_route"]["kwargs"]["conversation_id"])
        allowed = await self._may_access(user, self.conversation_id)
        if not allowed:
            # 4403 tells the client it was a permission problem, not a network blip.
            await self.close(code=4403)
            return

        self.room = f"conversation.{self.conversation_id}"
        await self.channel_layer.group_add(self.room, self.channel_name)
        await self.accept()

    async def disconnect(self, code):
        room = getattr(self, "room", None)
        if room:
            await self.channel_layer.group_discard(room, self.channel_name)

    async def receive_json(self, content, **kwargs):
        """Inbound frames are deliberately limited to typing + read receipts.

        Messages are sent over HTTP so they get validation, rate limiting and a
        transcript; a WebSocket write path would duplicate those rules.
        """
        user = self.scope["user"]
        action = (content or {}).get("action")
        if action == "typing":
            await self.channel_layer.group_send(
                self.room,
                {"type": "chat.event", "event": "typing", "user_id": str(user.pk),
                 "display_name": user.display_name},
            )
        elif action == "read":
            await self._mark_read(user, self.conversation_id)
            await self.channel_layer.group_send(
                self.room, {"type": "chat.event", "event": "read", "user_id": str(user.pk)}
            )
        else:
            await self.send_json({"event": "error", "message": "Unsupported action."})

    async def chat_event(self, event):
        await self.send_json(
            {k: v for k, v in event.items() if k != "type"}
        )

    @database_sync_to_async
    def _may_access(self, user, conversation_id):
        from apps.comms.models import Conversation
        from apps.comms.services import require_conversation_access

        conversation = Conversation.objects.filter(pk=conversation_id).first()
        if not conversation:
            return False
        try:
            require_conversation_access(user, conversation)
            return True
        except Exception:  # noqa: BLE001 - any refusal is a refusal
            return False

    @database_sync_to_async
    def _mark_read(self, user, conversation_id):
        from apps.comms.models import Conversation
        from apps.comms.services import mark_read

        conversation = Conversation.objects.filter(pk=conversation_id).first()
        if conversation:
            try:
                mark_read(actor=user, conversation=conversation)
            except Exception:  # noqa: BLE001
                pass
