"""Group endpoints. Every mutation goes through a service that checks permission."""

from __future__ import annotations

from django.db.models import Count, Q
from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.generics import ListCreateAPIView, RetrieveUpdateAPIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.exceptions import NotFoundError
from apps.common.throttling import ScopedBurstThrottle

from .models import Announcement, Group, Invitation, Membership, MembershipRequest, Permission as GroupPermission
from .permissions import membership_for, require_membership, require_permission
from .serializers import (
    AnnouncementSerializer, GroupCreateSerializer, GroupDetailSerializer, GroupListSerializer,
    InvitationAcceptSerializer, InvitationSerializer, JoinSerializer, MemberSerializer,
    MembershipRequestSerializer, MembershipRoleSerializer,
)
from .services import (
    accept_invitation, archive_group, change_role, create_group, invite, leave_group,
    post_announcement, remove_member, request_to_join, review_join_request, update_group,
)


class GroupListCreateView(ListCreateAPIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedBurstThrottle]

    def get_throttle_scope(self):
        return "read" if self.request.method == "GET" else "write"

    def get_serializer_class(self):
        return GroupCreateSerializer if self.request.method == "POST" else GroupListSerializer

    def get_queryset(self):
        user = self.request.user
        query = Group.objects.filter(is_archived=False).annotate(
            active_members=Count("memberships", filter=Q(memberships__status=Membership.Status.ACTIVE))
        )
        scope = self.request.query_params.get("scope", "mine")
        if scope == "mine":
            query = query.filter(memberships__user=user, memberships__status=Membership.Status.ACTIVE)
        elif scope == "discover":
            query = query.filter(visibility__in=[Group.Visibility.PUBLIC, Group.Visibility.RESTRICTED])
        search = self.request.query_params.get("search")
        if search:
            query = query.filter(Q(name__icontains=search) | Q(city__icontains=search)
                                 | Q(description__icontains=search))
        category = self.request.query_params.get("category")
        if category:
            query = query.filter(category=category)
        return query.distinct().order_by("name")

    def get_serializer_context(self):
        context = super().get_serializer_context()
        if self.request.user.is_authenticated:
            statuses = dict(
                Membership.objects.filter(user=self.request.user).values_list("group_id", "status")
            )
            context["membership_status"] = statuses
        return context

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        return response

    @extend_schema(request=GroupCreateSerializer, responses={201: GroupDetailSerializer})
    def post(self, request, *args, **kwargs):
        serializer = GroupCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        group = create_group(actor=request.user, **serializer.validated_data)
        membership = membership_for(request.user, group)
        return Response(
            {"data": GroupDetailSerializer(group, context={"membership": membership}).data},
            status=status.HTTP_201_CREATED,
        )


class GroupDetailView(RetrieveUpdateAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = GroupDetailSerializer
    lookup_field = "slug"
    queryset = Group.objects.all()

    def get_object(self):
        group = super().get_object()
        membership = membership_for(self.request.user, group)
        if not membership and group.visibility == Group.Visibility.PRIVATE:
            raise NotFoundError("That group is not available to you.", code="group_not_found")
        self.membership = membership
        return group

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["membership"] = getattr(self, "membership", None)
        return context

    def patch(self, request, *args, **kwargs):
        group = self.get_object()
        require_permission(request.user, group, GroupPermission.GROUP_EDIT)
        serializer = GroupCreateSerializer(group, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        updated = update_group(actor=request.user, group=group, **serializer.validated_data)
        return Response({"data": GroupDetailSerializer(updated, context={"membership": self.membership}).data})


class GroupArchiveView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, slug):
        group = Group.objects.get(slug=slug)
        archive_group(actor=request.user, group=group)
        return Response({"data": {"archived": True}})


class GroupMemberListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, slug):
        group = Group.objects.get(slug=slug)
        membership = require_membership(request.user, group)
        viewer_is_officer = bool({"finance.view", "member.remove"} & membership.permissions)
        members = group.memberships.filter(
            status__in=[Membership.Status.ACTIVE, Membership.Status.PENDING]
        ).select_related("user").order_by("display_name", "created_at")
        data = MemberSerializer(members, many=True, context={"viewer_is_officer": viewer_is_officer}).data
        return Response({"data": data})


class GroupMemberRoleView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, slug, member_id):
        group = Group.objects.get(slug=slug)
        membership = group.memberships.get(pk=member_id)
        serializer = MembershipRoleSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        updated = change_role(
            actor=request.user, group=group, membership=membership,
            role=serializer.validated_data["role"], overrides=serializer.validated_data.get("permissions"),
        )
        return Response({"data": MemberSerializer(updated, context={"viewer_is_officer": True}).data})


class GroupMemberRemoveView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, slug, member_id):
        group = Group.objects.get(slug=slug)
        membership = group.memberships.get(pk=member_id)
        remove_member(actor=request.user, group=group, membership=membership,
                      reason=request.data.get("reason", ""))
        return Response({"data": {"removed": True}})


class GroupLeaveView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, slug):
        group = Group.objects.get(slug=slug)
        leave_group(actor=request.user, group=group)
        return Response({"data": {"left": True}})


class GroupJoinView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "write"

    def post(self, request, slug):
        group = Group.objects.get(slug=slug)
        serializer = JoinSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        result = request_to_join(actor=request.user, group=group, message=serializer.validated_data.get("message", ""))
        if isinstance(result, Membership):
            return Response({"data": {"joined": True, "status": result.status}}, status=status.HTTP_201_CREATED)
        return Response({"data": {"requested": True, "request_id": str(result.pk)}}, status=status.HTTP_201_CREATED)


class GroupRequestListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, slug):
        group = Group.objects.get(slug=slug)
        require_permission(request.user, group, GroupPermission.MEMBER_APPROVE)
        requests_qs = group.join_requests.filter(status=MembershipRequest.Status.PENDING).select_related("user")
        return Response({"data": MembershipRequestSerializer(requests_qs, many=True).data})


class GroupRequestReviewView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, slug, request_id):
        group = Group.objects.get(slug=slug)
        join_request = group.join_requests.get(pk=request_id)
        approve = bool(request.data.get("approve", True))
        review_join_request(actor=request.user, request_obj=join_request, approve=approve)
        return Response({"data": {"status": join_request.status}})


class GroupInviteView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, slug):
        group = Group.objects.get(slug=slug)
        invitation = invite(
            actor=request.user, group=group,
            email=request.data.get("email", ""), phone=request.data.get("phone", ""),
        )
        return Response({"data": InvitationSerializer(invitation).data}, status=status.HTTP_201_CREATED)


class InvitationAcceptView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = InvitationAcceptSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        membership = accept_invitation(actor=request.user, token=serializer.validated_data["token"])
        return Response({"data": {"joined": True, "group_id": str(membership.group_id)}})


class GroupAnnouncementView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, slug):
        group = Group.objects.get(slug=slug)
        require_membership(request.user, group)
        items = group.announcements.select_related("author")[:50]
        return Response({"data": AnnouncementSerializer(items, many=True).data})

    def post(self, request, slug):
        group = Group.objects.get(slug=slug)
        announcement = post_announcement(
            actor=request.user, group=group,
            title=request.data.get("title", ""), body=request.data.get("body", ""),
            pinned=bool(request.data.get("is_pinned", False)),
        )
        return Response({"data": AnnouncementSerializer(announcement).data}, status=status.HTTP_201_CREATED)


class InvitationListView(APIView):
    """Every invitation this member has sent, and its state."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        invitations = Invitation.objects.filter(invited_by=request.user).order_by("-created_at")[:50]
        return Response({"data": InvitationSerializer(invitations, many=True).data})
