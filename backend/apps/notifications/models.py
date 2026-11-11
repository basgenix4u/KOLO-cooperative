"""In-app notifications, with push delivery tracked per notification."""

from __future__ import annotations

from django.conf import settings
from django.db import models

from apps.common.models import AuditModel


class Notification(AuditModel):
    """One message for one member.

    `dedupe_key` is the duplicate guard: the same domain event delivered twice
    updates nothing and sends nothing.
    """

    class Kind(models.TextChoices):
        PAYMENT_CONFIRMED = "payment_confirmed", "Payment confirmed"
        PAYMENT_FAILED = "payment_failed", "Payment failed"
        CONTRIBUTION_DUE = "contribution_due", "Contribution due"
        CONTRIBUTION_OVERDUE = "contribution_overdue", "Contribution overdue"
        PAYOUT_PAID = "payout_paid", "Payout paid"
        WITHDRAWAL_UPDATE = "withdrawal_update", "Withdrawal update"
        LOAN_UPDATE = "loan_update", "Loan update"
        VOTE_OPEN = "vote_open", "Voting open"
        ANNOUNCEMENT = "announcement", "Announcement"
        MEMBERSHIP = "membership", "Membership"
        PROGRAMME = "programme", "Programme update"
        SECURITY = "security", "Security"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications")
    kind = models.CharField(max_length=30, choices=Kind.choices, db_index=True)
    title = models.CharField(max_length=140)
    body = models.CharField(max_length=400)
    data = models.JSONField(default=dict, blank=True)
    dedupe_key = models.CharField(max_length=160, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)
    push_sent_at = models.DateTimeField(null=True, blank=True)
    push_error = models.CharField(max_length=300, blank=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(fields=["user", "dedupe_key"], condition=~models.Q(dedupe_key=""),
                                    name="uniq_notification_dedupe"),
        ]
        indexes = [models.Index(fields=["user", "read_at"]), models.Index(fields=["user", "-created_at"])]

    def __str__(self) -> str:
        return f"{self.kind} -> {self.user_id}"


class NotificationPreference(AuditModel):
    """What a member wants to hear about, and where."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notification_preferences")
    push_enabled = models.BooleanField(default=True)
    email_enabled = models.BooleanField(default=True)
    contributions = models.BooleanField(default=True)
    payouts = models.BooleanField(default=True)
    loans = models.BooleanField(default=True)
    governance = models.BooleanField(default=True)
    announcements = models.BooleanField(default=True)
    security = models.BooleanField(default=True, help_text="Security alerts cannot be fully disabled")
    quiet_hours_start = models.PositiveSmallIntegerField(null=True, blank=True, help_text="0-23, member's local time")
    quiet_hours_end = models.PositiveSmallIntegerField(null=True, blank=True)

    def __str__(self) -> str:
        return f"prefs for {self.user_id}"
