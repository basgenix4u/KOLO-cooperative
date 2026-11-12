"""Savings business logic.

The rotational engine is the most delicate part of KOLO. Its whole job is to
prevent a payout that the group has not actually funded, so the sequence is
deliberately rigid:

    contribution verified -> ledger posted -> cycle.collected updated
    -> payout only if collected >= payout -> two different officers approve
    -> funds reserved -> disbursed -> ledger posted -> cycle closed
"""

from __future__ import annotations

import logging
import secrets
import uuid
from datetime import date, timedelta

from django.conf import settings
from django.db import transaction
from django.db.models import F, Sum
from django.utils import timezone

from apps.common.audit import AuditLog
from apps.common.exceptions import (
    ConflictError,
    DomainError,
    FinancialSafetyError,
    InvalidStateError,
    NotFoundError,
    PermissionDeniedError,
)
from apps.common.outbox import publish
from apps.groups.models import GroupRole, Membership, Permission as GroupPermission
from apps.groups.permissions import require_membership, require_permission
from apps.ledger import services as ledger

from .models import (
    FREQUENCY_DAYS,
    Contribution,
    ContributionTarget,
    FundraisingCampaign,
    Frequency,
    Obligation,
    Participation,
    Programme,
    ProgrammeType,
    RotationCycle,
    RotationPosition,
    WithdrawalApproval,
    WithdrawalRequest,
)

logger = logging.getLogger("kolo.audit")


def new_reference(prefix: str) -> str:
    return f"{prefix}-{timezone.now():%Y%m%d}-{secrets.token_hex(3).upper()}"


# ---------------------------------------------------------------------------
# Programme lifecycle
# ---------------------------------------------------------------------------

ALLOWED_TRANSITIONS = {
    Programme.Status.DRAFT: {Programme.Status.PENDING_APPROVAL, Programme.Status.SCHEDULED, Programme.Status.CANCELLED},
    Programme.Status.PENDING_APPROVAL: {Programme.Status.SCHEDULED, Programme.Status.DRAFT, Programme.Status.CANCELLED},
    Programme.Status.SCHEDULED: {Programme.Status.ACTIVE, Programme.Status.CANCELLED},
    Programme.Status.ACTIVE: {Programme.Status.PAUSED, Programme.Status.COMPLETED, Programme.Status.CLOSED},
    Programme.Status.PAUSED: {Programme.Status.ACTIVE, Programme.Status.CANCELLED, Programme.Status.CLOSED},
    Programme.Status.COMPLETED: {Programme.Status.CLOSED},
    Programme.Status.CANCELLED: set(),
    Programme.Status.CLOSED: set(),
}


def create_programme(*, actor, group, **fields) -> Programme:
    """Create a programme. Officers only; it starts as a draft."""
    require_permission(actor, group, GroupPermission.PROGRAMME_CREATE)
    programme = Programme.objects.create(
        group=group,
        created_by=actor,
        currency=fields.pop("currency", group.currency).upper(),
        **fields,
    )
    AuditLog.record(
        action="programme.created", actor=actor, group_id=group.pk, target_type="programme",
        target_id=programme.pk, summary=f"{programme.name} created as draft",
    )
    return programme


def transition(*, actor, programme: Programme, to_status: str, note: str = "") -> Programme:
    """Move a programme through its lifecycle, refusing illegal jumps.

    Editing rules matter as much as transitions: a contribution amount cannot
    change under members who already agreed to it.
    """
    require_permission(actor, programme.group, GroupPermission.PROGRAMME_ACTIVATE)
    allowed = ALLOWED_TRANSITIONS.get(programme.status, set())
    if to_status not in allowed:
        raise InvalidStateError(
            f"A programme cannot go from {programme.status} to {to_status}.",
            code="programme_transition_invalid",
            details={"from": programme.status, "to": to_status},
        )

    with transaction.atomic():
        programme = Programme.objects.select_for_update().get(pk=programme.pk)
        if to_status == Programme.Status.ACTIVE:
            # The gate runs against the locked row, before any money or cycle
            # is created, so a half-built rotation can never start collecting.
            _assert_activation_ready(programme)
            programme.activated_at = timezone.now()
            if programme.type == ProgrammeType.ROTATIONAL:
                _ensure_first_cycle(programme)
            else:
                # Non-rotational programmes collect too. Obligations were only
                # ever created as a side effect of opening a rotation cycle, so a
                # target or accumulated savings pot activated cleanly, enrolled
                # its members, and then gave every one of them an empty
                # obligation list — nobody could pay into it at all. The first
                # period is opened here for the programmes that have no cycle.
                _ensure_first_period(programme)
        if to_status in {Programme.Status.COMPLETED, Programme.Status.CLOSED}:
            _assert_closeable(programme)
            programme.closed_at = timezone.now()
        programme.status = to_status
        programme.save()
        AuditLog.record(
            action="programme.status_changed", actor=actor, group_id=programme.group_id,
            target_type="programme", target_id=programme.pk,
            summary=f"{programme.name}: {to_status}" + (f" — {note}" if note else ""),
        )
        publish("programme.status_changed", {"programme_id": str(programme.pk), "status": to_status,
                                             "group_id": str(programme.group_id)})
    return programme


