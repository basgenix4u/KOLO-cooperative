"""Lending.

The first test in this file is the most important one in the product: lending
must be *off* until a licensed arrangement exists. Everything else here checks
that when it is switched on, it behaves like a lender rather than a money
printer.
"""

from __future__ import annotations

import pytest
from django.utils import timezone

from apps.common.exceptions import DomainError, FinancialSafetyError, PermissionDeniedError
from apps.ledger import services as ledger
from apps.loans import services
from apps.loans.models import Guarantor, Loan, LoanApplication, LoanProduct

pytestmark = pytest.mark.django_db


@pytest.fixture
def product(group, officers, memberships):
    """Members exist in every loan test; borrowing needs ordinary members."""
    return LoanProduct.objects.create(
        group=group, name="Cooperative loan", currency="NGN",
        min_amount_minor=10_000, max_amount_minor=1_000_000,
        interest_bps=1200, term_months_min=1, term_months_max=12,
        requires_guarantors=0, is_active=True,
    )


@pytest.fixture
def lending_on(settings):
    settings.KOLO["LENDING_ENABLED"] = True
    return settings


def _fund_pool(group, officers, amount=500_000):
    """Real money in the group pool, posted through the ledger."""
    from django.db import transaction

    from apps.groups.models import GroupRole

    officers["treasurer"].role = GroupRole.TREASURER
    officers["treasurer"].save(update_fields=["role"])
    pool = ledger.group_pool(group)
    holding = ledger.member_holding(group, officers["treasurer"].pk, "NGN")
    with transaction.atomic():
        ledger.post(
            kind="contribution", currency="NGN", description="Cooperative dues",
            legs=[ledger.Leg(account=pool, amount_minor=amount),
                  ledger.Leg(account=holding, amount_minor=-amount)],
        )
    return pool


def _approved_loan(group, officers, product, amount_minor=100_000, term_months=3):
    from apps.groups.models import GroupRole, Membership

    borrower = Membership.objects.filter(group=group, role=GroupRole.MEMBER).select_related("user").first()
    application = services.apply_for_loan(
        actor=borrower.user, product=product, amount_minor=amount_minor,
        term_months=term_months, purpose="Stock for my shop",
    )
    services.decide_application(actor=officers["chair"].user, application=application, approve=True)
    application.refresh_from_db()
    return borrower, application, application.loan


def test_lending_is_off_by_default(settings):
    assert services.lending_enabled() is False


def test_disbursement_is_refused_while_lending_is_disabled(group, officers, product):
    """No licensed arrangement, no loans — enforced in the service, not the UI."""
    _fund_pool(group, officers)
    borrower, application, loan = _approved_loan(group, officers, product)

    with pytest.raises(DomainError) as caught:
        services.disburse_loan(actor=officers["treasurer"].user, loan=loan)
    assert caught.value.code == "lending_disabled"

    loan.refresh_from_db()
    assert loan.status == Loan.Status.PENDING_DISBURSEMENT
    pool = ledger.group_pool(group)
    assert ledger.balance_of(pool) == 500_000, "not one unit moved"


def test_application_outside_the_product_range_is_refused(group, officers, product):
    from apps.groups.models import GroupRole, Membership

    borrower = Membership.objects.filter(group=group, role=GroupRole.MEMBER).first()
    with pytest.raises(DomainError) as caught:
        services.apply_for_loan(actor=borrower.user, product=product, amount_minor=5_000,
                                term_months=3, purpose="Too small")
    assert caught.value.code == "amount_out_of_range"


def test_self_approval_of_a_loan_is_refused(group, officers, product):
    """An officer who is also the borrower cannot sign off their own loan."""
    from apps.groups.models import GroupRole, Membership

    borrower_membership = Membership.objects.filter(group=group, role=GroupRole.MEMBER).first()
    borrower_membership.role = GroupRole.OWNER
    borrower_membership.save(update_fields=["role"])

    application = services.apply_for_loan(
        actor=borrower_membership.user, product=product, amount_minor=50_000,
        term_months=2, purpose="Personal",
    )
    with pytest.raises(PermissionDeniedError) as caught:
        services.decide_application(actor=borrower_membership.user, application=application, approve=True)
    assert caught.value.code == "self_approval_blocked"


