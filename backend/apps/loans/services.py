"""Lending business logic, with the regulatory guard in code rather than prose."""

from __future__ import annotations

import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.common.audit import AuditLog
from apps.common.exceptions import ConflictError, DomainError, FinancialSafetyError, InvalidStateError, PermissionDeniedError
from apps.common.outbox import publish
from apps.groups.models import Permission as GroupPermission
from apps.groups.permissions import require_membership, require_permission
from apps.ledger import services as ledger

from .models import Guarantor, Loan, LoanApplication, LoanProduct, RepaymentSchedule, Repayment

logger = logging.getLogger("kolo.audit")


def lending_enabled() -> bool:
    """Lending is off unless explicitly enabled for this deployment."""
    return bool(settings.KOLO.get("LENDING_ENABLED", False))


def apply_for_loan(*, actor, product: LoanProduct, amount_minor: int, term_months: int, purpose: str,
                   guarantor_membership_ids: list[str] | None = None) -> LoanApplication:
    membership = require_membership(actor, product.group)
    if membership.status != "active":
        raise PermissionDeniedError("Only active members can apply.", code="not_active_member")
    if not product.is_active:
        raise InvalidStateError("This loan product is not open.", code="product_inactive")
    if not (product.min_amount_minor <= amount_minor <= product.max_amount_minor):
        raise DomainError(
            "That amount is outside this product's range.",
            code="amount_out_of_range",
            details={"min_minor": product.min_amount_minor, "max_minor": product.max_amount_minor},
        )
    if not (product.term_months_min <= term_months <= product.term_months_max):
        raise DomainError("That term is not available for this product.", code="term_out_of_range")

    if product.min_membership_days:
        joined = membership.joined_at or membership.created_at
        if (timezone.now() - joined) < timedelta(days=product.min_membership_days):
            raise DomainError(
                "You need a longer membership history for this product.",
                code="membership_too_new",
                details={"required_days": product.min_membership_days},
            )

    with transaction.atomic():
        application = LoanApplication.objects.create(
            product=product,
            borrower=membership,
            amount_minor=amount_minor,
            currency=product.currency,
            term_months=term_months,
            purpose=purpose[:300],
            status=LoanApplication.Status.SUBMITTED,
            submitted_at=timezone.now(),
        )
        for membership_id in guarantor_membership_ids or []:
            Guarantor.objects.get_or_create(application=application, membership_id=membership_id)

    AuditLog.record(action="loan.applied", actor=actor, group_id=product.group_id,
                    target_type="loan_application", target_id=application.pk,
                    summary=f"{amount_minor} {product.currency} requested")
    return application


def decide_application(*, actor, application: LoanApplication, approve: bool, note: str = "") -> LoanApplication:
    require_permission(actor, application.product.group, GroupPermission.LOAN_APPROVE)
    with transaction.atomic():
        application = LoanApplication.objects.select_for_update().get(pk=application.pk)
        if application.status not in {LoanApplication.Status.SUBMITTED, LoanApplication.Status.UNDER_REVIEW,
                                      LoanApplication.Status.AWAITING_VOTE}:
            raise InvalidStateError("This application has already been decided.", code="application_decided")

        # Separation of duties: nobody approves their own loan.
        approver_membership = require_membership(actor, application.product.group)
        if approver_membership.pk == application.borrower_id:
            raise PermissionDeniedError("You cannot approve your own loan.", code="self_approval_blocked")

        required = application.product.requires_guarantors
        if approve and required:
            accepted = application.guarantors.filter(status=Guarantor.Status.ACCEPTED).count()
            if accepted < required:
                raise DomainError(
                    "This loan still needs guarantors to accept.",
                    code="guarantors_pending",
                    details={"required": required, "accepted": accepted},
                )

        application.status = LoanApplication.Status.APPROVED if approve else LoanApplication.Status.REJECTED
        application.decided_at = timezone.now()
        application.decided_by = actor
        application.decision_note = note[:500]
        application.save()

        if approve:
            _create_loan(application)

    AuditLog.record(action="loan.decision", actor=actor, group_id=application.product.group_id,
                    target_type="loan_application", target_id=application.pk,
                    summary=("approved" if approve else "rejected") + (f": {note}" if note else ""))
    publish("loan.decision", {"application_id": str(application.pk),
                              "borrower_user_id": str(application.borrower.user_id),
                              "approved": approve, "group_id": str(application.product.group_id)})
    return application


