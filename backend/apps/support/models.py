"""Disputes, support cases and risk events — the operational side."""

from __future__ import annotations

from django.conf import settings
from django.db import models

from apps.common.models import AuditModel


class Dispute(AuditModel):
    """A member contesting a financial outcome."""

    class Kind(models.TextChoices):
        CONTRIBUTION = "contribution", "Contribution not credited"
        PAYOUT = "payout", "Payout not received"
        WITHDRAWAL = "withdrawal", "Withdrawal problem"
        LOAN = "loan", "Loan disagreement"
        MEMBER = "member", "Problem with a member"

    class Status(models.TextChoices):
        OPEN = "open", "Open"
        INVESTIGATING = "investigating", "Investigating"
        RESOLVED = "resolved", "Resolved"
        REJECTED = "rejected", "Rejected"

    reference = models.CharField(max_length=40, unique=True)
    raised_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="disputes")
    group = models.ForeignKey("groups.Group", null=True, blank=True, on_delete=models.SET_NULL, related_name="disputes")
    kind = models.CharField(max_length=20, choices=Kind.choices)
    subject = models.CharField(max_length=180)
    description = models.TextField(max_length=4000)
    related_type = models.CharField(max_length=40, blank=True)
    related_id = models.CharField(max_length=64, blank=True, db_index=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.OPEN, db_index=True)
    resolution_note = models.TextField(blank=True, max_length=2000)
    resolved_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                    related_name="resolved_disputes")
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["status", "-created_at"])]


class SupportCase(AuditModel):
    """A conversation between a member and support."""

    class Status(models.TextChoices):
        OPEN = "open", "Open"
        PENDING_MEMBER = "pending_member", "Waiting on member"
        PENDING_KOLO = "pending_kolo", "Waiting on KOLO"
        CLOSED = "closed", "Closed"

    reference = models.CharField(max_length=40, unique=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="support_cases")
    subject = models.CharField(max_length=180)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.OPEN, db_index=True)
    assigned_to = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                    related_name="assigned_cases")
    closed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)


class SupportMessage(AuditModel):
    case = models.ForeignKey(SupportCase, on_delete=models.CASCADE, related_name="messages")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL)
    body = models.TextField(max_length=4000)
    is_internal = models.BooleanField(default=False, help_text="Internal notes are never shown to the member")

    class Meta:
        ordering = ("created_at",)


class RiskEvent(AuditModel):
    """Something that looked wrong and needs a human's eyes.

    Written by automated checks (velocity, mismatch, repeated failures) so the
    operations team reviews evidence instead of waiting for a complaint.
    """

    class Kind(models.TextChoices):
        PAYMENT_VELOCITY = "payment_velocity", "Unusual payment velocity"
        AMOUNT_MISMATCH = "amount_mismatch", "Amount mismatch"
        REPEATED_FAILURES = "repeated_failures", "Repeated payment failures"
        LOGIN_ANOMALY = "login_anomaly", "Sign-in anomaly"
        WITHDRAWAL_PATTERN = "withdrawal_pattern", "Withdrawal pattern"
        WEBHOOK_INVALID = "webhook_invalid", "Invalid webhook signature"
        OTHER = "other", "Other"

    class Severity(models.TextChoices):
        LOW = "low", "Low"
        MEDIUM = "medium", "Medium"
        HIGH = "high", "High"
        CRITICAL = "critical", "Critical"

    class Status(models.TextChoices):
        OPEN = "open", "Open"
        REVIEWING = "reviewing", "Reviewing"
        CLEARED = "cleared", "Cleared"
        CONFIRMED = "confirmed", "Confirmed"

    kind = models.CharField(max_length=30, choices=Kind.choices, db_index=True)
    severity = models.CharField(max_length=10, choices=Severity.choices, default=Severity.MEDIUM, db_index=True)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.OPEN, db_index=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                             related_name="risk_events")
    group = models.ForeignKey("groups.Group", null=True, blank=True, on_delete=models.SET_NULL)
    summary = models.CharField(max_length=300)
    evidence = models.JSONField(default=dict, blank=True)
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                    related_name="reviewed_risk_events")

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["status", "severity"])]
