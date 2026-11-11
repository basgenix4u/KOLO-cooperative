from django.urls import path

from . import views

app_name = "comms"

urlpatterns = [
    path("conversations/", views.ConversationListView.as_view(), name="conversations"),
    path("groups/<slug:slug>/chat/", views.GroupConversationView.as_view(), name="group-chat"),
    path("conversations/<uuid:conversation_id>/messages/", views.MessageListView.as_view(), name="messages"),
    path("conversations/<uuid:conversation_id>/read/", views.ConversationReadView.as_view(), name="read"),
    path("messages/<uuid:message_id>/moderate/", views.MessageModerateView.as_view(), name="moderate"),
]
