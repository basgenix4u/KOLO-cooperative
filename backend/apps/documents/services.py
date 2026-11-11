"""Document upload validation and signed-URL issuance."""

from __future__ import annotations

import hashlib
import logging
import os

from django.conf import settings
from django.utils import timezone

from apps.common.audit import AuditLog
from apps.common.exceptions import DomainError, PermissionDeniedError
from apps.groups.permissions import membership_for

from .models import Document, DocumentAccessLog

logger = logging.getLogger("kolo.audit")

# An allow-list, not a deny-list: unknown types are refused rather than risked.
ALLOWED_TYPES = {
    "image/jpeg": [".jpg", ".jpeg"],
    "image/png": [".png"],
    "image/webp": [".webp"],
    "application/pdf": [".pdf"],
}
def max_bytes() -> int:
    """Read the limit per call, not at import.

    A module-level constant froze whatever the process started with, so an
    operator raising the limit (or a test lowering it) had no effect.
    """
    return settings.KOLO["MAX_UPLOAD_BYTES"]


def validate_upload(uploaded_file) -> None:
    """Refuse anything that is too large, is not an allowed type, or lies about it."""
    limit = max_bytes()
    if uploaded_file.size > limit:
        raise DomainError(
            "That file is too large.",
            code="file_too_large",
            details={"max_bytes": limit, "size_bytes": uploaded_file.size},
        )
    content_type = (getattr(uploaded_file, "content_type", "") or "").lower()
    if content_type not in ALLOWED_TYPES:
        raise DomainError("Only JPEG, PNG, WebP or PDF files are accepted.", code="file_type_unsupported")

    extension = os.path.splitext(uploaded_file.name)[1].lower()
    if extension not in ALLOWED_TYPES[content_type]:
        # A .exe renamed to .pdf lands here.
        raise DomainError("The file extension does not match its type.", code="file_type_mismatch")

    header = uploaded_file.read(8)
    uploaded_file.seek(0)
    if content_type == "application/pdf" and not header.startswith(b"%PDF"):
        raise DomainError("That file is not a valid PDF.", code="file_content_invalid")
    if content_type.startswith("image/"):
        signatures = {b"\xff\xd8\xff": "jpeg", b"\x89PNG\r\n\x1a\n": "png"}
        if not any(header.startswith(sig) for sig in signatures) and b"WEBP" not in uploaded_file.read(16):
            uploaded_file.seek(0)
            raise DomainError("That image could not be read.", code="file_content_invalid")
        uploaded_file.seek(0)


def store_document(*, actor, uploaded_file, kind: str, title: str, group=None, owner=None,
                   storage: str = Document.Storage.PRIVATE) -> Document:
    """Persist a validated file with private defaults."""
    validate_upload(uploaded_file)
    owner = owner or actor

    digest = hashlib.sha256()
    for chunk in uploaded_file.chunks():
        digest.update(chunk)
    uploaded_file.seek(0)

    document = Document.objects.create(
        owner=owner,
        group=group,
        scope_type="group" if group else "user",
        scope_id=str(group.pk) if group else str(owner.pk),
        kind=kind,
        title=title[:180],
        file=uploaded_file,
        storage_kind=storage,
        content_type=uploaded_file.content_type,
        size_bytes=uploaded_file.size,
        checksum=digest.hexdigest(),
    )
    AuditLog.record(action="document.stored", actor=actor, group_id=getattr(group, "pk", None),
                    target_type="document", target_id=document.pk,
                    summary=f"{kind} uploaded ({document.size_bytes} bytes)")
    return document


def authorise_document_access(*, actor, document: Document, request=None) -> None:
    """Only the owner, a group officer, or platform staff may open a file."""
    if getattr(actor, "is_staff", False):
        pass
    elif document.owner_id == getattr(actor, "pk", None):
        pass
    elif document.group_id:
        membership = membership_for(actor, document.group)
        if not membership or "finance.view" not in membership.permissions:
            raise PermissionDeniedError("You cannot open this document.", code="document_forbidden")
    else:
        raise PermissionDeniedError("You cannot open this document.", code="document_forbidden")

    DocumentAccessLog.objects.create(
        document=document,
        user=actor if getattr(actor, "is_authenticated", False) else None,
        ip_address=(request.META.get("REMOTE_ADDR") if request else None),
    )


def signed_url(document: Document, *, expires_in: int = 300) -> str:
    """Short-lived URL. Five minutes is enough to open a file, short enough not
    to leak if it is copied out of a log."""
    storage = document.file.storage
    if hasattr(storage, "url") and hasattr(storage, "bucket_name"):  # S3-compatible
        return storage.url(document.file.name, expire=expires_in, parameters={"ResponseContentDisposition": "inline"})
    # Local filesystem storage has no signing; serve through an authenticated
    # view instead, never by exposing MEDIA_URL directly.
    return f"/api/v1/documents/{document.pk}/content/"


def cloudinary_upload(*, actor, uploaded_file, folder: str = "kolo/avatars") -> dict:
    """Public images only (avatars, group covers) go to Cloudinary.

    Absent credentials raise instead of silently falling back to local storage:
    an avatar that lives on a laptop is an avatar nobody else can load.
    """
    import cloudinary
    import cloudinary.uploader

    cloud_name = getattr(settings, "CLOUDINARY_CLOUD_NAME", "")
    if not cloud_name:
        from apps.common.exceptions import DomainError as E

        raise E("Image hosting is not configured.", code="media_not_configured")
    cloudinary.config(
        cloud_name=cloud_name,
        api_key=getattr(settings, "CLOUDINARY_API_KEY", ""),
        api_secret=getattr(settings, "CLOUDINARY_API_SECRET", ""),
        secure=True,
    )
    validate_upload(uploaded_file)
    result = cloudinary.uploader.upload(
        uploaded_file, folder=folder, resource_type="image",
        allowed_formats=["jpg", "jpeg", "png", "webp"], overwrite=False,
    )
    AuditLog.record(action="media.uploaded", actor=actor, summary=f"{folder} image stored")
    return {"url": result.get("secure_url", ""), "public_id": result.get("public_id", "")}
