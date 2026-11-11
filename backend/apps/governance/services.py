"""Voting rules that hold even when an administrator is curious."""

from __future__ import annotations

import logging

from django.db import transaction
from django.db.models import Count, Q
from django.utils import timezone

from apps.common.audit import AuditLog
from apps.common.exceptions import ConflictError, DomainError, InvalidStateError, PermissionDeniedError
from apps.common.outbox import publish
from apps.groups.models import Membership, Permission as GroupPermission
from apps.groups.permissions import require_membership, require_permission

from .models import Ballot, BallotReceipt, Proposal, Resolution

logger = logging.getLogger("kolo.audit")


def eligible_voters(proposal: Proposal):
    return Membership.objects.filter(group=proposal.group, status=Membership.Status.ACTIVE)


def cast_ballot(*, actor, proposal: Proposal, in_favour: bool, comment: str = "") -> Ballot:
    """One member, one vote. Secret ballots store no link to the voter."""
    membership = require_membership(actor, proposal.group)
    if not proposal.is_open:
        raise InvalidStateError("Voting is not open for this proposal.", code="vote_not_open")
    if BallotReceipt.objects.filter(proposal=proposal, voter=actor).exists():
        raise ConflictError("You have already voted on this proposal.", code="already_voted")

    with transaction.atomic():
        ballot = Ballot.objects.create(
            proposal=proposal,
            voter=None if proposal.is_secret else actor,
            choice=in_favour,
            comment="" if proposal.is_secret else comment[:300],
        )
        # Receipt proves turnout; for a secret ballot it carries no link back
        # to the ballot it belongs to.
        BallotReceipt.objects.create(
            proposal=proposal, voter=actor, ballot=None if proposal.is_secret else ballot
        )

    AuditLog.record(action="governance.vote_cast", actor=actor, group_id=proposal.group_id,
                    target_type="proposal", target_id=proposal.pk,
                    summary="Ballot cast" + (" (secret)" if proposal.is_secret else f": {'for' if in_favour else 'against'}"))
    return ballot


def open_proposal(*, actor, proposal: Proposal) -> Proposal:
    require_permission(actor, proposal.group, GroupPermission.PROPOSAL_MANAGE)
    with transaction.atomic():
        proposal = Proposal.objects.select_for_update().get(pk=proposal.pk)
        if proposal.status != Proposal.Status.DRAFT:
            raise InvalidStateError("Only a draft can be opened.", code="proposal_not_draft")
        if proposal.closes_at <= timezone.now():
            raise DomainError("Set a closing time in the future.", code="proposal_window_past")
        proposal.status = Proposal.Status.OPEN
        proposal.save(update_fields=["status", "updated_at"])
    publish("governance.vote_opened", {"proposal_id": str(proposal.pk), "group_id": str(proposal.group_id),
                                       "title": proposal.title})
    return proposal


def close_proposal(*, actor, proposal: Proposal) -> Resolution:
    """Count, decide and publish. Ties do not pass."""
    require_permission(actor, proposal.group, GroupPermission.PROPOSAL_MANAGE)
    with transaction.atomic():
        proposal = Proposal.objects.select_for_update().get(pk=proposal.pk)
        if proposal.status != Proposal.Status.OPEN:
            raise InvalidStateError("This proposal is not open.", code="proposal_not_open")

        # Count in one query, filtering on the choice itself.
        tally = proposal.ballots.aggregate(
            for_count=Count("id", filter=Q(choice=True)),
            against=Count("id", filter=Q(choice=False)),
        )
        votes_for = tally["for_count"] or 0
        votes_against = tally["against"] or 0
        eligible = eligible_voters(proposal).count()
        # Secret ballots count receipts, which is a reliable turnout figure.
        cast = proposal.receipts.count()
        quorum_met = True if not proposal.requires_quorum else (eligible > 0 and cast * 100 >= eligible * proposal.quorum_percent)
        decided = cast > 0 and votes_for > votes_against
        passed = quorum_met and decided

        proposal.status = Proposal.Status.PASSED if passed else Proposal.Status.REJECTED
        proposal.save(update_fields=["status", "updated_at"])
        resolution = Resolution.objects.create(
            proposal=proposal, passed=passed, votes_for=votes_for, votes_against=votes_against,
            eligible_voters=eligible, quorum_met=quorum_met, published_by=actor,
            text=proposal.resolution_text or f"{proposal.title}: {'carried' if passed else 'not carried'}",
        )

    AuditLog.record(action="governance.proposal_closed", actor=actor, group_id=proposal.group_id,
                    target_type="proposal", target_id=proposal.pk,
                    summary=f"{'passed' if passed else 'rejected'} ({votes_for}-{votes_against}, quorum {'met' if quorum_met else 'not met'})")
    publish("governance.resolution_published", {"proposal_id": str(proposal.pk), "group_id": str(proposal.group_id),
                                                "passed": passed})
    return resolution
