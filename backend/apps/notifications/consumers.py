"""Live notification stream for a signed-in member."""

from __future__ import annotations

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer


class NotificationConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        user = self.scope.get("user")
        if not user or not user.is_authenticated:
            await self.close(code=4401)
            return
        self.group_name = f"user.{user.pk}"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        unread = await self._unread(user)
        await self.accept()
        await self.send_json({"event": "ready", "unread": unread})

    async def disconnect(self, code):
        if hasattr(self, "group_name"):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def notification_event(self, event):
        await self.send_json({k: v for k, v in event.items() if k != "type"})

    @database_sync_to_async
    def _unread(self, user):
        from apps.notifications.models import Notification

        return Notification.objects.filter(user=user, read_at__isnull=True).count()