def _assert_activation_ready(programme: Programme) -> None:
    participants = programme.participants.filter(status=Participation.Status.ACTIVE).count()
    if participants < 2:
        raise DomainError("A programme needs at least two active participants to start.", code="programme_too_small")
    if programme.type == ProgrammeType.ROTATIONAL:
        if not programme.contribution_amount_minor:
            raise DomainError("A rotational programme needs a fixed contribution amount.", code="programme_amount_missing")
        positions = programme.rotation_positions.count()
        if positions != participants:
            raise DomainError(
                "Every rotational participant needs a payout position before the programme starts.",
                code="rotation_incomplete",
                details={"participants": participants, "positions": positions},
            )


def _assert_closeable(programme: Programme) -> None:
    """Refuse to close a programme whose money is unaccounted for."""
    unsettled = programme.contributions.filter(
        status__in=[Contribution.Status.INITIATED, Contribution.Status.PENDING, Contribution.Status.PROCESSING]
    ).count()
    if unsettled:
        raise ConflictError(
            "Some contributions are still processing. Settle them before closing.",
            code="programme_has_pending_payments",
            details={"pending_count": unsettled},
        )
    pending_withdrawals = programme.withdrawals.filter(
        status__in=[
            WithdrawalRequest.Status.PENDING_APPROVAL,
            WithdrawalRequest.Status.APPROVED,
            WithdrawalRequest.Status.PROCESSING,
        ]
    ).count()
    if pending_withdrawals:
        raise ConflictError(
            "This programme has withdrawals in progress.", code="programme_has_pending_withdrawals"
        )
    pool = ledger.programme_pool(programme)
    remaining = ledger.balance_of(pool)
    if remaining != 0 and programme.type != ProgrammeType.ROTATIONAL:
        # Money left in a pooled programme must be explicitly withdrawn or
        # transferred — silently closing would strand it.
        raise FinancialSafetyError(
            "This programme still holds a balance. Withdraw or transfer it first.",
            code="programme_has_balance",
            details={"balance_minor": remaining, "currency": programme.currency},
        )


def add_participants(*, actor, programme: Programme, membership_ids: list, amount_minor: int | None = None) -> list:
    """Enrol members. The actor must be an officer, and the programme editable."""
    require_permission(actor, programme.group, GroupPermission.PROGRAMME_EDIT)
    if programme.status in {Programme.Status.COMPLETED, Programme.Status.CANCELLED, Programme.Status.CLOSED}:
        raise InvalidStateError("This programme is finished and cannot take new participants.", code="programme_closed")

    created = []
    with transaction.atomic():
        memberships = Membership.objects.filter(
            pk__in=membership_ids, group=programme.group, status=Membership.Status.ACTIVE
        ).select_related("user")
        if len(memberships) != len(set(membership_ids)):
            raise DomainError("One or more selected members are not active in this group.", code="member_not_active")
        for membership in memberships:
            participation, made = Participation.objects.get_or_create(
                programme=programme,
                membership=membership,
                defaults={
                    "amount_minor": amount_minor if amount_minor is not None else programme.contribution_amount_minor,
                },
            )
            if made:
                created.append(participation)
                publish(
                    "programme.participant_added",
                    {"programme_id": str(programme.pk), "user_id": str(membership.user_id),
                     "group_id": str(programme.group_id)},
                )
    AuditLog.record(action="programme.participants_added", actor=actor, group_id=programme.group_id,
                    target_type="programme", target_id=programme.pk,
                    summary=f"{len(created)} members joined {programme.name}")
    return created


def set_rotation_order(*, actor, programme: Programme, ordered_participation_ids: list) -> list:
    """Lock in who gets paid, and when.

    The order is fixed before activation; changing it afterwards would let a
    late joiner jump the queue, which is exactly the trust failure that ruins
    real esusu groups.
    """
    require_permission(actor, programme.group, GroupPermission.PROGRAMME_EDIT)
    if programme.type != ProgrammeType.ROTATIONAL:
        raise DomainError("Rotation order only applies to rotational programmes.", code="not_rotational")
    if programme.rotation_order_locked or programme.status == Programme.Status.ACTIVE:
        raise InvalidStateError("The rotation order is already locked.", code="rotation_locked")

    active = set(
        programme.participants.filter(status=Participation.Status.ACTIVE).values_list("pk", flat=True)
    )
    # Ids arrive as strings from JSON; compare UUID to UUID or a perfectly valid
    # order is rejected as a mismatch.
    ordered_ids = [uuid.UUID(str(pid)) for pid in ordered_participation_ids]
    if len(set(ordered_ids)) != len(ordered_ids):
        raise DomainError(
            "The same participant appears twice in the payout order.",
            code="rotation_order_duplicate",
        )
    if set(ordered_ids) != active:
        raise DomainError(
            "The order must include every active participant exactly once.",
            code="rotation_order_mismatch",
            details={"missing": [str(p) for p in active - set(ordered_ids)],
                     "unknown": [str(p) for p in set(ordered_ids) - active]},
        )

    with transaction.atomic():
        programme.rotation_positions.all().delete()
        RotationPosition.objects.bulk_create(
            [
                RotationPosition(programme=programme, participation_id=pid, position=index + 1)
                for index, pid in enumerate(ordered_ids)
            ]
        )
        programme.rotation_order_locked = True
        programme.save(update_fields=["rotation_order_locked", "updated_at"])
    AuditLog.record(action="programme.rotation_locked", actor=actor, group_id=programme.group_id,
                    target_type="programme", target_id=programme.pk, summary="Payout order locked")
    return list(programme.rotation_positions.order_by("position"))


