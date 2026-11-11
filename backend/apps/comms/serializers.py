from rest_framework import serializers

from .models import Conversation, Message


class ConversationSerializer(serializers.ModelSerializer):
    unread = serializers.SerializerMethodField()
    last_message = serializers.SerializerMethodField()

    class Meta:
        model = Conversation
        fields = ["id", "kind", "group_id", "title", "is_locked", "unread", "last_message", "created_at"]

    def get_unread(self, obj) -> int:
        from .services import unread_count

        request = self.context.get("request")
        if not request or not request.user.is_authenticated:
            return 0
        try:
            return unread_count(actor=request.user, conversation=obj)
        except Exception:  # noqa: BLE001
            return 0

    def get_last_message(self, obj):
        message = obj.messages.filter(is_deleted=False).order_by("-created_at").first()
        if not message:
            return None
        return {
            "body": message.body[:140],
            "sender_name": (message.sender.full_name if message.sender else "KOLO"),
            "created_at": message.created_at,
        }


class MessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.SerializerMethodField()

    class Meta:
        model = Message
        fields = ["id", "kind", "body", "sender_id", "sender_name", "is_deleted", "created_at"]

    def get_sender_name(self, obj) -> str:
        return obj.sender.full_name if obj.sender else "KOLO"


class MessageCreateSerializer(serializers.Serializer):
    body = serializers.CharField(max_length=4000)
