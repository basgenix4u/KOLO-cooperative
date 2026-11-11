"""Cross-cutting records: audit trail and the transactional outbox."""

from __future__ import annotations

from django.conf import settings
from django.db import models

from .models import UUIDModel


class AuditLog(UUIDModel):
    """Append-only record of security- and money-relevant actions.

    Deliberately denormalised: it must stay readable after the actor is deleted
    or renamed, so the actor id and label are copied in rather than joined.
    """

    class Severity(models.TextChoices):
        INFO = "info", "Info"
        NOTICE = "notice", "Notice"
        WARNING = "warning", "Warning"
        CRITICAL = "critical", "Critical"

    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="audit_entries",
    )
    actor_label = models.CharField(max_length=180, blank=True)
    action = models.CharField(max_length=120, db_index=True)
    severity = models.CharField(max_length=16, choices=Severity.choices, default=Severity.INFO, db_index=True)
    # Free-form references: what was touched, and in which scope.
    group_id = models.UUIDField(null=True, blank=True, db_index=True)
    target_type = models.CharField(max_length=80, blank=True)
    target_id = models.CharField(max_length=64, blank=True)
    summary = models.CharField(max_length=400, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    request_id = models.CharField(max_length=64, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [
            models.Index(fields=["target_type", "target_id"]),
            models.Index(fields=["action", "-created_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.action} by {self.actor_label or 'system'}"

    def save(self, *args, **kwargs):  # noqa: D102 - append-only guard
        if not self._state.adding:
            raise ValueError("AuditLog entries are immutable")
        super().save(*args, **kwargs)

    @classmethod
    def record(
        cls,
        *,
        action: str,
        actor=None,
        severity: str = Severity.INFO,
        summary: str = "",
        group_id=None,
        target_type: str = "",
        target_id: str = "",
        metadata: dict | None = None,
        request=None,
    ) -> "AuditLog":
        return cls.objects.create(
            action=action,
            actor=actor if getattr(actor, "pk", None) else None,
            actor_label=_label_for(actor),
            severity=severity,
            summary=summary[:400],
            group_id=group_id,
            target_type=target_type,
            target_id=str(target_id or ""),
            metadata=metadata or {},
            ip_address=_client_ip(request),
            request_id=getattr(request, "request_id", "") if request else "",
        )


def _label_for(actor) -> str:
    """A human-readable actor label that never carries unnecessary PII.

    KOLO's user model exposes `full_name` rather than Django's `get_full_name`,
    so read the attribute instead of assuming the default user shape. A wrong
    assumption here would break every audited action, so it is a pure read with
    a fallback rather than a hard dependency.
    """
    if actor is None:
        return "system"
    if getattr(actor, "is_authenticated", False) is False:
        return "anonymous"
    name = getattr(actor, "full_name", "") or getattr(actor, "email", "") or str(actor.pk)
    return str(name)[:150]


def _client_ip(request) -> str | None:
    if request is None:
        return None
    forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.META.get("REMOTE_ADDR")


class OutboxEvent(UUIDModel):
    """A domain event written in the same transaction as the state change.

    Why this exists: a payment can be marked successful and committed, and then
    the worker that should notify the member, update the obligation and schedule
    the receipt never runs because the broker was down. The outbox makes the
    event part of the same atomic commit, so it cannot be lost; a sweeper
    delivers anything still pending.
    """

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        DELIVERED = "delivered", "Delivered"
        FAILED = "failed", "Failed"

    topic = models.CharField(max_length=80, db_index=True)
    payload = models.JSONField(default=dict)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.PENDING, db_index=True)
    attempts = models.PositiveIntegerField(default=0)
    last_error = models.CharField(max_length=400, blank=True)
    available_at = models.DateTimeField(auto_now_add=True, db_index=True)
    delivered_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("created_at",)
        indexes = [models.Index(fields=["status", "available_at"])]

    def __str__(self) -> str:
        return f"{self.topic} ({self.status})"
