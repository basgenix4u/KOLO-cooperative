"""Document upload and secure retrieval."""

from __future__ import annotations

import mimetypes

from django.http import FileResponse
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.exceptions import DomainError

from .models import Document
from .services import authorise_document_access, signed_url, store_document


class DocumentUploadView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        upload = request.FILES.get("file")
        if not upload:
            raise DomainError("Choose a file to upload.", code="file_missing")
        group = None
        if request.data.get("group"):
            from apps.groups.models import Group
            from apps.groups.permissions import require_permission
            from apps.groups.models import Permission as GroupPermission

            group = get_object_or_404(Group, slug=request.data["group"])
            require_permission(request.user, group, GroupPermission.FINANCE_VIEW)

        document = store_document(
            actor=request.user, uploaded_file=upload,
            kind=request.data.get("kind", Document.Kind.OTHER),
            title=request.data.get("title", upload.name)[:180],
            group=group,
        )
        return Response(
            {"data": {"id": str(document.pk), "title": document.title, "kind": document.kind,
                      "size_bytes": document.size_bytes}},
            status=status.HTTP_201_CREATED,
        )


class DocumentDownloadView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, document_id):
        document = get_object_or_404(Document, pk=document_id)
        authorise_document_access(actor=request.user, document=document, request=request)
        return Response({"data": {"url": signed_url(document, expires_in=300), "expires_in": 300}})


class DocumentContentView(APIView):
    """Streams a private file locally; S3 deployments use the signed URL instead."""

    permission_classes = [IsAuthenticated]

    def get(self, request, document_id):
        document = get_object_or_404(Document, pk=document_id)
        authorise_document_access(actor=request.user, document=document, request=request)
        content_type = document.content_type or mimetypes.guess_type(document.file.name)[0] or "application/octet-stream"
        response = FileResponse(document.file.open("rb"), content_type=content_type)
        response["Content-Disposition"] = "inline"
        response["X-Content-Type-Options"] = "nosniff"
        return response


class DocumentListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        documents = Document.objects.filter(owner=request.user).order_by("-created_at")
        return Response({"data": [
            {"id": str(d.pk), "title": d.title, "kind": d.kind, "size_bytes": d.size_bytes,
             "created_at": d.created_at, "is_verified": d.is_verified}
            for d in documents
        ]})