def _create_loan(application: LoanApplication) -> Loan:
    product = application.product
    principal = application.amount_minor
    interest = principal * product.interest_bps * application.term_months // (10000 * 12)
    total = principal + interest
    loan = Loan.objects.create(
        application=application,
        reference=f"LN-{timezone.now():%Y%m%d}-{secrets.token_hex(3).upper()}",
        group=product.group,
        borrower=application.borrower,
        principal_minor=principal,
        currency=application.currency,
        interest_bps=product.interest_bps,
        term_months=application.term_months,
        total_repayable_minor=total,
        outstanding_minor=total,
        due_date=timezone.localdate() + timedelta(days=30 * application.term_months),
    )

    installment_count = application.term_months
    base = total // installment_count
    remainder = total - base * installment_count

    # Principal is allocated the same way the total is: floor per installment,
    # with the leftover minor units on the final one. Without this a 3-month
    # loan of 100,000 would allocate 99,999 of principal and quietly reclassify
    # one unit as interest.
    principal_base = principal // installment_count
    principal_remainder = principal - principal_base * installment_count

    for index in range(installment_count):
        is_last = index == installment_count - 1
        amount = base + (remainder if is_last else 0)
        principal_part = principal_base + (principal_remainder if is_last else 0)
        RepaymentSchedule.objects.create(
            loan=loan,
            installment_no=index + 1,
            due_date=loan.due_date - timedelta(days=30 * (installment_count - index - 1)),
            amount_minor=amount,
            principal_minor=principal_part,
            interest_minor=amount - principal_part,
        )
    return loan


def disburse_loan(*, actor, loan: Loan) -> Loan:
    """Pay out an approved loan from the group's cooperative pool.

    Refused in any environment where lending has not been explicitly enabled,
    and refused when the pool cannot cover it — no loan is created from thin air.
    """
    if not lending_enabled():
        raise DomainError(
            "Lending is not enabled for this deployment. A licensed arrangement is required first.",
            code="lending_disabled",
        )
    require_permission(actor, loan.group, GroupPermission.LOAN_DISBURSE)

    with transaction.atomic():
        loan = (
            Loan.objects.select_for_update(of=("self",))
            .select_related("borrower", "group")
            .get(pk=loan.pk)
        )
        if loan.status == Loan.Status.ACTIVE:
            return loan
        if loan.status != Loan.Status.PENDING_DISBURSEMENT:
            raise InvalidStateError("This loan is not awaiting disbursement.", code="loan_not_disbursable")

        pool = ledger.group_pool(loan.group)
        available = ledger.available_of(ledger.lock_account(pool.pk))
        if available < loan.principal_minor:
            raise FinancialSafetyError(
                "The cooperative pool does not hold enough to fund this loan.",
                code="pool_underfunded",
                details={"available_minor": available, "required_minor": loan.principal_minor},
            )

        # Cash leaves the pool and becomes a receivable: the group is owed the
        # money, so its net position is unchanged the moment it lends.
        receivable = ledger.group_loan_receivable(loan.group)
        txn = ledger.post(
            kind=ledger.JournalTransaction.Kind.LOAN_DISBURSEMENT,
            currency=loan.currency,
            description=f"Loan {loan.reference}",
            source_type="loan",
            source_id=str(loan.pk),
            idempotency_key=f"loan-disburse:{loan.pk}",
            posted_by=actor,
            legs=[
                ledger.Leg(account=receivable, amount_minor=loan.principal_minor, memo="Amount owed to group"),
                ledger.Leg(account=pool, amount_minor=-loan.principal_minor, memo="Paid out from pool"),
            ],
        )
        loan.status = Loan.Status.ACTIVE
        loan.disbursed_at = timezone.now()
        loan.ledger_reference = txn.reference
        loan.save(update_fields=["status", "disbursed_at", "ledger_reference", "updated_at"])
        loan.application.status = LoanApplication.Status.DISBURSED
        loan.application.save(update_fields=["status"])

    AuditLog.record(action="loan.disbursed", actor=actor, group_id=loan.group_id, severity=AuditLog.Severity.NOTICE,
                    target_type="loan", target_id=loan.pk, summary=f"{loan.principal_minor} {loan.currency} disbursed")
    return loan


def create_repayment(*, actor, loan: Loan, amount_minor: int) -> Repayment:
    # Trust the database, not the caller's copy: a client may hold an instance
    # read before the loan was disbursed, and refusing a valid repayment because
    # of a stale object would look like the app is broken.
    loan = Loan.objects.select_related("group", "borrower").get(pk=loan.pk)
    membership = require_membership(actor, loan.group)
    if membership.pk != loan.borrower_id:
        raise PermissionDeniedError("Only the borrower can repay this loan.", code="not_borrower")
    if loan.status not in {Loan.Status.ACTIVE, Loan.Status.OVERDUE}:
        raise InvalidStateError("This loan is not open for repayment.", code="loan_not_repayable")
    if amount_minor <= 0:
        raise DomainError("Enter an amount greater than zero.", code="amount_invalid")
    if amount_minor > loan.outstanding_minor:
        raise DomainError(
            "That is more than you owe.",
            code="amount_exceeds_outstanding",
            details={"outstanding_minor": loan.outstanding_minor},
        )
    return Repayment.objects.create(
        loan=loan, amount_minor=amount_minor, currency=loan.currency,
        reference=f"RPY-{timezone.now():%Y%m%d}-{secrets.token_hex(3).upper()}",
    )


