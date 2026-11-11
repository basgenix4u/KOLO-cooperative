"""Savings endpoints."""

from __future__ import annotations

from django.db.models import Sum
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.generics import ListAPIView, ListCreateAPIView, RetrieveAPIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.exceptions import DomainError, NotFoundError, PermissionDeniedError
from apps.common.throttling import ScopedBurstThrottle
from apps.groups.models import Group, Membership, Permission as GroupPermission
from apps.groups.permissions import membership_for, require_membership, require_permission
from apps.ledger import services as ledger

from .models import (
    Contribution, ContributionTarget, FundraisingCampaign, Obligation, Participation, Programme,
    RotationCycle, WithdrawalRequest,
)
from .serializers import (
    CampaignCreateSerializer, CampaignSerializer, ContributionCreateSerializer, ContributionSerializer,
    ObligationSerializer, OfflineContributionSerializer, ParticipantAddSerializer, ProgrammeCreateSerializer,
    ProgrammeDetailSerializer, ProgrammeListSerializer, RotationCycleSerializer, RotationOrderSerializer,
    RotationPositionSerializer, TargetSerializer, WithdrawalCreateSerializer, WithdrawalSerializer,
)
from .services import (
    add_participants, approve_payout, create_programme, execute_payout, open_next_cycle,
    record_offline_contribution, set_rotation_order, transition,
)


def _programme_or_404(programme_id) -> Programme:
    programme = Programme.objects.select_related("group").filter(pk=programme_id).first()
    if not programme:
        raise NotFoundError("That programme is not available.", code="programme_not_found")
    return programme


class ProgrammeListCreateView(ListCreateAPIView):
    permission_classes = [IsAuthenticated]

    def get_serializer_class(self):
        return ProgrammeCreateSerializer if self.request.method == "POST" else ProgrammeListSerializer

    def get_queryset(self):
        user = self.request.user
        query = Programme.objects.filter(
            group__memberships__user=user, group__memberships__status=Membership.Status.ACTIVE
        ).select_related("group")
        group_slug = self.request.query_params.get("group")
        if group_slug:
            query = query.filter(group__slug=group_slug)
        status_filter = self.request.query_params.get("status")
        if status_filter:
            query = query.filter(status=status_filter)
        return query.distinct().order_by("-created_at")

    def post(self, request):
        group = get_object_or_404(Group, slug=request.data.get("group", ""))
        serializer = ProgrammeCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        if not data.get("currency"):
            data["currency"] = group.currency
        programme = create_programme(actor=request.user, group=group, **data)
        return Response(
            {"data": ProgrammeDetailSerializer(programme, context={"my_participation": None}).data},
            status=status.HTTP_201_CREATED,
        )


class ProgrammeDetailView(RetrieveAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = ProgrammeDetailSerializer

    def get_object(self):
        programme = _programme_or_404(self.kwargs["programme_id"])
        require_membership(self.request.user, programme.group)
        self.participation = Participation.objects.filter(
            programme=programme, membership__user=self.request.user
        ).select_related("membership").first()
        return programme

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["my_participation"] = getattr(self, "participation", None)
        return context


class ProgrammeTransitionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, programme_id):
        programme = _programme_or_404(programme_id)
        to_status = request.data.get("status", "")
        updated = transition(actor=request.user, programme=programme, to_status=to_status,
                             note=request.data.get("note", ""))
        return Response({"data": ProgrammeListSerializer(updated).data})


class ProgrammeParticipantView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, programme_id):
        programme = _programme_or_404(programme_id)
        serializer = ParticipantAddSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        created = add_participants(
            actor=request.user, programme=programme,
            membership_ids=[str(m) for m in serializer.validated_data["membership_ids"]],
            amount_minor=serializer.validated_data.get("amount_minor"),
        )
        return Response({"data": {"added": len(created)}}, status=status.HTTP_201_CREATED)

    def get(self, request, programme_id):
        programme = _programme_or_404(programme_id)
        require_membership(request.user, programme.group)
        participants = programme.participants.select_related("membership__user").filter(
            status=Participation.Status.ACTIVE
        )
        return Response({
            "data": [
                {
                    "id": str(p.pk),
                    "name": p.membership.display_name or p.membership.user.full_name,
                    "amount_minor": p.amount_minor,
                    "status": p.status,
                    "joined_at": p.joined_at,
                }
                for p in participants
            ]
        })