# ---------------------------------------------------------------------------
# Obligations and cycles
# ---------------------------------------------------------------------------

def generate_obligations(*, programme: Programme, period_start: date, period_end: date,
                         cycle: RotationCycle | None = None) -> list:
    """Create this period's expected contributions. Idempotent per period."""
    participations = programme.participants.filter(status=Participation.Status.ACTIVE).select_related("membership")
    created = []
    for participation in participations:
        amount = participation.amount_minor or programme.contribution_amount_minor
        if not amount:
            continue
        obligation, made = Obligation.objects.get_or_create(
            programme=programme,
            participation=participation,
            due_date=period_end,
            defaults={"amount_minor": amount, "cycle": cycle},
        )
        if made:
            created.append(obligation)
    return created


def _ensure_first_cycle(programme: Programme) -> RotationCycle:
    if programme.cycles.exists():
        return programme.cycles.order_by("sequence").first()
    interval = programme.custom_interval_days or FREQUENCY_DAYS.get(programme.frequency, 30)
    start = max(programme.start_date, timezone.localdate())
    end = start + timedelta(days=interval)
    beneficiary = (
        programme.rotation_positions.select_related("participation").order_by("position").first()
    )
    cycle = RotationCycle.objects.create(
        programme=programme,
        sequence=1,
        beneficiary=beneficiary.participation if beneficiary else None,
        period_start=start,
        period_end=end,
        expected_total_minor=programme.expected_total_minor(),
        payout_amount_minor=programme.expected_total_minor(),
        status=RotationCycle.Status.COLLECTING,
    )
    generate_obligations(programme=programme, period_start=start, period_end=end, cycle=cycle)
    return cycle


def _ensure_first_period(programme: Programme) -> list:
    """Open the first collection period for a programme with no rotation.

    Idempotent: `generate_obligations` is keyed on (programme, participation,
    due date), so re-activating a paused programme does not double-bill anyone.
    """
    interval = programme.custom_interval_days or FREQUENCY_DAYS.get(programme.frequency, 30)
    start = max(programme.start_date, timezone.localdate())
    end = start + timedelta(days=interval)
    return generate_obligations(programme=programme, period_start=start, period_end=end)


def record_offline_contribution(
    *, actor, programme: Programme, participation: Participation, amount_minor: int, note: str = ""
) -> Contribution:
    """An officer records cash received (a market association collects in person).

    This still posts a real ledger transaction — the money is accounted for the
    same way as an online payment — but it is marked with its source so audits
    can distinguish it, and it requires the treasurer permission.
    """
    require_permission(actor, programme.group, GroupPermission.FINANCE_POST)
    if amount_minor <= 0:
        raise DomainError("Enter an amount greater than zero.", code="amount_invalid")
    if programme.status not in {Programme.Status.ACTIVE, Programme.Status.PAUSED}:
        raise InvalidStateError("This programme is not collecting.", code="programme_not_collecting")

    with transaction.atomic():
        obligation = (
            Obligation.objects.select_for_update()
            .filter(programme=programme, participation=participation, status__in=[
                Obligation.Status.PENDING, Obligation.Status.PARTIALLY_PAID, Obligation.Status.OVERDUE
            ])
            .order_by("due_date")
            .first()
        )
        contribution = Contribution.objects.create(
            programme=programme,
            obligation=obligation,
            participation=participation,
            payer=actor if participation.membership.user_id == getattr(actor, "pk", None) else None,
            amount_minor=amount_minor,
            currency=programme.currency,
            source=Contribution.Source.OFFLINE,
            reference=new_reference("CON"),
        )
        settle_contribution(contribution, actor=actor)
    return contribution


