"""Documents: public-ish images on Cloudinary, sensitive files on private storage.

The rule that decides the store: if leaking the file would harm a member, it
never goes to a public CDN. Identity documents and signed agreements go to
private S3-compatible storage and are served only as short-lived signed URLs.
"""

from __future__ import annotations

import os
import uuid

from django.conf import settings
from django.db import models

from apps.common.models import AuditModel, UUIDModel


def _private_key(instance, filename: str) -> str:
    """Opaque, unguessable key. Never the member's original filename."""
    ext = os.path.splitext(filename)[1].lower()[:10]
    return f"{instance.scope_type}/{instance.scope_id or 'platform'}/{uuid.uuid4().hex}{ext}"


class Document(AuditModel):
    class Kind(models.TextChoices):
        IDENTITY = "identity", "Identity document"
        AGREEMENT = "agreement", "Loan or group agreement"
        RECEIPT = "receipt", "Receipt"
        STATEMENT = "statement", "Statement"
        GROUP = "group", "Group document"
        PROOF = "proof", "Proof of payment"
        OTHER = "other", "Other"

    class Storage(models.TextChoices):
        PRIVATE = "private", "Private object storage"
        CDN = "cdn", "Public image CDN"

    owner = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE,
                              related_name="documents")
    group = models.ForeignKey("groups.Group", null=True, blank=True, on_delete=models.CASCADE,
                              related_name="documents")
    scope_type = models.CharField(max_length=20, default="user")
    scope_id = models.CharField(max_length=64, blank=True)

    kind = models.CharField(max_length=20, choices=Kind.choices, default=Kind.OTHER, db_index=True)
    title = models.CharField(max_length=180)
    file = models.FileField(upload_to=_private_key, max_length=300)
    storage_kind = models.CharField(max_length=10, choices=Storage.choices, default=Storage.PRIVATE)
    content_type = models.CharField(max_length=100, blank=True)
    size_bytes = models.PositiveIntegerField(default=0)
    checksum = models.CharField(max_length=64, blank=True)
    is_verified = models.BooleanField(default=False)
    verified_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                    related_name="verified_documents")

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["owner", "kind"]), models.Index(fields=["group", "kind"])]

    def __str__(self) -> str:
        return f"{self.kind}: {self.title}"


class DocumentAccessLog(UUIDModel):
    """Who opened which sensitive file, and when. Required for audits."""

    document = models.ForeignKey(Document, on_delete=models.CASCADE, related_name="access_log")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL)
    action = models.CharField(max_length=20, default="download")
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("-created_at",)
