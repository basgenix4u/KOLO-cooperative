from rest_framework import serializers

from .models import Notification, NotificationPreference


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ["id", "kind", "title", "body", "data", "read_at", "created_at"]


class PreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = NotificationPreference
        fields = ["push_enabled", "email_enabled", "contributions", "payouts", "loans", "governance",
                  "announcements", "security", "quiet_hours_start", "quiet_hours_end"]
        read_only_fields = ["security"]