def settle_contribution(contribution: Contribution, *, actor=None, provider_reference: str = "") -> Contribution:
    """Mark a contribution paid and post it to the ledger. Idempotent.

    The ledger posting is the moment money becomes real. Everything before it is
    intent; everything after reads from it.
    """
    with transaction.atomic():
        contribution = (
            Contribution.objects.select_for_update(of=("self",))
            .select_related("programme", "participation")
            .get(pk=contribution.pk)
        )
        if contribution.counts_towards_balance:
            return contribution  # already settled: a retried webhook is not a second payment
        if contribution.status in {Contribution.Status.REVERSED, Contribution.Status.REFUNDED}:
            raise ConflictError("This contribution was reversed.", code="contribution_reversed")

        programme = contribution.programme
        pool = ledger.programme_pool(programme)
        liability = ledger.programme_liability(programme)
        settlement = ledger.provider_settlement(contribution.currency)
        payable = ledger.provider_payable(contribution.currency)

        # Provider money arrives as an asset with a matching liability (we
        # owe the programme), then moves into the programme's ring-fenced pool.
        txn = ledger.post(
            kind=ledger.JournalTransaction.Kind.CONTRIBUTION,
            currency=contribution.currency,
            description=f"Contribution {contribution.reference}",
            source_type="contribution",
            source_id=str(contribution.pk),
            idempotency_key=f"contribution:{contribution.pk}",
            external_reference=provider_reference,
            posted_by=actor,
            legs=[
                ledger.Leg(account=settlement, amount_minor=contribution.amount_minor, memo="Received"),
                ledger.Leg(account=payable, amount_minor=-contribution.amount_minor, memo="Held for programme"),
                ledger.Leg(account=pool, amount_minor=contribution.amount_minor, memo="Programme pool"),
                ledger.Leg(account=liability, amount_minor=-contribution.amount_minor, memo="Owed to members"),
            ],
        )

        contribution.status = Contribution.Status.CONFIRMED
        contribution.confirmed_at = timezone.now()
        contribution.ledger_reference = txn.reference
        contribution.save(update_fields=["status", "confirmed_at", "ledger_reference", "updated_at"])

        _apply_to_obligation(contribution)
        if contribution.obligation and contribution.obligation.cycle_id:
            _refresh_cycle_collected(contribution.obligation.cycle_id)

        publish(
            "contribution.succeeded",
            {
                "contribution_id": str(contribution.pk),
                "programme_id": str(programme.pk),
                "group_id": str(programme.group_id),
                "amount_minor": contribution.amount_minor,
                "currency": contribution.currency,
                "payer_id": str(contribution.participation.membership.user_id),
            },
        )

    AuditLog.record(action="contribution.settled", actor=actor, group_id=contribution.programme.group_id,
                    target_type="contribution", target_id=contribution.pk,
                    summary=f"{contribution.amount_minor} {contribution.currency} confirmed")
    return contribution


def _apply_to_obligation(contribution: Contribution) -> None:
    """Credit a payment against the member's oldest outstanding obligation(s).

    Overpayment spills onto the next obligation rather than disappearing; any
    remainder stays as the member's holding, which is a real balance they own.
    """
    if not contribution.obligation_id:
        return
    remaining = contribution.amount_minor
    obligations = (
        Obligation.objects.select_for_update()
        .filter(participation=contribution.participation, status__in=[
            Obligation.Status.PENDING, Obligation.Status.PARTIALLY_PAID, Obligation.Status.OVERDUE
        ])
        .order_by("due_date")
    )
    for obligation in obligations:
        if remaining <= 0:
            break
        applied = min(remaining, obligation.outstanding_minor)
        obligation.paid_minor += applied
        remaining -= applied
        if obligation.paid_minor >= obligation.amount_minor:
            obligation.status = Obligation.Status.SETTLED
        else:
            obligation.status = Obligation.Status.PARTIALLY_PAID
        obligation.save(update_fields=["paid_minor", "status"])

    if remaining > 0:
        membership = contribution.participation.membership
        holding = ledger.member_holding(contribution.programme.group, membership.pk, contribution.currency)
        # The cash stays physically in the programme's pool; what changes is
        # who it is owed to. So this is a reclassification between two
        # liability accounts, not a movement of assets. Posting it against the
        # pool would have inflated the group's assets by money it never
        # received.
        liability = ledger.programme_liability(contribution.programme)
        with transaction.atomic():
            ledger.post(
                kind=ledger.JournalTransaction.Kind.TRANSFER,
                currency=contribution.currency,
                description="Overpayment earmarked to member holding",
                source_type="contribution",
                source_id=str(contribution.pk),
                idempotency_key=f"overpay:{contribution.pk}",
                legs=[
                    ledger.Leg(account=liability, amount_minor=remaining, memo="Release from programme funds"),
                    ledger.Leg(account=holding, amount_minor=-remaining, memo="Owed to member"),
                ],
            )


def _refresh_cycle_collected(cycle_id) -> RotationCycle:
    cycle = RotationCycle.objects.select_for_update().get(pk=cycle_id)
    collected = (
        Contribution.objects.filter(
            obligation__cycle=cycle, status__in=[Contribution.Status.CONFIRMED, Contribution.Status.SETTLED]
        ).aggregate(total=Sum("amount_minor"))["total"]
        or 0
    )
    cycle.collected_total_minor = collected
    if cycle.status in {RotationCycle.Status.COLLECTING, RotationCycle.Status.SHORTFALL}:
        cycle.status = (
            RotationCycle.Status.READY_FOR_PAYOUT
            if collected >= cycle.payout_amount_minor and cycle.payout_amount_minor > 0
            else RotationCycle.Status.COLLECTING
        )
    cycle.save(update_fields=["collected_total_minor", "status"])
    return cycle