class RotationOrderView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, programme_id):
        programme = _programme_or_404(programme_id)
        require_membership(request.user, programme.group)
        positions = programme.rotation_positions.select_related("participation__membership__user").order_by("position")
        return Response({"data": RotationPositionSerializer(positions, many=True).data})

    def put(self, request, programme_id):
        programme = _programme_or_404(programme_id)
        serializer = RotationOrderSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        positions = set_rotation_order(
            actor=request.user, programme=programme,
            ordered_participation_ids=[str(p) for p in serializer.validated_data["participation_ids"]],
        )
        return Response({"data": RotationPositionSerializer(positions, many=True).data})


class ProgrammeCycleView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, programme_id):
        programme = _programme_or_404(programme_id)
        require_membership(request.user, programme.group)
        cycles = programme.cycles.select_related("beneficiary__membership__user").order_by("sequence")
        return Response({"data": RotationCycleSerializer(cycles, many=True).data})

    def post(self, request, programme_id):
        programme = _programme_or_404(programme_id)
        cycle = open_next_cycle(actor=request.user, programme=programme)
        return Response({"data": RotationCycleSerializer(cycle).data}, status=status.HTTP_201_CREATED)


class CycleApproveView(APIView):
    """First signature: an officer confirms the payout is due."""

    permission_classes = [IsAuthenticated]

    def post(self, request, cycle_id):
        cycle = get_object_or_404(RotationCycle, pk=cycle_id)
        cycle = approve_payout(actor=request.user, cycle=cycle)
        return Response({"data": RotationCycleSerializer(cycle).data})


class CycleExecuteView(APIView):
    """Second signature: post the payout to the ledger."""

    permission_classes = [IsAuthenticated]

    def post(self, request, cycle_id):
        cycle = get_object_or_404(RotationCycle, pk=cycle_id)
        cycle = execute_payout(actor=request.user, cycle=cycle)
        return Response({"data": RotationCycleSerializer(cycle).data})


class MyObligationView(ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = ObligationSerializer

    def get_queryset(self):
        query = Obligation.objects.filter(
            participation__membership__user=self.request.user
        ).select_related("programme")
        status_filter = self.request.query_params.get("status", "open")
        if status_filter == "open":
            query = query.filter(status__in=[
                Obligation.Status.PENDING, Obligation.Status.PARTIALLY_PAID, Obligation.Status.OVERDUE
            ])
        return query.order_by("due_date")


class MyContributionView(ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = ContributionSerializer

    def get_queryset(self):
        return Contribution.objects.filter(
            participation__membership__user=self.request.user
        ).select_related("programme").order_by("-created_at")


class ContributionCreateView(APIView):
    """Start a contribution: creates the intent the member pays through."""

    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "payment"

    @extend_schema(request=ContributionCreateSerializer)
    def post(self, request, programme_id):
        from apps.payments.services import create_intent

        programme = _programme_or_404(programme_id)
        membership = require_membership(request.user, programme.group)
        if programme.status not in {Programme.Status.ACTIVE, Programme.Status.SCHEDULED}:
            raise DomainError("This programme is not collecting contributions.", code="programme_not_collecting")

        serializer = ContributionCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        participation = Participation.objects.filter(programme=programme, membership=membership).first()
        if not participation or participation.status != Participation.Status.ACTIVE:
            raise PermissionDeniedError("You are not taking part in this programme.", code="not_a_participant")

        obligation = None
        if data.get("obligation_id"):
            obligation = Obligation.objects.filter(
                pk=data["obligation_id"], participation=participation
            ).first()
            if not obligation:
                raise NotFoundError("That contribution request was not found.", code="obligation_not_found")

        contribution = Contribution.objects.create(
            programme=programme,
            obligation=obligation,
            participation=participation,
            payer=request.user,
            amount_minor=data["amount_minor"],
            currency=programme.currency,
            source=Contribution.Source.MEMBER,
            reference=f"CON-{programme.pk.hex[:6].upper()}-{Contribution.objects.count() + 1}",
        )
        intent = create_intent(
            user=request.user,
            purpose="contribution",
            amount_minor=data["amount_minor"],
            currency=programme.currency,
            source_type="contribution",
            source_id=str(contribution.pk),
            idempotency_key=data.get("idempotency_key", ""),
            callback_url=data.get("callback_url", ""),
            description=f"{programme.name} contribution",
        )
        contribution.payment_intent = intent
        contribution.status = Contribution.Status.PENDING
        contribution.save(update_fields=["payment_intent", "status", "updated_at"])

        return Response(
            {
                "data": {
                    "contribution": ContributionSerializer(contribution).data,
                    "payment": {
                        "intent_id": str(intent.pk),
                        "reference": intent.reference,
                        "status": intent.status,
                        "checkout_url": intent.checkout_url,
                        "amount_minor": intent.amount_minor,
                        "currency": intent.currency,
                    },
                }
            },
            status=status.HTTP_201_CREATED,
        )


class OfflineContributionView(APIView):
    """Treasurer records cash received in person."""

    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "payment"

    @extend_schema(request=OfflineContributionSerializer)
    def post(self, request, programme_id):
        programme = _programme_or_404(programme_id)
        serializer = OfflineContributionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        participation = get_object_or_404(
            Participation, pk=serializer.validated_data["participation_id"], programme=programme
        )
        contribution = record_offline_contribution(
            actor=request.user, programme=programme, participation=participation,
            amount_minor=serializer.validated_data["amount_minor"],
            note=serializer.validated_data.get("note", ""),
        )
        return Response({"data": ContributionSerializer(contribution).data}, status=status.HTTP_201_CREATED)


class WithdrawalListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, programme_id):
        programme = _programme_or_404(programme_id)
        require_permission(request.user, programme.group, GroupPermission.FINANCE_VIEW)
        withdrawals = programme.withdrawals.select_related("requested_by").order_by("-created_at")
        return Response({"data": WithdrawalSerializer(withdrawals, many=True).data})

    @extend_schema(request=WithdrawalCreateSerializer)
    def post(self, request, programme_id):
        from .services import request_withdrawal

        programme = _programme_or_404(programme_id)
        serializer = WithdrawalCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        withdrawal = request_withdrawal(
            actor=request.user, programme=programme,
            amount_minor=serializer.validated_data["amount_minor"],
            reason=serializer.validated_data["reason"],
            beneficiary_participation_id=serializer.validated_data.get("beneficiary_participation_id"),
            note=serializer.validated_data.get("note", ""),
        )
        return Response({"data": WithdrawalSerializer(withdrawal).data}, status=status.HTTP_201_CREATED)


class WithdrawalDecisionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, withdrawal_id):
        from .services import decide_withdrawal

        withdrawal = get_object_or_404(WithdrawalRequest, pk=withdrawal_id)
        approve = bool(request.data.get("approve", True))
        decide_withdrawal(actor=request.user, withdrawal=withdrawal, approve=approve,
                          comment=request.data.get("comment", ""))
        return Response({"data": WithdrawalSerializer(withdrawal).data})


