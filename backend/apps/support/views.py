"""Support cases and disputes raised by members."""

from __future__ import annotations

import secrets

from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.audit import AuditLog
from apps.common.exceptions import NotFoundError
from apps.groups.models import Group

from .models import Dispute, SupportCase, SupportMessage


class DisputeListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        disputes = Dispute.objects.filter(raised_by=request.user).order_by("-created_at")
        return Response({"data": [
            {"id": str(d.pk), "reference": d.reference, "kind": d.kind, "subject": d.subject,
             "status": d.status, "created_at": d.created_at, "resolution_note": d.resolution_note}
            for d in disputes
        ]})

    def post(self, request):
        group = None
        if request.data.get("group"):
            group = get_object_or_404(Group, slug=request.data["group"])
        dispute = Dispute.objects.create(
            reference=f"DSP-{timezone.now():%Y%m%d}-{secrets.token_hex(3).upper()}",
            raised_by=request.user,
            group=group,
            kind=request.data.get("kind", Dispute.Kind.CONTRIBUTION),
            subject=request.data.get("subject", "")[:180],
            description=request.data.get("description", "")[:4000],
            related_type=request.data.get("related_type", "")[:40],
            related_id=str(request.data.get("related_id", ""))[:64],
        )
        AuditLog.record(action="dispute.raised", actor=request.user, severity=AuditLog.Severity.NOTICE,
                        target_type="dispute", target_id=dispute.pk, summary=dispute.subject)
        return Response({"data": {"id": str(dispute.pk), "reference": dispute.reference, "status": dispute.status}},
                        status=status.HTTP_201_CREATED)


class SupportCaseListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        cases = SupportCase.objects.filter(user=request.user).order_by("-created_at")
        return Response({"data": [
            {"id": str(c.pk), "reference": c.reference, "subject": c.subject, "status": c.status,
             "created_at": c.created_at}
            for c in cases
        ]})

    def post(self, request):
        case = SupportCase.objects.create(
            reference=f"SUP-{timezone.now():%Y%m%d}-{secrets.token_hex(3).upper()}",
            user=request.user,
            subject=request.data.get("subject", "Support request")[:180],
        )
        if request.data.get("message"):
            SupportMessage.objects.create(case=case, author=request.user,
                                          body=request.data["message"][:4000])
        return Response({"data": {"id": str(case.pk), "reference": case.reference}},
                        status=status.HTTP_201_CREATED)


class SupportMessageView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, case_id):
        case = get_object_or_404(SupportCase, pk=case_id, user=request.user)
        # Internal notes are filtered out unless the reader is staff.
        messages = case.messages.filter(is_internal=False).order_by("created_at")
        return Response({"data": [
            {"id": str(m.pk), "body": m.body, "created_at": m.created_at,
             "from_member": m.author_id == request.user.pk}
            for m in messages
        ]})

    def post(self, request, case_id):
        case = get_object_or_404(SupportCase, pk=case_id, user=request.user)
        message = SupportMessage.objects.create(case=case, author=request.user,
                                                body=request.data.get("body", "")[:4000])
        case.status = SupportCase.Status.PENDING_KOLO
        case.save(update_fields=["status", "updated_at"])
        return Response({"data": {"id": str(message.pk)}}, status=status.HTTP_201_CREATED)
