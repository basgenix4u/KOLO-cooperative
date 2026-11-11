"""The rotational engine: the promise is "you get paid when your turn comes".

That promise is only honest if the payout is backed by money the group actually
collected. These tests attack that guarantee from every angle a real group
would: short collection, self-approval, double execution, replay.
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest
from django.utils import timezone

from apps.common.exceptions import (
    FinancialSafetyError, InvalidStateError, PermissionDeniedError,
)
from apps.ledger import services as ledger
from apps.savings import services
from apps.savings.models import Contribution, Obligation, Participation, Programme, RotationCycle

pytestmark = pytest.mark.django_db


@pytest.fixture
def rotation_group(group, officers):
    """A group of four, each contributing 10,000 NGN monthly."""
    from apps.groups.models import GroupRole, Membership

    for user, name in [
        (group.created_by, "Chair"),
    ]:
        pass
    return group


def _staff(group, officers, memberships, n=2):
    """Total active members: 2 officers + 2 members."""
    return list(memberships.values())


@pytest.fixture
def programme(group, officers, memberships):
    """An active rotational programme with a locked payout order."""
    all_memberships = [officers["chair"], officers["treasurer"], memberships["a"], memberships["b"]]
    programme = services.create_programme(
        actor=officers["chair"].user,
        group=group,
        name="Monthly Ajo",
        description="Four friends, one pot a month",
        type="rotational",
        currency="NGN",
        contribution_amount_minor=10_000,
        frequency="monthly",
        start_date=timezone.localdate(),
    )
    services.add_participants(
        actor=officers["chair"].user, programme=programme,
        membership_ids=[str(m.pk) for m in all_memberships],
    )
    participations = list(programme.participants.order_by("created_at"))
    services.set_rotation_order(
        actor=officers["chair"].user, programme=programme,
        ordered_participation_ids=[str(p.pk) for p in participations],
    )
    # transition() re-reads the row under lock and returns it; using the stale
    # local would try the same transition from "draft" twice.
    programme = services.transition(
        actor=officers["chair"].user, programme=programme, to_status=Programme.Status.SCHEDULED
    )
    programme = services.transition(
        actor=officers["chair"].user, programme=programme, to_status=Programme.Status.ACTIVE
    )
    return programme


def _third_officer(programme, exclude_user_ids):
    """An officer who is neither the approver nor the beneficiary.

    Two signatures are meaningless if the same person can supply both, so the
    tests refuse to collapse them either.
    """
    from apps.groups.models import GroupRole, Membership

    membership = (
        Membership.objects.filter(group=programme.group, status=Membership.Status.ACTIVE,
                                  role=GroupRole.MEMBER)
        .exclude(user_id__in=exclude_user_ids)
        .select_related("user")
        .first()
    )
    assert membership is not None, "test setup needs an eligible third officer"
    # Treasurer carries finance.post; grant it for this person only.
    membership.role = GroupRole.TREASURER
    membership.save(update_fields=["role"])
    return membership.user


def _pay(programme, actor, participating_membership, amount_minor=None):
    """Clear one member's obligation for the first cycle, as an officer would."""
    obligation = (
        programme.obligations.filter(participation__membership=participating_membership)
        .order_by("due_date")
        .first()
    )
    participation = obligation.participation
    return services.record_offline_contribution(
        actor=actor, programme=programme, participation=participation,
        amount_minor=amount_minor or obligation.amount_minor,
    )


def test_activation_requires_a_full_rotation_order(group, officers, memberships):
    programme = services.create_programme(
        actor=officers["chair"].user, group=group, name="Half-built",
        type="rotational", currency="NGN", contribution_amount_minor=5_000,
        frequency="monthly", start_date=timezone.localdate(),
    )
    services.add_participants(
        actor=officers["chair"].user, programme=programme,
        membership_ids=[str(officers["chair"].pk), str(memberships["a"].pk)],
    )
    programme = services.transition(
        actor=officers["chair"].user, programme=programme, to_status=Programme.Status.SCHEDULED
    )

    with pytest.raises(Exception) as caught:
        services.transition(actor=officers["chair"].user, programme=programme, to_status=Programme.Status.ACTIVE)
    assert getattr(caught.value, "code", "") == "rotation_incomplete"


def test_activation_needs_at_least_two_people(group, officers):
    programme = services.create_programme(
        actor=officers["chair"].user, group=group, name="Solo",
        type="rotational", currency="NGN", contribution_amount_minor=5_000,
        frequency="monthly", start_date=timezone.localdate(),
    )
    services.add_participants(
        actor=officers["chair"].user, programme=programme,
        membership_ids=[str(officers["chair"].pk)],
    )
    programme = services.transition(
        actor=officers["chair"].user, programme=programme, to_status=Programme.Status.SCHEDULED
    )
    with pytest.raises(Exception) as caught:
        services.transition(actor=officers["chair"].user, programme=programme, to_status=Programme.Status.ACTIVE)
    assert getattr(caught.value, "code", "") == "programme_too_small"


