"""Uniform error contract for the whole API.

Clients get a stable machine-readable `code`, a human `message` they can show,
and `details` when a field is at fault. Flutter switches on `code`, never on
prose, so wording can change without breaking the app.
"""

from __future__ import annotations

import logging

from django.core.exceptions import PermissionDenied as DjangoPermissionDenied
from django.db import IntegrityError
from rest_framework import status
from rest_framework.exceptions import APIException, ValidationError
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

logger = logging.getLogger("kolo.audit")


class DomainError(APIException):
    """A business rule refused the operation.

    Every subclass carries a stable `code` and a default status. Views raise
    these instead of hand-rolling responses so the contract cannot drift.
    """

    default_code = "domain_error"
    default_detail = "This action could not be completed."
    status_code = status.HTTP_400_BAD_REQUEST

    def __init__(self, detail: str | None = None, *, code: str | None = None, details: dict | None = None):
        self.code = code or self.default_code
        self.details = details or {}
        super().__init__(detail or self.default_detail)


class PermissionDeniedError(DomainError):
    default_code = "permission_denied"
    default_detail = "You do not have permission to do that."
    status_code = status.HTTP_403_FORBIDDEN


class NotFoundError(DomainError):
    default_code = "not_found"
    default_detail = "That record does not exist or is not available to you."
    status_code = status.HTTP_404_NOT_FOUND


class ConflictError(DomainError):
    default_code = "conflict"
    default_detail = "This action conflicts with the current state."
    status_code = status.HTTP_409_CONFLICT


class InvalidStateError(DomainError):
    default_code = "invalid_state"
    default_detail = "This action is not available in the record's current state."


class FinancialSafetyError(DomainError):
    """A financial invariant would be broken."""

    default_code = "financial_safety"
    default_detail = "This operation would break a financial rule and was refused."


class InsufficientFundsError(FinancialSafetyError):
    default_code = "insufficient_funds"
    default_detail = "The available balance is not enough for this request."


class IdempotencyConflict(DomainError):
    default_code = "idempotency_conflict"
    default_detail = "This request key was already used with different content."
    status_code = status.HTTP_409_CONFLICT


def error_body(code: str, message: str, details: dict | None = None) -> dict:
    return {"error": {"code": code, "message": message, "details": details or {}}}


def api_exception_handler(exc, context):
    """Render every failure with the same shape."""
    if isinstance(exc, DjangoPermissionDenied):
        exc = PermissionDeniedError()

    if isinstance(exc, ValidationError):
        details = exc.detail if isinstance(exc.detail, dict) else {"non_field_errors": exc.detail}
        return Response(
            error_body("validation_error", "Some of the information provided is not valid.", details),
            status=status.HTTP_400_BAD_REQUEST,
        )

    if isinstance(exc, DomainError):
        return Response(error_body(exc.code, str(exc.detail), exc.details), status=exc.status_code)

    if isinstance(exc, IntegrityError):
        # Never leak SQL or constraint names to a client.
        logger.warning('{"event":"integrity_error","detail":%r}', str(exc))
        return Response(
            error_body("conflict", "That action conflicts with existing data."),
            status=status.HTTP_409_CONFLICT,
        )

    response = drf_exception_handler(exc, context)
    if response is None:
        return None
    code = getattr(exc, "default_code", "error")
    detail = response.data
    if isinstance(detail, dict) and "detail" in detail:
        message = str(detail["detail"])
    elif isinstance(detail, list) and detail:
        message = str(detail[0])
    else:
        message = str(detail)
    response.data = error_body(code, message)
    return response
