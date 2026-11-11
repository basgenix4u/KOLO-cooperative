from rest_framework import serializers

from .models import Announcement, Group, Invitation, Membership, MembershipRequest


class GroupListSerializer(serializers.ModelSerializer):
    member_count = serializers.SerializerMethodField()
    my_status = serializers.SerializerMethodField()

    class Meta:
        model = Group
        fields = ["id", "name", "slug", "category", "visibility", "currency", "city", "country",
                  "avatar_url", "member_count", "is_archived", "my_status", "created_at"]

    def get_member_count(self, obj) -> int:
        annotated = getattr(obj, "active_members", None)
        return annotated if annotated is not None else obj.member_count()

    def get_my_status(self, obj) -> str | None:
        statuses = self.context.get("membership_status") or {}
        return statuses.get(obj.pk)


class GroupDetailSerializer(GroupListSerializer):
    my_role = serializers.SerializerMethodField()
    my_permissions = serializers.SerializerMethodField()

    class Meta(GroupListSerializer.Meta):
        fields = GroupListSerializer.Meta.fields + [
            "description", "requires_approval", "max_members", "requires_dual_approval_for_withdrawals",
            "cover_url", "latitude", "longitude", "my_role", "my_permissions",
        ]

    def get_my_role(self, obj) -> str | None:
        membership = self.context.get("membership")
        return membership.role if membership and membership.group_id == obj.pk else None

    def get_my_permissions(self, obj) -> list[str]:
        membership = self.context.get("membership")
        if not membership or membership.group_id != obj.pk:
            return []
        return sorted(membership.permissions)


class GroupCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Group
        fields = ["name", "description", "category", "visibility", "currency", "city", "country",
                  "requires_approval", "max_members", "requires_dual_approval_for_withdrawals"]
        extra_kwargs = {"currency": {"required": False}}

    def validate_currency(self, value):
        from django.conf import settings

        if value and value.upper() not in settings.KOLO["SUPPORTED_CURRENCIES"]:
            raise serializers.ValidationError("That currency is not supported yet.")
        return (value or "NGN").upper()


class MemberSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(source="user.full_name", read_only=True)
    avatar_url = serializers.CharField(source="user.avatar_url", read_only=True)
    email = serializers.SerializerMethodField()
    phone = serializers.SerializerMethodField()

    class Meta:
        model = Membership
        fields = ["id", "full_name", "avatar_url", "display_name", "role", "status", "joined_at",
                  "email", "phone", "share_financials"]

    def get_email(self, obj):
        # Contact details are visible to officers only.
        if not self.context.get("viewer_is_officer"):
            return None
        return obj.user.email

    def get_phone(self, obj):
        if not self.context.get("viewer_is_officer"):
            return None
        return obj.user.phone


class MembershipRoleSerializer(serializers.Serializer):
    role = serializers.ChoiceField(choices=Membership._meta.get_field("role").choices)
    permissions = serializers.DictField(child=serializers.BooleanField(), required=False)


class JoinSerializer(serializers.Serializer):
    message = serializers.CharField(required=False, allow_blank=True, max_length=500)


class InvitationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Invitation
        fields = ["id", "invited_email", "invited_phone", "token", "expires_at", "accepted_at", "created_at"]
        read_only_fields = ["token", "accepted_at", "created_at"]


class InvitationAcceptSerializer(serializers.Serializer):
    token = serializers.CharField()


class AnnouncementSerializer(serializers.ModelSerializer):
    author_name = serializers.CharField(source="author.full_name", read_only=True)

    class Meta:
        model = Announcement
        fields = ["id", "title", "body", "is_pinned", "author_name", "created_at"]


class MembershipRequestSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(source="user.full_name", read_only=True)
    avatar_url = serializers.CharField(source="user.avatar_url", read_only=True)

    class Meta:
        model = MembershipRequest
        fields = ["id", "full_name", "avatar_url", "message", "status", "created_at", "reviewed_at"]