def test_guarantors_must_accept_before_approval(group, officers, memberships):
    product = LoanProduct.objects.create(
        group=group, name="Guaranteed loan", currency="NGN",
        min_amount_minor=10_000, max_amount_minor=500_000, interest_bps=600,
        term_months_min=1, term_months_max=6, requires_guarantors=1, is_active=True,
    )
    application = services.apply_for_loan(
        actor=memberships["a"].user, product=product, amount_minor=50_000, term_months=2,
        purpose="Farm inputs", guarantor_membership_ids=[str(memberships["b"].pk)],
    )
    with pytest.raises(DomainError) as caught:
        services.decide_application(actor=officers["chair"].user, application=application, approve=True)
    assert caught.value.code == "guarantors_pending"

    guarantor = Guarantor.objects.get(application=application)
    with pytest.raises(PermissionDeniedError):
        # A different member cannot accept on someone else's behalf.
        services.decide_application(actor=memberships["a"].user, application=application, approve=True)

    guarantor.status = Guarantor.Status.ACCEPTED
    guarantor.responded_at = timezone.now()
    guarantor.save(update_fields=["status", "responded_at"])
    approved = services.decide_application(actor=officers["chair"].user, application=application, approve=True)
    assert approved.status == LoanApplication.Status.APPROVED


def test_interest_and_schedule_are_exact(group, officers, product):
    _, application, loan = _approved_loan(group, officers, product, amount_minor=100_000, term_months=3)
    # 12% per annum, 3 months: 100000 * 1200 * 3 // (10000*12) = 3000
    assert loan.total_repayable_minor == 103_000
    assert loan.outstanding_minor == 103_000

    installments = list(loan.schedule.order_by("installment_no"))
    assert len(installments) == 3
    assert sum(i.amount_minor for i in installments) == 103_000, "installments must sum to the total exactly"
    assert sum(i.principal_minor for i in installments) == 100_000, "principal must sum exactly"
    assert sum(i.interest_minor for i in installments) == 3_000


def test_odd_principal_lands_on_the_final_installment(group, officers, memberships):
    product = LoanProduct.objects.create(
        group=group, name="Odd loan", currency="NGN", min_amount_minor=1,
        max_amount_minor=1_000_000, interest_bps=0, term_months_min=1, term_months_max=12, is_active=True,
    )
    _, _, loan = _approved_loan(group, officers, product, amount_minor=100_000, term_months=3)
    installments = list(loan.schedule.order_by("installment_no"))
    assert sum(i.principal_minor for i in installments) == 100_000
    assert sum(i.amount_minor for i in installments) == 100_000
    assert installments[-1].principal_minor == 33_334


def test_disbursement_is_refused_when_the_pool_cannot_cover_it(group, officers, product, settings):
    settings.KOLO["LENDING_ENABLED"] = True
    _fund_pool(group, officers, amount=50_000)
    _, application, loan = _approved_loan(group, officers, product, amount_minor=100_000)

    with pytest.raises(FinancialSafetyError) as caught:
        services.disburse_loan(actor=officers["treasurer"].user, loan=loan)
    assert caught.value.code == "pool_underfunded"
    assert caught.value.details["available_minor"] == 50_000

    loan.refresh_from_db()
    assert loan.status == Loan.Status.PENDING_DISBURSEMENT


def test_disbursement_creates_a_receivable_not_an_expense(group, officers, product, settings):
    settings.KOLO["LENDING_ENABLED"] = True
    pool = _fund_pool(group, officers, amount=500_000)
    _, application, loan = _approved_loan(group, officers, product, amount_minor=100_000)

    loan = services.disburse_loan(actor=officers["treasurer"].user, loan=loan)
    assert loan.status == Loan.Status.ACTIVE

    pool.refresh_from_db()
    receivable = ledger.group_loan_receivable(group)
    assert ledger.balance_of(pool) == 400_000
    assert ledger.balance_of(receivable) == 100_000, "the group is owed the money"

    # Idempotent: a retried call is not a second loan.
    services.disburse_loan(actor=officers["treasurer"].user, loan=loan)
    pool.refresh_from_db()
    assert ledger.balance_of(pool) == 400_000