def open_next_cycle(*, actor, programme: Programme) -> RotationCycle:
    """Close the current cycle and schedule the next turn in the order."""
    require_permission(actor, programme.group, GroupPermission.PROGRAMME_EDIT)
    if programme.type != ProgrammeType.ROTATIONAL:
        raise DomainError("Only rotational programmes have cycles.", code="not_rotational")

    with transaction.atomic():
        current = programme.cycles.select_for_update().order_by("-sequence").first()
        if current and current.status not in {RotationCycle.Status.PAID, RotationCycle.Status.SHORTFALL,
                                             RotationCycle.Status.CANCELLED}:
            raise ConflictError("Finish the current cycle before starting the next.", code="cycle_not_finished")

        next_sequence = (current.sequence + 1) if current else 1
        positions = list(programme.rotation_positions.select_related("participation").order_by("position"))
        if not positions:
            raise DomainError("This programme has no rotation order.", code="rotation_missing")
        beneficiary = positions[(next_sequence - 1) % len(positions)]
        someone_has_been_paid = RotationCycle.objects.filter(programme=programme, status=RotationCycle.Status.PAID).count()
        if someone_has_been_paid >= len(positions):
            raise DomainError("Every participant has been paid. Complete the programme.", code="rotation_finished")

        interval = programme.custom_interval_days or FREQUENCY_DAYS.get(programme.frequency, 30)
        start = current.period_end if current else max(programme.start_date, timezone.localdate())
        end = start + timedelta(days=interval)
        cycle = RotationCycle.objects.create(
            programme=programme,
            sequence=next_sequence,
            beneficiary=beneficiary.participation,
            period_start=start,
            period_end=end,
            expected_total_minor=programme.expected_total_minor(),
            payout_amount_minor=programme.expected_total_minor(),
            status=RotationCycle.Status.COLLECTING,
        )
        generate_obligations(programme=programme, period_start=start, period_end=end, cycle=cycle)
        publish("rotation.cycle_opened", {"programme_id": str(programme.pk), "cycle_id": str(cycle.pk),
                                         "sequence": next_sequence})
    AuditLog.record(action="rotation.cycle_opened", actor=actor, group_id=programme.group_id,
                    target_type="cycle", target_id=cycle.pk, summary=f"Cycle {next_sequence} opened")
    return cycle


def approve_payout(*, actor, cycle: RotationCycle) -> RotationCycle:
    """Second signature on a rotation payout.

    Refused when the money is not actually there, and refused when the approver
    is the beneficiary — a payout to yourself needs a different officer.
    """
    require_permission(actor, cycle.programme.group, GroupPermission.PAYOUT_APPROVE)

    with transaction.atomic():
        cycle = (
            RotationCycle.objects.select_for_update(of=("self",))
            .select_related("programme", "beneficiary")
            .get(pk=cycle.pk)
        )

        if cycle.status == RotationCycle.Status.READY_FOR_PAYOUT:
            pass
        elif cycle.status == RotationCycle.Status.PAYOUT_PENDING_APPROVAL:
            # Already approved. Pressing again is a client retry, not a second
            # signature: return the same state instead of an error the UI would
            # have to explain away.
            return cycle
        else:
            raise InvalidStateError(
                "This cycle is not ready for payout.",
                code="cycle_not_ready",
                details={"status": cycle.status, "collected_minor": cycle.collected_total_minor,
                         "required_minor": cycle.payout_amount_minor},
            )

        if cycle.collected_total_minor < cycle.payout_amount_minor:
            # The explicit refusal the whole feature exists for.
            raise FinancialSafetyError(
                "Only what has actually been collected can be paid out.",
                code="payout_underfunded",
                details={
                    "collected_minor": cycle.collected_total_minor,
                    "payout_minor": cycle.payout_amount_minor,
                    "shortfall_minor": cycle.shortfall_minor,
                    "currency": cycle.programme.currency,
                },
            )

        beneficiary_membership = cycle.beneficiary.membership if cycle.beneficiary else None
        approver_membership = require_membership(actor, cycle.programme.group)
        if beneficiary_membership and beneficiary_membership.pk == approver_membership.pk:
            raise PermissionDeniedError(
                "You are the beneficiary of this payout, so another officer must approve it.",
                code="self_approval_blocked",
            )

        cycle.status = RotationCycle.Status.PAYOUT_PENDING_APPROVAL
        cycle.payout_approved_by = actor
        cycle.payout_approved_at = timezone.now()
        cycle.save(update_fields=["status", "payout_approved_by", "payout_approved_at", "updated_at"])

    AuditLog.record(action="rotation.payout_approved", actor=actor, group_id=cycle.programme.group_id,
                    target_type="cycle", target_id=cycle.pk,
                    summary=f"Payout of {cycle.payout_amount_minor} approved for cycle {cycle.sequence}")
    return cycle


