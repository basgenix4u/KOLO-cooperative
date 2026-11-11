"""Governance endpoints."""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.exceptions import NotFoundError
from apps.groups.models import Group, Permission as GroupPermission
from apps.groups.permissions import require_membership, require_permission

from .models import Proposal
from .serializers import BallotCreateSerializer, ProposalCreateSerializer, ProposalSerializer, ResolutionSerializer
from .services import cast_ballot, close_proposal, open_proposal


class ProposalListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, slug):
        group = get_object_or_404(Group, slug=slug)
        require_membership(request.user, group)
        proposals = group.proposals.order_by("-created_at")
        return Response({"data": ProposalSerializer(proposals, many=True, context={"request": request}).data})

    def post(self, request, slug):
        group = get_object_or_404(Group, slug=slug)
        require_permission(request.user, group, GroupPermission.PROPOSAL_CREATE)
        serializer = ProposalCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        proposal = Proposal.objects.create(group=group, created_by=request.user, **serializer.validated_data)
        return Response(
            {"data": ProposalSerializer(proposal, context={"request": request}).data},
            status=status.HTTP_201_CREATED,
        )


class ProposalDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, proposal_id):
        proposal = get_object_or_404(Proposal, pk=proposal_id)
        require_membership(request.user, proposal.group)
        return Response({"data": ProposalSerializer(proposal, context={"request": request}).data})


class ProposalOpenView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, proposal_id):
        proposal = get_object_or_404(Proposal, pk=proposal_id)
        open_proposal(actor=request.user, proposal=proposal)
        return Response({"data": ProposalSerializer(proposal, context={"request": request}).data})


class ProposalCloseView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, proposal_id):
        proposal = get_object_or_404(Proposal, pk=proposal_id)
        resolution = close_proposal(actor=request.user, proposal=proposal)
        return Response({"data": ResolutionSerializer(resolution).data})


class BallotView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, proposal_id):
        proposal = get_object_or_404(Proposal, pk=proposal_id)
        serializer = BallotCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        cast_ballot(
            actor=request.user, proposal=proposal,
            in_favour=serializer.validated_data["in_favour"],
            comment=serializer.validated_data.get("comment", ""),
        )
        return Response({"data": {"voted": True}}, status=status.HTTP_201_CREATED)