def test_rotation_order_cannot_be_changed_once_locked(programme, officers):
    participations = list(programme.participants.all())
    with pytest.raises(Exception) as caught:
        services.set_rotation_order(
            actor=officers["chair"].user, programme=programme,
            ordered_participation_ids=[str(p.pk) for p in reversed(participations)],
        )
    assert getattr(caught.value, "code", "") == "rotation_locked"


def test_rotation_order_must_name_every_participant(group, officers, memberships):
    """Order is set before activation; a partial order is refused."""
    all_memberships = [officers["chair"], officers["treasurer"], memberships["a"], memberships["b"]]
    programme = services.create_programme(
        actor=officers["chair"].user, group=group, name="Partial order",
        type="rotational", currency="NGN", contribution_amount_minor=10_000,
        frequency="monthly", start_date=timezone.localdate(),
    )
    services.add_participants(
        actor=officers["chair"].user, programme=programme,
        membership_ids=[str(m.pk) for m in all_memberships],
    )
    participations = list(programme.participants.order_by("created_at"))
    with pytest.raises(Exception) as caught:
        services.set_rotation_order(
            actor=officers["chair"].user, programme=programme,
            ordered_participation_ids=[str(p.pk) for p in participations[:-1]],
        )
    assert getattr(caught.value, "code", "") == "rotation_order_mismatch"


def test_rotation_order_refuses_a_duplicate(group, officers, memberships):
    all_memberships = [officers["chair"], officers["treasurer"], memberships["a"], memberships["b"]]
    programme = services.create_programme(
        actor=officers["chair"].user, group=group, name="Duplicate order",
        type="rotational", currency="NGN", contribution_amount_minor=10_000,
        frequency="monthly", start_date=timezone.localdate(),
    )
    services.add_participants(
        actor=officers["chair"].user, programme=programme,
        membership_ids=[str(m.pk) for m in all_memberships],
    )
    participations = list(programme.participants.order_by("created_at"))
    dup_ids = [str(p.pk) for p in participations[:-1]] + [str(participations[0].pk)]
    with pytest.raises(Exception) as caught:
        services.set_rotation_order(
            actor=officers["chair"].user, programme=programme, ordered_participation_ids=dup_ids,
        )
    assert getattr(caught.value, "code", "") == "rotation_order_duplicate"


def test_payout_is_refused_when_collection_is_short(programme, officers, memberships):
    """The core refusal: 40,000 is due, one member has paid."""
    cycle = programme.cycles.first()
    assert cycle.payout_amount_minor == 40_000

    _pay(programme, officers["treasurer"].user, memberships["a"])

    cycle.refresh_from_db()
    assert cycle.collected_total_minor == 10_000
    assert cycle.status == RotationCycle.Status.COLLECTING

    with pytest.raises(InvalidStateError):
        services.approve_payout(actor=officers["treasurer"].user, cycle=cycle)


def test_payout_never_exceeds_collected_even_when_ready(programme, officers, memberships):
    """Three of four pay: still not ready, and the shortfall is stated."""
    cycle = programme.cycles.first()
    _pay(programme, officers["treasurer"].user, memberships["a"])
    _pay(programme, officers["treasurer"].user, memberships["b"])
    _pay(programme, officers["treasurer"].user, officers["treasurer"])

    cycle.refresh_from_db()
    assert cycle.collected_total_minor == 30_000
    assert cycle.shortfall_minor == 10_000
    assert cycle.status == RotationCycle.Status.COLLECTING

    with pytest.raises(InvalidStateError) as caught:
        services.approve_payout(actor=officers["treasurer"].user, cycle=cycle)
    assert caught.value.code == "cycle_not_ready"
    assert caught.value.details["collected_minor"] == 30_000


def test_full_collection_marks_the_cycle_ready(programme, officers, memberships):
    cycle = programme.cycles.first()
    for membership in [officers["chair"], officers["treasurer"], memberships["a"], memberships["b"]]:
        _pay(programme, officers["treasurer"].user, membership)

    cycle.refresh_from_db()
    assert cycle.collected_total_minor == 40_000
    assert cycle.status == RotationCycle.Status.READY_FOR_PAYOUT
    pool = ledger.programme_pool(programme)
    assert ledger.balance_of(pool) == 40_000


def test_beneficiary_cannot_approve_their_own_payout(programme, officers, memberships):
    cycle = programme.cycles.first()
    for membership in [officers["chair"], officers["treasurer"], memberships["a"], memberships["b"]]:
        _pay(programme, officers["treasurer"].user, membership)

    beneficiary_user = cycle.beneficiary.membership.user
    assert beneficiary_user in {officers["chair"].user, officers["treasurer"].user}

    with pytest.raises(PermissionDeniedError) as caught:
        services.approve_payout(actor=beneficiary_user, cycle=cycle)
    assert caught.value.code == "self_approval_blocked"