def execute_payout(*, actor, cycle: RotationCycle) -> RotationCycle:
    """Post the payout once approved. Debits the pool, credits the beneficiary."""
    require_permission(actor, cycle.programme.group, GroupPermission.FINANCE_POST)

    with transaction.atomic():
        cycle = (
            RotationCycle.objects.select_for_update(of=("self",))
            .select_related("programme", "beneficiary")
            .get(pk=cycle.pk)
        )
        if cycle.status == RotationCycle.Status.PAID:
            return cycle
        if cycle.status != RotationCycle.Status.PAYOUT_PENDING_APPROVAL:
            raise InvalidStateError("This payout has not been approved.", code="payout_not_approved")
        if not cycle.beneficiary:
            raise DomainError("This cycle has no beneficiary.", code="beneficiary_missing")

        # Separation of duties holds at execution too. Without this an officer
        # who both approves and executes is a single point of failure for the
        # group's whole pot — the exact thing two signatures exist to prevent.
        if cycle.payout_approved_by_id and cycle.payout_approved_by_id == getattr(actor, "pk", None):
            raise PermissionDeniedError(
                "You approved this payout, so a different officer must execute it.",
                code="approver_cannot_execute",
            )
        if cycle.beneficiary.membership.user_id == getattr(actor, "pk", None):
            raise PermissionDeniedError(
                "You are the beneficiary of this payout and cannot execute it yourself.",
                code="self_approval_blocked",
            )

        programme = cycle.programme
        pool = ledger.programme_pool(programme)
        liability = ledger.programme_liability(programme)
        settlement = ledger.provider_settlement(programme.currency)
        payable = ledger.provider_payable(programme.currency)

        available = ledger.available_of(ledger.lock_account(pool.pk))
        if available < cycle.payout_amount_minor:
            raise FinancialSafetyError(
                "The programme pool does not hold enough for this payout.",
                code="pool_underfunded",
                details={"available_minor": available, "required_minor": cycle.payout_amount_minor},
            )

        txn = ledger.post(
            kind=ledger.JournalTransaction.Kind.PAYOUT,
            currency=programme.currency,
            description=f"Rotation payout, cycle {cycle.sequence}",
            source_type="rotation_cycle",
            source_id=str(cycle.pk),
            idempotency_key=f"payout:{cycle.pk}",
            posted_by=actor,
            # The money leaves the programme for good. An earlier version
            # credited the pool back on its third leg and debited the
            # beneficiary's holding on its fourth, so the pool never went down
            # and `paid` cycles left the books unchanged. The debit belongs to
            # the account that actually loses the money.
            legs=[
                ledger.Leg(account=pool, amount_minor=-cycle.payout_amount_minor, memo="Pool out"),
                ledger.Leg(account=liability, amount_minor=cycle.payout_amount_minor, memo="Member funds out"),
                ledger.Leg(account=payable, amount_minor=-cycle.payout_amount_minor, memo="Payable to beneficiary"),
                ledger.Leg(account=settlement, amount_minor=cycle.payout_amount_minor, memo="Held for payout"),
            ],
        )

        cycle.status = RotationCycle.Status.PAID
        cycle.paid_at = timezone.now()
        cycle.ledger_reference = txn.reference
        cycle.save(update_fields=["status", "paid_at", "ledger_reference", "updated_at"])
        publish("rotation.payout_paid", {
            "programme_id": str(programme.pk), "cycle_id": str(cycle.pk), "group_id": str(programme.group_id),
            "beneficiary_user_id": str(cycle.beneficiary.membership.user_id),
            "amount_minor": cycle.payout_amount_minor, "currency": programme.currency,
        })

    AuditLog.record(action="rotation.payout_executed", actor=actor, group_id=cycle.programme.group_id,
                    target_type="cycle", target_id=cycle.pk, summary=f"Payout posted {cycle.ledger_reference}")
    return cycle


def mark_missed_obligations(*, programme: Programme, as_of: date | None = None) -> int:
    """Flag overdue obligations. No money moves; members are told, not punished."""
    as_of = as_of or timezone.localdate()
    grace_end = as_of - timedelta(days=programme.grace_period_days)
    stale = programme.obligations.filter(
        status__in=[Obligation.Status.PENDING, Obligation.Status.PARTIALLY_PAID], due_date__lt=grace_end
    )
    count = 0
    for obligation in stale:
        obligation.status = Obligation.Status.OVERDUE
        obligation.save(update_fields=["status"])
        publish("obligation.overdue", {
            "programme_id": str(programme.pk), "obligation_id": str(obligation.pk),
            "group_id": str(programme.group_id),
            "user_id": str(obligation.participation.membership.user_id),
            "outstanding_minor": obligation.outstanding_minor, "currency": programme.currency,
            "due_date": str(obligation.due_date),
        })
        count += 1
    return count


def progress_percent(programme: Programme) -> float:
    """Display metric. Derived from verified money only, never from a schedule."""
    if not programme.target_amount_minor:
        return 0.0
    collected = ledger.balance_of(ledger.programme_pool(programme))
    return round(min(100.0, max(0.0, collected / programme.target_amount_minor * 100)), 1)


