"""Payment endpoints, including the provider webhook."""

from __future__ import annotations

import logging

from django.shortcuts import get_object_or_404
from django.views.decorators.csrf import csrf_exempt
from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.exceptions import DomainError, PermissionDeniedError
from apps.common.throttling import ScopedBurstThrottle
from apps.groups.models import Group, Permission as GroupPermission
from apps.groups.permissions import require_permission

from .models import PaymentIntent, ReconciliationRun
from .serializers import (
    IntentCreateSerializer, PaymentIntentSerializer, ReconciliationRunSerializer, VerifySerializer,
)
from .services import create_intent, run_reconciliation, verify_and_settle

logger = logging.getLogger("kolo.audit")


class IntentCreateView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "payment"

    @extend_schema(request=IntentCreateSerializer, responses=PaymentIntentSerializer)
    def post(self, request):
        serializer = IntentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        intent = create_intent(
            user=request.user, purpose=data["purpose"], amount_minor=data["amount_minor"],
            currency=data["currency"], source_type="", source_id=data.get("source_id", ""),
            idempotency_key=data.get("idempotency_key", ""), callback_url=data.get("callback_url", ""),
        )
        return Response({"data": PaymentIntentSerializer(intent).data}, status=status.HTTP_201_CREATED)


class IntentVerifyView(APIView):
    """The app calls this when it returns from checkout.

    It is a *request to check*, not a claim of payment: the server asks the
    provider what happened and believes only that.
    """

    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "payment"

    @extend_schema(request=VerifySerializer)
    def post(self, request):
        serializer = VerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        intent = PaymentIntent.objects.filter(
            reference=serializer.validated_data["reference"], user=request.user
        ).first()
        if not intent:
            raise DomainError("That payment was not found.", code="intent_not_found")
        intent = verify_and_settle(intent, actor=request.user, source="client-verify")
        return Response({"data": PaymentIntentSerializer(intent).data})


class IntentDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, reference):
        intent = get_object_or_404(PaymentIntent, reference=reference, user=request.user)
        return Response({"data": PaymentIntentSerializer(intent).data})


class WebhookView(APIView):
    """Provider callbacks.

    Unauthenticated by necessity — the signature is the authentication. CSRF is
    exempt because there is no browser session involved.
    """

    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request, provider):
        from .services import handle_webhook

        event = handle_webhook(
            provider_name=provider,
            headers={k: v for k, v in request.headers.items()},
            body=request.body,
            ip=request.META.get("REMOTE_ADDR"),
        )
        # Always 200 for a well-formed request: a provider that sees an error
        # will retry, and retries of an already-recorded event are noise.
        return Response({"received": True, "status": event.status})


class ReconciliationTriggerView(APIView):
    """Operators start a reconciliation run. Not exposed to members."""

    permission_classes = [IsAuthenticated]

    def post(self, request, slug):
        if not request.user.is_staff:
            raise PermissionDeniedError("Only platform operators can reconcile.", code="operator_only")
        group = get_object_or_404(Group, slug=slug)
        require_permission(request.user, group, GroupPermission.FINANCE_VIEW)
        data = request.data
        run = run_reconciliation(
            provider_name=data.get("provider", "mock"),
            period_start=__import__("datetime").date.fromisoformat(data["period_start"]),
            period_end=__import__("datetime").date.fromisoformat(data["period_end"]),
            currency=data.get("currency", group.currency),
        )
        return Response({"data": ReconciliationRunSerializer(run).data}, status=status.HTTP_201_CREATED)
