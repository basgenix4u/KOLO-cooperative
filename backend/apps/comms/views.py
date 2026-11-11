"""Chat history over HTTP; live updates arrive over the WebSocket."""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.groups.models import Group
from apps.groups.permissions import require_membership

from .models import Conversation, Message
from .serializers import ConversationSerializer, MessageCreateSerializer, MessageSerializer
from .services import (
    mark_read, moderate_message, post_message, require_conversation_access, unread_count,
)


class GroupConversationView(APIView):
    """The group's chat channel, created on first use."""

    permission_classes = [IsAuthenticated]

    def get(self, request, slug):
        group = get_object_or_404(Group, slug=slug)
        require_membership(request.user, group)
        conversation, _ = Conversation.objects.get_or_create(
            group=group, kind=Conversation.Kind.GROUP,
            defaults={"title": f"{group.name} chat", "created_by": request.user},
        )
        return Response({"data": ConversationSerializer(conversation, context={"request": request}).data})


class ConversationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        conversations = (
            Conversation.objects.filter(participants__user=request.user)
            | Conversation.objects.filter(group__memberships__user=request.user,
                                          group__memberships__status="active")
        ).distinct().order_by("-created_at")
        return Response({"data": ConversationSerializer(conversations, many=True,
                                                        context={"request": request}).data})


class MessageListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, conversation_id):
        conversation = get_object_or_404(Conversation, pk=conversation_id)
        require_conversation_access(request.user, conversation)
        limit = min(int(request.query_params.get("limit", 50)), 100)
        messages = conversation.messages.select_related("sender").order_by("-created_at")[:limit]
        return Response({"data": MessageSerializer(reversed(list(messages)), many=True).data})

    def post(self, request, conversation_id):
        conversation = get_object_or_404(Conversation, pk=conversation_id)
        serializer = MessageCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        message = post_message(actor=request.user, conversation=conversation,
                               body=serializer.validated_data["body"])
        return Response({"data": MessageSerializer(message).data}, status=status.HTTP_201_CREATED)


class ConversationReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, conversation_id):
        conversation = get_object_or_404(Conversation, pk=conversation_id)
        count = mark_read(actor=request.user, conversation=conversation)
        return Response({"data": {"marked": count}})


class MessageModerateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, message_id):
        message = get_object_or_404(Message, pk=message_id)
        moderate_message(actor=request.user, message=message)
        return Response({"data": MessageSerializer(message).data})
