"""Cooperative governance: proposals, ballots, resolutions.

A ballot can be secret. When it is, the vote row stores the choice but not the
voter, and a separate receipt row proves *that* the member voted without
proving *how* — so an administrator cannot reconstruct a secret choice from
ordinary reporting.
"""

from __future__ import annotations

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.common.models import AuditModel, UUIDModel


class Proposal(AuditModel):
    class Kind(models.TextChoices):
        GENERAL = "general", "General decision"
        LOAN = "loan", "Loan approval"
        WITHDRAWAL = "withdrawal", "Withdrawal approval"
        RULE_CHANGE = "rule_change", "Rule change"
        ELECTION = "election", "Election"

    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        OPEN = "open", "Voting open"
        CLOSED = "closed", "Voting closed"
        PASSED = "passed", "Passed"
        REJECTED = "rejected", "Rejected"
        WITHDRAWN = "withdrawn", "Withdrawn"

    group = models.ForeignKey("groups.Group", on_delete=models.CASCADE, related_name="proposals")
    kind = models.CharField(max_length=20, choices=Kind.choices, default=Kind.GENERAL)
    title = models.CharField(max_length=180)
    description = models.TextField(max_length=4000)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.DRAFT, db_index=True)

    requires_quorum = models.BooleanField(default=True)
    quorum_percent = models.PositiveSmallIntegerField(default=50, help_text="Percentage of eligible voters")
    pass_threshold_percent = models.PositiveSmallIntegerField(default=50)
    is_secret = models.BooleanField(default=False)
    opens_at = models.DateTimeField(default=timezone.now)
    closes_at = models.DateTimeField()
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL)
    resolution_text = models.TextField(blank=True, max_length=2000)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.CheckConstraint(condition=models.Q(closes_at__gt=models.F("opens_at")), name="proposal_window_valid"),
            models.CheckConstraint(condition=models.Q(quorum_percent__lte=100), name="proposal_quorum_sane"),
        ]
        indexes = [models.Index(fields=["group", "status"])]

    def __str__(self) -> str:
        return self.title

    @property
    def is_open(self) -> bool:
        return self.status == self.Status.OPEN and self.opens_at <= timezone.now() < self.closes_at


class Ballot(UUIDModel):
    """A vote. `voter` is null for a secret ballot."""

    proposal = models.ForeignKey(Proposal, on_delete=models.CASCADE, related_name="ballots")
    voter = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE,
                              related_name="ballots")
    choice = models.BooleanField(help_text="True = in favour")
    comment = models.CharField(max_length=300, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = []

    def __str__(self) -> str:
        return f"{self.proposal_id} -> {self.choice}"


class BallotReceipt(UUIDModel):
    """Proof that a member cast a ballot, without the ballot itself.

    `ballot` is deliberately nullable and is left empty for secret proposals.
    A foreign key here would be a permanent link from a named member to a named
    vote — the exact record a secret ballot exists to make impossible. Without
    it, turnout is still provable (this row exists) while the choice is not
    attributable to anyone.
    """

    proposal = models.ForeignKey(Proposal, on_delete=models.CASCADE, related_name="receipts")
    voter = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="ballot_receipts")
    ballot = models.OneToOneField(
        Ballot, null=True, blank=True, on_delete=models.SET_NULL, related_name="receipt",
        help_text="Empty for secret ballots: a link here would deanonymise the vote",
    )
    cast_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["proposal", "voter"], name="uniq_ballot_per_voter")]


class Resolution(AuditModel):
    """The published outcome of a closed proposal."""

    proposal = models.OneToOneField(Proposal, on_delete=models.CASCADE, related_name="resolution")
    passed = models.BooleanField()
    votes_for = models.PositiveIntegerField(default=0)
    votes_against = models.PositiveIntegerField(default=0)
    eligible_voters = models.PositiveIntegerField(default=0)
    quorum_met = models.BooleanField(default=False)
    published_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL)
    published_at = models.DateTimeField(default=timezone.now)
    text = models.TextField(max_length=2000)

    class Meta:
        ordering = ("-published_at",)
