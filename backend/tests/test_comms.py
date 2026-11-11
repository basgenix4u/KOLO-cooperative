"""Chat access and the HTTP surface.

Two things are being proved here: a non-member cannot read or write a group's
chat through any path, and the REST endpoints behave (auth required, private
group answers 404, message bodies validated server side).
"""

from __future__ import annotations

import pytest
from rest_framework.test import APIClient

from apps.comms import services as comms
from apps.comms.models import Conversation, Message
from apps.common.exceptions import DomainError, PermissionDeniedError

pytestmark = pytest.mark.django_db


@pytest.fixture
def conversation(group, officers, memberships):
    conversation, _ = Conversation.objects.get_or_create(
        group=group, kind=Conversation.Kind.GROUP,
        defaults={"title": f"{group.name} chat", "created_by": officers["chair"].user},
    )
    return conversation


def test_a_member_can_post_and_read(conversation, memberships):
    message = comms.post_message(actor=memberships["a"].user, conversation=conversation, body="I've paid")
    assert message.body == "I've paid"
    assert conversation.messages.count() == 1


def test_an_outsider_cannot_read_the_group_chat(conversation, outsider):
    with pytest.raises(PermissionDeniedError):
        comms.require_conversation_access(outsider, conversation)


def test_an_outsider_cannot_post_to_the_group_chat(conversation, outsider):
    with pytest.raises(PermissionDeniedError):
        comms.post_message(actor=outsider, conversation=conversation, body="Let me in")
    assert conversation.messages.count() == 0


def test_a_member_who_left_loses_access(conversation, memberships):
    from apps.groups.models import Membership

    Membership.objects.filter(pk=memberships["a"].pk).update(status=Membership.Status.LEFT)
    with pytest.raises(PermissionDeniedError):
        comms.require_conversation_access(memberships["a"].user, conversation)


def test_empty_and_oversized_messages_are_refused(conversation, memberships):
    with pytest.raises(DomainError) as caught:
        comms.post_message(actor=memberships["a"].user, conversation=conversation, body="   ")
    assert caught.value.code == "message_empty"

    with pytest.raises(DomainError) as caught:
        comms.post_message(actor=memberships["a"].user, conversation=conversation, body="x" * 4001)
    assert caught.value.code == "message_too_long"


def test_a_locked_conversation_refuses_new_messages(conversation, memberships, officers):
    Conversation.objects.filter(pk=conversation.pk).update(is_locked=True)
    conversation.refresh_from_db()
    with pytest.raises(DomainError) as caught:
        comms.post_message(actor=memberships["a"].user, conversation=conversation, body="Hello?")
    assert caught.value.code == "conversation_locked"


def test_unread_counts_are_per_member(conversation, memberships):
    """Posting marks the sender as read; everyone else still has one to read."""
    comms.post_message(actor=memberships["a"].user, conversation=conversation, body="One")
    assert comms.unread_count(actor=memberships["a"].user, conversation=conversation) == 0
    assert comms.unread_count(actor=memberships["b"].user, conversation=conversation) == 1

    comms.mark_read(actor=memberships["b"].user, conversation=conversation)
    assert comms.unread_count(actor=memberships["b"].user, conversation=conversation) == 0


# ---------------------------------------------------------------------------
# HTTP surface
# ---------------------------------------------------------------------------

@pytest.fixture
def api():
    return APIClient()


def test_endpoints_require_authentication(api, conversation):
    response = api.get(f"/api/v1/comms/conversations/{conversation.pk}/messages/")
    assert response.status_code == 401


def test_a_member_reads_history_over_http(api, conversation, memberships):
    comms.post_message(actor=memberships["a"].user, conversation=conversation, body="Hello group")
    api.force_authenticate(user=memberships["a"].user)

    response = api.get(f"/api/v1/comms/conversations/{conversation.pk}/messages/")
    assert response.status_code == 200
    payload = response.json()["data"]
    assert payload[-1]["body"] == "Hello group"


def test_an_outsider_gets_a_refusal_over_http(api, conversation, outsider):
    api.force_authenticate(user=outsider)
    response = api.get(f"/api/v1/comms/conversations/{conversation.pk}/messages/")
    assert response.status_code in {403, 404}


def test_a_private_group_chat_answers_404_not_403(api, group, officers, memberships, outsider):
    """A 403 would confirm the private group exists; membership is checked first."""
    response = api.get("/api/v1/comms/groups/abuja-friends-ajo/chat/")
    assert response.status_code == 401

    api.force_authenticate(user=outsider)
    response = api.get("/api/v1/comms/groups/abuja-friends-ajo/chat/")
    assert response.status_code == 404


def test_posting_a_message_over_http_is_validated(api, conversation, memberships):
    api.force_authenticate(user=memberships["a"].user)
    response = api.post(
        f"/api/v1/comms/conversations/{conversation.pk}/messages/",
        {"body": "   "}, format="json",
    )
    assert response.status_code == 400
    assert conversation.messages.count() == 0
