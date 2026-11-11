from django.urls import path

from apps.comms.consumers import ConversationConsumer
from apps.notifications.consumers import NotificationConsumer

websocket_urlpatterns = [
    path("ws/conversations/<uuid:conversation_id>/", ConversationConsumer.as_asgi()),
    path("ws/notifications/", NotificationConsumer.as_asgi()),
]
