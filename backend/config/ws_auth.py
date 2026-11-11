"""Token authentication for WebSocket connections.

Browsers cannot set headers on a WebSocket, so the token arrives as a query
parameter. It is validated before the consumer is instantiated, and the
connection is closed immediately when it fails — an anonymous socket never
reaches a consumer.
"""

from __future__ import annotations

from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser


@database_sync_to_async
def _user_from_token(raw_token: str):
    from rest_framework_simplejwt.exceptions import TokenError
    from rest_framework_simplejwt.tokens import AccessToken

    from apps.accounts.models import User

    try:
        token = AccessToken(raw_token)
        return User.objects.get(pk=token["sub"], status=User.Status.ACTIVE)
    except (TokenError, User.DoesNotExist, KeyError):
        return AnonymousUser()


class TokenAuthMiddleware:
    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        query = parse_qs(scope.get("query_string", b"").decode())
        token = (query.get("token") or [""])[0]
        scope = dict(scope)
        scope["user"] = await _user_from_token(token) if token else AnonymousUser()
        return await self.inner(scope, receive, send)
