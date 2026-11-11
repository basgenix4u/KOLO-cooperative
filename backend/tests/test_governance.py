"""Governance: one member one vote, secret ballots that stay secret, ties fail.

A group's rules are only worth the enforcement behind them. These tests act as
an administrator who is curious and a member who tries to vote twice.
"""

from __future__ import annotations

import pytest
from django.utils import timezone

from apps.common.exceptions import ConflictError, InvalidStateError, PermissionDeniedError
from apps.governance import services
from apps.governance.models import Ballot, BallotReceipt, Proposal, Resolution

pytestmark = pytest.mark.django_db


def _proposal(group, officers, *, secret=False, quorum=0, threshold=50, hours=24):
    from datetime import timedelta

    proposal = Proposal.objects.create(
        group=group,
        title="Raise the monthly contribution to 15,000",
        description="Needed to cover the new payout schedule.",
        resolution_text="Contribution becomes 15,000 from next month.",
        created_by=officers["chair"].user,
        requires_quorum=quorum > 0,
        quorum_percent=quorum,
        pass_threshold_percent=threshold,
        is_secret=secret,
        opens_at=timezone.now(),
        closes_at=timezone.now() + timedelta(hours=hours),
    )
    return services.open_proposal(actor=officers["chair"].user, proposal=proposal)


def test_one_member_cannot_vote_twice(group, officers, memberships):
    proposal = _proposal(group, officers)
    services.cast_ballot(actor=officers["chair"].user, proposal=proposal, in_favour=True)

    with pytest.raises(ConflictError) as caught:
        services.cast_ballot(actor=officers["chair"].user, proposal=proposal, in_favour=False)
    assert caught.value.code == "already_voted"
    assert proposal.ballots.count() == 1


def test_non_member_cannot_vote(group, officers, outsider):
    """A private group answers 404, not 403: a 403 would confirm it exists."""
    from apps.common.exceptions import NotFoundError

    proposal = _proposal(group, officers)
    with pytest.raises(NotFoundError) as caught:
        services.cast_ballot(actor=outsider, proposal=proposal, in_favour=True)
    assert caught.value.code == "group_not_found"


def test_voting_is_refused_when_closed(group, officers):
    proposal = _proposal(group, officers)
    Proposal.objects.filter(pk=proposal.pk).update(
        status=Proposal.Status.REJECTED, closes_at=timezone.now()
    )
    proposal.refresh_from_db()
    with pytest.raises(InvalidStateError) as caught:
        services.cast_ballot(actor=officers["chair"].user, proposal=proposal, in_favour=True)
    assert caught.value.code == "vote_not_open"


def test_secret_ballot_stores_no_voter_on_the_ballot(group, officers, memberships):
    proposal = _proposal(group, officers, secret=True)
    ballot = services.cast_ballot(actor=memberships["a"].user, proposal=proposal, in_favour=True)

    ballot.refresh_from_db()
    assert ballot.voter is None, "a secret ballot must not name its voter"
    assert ballot.comment == "", "and must not carry a comment that could identify them"


def test_secret_ballot_receipt_does_not_point_at_the_ballot(group, officers, memberships):
    """Turnout is provable; the choice is not attributable."""
    proposal = _proposal(group, officers, secret=True)
    services.cast_ballot(actor=memberships["a"].user, proposal=proposal, in_favour=True)

    receipt = BallotReceipt.objects.get(proposal=proposal, voter=memberships["a"].user)
    assert receipt.ballot_id is None, "a link here would deanonymise the vote"
    # The member still cannot vote again, which is what the receipt is for.
    with pytest.raises(ConflictError):
        services.cast_ballot(actor=memberships["a"].user, proposal=proposal, in_favour=False)


def test_open_ballot_records_the_voter(group, officers, memberships):
    proposal = _proposal(group, officers, secret=False)
    ballot = services.cast_ballot(actor=memberships["a"].user, proposal=proposal, in_favour=False)
    ballot.refresh_from_db()
    assert ballot.voter_id == memberships["a"].user_id, "an open ballot is attributable"


def test_tie_does_not_pass(group, officers, memberships):
    proposal = _proposal(group, officers, secret=False)
    services.cast_ballot(actor=memberships["a"].user, proposal=proposal, in_favour=True)
    services.cast_ballot(actor=memberships["b"].user, proposal=proposal, in_favour=False)

    resolution = services.close_proposal(actor=officers["chair"].user, proposal=proposal)
    assert resolution.votes_for == 1
    assert resolution.votes_against == 1
    assert resolution.passed is False, "a tie is not a mandate"
    proposal.refresh_from_db()
    assert proposal.status == Proposal.Status.REJECTED


def test_zero_turnout_does_not_pass(group, officers):
    proposal = _proposal(group, officers)
    resolution = services.close_proposal(actor=officers["chair"].user, proposal=proposal)
    assert resolution.passed is False
    assert resolution.votes_for == 0


def test_majority_passes(group, officers, memberships):
    proposal = _proposal(group, officers, secret=True)
    services.cast_ballot(actor=memberships["a"].user, proposal=proposal, in_favour=True)
    services.cast_ballot(actor=memberships["b"].user, proposal=proposal, in_favour=True)
    services.cast_ballot(actor=officers["treasurer"].user, proposal=proposal, in_favour=False)

    resolution = services.close_proposal(actor=officers["chair"].user, proposal=proposal)
    assert (resolution.votes_for, resolution.votes_against) == (2, 1)
    assert resolution.passed is True
    proposal.refresh_from_db()
    assert proposal.status == Proposal.Status.PASSED


def test_quorum_must_be_met_even_with_a_majority(group, officers, memberships):
    """Four members; a 75% quorum needs three votes. One vote is not enough."""
    proposal = _proposal(group, officers, quorum=75)
    services.cast_ballot(actor=memberships["a"].user, proposal=proposal, in_favour=True)

    resolution = services.close_proposal(actor=officers["chair"].user, proposal=proposal)
    assert resolution.quorum_met is False
    assert resolution.passed is False, "a majority of one voter is not a decision"
    assert resolution.eligible_voters == 4


def test_quorum_met_with_enough_turnout(group, officers, memberships):
    proposal = _proposal(group, officers, quorum=50)
    services.cast_ballot(actor=memberships["a"].user, proposal=proposal, in_favour=True)
    services.cast_ballot(actor=memberships["b"].user, proposal=proposal, in_favour=True)

    resolution = services.close_proposal(actor=officers["chair"].user, proposal=proposal)
    assert resolution.quorum_met is True
    assert resolution.passed is True


def test_only_an_officer_can_close(group, officers, memberships):
    proposal = _proposal(group, officers)
    with pytest.raises(PermissionDeniedError):
        services.close_proposal(actor=memberships["a"].user, proposal=proposal)


def test_a_proposal_cannot_be_closed_twice(group, officers):
    proposal = _proposal(group, officers)
    services.close_proposal(actor=officers["chair"].user, proposal=proposal)
    with pytest.raises(InvalidStateError) as caught:
        services.close_proposal(actor=officers["chair"].user, proposal=proposal)
    assert caught.value.code == "proposal_not_open"
    assert Resolution.objects.filter(proposal=proposal).count() == 1


def test_a_draft_cannot_be_voted_on(group, officers):
    proposal = Proposal.objects.create(
        group=group, title="Not yet open", created_by=officers["chair"].user,
        closes_at=timezone.now() + timezone.timedelta(hours=1),
    )
    with pytest.raises(InvalidStateError) as caught:
        services.cast_ballot(actor=officers["chair"].user, proposal=proposal, in_favour=True)
    assert caught.value.code == "vote_not_open"
