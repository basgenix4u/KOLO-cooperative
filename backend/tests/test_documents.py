"""Documents: private by default, access logged, type not trusted from the client.

A receipt or an ID card is the most sensitive thing a member uploads. The tests
below are about who can open one, and what happens when someone uploads a file
that lies about what it is.
"""

from __future__ import annotations

import io

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.common.exceptions import DomainError, PermissionDeniedError
from apps.documents import services
from apps.documents.models import Document, DocumentAccessLog

pytestmark = pytest.mark.django_db

PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00"
    b"\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00"
    b"\x00\x00IEND\xaeB`\x82"
)
PDF = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n"


def _upload(content, name, content_type):
    return SimpleUploadedFile(name, content, content_type=content_type)


@pytest.fixture
def png_file():
    return _upload(PNG, "receipt.png", "image/png")


def _make_document(actor, file, **kwargs):
    return services.store_document(
        actor=actor, uploaded_file=file, kind=Document.Kind.RECEIPT,
        title=kwargs.pop("title", "Transfer receipt"), **kwargs,
    )


def test_a_valid_png_is_stored_privately(member_a, png_file):
    document = _make_document(member_a, png_file)
    assert document.owner_id == member_a.pk
    assert document.storage_kind == Document.Storage.PRIVATE


def test_a_disallowed_type_is_refused(member_a):
    bad = _upload(b"#!/bin/sh\necho hi\n", "script.sh", "text/x-shellscript")
    with pytest.raises(DomainError) as caught:
        _make_document(member_a, bad)
    assert caught.value.code == "file_type_unsupported"
    assert Document.objects.count() == 0


def test_a_file_lying_about_its_type_is_refused(member_a):
    """Declared as a PDF, actually a shell script."""
    liar = _upload(b"#!/bin/sh\nrm -rf /\n", "receipt.pdf", "application/pdf")
    with pytest.raises(DomainError) as caught:
        _make_document(member_a, liar)
    assert caught.value.code in {"file_content_mismatch", "file_type_unsupported", "file_content_invalid"}
    assert Document.objects.count() == 0


def test_an_executable_renamed_as_an_image_is_refused(member_a):
    liar = _upload(b"MZ\x90\x00\x03\x00\x00\x00" + b"\x00" * 200, "photo.png", "image/png")
    with pytest.raises(DomainError):
        _make_document(member_a, liar)


def test_an_oversized_file_is_refused(member_a, settings):
    settings.KOLO["MAX_UPLOAD_BYTES"] = 100
    # Still a valid PNG header, just longer than the (lowered) limit.
    big = _upload(PNG + b"\x00" * 500, "huge.png", "image/png")
    with pytest.raises(DomainError) as caught:
        _make_document(member_a, big)
    assert caught.value.code == "file_too_large"


def test_the_owner_can_open_their_own_document(member_a, png_file):
    document = _make_document(member_a, png_file)
    services.authorise_document_access(actor=member_a, document=document)
    assert DocumentAccessLog.objects.filter(document=document).exists()


def test_another_member_cannot_open_it(group, officers, memberships, png_file):
    document = _make_document(memberships["a"].user, png_file)
    with pytest.raises(PermissionDeniedError) as caught:
        services.authorise_document_access(actor=memberships["b"].user, document=document)
    assert caught.value.code == "document_forbidden"


def test_a_group_officer_can_open_a_group_document(group, officers, png_file):
    document = _make_document(officers["treasurer"].user, png_file, group=group)
    services.authorise_document_access(actor=officers["treasurer"].user, document=document)


def test_an_ordinary_member_cannot_open_a_group_document(group, officers, memberships, png_file):
    document = _make_document(officers["treasurer"].user, png_file, group=group)
    with pytest.raises(PermissionDeniedError):
        services.authorise_document_access(actor=memberships["b"].user, document=document)


def test_access_is_logged_for_every_open(member_a, png_file):
    document = _make_document(member_a, png_file)
    services.authorise_document_access(actor=member_a, document=document)
    services.authorise_document_access(actor=member_a, document=document)
    assert DocumentAccessLog.objects.filter(document=document).count() == 2


def test_local_storage_never_returns_a_public_media_url(member_a, png_file):
    document = _make_document(member_a, png_file)
    url = services.signed_url(document, expires_in=300)
    assert url.startswith("/api/v1/documents/")
    assert "/media/" not in url, "a guessed MEDIA_URL path must not be the way in"


def test_storage_keys_are_opaque(member_a, png_file):
    """The stored name must not carry the member's chosen filename."""
    document = _make_document(member_a, png_file)
    assert "receipt" not in document.file.name.lower()


def test_download_endpoint_requires_authentication(group, officers, png_file):
    document = _make_document(officers["treasurer"].user, png_file, group=group)
    client = APIClient()
    assert client.get(f"/api/v1/documents/{document.pk}/").status_code == 401


def test_download_endpoint_refuses_a_non_owner(group, officers, memberships, png_file):
    document = _make_document(officers["treasurer"].user, png_file, group=group)
    client = APIClient()
    client.force_authenticate(user=memberships["b"].user)
    assert client.get(f"/api/v1/documents/{document.pk}/").status_code in {403, 404}
