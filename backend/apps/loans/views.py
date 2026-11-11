"""Loan endpoints."""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.exceptions import NotFoundError, PermissionDeniedError
from apps.groups.models import Group, Membership, Permission as GroupPermission
from apps.groups.permissions import require_membership, require_permission
from apps.payments.services import create_intent

from .models import Guarantor, Loan, LoanApplication, LoanProduct, Repayment
from .serializers import (
    GuarantorRespondSerializer, LoanApplicationCreateSerializer, LoanApplicationSerializer,
    LoanProductSerializer, LoanSerializer, RepaymentCreateSerializer, RepaymentSerializer,
)
from .services import (
    apply_for_loan, create_repayment, decide_application, disburse_loan, lending_enabled,
)


class ProductListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, slug):
        group = get_object_or_404(Group, slug=slug)
        require_membership(request.user, group)
        products = group.loan_products.filter(is_active=True)
        return Response({"data": LoanProductSerializer(products, many=True).data,
                         "meta": {"lending_enabled": lending_enabled()}})


class ApplicationListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, slug):
        group = get_object_or_404(Group, slug=slug)
        membership = require_membership(request.user, group)
        mine = LoanApplication.objects.filter(borrower=membership).select_related("product", "borrower__user")
        if "loan.approve" in membership.permissions:
            mine = LoanApplication.objects.filter(product__group=group).select_related("product", "borrower__user")
        return Response({"data": LoanApplicationSerializer(mine.order_by("-created_at"), many=True).data})

    @extend_schema(request=LoanApplicationCreateSerializer)
    def post(self, request, slug):
        group = get_object_or_404(Group, slug=slug)
        serializer = LoanApplicationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        product = get_object_or_404(LoanProduct, pk=serializer.validated_data["product_id"], group=group)
        application = apply_for_loan(
            actor=request.user, product=product,
            amount_minor=serializer.validated_data["amount_minor"],
            term_months=serializer.validated_data["term_months"],
            purpose=serializer.validated_data["purpose"],
            guarantor_membership_ids=[str(g) for g in serializer.validated_data.get("guarantor_membership_ids", [])],
        )
        return Response({"data": LoanApplicationSerializer(application).data}, status=status.HTTP_201_CREATED)


class ApplicationDecisionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, application_id):
        application = get_object_or_404(LoanApplication, pk=application_id)
        decide_application(
            actor=request.user, application=application,
            approve=bool(request.data.get("approve", True)),
            note=request.data.get("note", ""),
        )
        return Response({"data": LoanApplicationSerializer(application).data})


class GuarantorRespondView(APIView):
    """A guarantor accepts or declines. Silence never counts as consent."""

    permission_classes = [IsAuthenticated]

    def post(self, request, guarantor_id):
        guarantor = get_object_or_404(Guarantor, pk=guarantor_id)
        if guarantor.membership.user_id != request.user.pk:
            raise PermissionDeniedError("This guarantee request is not yours.", code="not_guarantor")
        serializer = GuarantorRespondSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        from django.utils import timezone

        guarantor.status = Guarantor.Status.ACCEPTED if serializer.validated_data["accept"] else Guarantor.Status.DECLINED
        guarantor.responded_at = timezone.now()
        guarantor.save(update_fields=["status", "responded_at"])
        return Response({"data": {"status": guarantor.status}})


class LoanListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, slug):
        group = get_object_or_404(Group, slug=slug)
        membership = require_membership(request.user, group)
        if "loan.view" in membership.permissions:
            loans = Loan.objects.filter(group=group)
        else:
            loans = Loan.objects.filter(borrower=membership)
        return Response({"data": LoanSerializer(loans.select_related("borrower__user").prefetch_related("schedule"),
                                                many=True).data})


class LoanDisburseView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, loan_id):
        loan = get_object_or_404(Loan, pk=loan_id)
        loan = disburse_loan(actor=request.user, loan=loan)
        return Response({"data": LoanSerializer(loan).data})


class RepaymentCreateView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(request=RepaymentCreateSerializer)
    def post(self, request, loan_id):
        loan = get_object_or_404(Loan, pk=loan_id)
        serializer = RepaymentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        repayment = create_repayment(actor=request.user, loan=loan,
                                     amount_minor=serializer.validated_data["amount_minor"])
        intent = create_intent(
            user=request.user, purpose="loan_repayment", amount_minor=repayment.amount_minor,
            currency=repayment.currency, source_type="repayment", source_id=str(repayment.pk),
        )
        repayment.payment_intent = intent
        repayment.status = Repayment.Status.PENDING
        repayment.save(update_fields=["payment_intent", "status", "updated_at"])
        return Response({
            "data": {
                "repayment": RepaymentSerializer(repayment).data,
                "payment": {"reference": intent.reference, "checkout_url": intent.checkout_url,
                            "amount_minor": intent.amount_minor, "currency": intent.currency},
            }
        }, status=status.HTTP_201_CREATED)


class MyLoanListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        loans = Loan.objects.filter(borrower__user=request.user).select_related("borrower__user")
        return Response({"data": LoanSerializer(loans, many=True).data})
