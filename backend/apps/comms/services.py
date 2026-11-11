"""Chat authorisation lives here, not in the consumer.

The WebSocket consumer and the REST history endpoint both call
`require_conversation_access`, so a member cannot subscribe to a room they
could not read over HTTP.
"""

from __future__ import annotations

import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.db import transaction
from django.db.models import Max
from django.utils import timezone

from apps.common.audit import AuditLog
from apps.common.exceptions import DomainError, PermissionDeniedError
from apps.groups.models import Membership, Permission as GroupPermission
from apps.groups.permissions import membership_for

from .models import Conversation, Message, MessageRead, Participant

logger = logging.getLogger("kolo.audit")


def require_conversation_access(user, conversation: Conversation) -> Participant | None:
    """Return the participant row, or refuse. One gate for every read path."""
    if conversation.kind == Conversation.Kind.GROUP:
        if not conversation.group_id:
            raise PermissionDeniedError("This conversation is not available.", code="conversation_unavailable")
        membership = membership_for(user, conversation.group)
        if not membership:
            raise PermissionDeniedError("You are not a member of this group.", code="not_a_member")
        return conversation.participants.filter(user=user).first()

    participant = conversation.participants.filter(user=user).first()
    if not participant:
        raise PermissionDeniedError("This conversation is not available to you.", code="conversation_unavailable")
    return participant


def post_message(*, actor, conversation: Conversation, body: str, kind: str = Message.Kind.TEXT) -> Message:
    require_conversation_access(actor, conversation)
    if conversation.is_locked:
        raise DomainError("This conversation is locked.", code="conversation_locked")
    text = (body or "").strip()
    if not text:
        raise DomainError("Write a message first.", code="message_empty")
    if len(text) > 4000:
        raise DomainError("That message is too long.", code="message_too_long")

    with transaction.atomic():
        message = Message.objects.create(conversation=conversation, sender=actor, body=text, kind=kind)
        Participant.objects.filter(conversation=conversation, user=actor).update(last_read_at=timezone.now())
        # Broadcast after the row is committed, so a subscriber never receives a
        # message that a rollback then removes. Without this the sockets accepted
        # connections and stayed silent: every member would have had to poll.
        transaction.on_commit(lambda: _broadcast_message(conversation, message))
    return message


def _broadcast_message(conversation: Conversation, message: Message) -> None:
    """Push a new message to everyone connected to the conversation's room."""
    layer = get_channel_layer()
    if layer is None:
        logger.info('{"event":"chat_broadcast_skipped","reason":"no channel layer"}')
        return
    payload = {
        "event": "message",
        "conversation_id": str(conversation.pk),
        "message": {
            "id": str(message.pk),
            "body": message.body,
            "kind": message.kind,
            "sender_id": str(message.sender_id),
            "sender_name": message.sender.display_name if message.sender_id else "",
            "created_at": message.created_at.isoformat(),
        },
    }
    try:
        async_to_sync(layer.group_send)(
            f"conversation.{conversation.pk}", {"type": "chat.event", **payload}
        )
    except Exception as exc:  # noqa: BLE001 - delivery is best effort, the row is already saved
        # A chat message that is stored but not pushed is still readable over
        # HTTP; losing it entirely would be worse.
        logger.warning('{"event":"chat_broadcast_failed","reason":%r}', str(exc))


def mark_read(*, actor, conversation: Conversation, message_id=None) -> int:
    require_conversation_access(actor, conversation)
    query = conversation.messages.all()
    if message_id:
        query = query.filter(pk=message_id)
    unread = query.exclude(reads__user=actor)
    created = 0
    for message in unread.iterator():
        _, made = MessageRead.objects.get_or_create(message=message, user=actor)
        created += int(made)
    Participant.objects.filter(conversation=conversation, user=actor).update(last_read_at=timezone.now())
    return created


def unread_count(*, actor, conversation: Conversation) -> int:
    """Messages this member has not marked read.

    Counts the per-message read records that `mark_read` writes, so the badge
    actually clears. Deriving this from `Participant.last_read_at` instead meant
    the two disagreed and the count never went down for group chats, where no
    Participant row exists to hold a timestamp.
    """
    require_conversation_access(actor, conversation)
    return (
        conversation.messages.exclude(sender=actor)
        .exclude(reads__user=actor)
        .exclude(is_deleted=True)
        .count()
    )


def moderate_message(*, actor, message: Message) -> Message:
    """Hide a message. Roles are checked against the message's own group."""
    if not message.conversation.group_id:
        raise DomainError("Only group messages can be moderated.", code="not_group_message")
    from apps.groups.permissions import require_permission

    require_permission(actor, message.conversation.group, GroupPermission.CHAT_MODERATE)
    message.is_deleted = True
    message.deleted_by = actor
    message.body = "[removed by a moderator]"
    message.save(update_fields=["is_deleted", "deleted_by", "body", "updated_at"])
    AuditLog.record(action="chat.message_moderated", actor=actor, group_id=message.conversation.group_id,
                    target_type="message", target_id=message.pk, summary="Message hidden by moderator")
    return message