def test_repayment_requires_an_active_loan(group, officers, product, settings):
    """A loan that has not been disbursed cannot be repaid."""
    settings.KOLO["LENDING_ENABLED"] = True
    _fund_pool(group, officers, amount=500_000)
    borrower, application, loan = _approved_loan(group, officers, product, amount_minor=50_000, term_months=1)
    with pytest.raises(Exception) as caught:
        services.create_repayment(actor=borrower.user, loan=loan, amount_minor=1_000)
    assert getattr(caught.value, "code", "") == "loan_not_repayable"


def test_repayment_splits_principal_from_interest(group, officers, product, settings):
    settings.KOLO["LENDING_ENABLED"] = True
    pool = _fund_pool(group, officers, amount=500_000)
    borrower, application, loan = _approved_loan(group, officers, product, amount_minor=100_000, term_months=3)
    loan = services.disburse_loan(actor=officers["treasurer"].user, loan=loan)

    receivable = ledger.group_loan_receivable(group)
    income = ledger.interest_income("NGN")

    repayment = services.create_repayment(actor=borrower.user, loan=loan, amount_minor=34_334)
    services.settle_repayment(repayment, actor=borrower.user)

    pool.refresh_from_db()
    receivable.refresh_from_db()
    # Installment 1 is 34,333 (33,333 principal + 1,000 interest). Paying
    # 34,334 settles it and puts the single extra unit against installment 2's
    # interest first, so interest taken is 1,001 and principal 33,333.
    assert ledger.balance_of(pool) == 400_000 + 34_334
    assert ledger.natural_balance(income) == 1_001
    assert ledger.balance_of(receivable) == 100_000 - 33_333

    loan.refresh_from_db()
    assert loan.outstanding_minor == 103_000 - 34_334


def test_repayment_is_idempotent(group, officers, product, settings):
    settings.KOLO["LENDING_ENABLED"] = True
    _fund_pool(group, officers, amount=500_000)
    borrower, application, loan = _approved_loan(group, officers, product, amount_minor=60_000, term_months=2)
    services.disburse_loan(actor=officers["treasurer"].user, loan=loan)

    repayment = services.create_repayment(actor=borrower.user, loan=loan, amount_minor=10_000)
    services.settle_repayment(repayment, actor=borrower.user)
    services.settle_repayment(repayment, actor=borrower.user)

    loan.refresh_from_db()
    # 60,000 over 2 months at 12% p.a. is 61,200 repayable.
    assert loan.outstanding_minor == 61_200 - 10_000, "a replayed repayment is not a second payment"


def test_borrower_cannot_overpay_beyond_the_outstanding_balance(group, officers, product, settings):
    settings.KOLO["LENDING_ENABLED"] = True
    _fund_pool(group, officers, amount=500_000)
    borrower, application, loan = _approved_loan(group, officers, product, amount_minor=50_000, term_months=1)
    services.disburse_loan(actor=officers["treasurer"].user, loan=loan)

    with pytest.raises(DomainError) as caught:
        services.create_repayment(actor=borrower.user, loan=loan, amount_minor=999_999)
    assert caught.value.code == "amount_exceeds_outstanding"


def test_only_the_borrower_can_repay(group, officers, product, settings):
    settings.KOLO["LENDING_ENABLED"] = True
    _fund_pool(group, officers, amount=500_000)
    borrower, application, loan = _approved_loan(group, officers, product, amount_minor=50_000, term_months=1)
    services.disburse_loan(actor=officers["treasurer"].user, loan=loan)

    with pytest.raises(PermissionDeniedError) as caught:
        services.create_repayment(actor=officers["chair"].user, loan=loan, amount_minor=1_000)
    assert caught.value.code == "not_borrower"


def test_full_repayment_closes_the_loan(group, officers, product, settings):
    settings.KOLO["LENDING_ENABLED"] = True
    _fund_pool(group, officers, amount=500_000)
    borrower, application, loan = _approved_loan(group, officers, product, amount_minor=50_000, term_months=1)
    services.disburse_loan(actor=officers["treasurer"].user, loan=loan)

    repayment = services.create_repayment(actor=borrower.user, loan=loan, amount_minor=50_500)
    services.settle_repayment(repayment, actor=borrower.user)

    loan.refresh_from_db()
    assert loan.outstanding_minor == 0
    assert loan.status == Loan.Status.REPAID
