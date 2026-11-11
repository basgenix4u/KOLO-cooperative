"""Group chat and direct messages, scoped by membership."""

from __future__ import annotations

from django.conf import settings
from django.db import models

from apps.common.models import AuditModel, UUIDModel


class Conversation(AuditModel):
    """A chat channel. Group conversations are readable only by active members."""

    class Kind(models.TextChoices):
        GROUP = "group", "Group chat"
        DIRECT = "direct", "Direct message"

    kind = models.CharField(max_length=10, choices=Kind.choices, default=Kind.GROUP)
    group = models.ForeignKey("groups.Group", null=True, blank=True, on_delete=models.CASCADE,
                              related_name="conversations")
    title = models.CharField(max_length=140, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL)
    is_locked = models.BooleanField(default=False)

    class Meta:
        ordering = ("-created_at",)
        constraints = []
        indexes = [models.Index(fields=["group", "kind"])]

    def __str__(self) -> str:
        return self.title or f"{self.kind} conversation {self.pk}"


class Participant(UUIDModel):
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name="participants")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="conversations")
    joined_at = models.DateTimeField(auto_now_add=True)
    last_read_at = models.DateTimeField(null=True, blank=True)
    is_muted = models.BooleanField(default=False)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["conversation", "user"], name="uniq_conversation_participant")]


class Message(AuditModel):
    class Kind(models.TextChoices):
        TEXT = "text", "Text"
        SYSTEM = "system", "System"
        ANNOUNCEMENT = "announcement", "Announcement"

    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name="messages")
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="messages")
    kind = models.CharField(max_length=16, choices=Kind.choices, default=Kind.TEXT)
    body = models.TextField(max_length=4000)
    is_deleted = models.BooleanField(default=False)
    deleted_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="deleted_messages")

    class Meta:
        ordering = ("created_at",)
        indexes = [models.Index(fields=["conversation", "created_at"])]

    def __str__(self) -> str:
        return f"{self.kind} from {self.sender_id}"


class MessageRead(UUIDModel):
    """Per-member read state, so unread counts are exact rather than guessed."""

    message = models.ForeignKey(Message, on_delete=models.CASCADE, related_name="reads")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    read_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["message", "user"], name="uniq_message_read")]