# ---------------------------------------------------------------------------
# Withdrawals
# ---------------------------------------------------------------------------

def request_withdrawal(*, actor, programme: Programme, amount_minor: int, reason: str,
                       beneficiary_participation_id=None, note: str = "") -> WithdrawalRequest:
    """Officer asks for money to leave a programme.

    Nothing moves yet: a reservation is *not* taken here, because an unapproved
    request should not freeze funds other members may need. Availability is
    checked now for a useful error, and checked again under lock at execution.
    """
    require_permission(actor, programme.group, GroupPermission.WITHDRAWAL_REQUEST)
    if amount_minor <= 0:
        raise DomainError("Enter an amount greater than zero.", code="amount_invalid")

    pool = ledger.programme_pool(programme)
    available = ledger.available_of(pool)
    if available < amount_minor:
        from apps.common.exceptions import InsufficientFundsError

        raise InsufficientFundsError(
            details={"available_minor": available, "required_minor": amount_minor,
                     "currency": programme.currency}
        )

    beneficiary = None
    if beneficiary_participation_id:
        beneficiary = programme.participants.filter(pk=beneficiary_participation_id).first()
        if not beneficiary:
            raise NotFoundError("That member is not in this programme.", code="participant_not_found")

    withdrawal = WithdrawalRequest.objects.create(
        programme=programme,
        beneficiary=beneficiary,
        amount_minor=amount_minor,
        currency=programme.currency,
        reason=reason,
        note=note[:500],
        status=WithdrawalRequest.Status.PENDING_APPROVAL,
        requested_by=actor,
    )
    AuditLog.record(action="withdrawal.requested", actor=actor, group_id=programme.group_id,
                    target_type="withdrawal", target_id=withdrawal.pk,
                    summary=f"{amount_minor} {programme.currency} requested")
    return withdrawal


def decide_withdrawal(*, actor, withdrawal: WithdrawalRequest, approve: bool, comment: str = "") -> WithdrawalRequest:
    """One officer's decision on a request.

    Approving your own request, or the request of a programme you benefit from,
    is refused. This is the check that makes "treasurer" a job rather than a key
    to the safe.
    """
    programme = withdrawal.programme
    require_permission(actor, programme.group, GroupPermission.WITHDRAWAL_APPROVE)

    with transaction.atomic():
        withdrawal = WithdrawalRequest.objects.select_for_update().get(pk=withdrawal.pk)
        if withdrawal.status != WithdrawalRequest.Status.PENDING_APPROVAL:
            raise InvalidStateError(
                "This request is not awaiting approval.",
                code="withdrawal_not_pending",
                details={"status": withdrawal.status},
            )

        actor_membership = require_membership(actor, programme.group)

        # Separation of duties, enforced here rather than assumed from roles.
        #
        # A founder or owner holds both `withdrawal.request` and
        # `withdrawal.approve`, so without this check one person could request
        # money to someone else and sign it off alone. The role table is not
        # enough: it is a permission table, and this is a conflict-of-interest
        # rule that has to be applied to the specific request.
        if withdrawal.requested_by_id == actor.pk:
            raise PermissionDeniedError(
                "You requested this payout, so another officer must approve it.",
                code="self_approval_blocked",
                details={"reason": "requester_cannot_approve"},
            )
        if withdrawal.beneficiary and withdrawal.beneficiary.membership_id == actor_membership.pk:
            raise PermissionDeniedError(
                "This withdrawal is for you, so another officer must approve it.",
                code="self_approval_blocked",
                details={"reason": "beneficiary_cannot_approve"},
            )

        WithdrawalApproval.objects.update_or_create(
            withdrawal=withdrawal, approver=actor,
            defaults={"approved": approve, "comment": comment[:400]},
        )

        if not approve:
            withdrawal.status = WithdrawalRequest.Status.REJECTED
            withdrawal.save(update_fields=["status", "updated_at"])
        else:
            approvals = withdrawal.approval_records.filter(approved=True).count()
            required = 2 if programme.requires_dual_approval else 1
            if approvals >= required:
                withdrawal.status = WithdrawalRequest.Status.APPROVED
                withdrawal.save(update_fields=["status", "updated_at"])

    AuditLog.record(action="withdrawal.decision", actor=actor, group_id=programme.group_id,
                    target_type="withdrawal", target_id=withdrawal.pk,
                    summary=f"{'approved' if approve else 'rejected'} ({withdrawal.status})")
    if withdrawal.status == WithdrawalRequest.Status.APPROVED:
        publish("withdrawal.approved", {"withdrawal_id": str(withdrawal.pk), "group_id": str(programme.group_id),
                                        "amount_minor": withdrawal.amount_minor, "currency": withdrawal.currency})
    return withdrawal