def test_payout_requires_two_different_officers(programme, officers, memberships):
    cycle = programme.cycles.first()
    for membership in [officers["chair"], officers["treasurer"], memberships["a"], memberships["b"]]:
        _pay(programme, officers["treasurer"].user, membership)

    beneficiary_user = cycle.beneficiary.membership.user
    approver = officers["chair"].user if beneficiary_user == officers["treasurer"].user else officers["treasurer"].user
    other = officers["treasurer"].user if approver == officers["chair"].user else officers["chair"].user

    approved = services.approve_payout(actor=approver, cycle=cycle)
    assert approved.status == RotationCycle.Status.PAYOUT_PENDING_APPROVAL

    # Pressing approve again is a client retry, and it does not mint a second
    # signature: the approver still cannot execute.
    again = services.approve_payout(actor=approver, cycle=cycle)
    assert again.status == RotationCycle.Status.PAYOUT_PENDING_APPROVAL

    with pytest.raises(PermissionDeniedError) as caught:
        services.execute_payout(actor=approver, cycle=approved)
    assert caught.value.code == "approver_cannot_execute"


def test_execute_posts_the_payout_once(programme, officers, memberships):
    cycle = programme.cycles.first()
    for membership in [officers["chair"], officers["treasurer"], memberships["a"], memberships["b"]]:
        _pay(programme, officers["treasurer"].user, membership)

    beneficiary_user = cycle.beneficiary.membership.user
    approver = officers["chair"].user if beneficiary_user == officers["treasurer"].user else officers["treasurer"].user

    services.approve_payout(actor=approver, cycle=cycle)
    executor = _third_officer(programme, {approver.pk, beneficiary_user.pk})
    paid = services.execute_payout(actor=executor, cycle=cycle)
    assert paid.status == RotationCycle.Status.PAID

    holding = ledger.member_holding(programme.group, cycle.beneficiary.membership_id, "NGN")
    assert ledger.natural_balance(holding) == 40_000

    # Calling it again is a no-op, not a second payment.
    services.execute_payout(actor=executor, cycle=cycle)
    holding.refresh_from_db()
    assert ledger.natural_balance(holding) == 40_000


def test_execute_refuses_an_unapproved_payout(programme, officers, memberships):
    cycle = programme.cycles.first()
    for membership in [officers["chair"], officers["treasurer"], memberships["a"], memberships["b"]]:
        _pay(programme, officers["treasurer"].user, membership)

    with pytest.raises(InvalidStateError) as caught:
        services.execute_payout(actor=officers["treasurer"].user, cycle=cycle)
    assert caught.value.code == "payout_not_approved"


def test_pool_cannot_be_drained_by_editing_the_cycle(programme, officers, memberships):
    """Even if a cycle is doctored to claim more than was collected, the pool check holds."""
    cycle = programme.cycles.first()
    _pay(programme, officers["treasurer"].user, memberships["a"])

    RotationCycle.objects.filter(pk=cycle.pk).update(
        status=RotationCycle.Status.READY_FOR_PAYOUT,
        collected_total_minor=40_000,
        payout_amount_minor=40_000,
    )
    cycle.refresh_from_db()
    approver = officers["chair"].user
    if cycle.beneficiary and cycle.beneficiary.membership.user_id == approver.pk:
        approver = officers["treasurer"].user
    services.approve_payout(actor=approver, cycle=cycle)

    executor = _third_officer(programme, {approver.pk})
    with pytest.raises(FinancialSafetyError) as caught:
        services.execute_payout(actor=executor, cycle=cycle)
    assert caught.value.code == "pool_underfunded"
    pool = ledger.programme_pool(programme)
    assert ledger.balance_of(pool) == 10_000, "the ledger refused to invent money"


def test_offline_contribution_posts_real_ledger_money(programme, officers, memberships):
    contribution = _pay(programme, officers["treasurer"].user, memberships["a"])
    contribution.refresh_from_db()
    assert contribution.status == Contribution.Status.CONFIRMED
    assert contribution.ledger_reference
    pool = ledger.programme_pool(programme)
    assert ledger.balance_of(pool) == 10_000

    obligation = programme.obligations.filter(participation__membership=memberships["a"]).first()
    obligation.refresh_from_db()
    assert obligation.status == Obligation.Status.SETTLED


def test_offline_contribution_requires_the_treasurer_permission(programme, memberships):
    with pytest.raises(PermissionDeniedError):
        _pay(programme, memberships["a"].user, memberships["a"])


def test_settling_the_same_contribution_twice_does_not_double_the_money(programme, officers, memberships):
    contribution = _pay(programme, officers["treasurer"].user, memberships["a"])
    services.settle_contribution(contribution)
    services.settle_contribution(contribution)
    pool = ledger.programme_pool(programme)
    assert ledger.balance_of(pool) == 10_000


def test_overpayment_becomes_member_holding_not_lost_money(programme, officers, memberships):
    contribution = _pay(programme, officers["treasurer"].user, memberships["a"], amount_minor=15_000)
    holding = ledger.member_holding(programme.group, memberships["a"].pk, "NGN")
    assert ledger.natural_balance(holding) == 5_000, "the extra 5,000 belongs to the member"
    # The cash never left the pool; only the claim on it moved, so the group's
    # assets are not inflated by money nobody paid.
    pool = ledger.programme_pool(programme)
    assert ledger.balance_of(pool) == 15_000
    liability = ledger.programme_liability(programme)
    assert ledger.natural_balance(liability) == 15_000 - 5_000