class WithdrawalExecuteView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, withdrawal_id):
        from .services import execute_withdrawal

        withdrawal = get_object_or_404(WithdrawalRequest, pk=withdrawal_id)
        account_number = request.data.get("account_number", "")
        bank_code = request.data.get("bank_code", "")
        withdrawal = execute_withdrawal(
            actor=request.user, withdrawal=withdrawal,
            account_number=account_number, bank_code=bank_code,
            account_name=request.data.get("account_name", ""),
        )
        return Response({"data": WithdrawalSerializer(withdrawal).data})


class CampaignListCreateView(ListCreateAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = CampaignSerializer

    def get_queryset(self):
        user = self.request.user
        query = FundraisingCampaign.objects.filter(
            group__memberships__user=user, group__memberships__status=Membership.Status.ACTIVE
        )
        return query.distinct().order_by("-created_at")

    def post(self, request):
        group = get_object_or_404(Group, slug=request.data.get("group", ""))
        require_permission(request.user, group, GroupPermission.PROGRAMME_CREATE)
        serializer = CampaignCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        campaign = FundraisingCampaign.objects.create(
            group=group, created_by=request.user, **serializer.validated_data
        )
        return Response({"data": CampaignSerializer(campaign).data}, status=status.HTTP_201_CREATED)


class ProgrammeSummaryView(APIView):
    """Group-level financial summary.

    Programme balances are summed from their own ring-fenced accounts, so the
    parent's report never double-counts money that already sits in a programme.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request, slug):
        group = get_object_or_404(Group, slug=slug)
        require_permission(request.user, group, GroupPermission.FINANCE_VIEW)

        programmes = []
        total_collected = 0
        for programme in group.programmes.all():
            pool = ledger.programme_pool(programme)
            collected = ledger.balance_of(pool)
            total_collected += collected
            programmes.append({
                "id": str(programme.pk),
                "name": programme.name,
                "type": programme.type,
                "status": programme.status,
                "currency": programme.currency,
                "collected_minor": collected,
                "available_minor": ledger.available_of(pool),
                "expected_minor": programme.expected_total_minor(),
            })

        return Response({
            "data": {
                "group_id": str(group.pk),
                "group_name": group.name,
                "currency": group.currency,
                "programmes": programmes,
                "totals": {"collected_minor": total_collected},
                "note": "Each programme balance comes from its own ledger account; the total is a sum, not a copy.",
            }
        })
