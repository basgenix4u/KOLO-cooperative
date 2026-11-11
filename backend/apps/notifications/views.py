"""Notification feed and preferences."""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Notification, NotificationPreference
from .serializers import NotificationSerializer, PreferenceSerializer
from .services import mark_all_read


class NotificationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        query = Notification.objects.filter(user=request.user)
        if request.query_params.get("unread") == "true":
            query = query.filter(read_at__isnull=True)
        limit = min(int(request.query_params.get("limit", 30)), 100)
        items = query[:limit]
        return Response({
            "data": NotificationSerializer(items, many=True).data,
            "meta": {"unread": Notification.objects.filter(user=request.user, read_at__isnull=True).count()},
        })


class NotificationReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, notification_id=None):
        if notification_id:
            from django.utils import timezone

            notification = get_object_or_404(Notification, pk=notification_id, user=request.user)
            notification.read_at = timezone.now()
            notification.save(update_fields=["read_at"])
            return Response({"data": {"read": True}})
        return Response({"data": {"marked": mark_all_read(user=request.user)}})


class PreferenceView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        prefs, _ = NotificationPreference.objects.get_or_create(user=request.user)
        return Response({"data": PreferenceSerializer(prefs).data})

    def patch(self, request):
        prefs, _ = NotificationPreference.objects.get_or_create(user=request.user)
        serializer = PreferenceSerializer(prefs, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response({"data": serializer.data})
