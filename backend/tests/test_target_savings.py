"""Programmes that are not rotational still have to collect contributions."""
import pytest

from apps.savings import services

def test_a_target_programme_generates_contribution_obligations(db):
    """A goal-based pot must be able to collect money, not just exist.

    Obligations were only generated as a side effect of opening a rotation
    cycle, so a `target` programme activated correctly, enrolled its members,
    and then handed every one of them an empty obligation list. Nobody could
    contribute to it, and the symptom was an empty screen rather than an error.
    """
    from datetime import date, timedelta

    from django.utils import timezone

    from apps.accounts.models import User
    from apps.groups.models import Group, GroupRole, Membership
    from apps.savings.models import Programme, ProgrammeType

    owner = User.objects.create_user(email="t-owner@example.com", password="x" * 12)
    group = Group.objects.create(name="Target Group", slug="target-group", created_by=owner)
    membership = Membership.objects.create(
        group=group, user=owner, role=GroupRole.FOUNDER,
        status=Membership.Status.ACTIVE, joined_at=timezone.now(),
    )
    second = User.objects.create_user(email="t-second@example.com", password="x" * 12)
    second_membership = Membership.objects.create(
        group=group, user=second, role=GroupRole.MEMBER,
        status=Membership.Status.ACTIVE, joined_at=timezone.now(),
    )

    programme = Programme.objects.create(
        group=group, name="Welfare", type=ProgrammeType.TARGET,
        contribution_amount_minor=50_000, frequency="monthly", currency="NGN",
        start_date=date.today() + timedelta(days=1), created_by=owner,
        target_amount_minor=200_000,
    )
    services.add_participants(
        actor=owner, programme=programme,
        membership_ids=[membership.pk, second_membership.pk],
    )
    services.transition(actor=owner, programme=programme, to_status="scheduled")
    programme.refresh_from_db()
    services.transition(actor=owner, programme=programme, to_status="active")

    programme.refresh_from_db()
    assert programme.status == Programme.Status.ACTIVE
    assert programme.obligations.count() == 2, "each participant owes exactly one contribution"
    assert all(o.amount_minor == 50_000 for o in programme.obligations.all())

    # Activating again must not double-bill: the period is keyed on its due date.
    services.transition(actor=owner, programme=programme, to_status="paused")
    programme.refresh_from_db()
    services.transition(actor=owner, programme=programme, to_status="active")
    assert programme.obligations.count() == 2