def execute_withdrawal(*, actor, withdrawal: WithdrawalRequest, account_number: str = "", bank_code: str = "",
                       account_name: str = "") -> WithdrawalRequest:
    """Post an approved withdrawal and hand it to the payment provider.

    The order matters: reserve under lock, post the ledger movement, then call
    the provider. If the provider call fails the money is already accounted for
    as moving out, and the disbursement failure is recorded against it — which
    is recoverable. The reverse order risks paying twice on a retry.
    """
    programme = withdrawal.programme
    require_permission(actor, programme.group, GroupPermission.WITHDRAWAL_EXECUTE)

    with transaction.atomic():
        withdrawal = (
            WithdrawalRequest.objects.select_for_update(of=("self",))
            .select_related("programme", "beneficiary__membership")
            .get(pk=withdrawal.pk)
        )
        if withdrawal.status == WithdrawalRequest.Status.PAID:
            return withdrawal
        if withdrawal.status != WithdrawalRequest.Status.APPROVED:
            raise InvalidStateError(
                "This withdrawal has not been approved.",
                code="withdrawal_not_approved",
                details={"status": withdrawal.status},
            )

        # Rotation payouts already refuse this; withdrawals did not. Approving
        # and paying are the two halves of one act, and one officer holding both
        # halves is indistinguishable from one officer holding all of it.
        if withdrawal.approval_records.filter(approver=actor, approved=True).exists():
            raise PermissionDeniedError(
                "You approved this payout, so a different officer must send it.",
                code="approver_cannot_execute",
                details={"reason": "approver_cannot_execute"},
            )

        pool = ledger.programme_pool(programme)
        reservation = ledger.reserve(
            pool, withdrawal.amount_minor, reason="withdrawal",
            source_type="withdrawal", source_id=str(withdrawal.pk), ttl_seconds=900,
        )
        withdrawal.reservation = reservation
        withdrawal.save(update_fields=["reservation", "updated_at"])

        liability = ledger.programme_liability(programme)
        settlement = ledger.provider_settlement(withdrawal.currency)
        payable = ledger.provider_payable(withdrawal.currency)

        txn = ledger.post(
            kind=ledger.JournalTransaction.Kind.WITHDRAWAL,
            currency=withdrawal.currency,
            description=f"Withdrawal {withdrawal.pk}",
            source_type="withdrawal",
            source_id=str(withdrawal.pk),
            idempotency_key=f"withdrawal:{withdrawal.pk}",
            posted_by=actor,
            legs=[
                ledger.Leg(account=pool, amount_minor=-withdrawal.amount_minor, memo="Pool out"),
                ledger.Leg(account=liability, amount_minor=withdrawal.amount_minor, memo="Member funds out"),
                ledger.Leg(account=payable, amount_minor=-withdrawal.amount_minor, memo="Payable to member"),
                ledger.Leg(account=settlement, amount_minor=withdrawal.amount_minor, memo="Held for payout"),
            ],
        )
        ledger.capture_reservation(reservation)
        withdrawal.ledger_reference = txn.reference
        withdrawal.status = WithdrawalRequest.Status.PROCESSING
        withdrawal.save(update_fields=["ledger_reference", "status", "updated_at"])

    # Provider call happens outside the transaction: a slow partner must not
    # hold a row lock, and its failure is recorded rather than rolled back.
    if account_number:
        from apps.payments.services import create_disbursement, execute_disbursement

        disbursement = create_disbursement(
            user=withdrawal.requested_by,
            amount_minor=withdrawal.amount_minor,
            currency=withdrawal.currency,
            account_number=account_number,
            account_name=account_name,
            bank_code=bank_code,
        )
        execute_disbursement(disbursement, actor=actor)
        withdrawal.disbursement = disbursement
        withdrawal.status = (
            WithdrawalRequest.Status.PAID
            if disbursement.status == "queued"
            else WithdrawalRequest.Status.FAILED
        )
        withdrawal.executed_at = timezone.now()
        withdrawal.save(update_fields=["disbursement", "status", "executed_at", "updated_at"])
    else:
        # No destination supplied: recorded as paid out of the ledger into the
        # member's holding, which is the honest state until a bank is given.
        withdrawal.status = WithdrawalRequest.Status.PAID
        withdrawal.executed_at = timezone.now()
        withdrawal.save(update_fields=["status", "executed_at", "updated_at"])

    publish("withdrawal.executed", {
        "withdrawal_id": str(withdrawal.pk), "group_id": str(programme.group_id),
        "requested_by": str(withdrawal.requested_by_id), "amount_minor": withdrawal.amount_minor,
        "currency": withdrawal.currency, "status": withdrawal.status,
    })
    return withdrawal


def record_donation(*, intent, campaign_id) -> None:
    """A confirmed donation is credited to the campaign's programme."""
    campaign = FundraisingCampaign.objects.filter(pk=campaign_id).first()
    if not campaign:
        return
    FundraisingCampaign.objects.filter(pk=campaign.pk).update(
        collected_minor=F("collected_minor") + intent.amount_minor
    )
    publish("campaign.donation_received", {
        "campaign_id": str(campaign.pk), "group_id": str(campaign.group_id),
        "amount_minor": intent.amount_minor, "currency": intent.currency,
    })