def settle_repayment(repayment: Repayment, *, actor=None, provider_reference: str = "") -> Repayment:
    with transaction.atomic():
        repayment = (
            Repayment.objects.select_for_update(of=("self",))
            .select_related("loan", "loan__group")
            .get(pk=repayment.pk)
        )
        if repayment.status == Repayment.Status.SETTLED:
            return repayment
        loan = Loan.objects.select_for_update().get(pk=repayment.loan_id)

        pool = ledger.group_pool(loan.group)
        receivable = ledger.group_loan_receivable(loan.group)

        # Split the payment the way the schedule will apply it: principal
        # reduces the receivable, interest is income. Booking the whole payment
        # against the receivable would quietly write off the interest owed to
        # the group — and interest income is the only reason a pool lends at all.
        principal_part, interest_part = _split_repayment(loan, repayment.amount_minor)

        legs = [
            # Cash arrives in the group's pool (the provider settles to it).
            ledger.Leg(account=pool, amount_minor=repayment.amount_minor, memo="Repayment received"),
            # The claim we held against the borrower shrinks by the principal.
            ledger.Leg(account=receivable, amount_minor=-principal_part, memo="Receivable settled"),
        ]
        if interest_part:
            legs.append(ledger.Leg(account=ledger.interest_income(repayment.currency),
                                   amount_minor=-interest_part, memo="Interest earned"))

        txn = ledger.post(
            kind=ledger.JournalTransaction.Kind.LOAN_REPAYMENT,
            currency=repayment.currency,
            description=f"Repayment {repayment.reference}",
            source_type="repayment",
            source_id=str(repayment.pk),
            idempotency_key=f"repayment:{repayment.pk}",
            external_reference=provider_reference,
            posted_by=actor,
            legs=legs,
        )

        repayment.status = Repayment.Status.SETTLED
        repayment.paid_at = timezone.now()
        repayment.ledger_reference = txn.reference
        repayment.save(update_fields=["status", "paid_at", "ledger_reference", "updated_at"])

        loan.outstanding_minor = max(0, loan.outstanding_minor - repayment.amount_minor)
        if loan.outstanding_minor == 0:
            loan.status = Loan.Status.REPAID
        loan.save(update_fields=["outstanding_minor", "status", "updated_at"])

        _apply_to_schedule(loan, repayment.amount_minor)
        publish("loan.repayment_settled", {
            "loan_id": str(loan.pk), "borrower_user_id": str(loan.borrower.user_id),
            "amount_minor": repayment.amount_minor, "currency": repayment.currency,
            "outstanding_minor": loan.outstanding_minor, "group_id": str(loan.group_id),
        })
    return repayment


def _split_repayment(loan: Loan, amount_minor: int) -> tuple[int, int]:
    """How much of a payment is principal and how much is interest.

    Mirrors `_apply_to_schedule` exactly — oldest installment first — so the
    ledger and the schedule can never tell different stories about one payment.
    """
    remaining = amount_minor
    principal = 0
    interest = 0
    for item in loan.schedule.order_by("installment_no"):
        if remaining <= 0:
            break
        due = item.amount_minor - item.paid_minor
        if due <= 0:
            continue
        applied = min(remaining, due)
        # Within an installment, interest is settled before principal.
        interest_due = max(0, item.interest_minor - min(item.paid_minor, item.interest_minor))
        take_interest = min(applied, interest_due)
        interest += take_interest
        principal += applied - take_interest
        remaining -= applied
    return principal, interest


def _apply_to_schedule(loan: Loan, amount_minor: int) -> None:
    remaining = amount_minor
    for item in loan.schedule.order_by("installment_no"):
        if remaining <= 0:
            break
        due = item.amount_minor - item.paid_minor
        if due <= 0:
            continue
        applied = min(remaining, due)
        item.paid_minor += applied
        remaining -= applied
        if item.paid_minor >= item.amount_minor:
            item.paid_at = timezone.now()
        item.save(update_fields=["paid_minor", "paid_at"])


def mark_overdue_installments() -> int:
    """Flag loans that have slipped past a due installment. No fees invented."""
    count = 0
    for loan in Loan.objects.filter(status=Loan.Status.ACTIVE).select_related("borrower"):
        if loan.schedule.filter(paid_at__isnull=True, due_date__lt=timezone.localdate()).exists():
            loan.status = Loan.Status.OVERDUE
            loan.save(update_fields=["status", "updated_at"])
            publish("loan.overdue", {"loan_id": str(loan.pk), "borrower_user_id": str(loan.borrower.user_id),
                                    "group_id": str(loan.group_id), "outstanding_minor": loan.outstanding_minor})
            count += 1
    return count
