"""Auth and profile serialisation.

Nothing here ever returns a password, a token hash, or an OTP code.
"""

from __future__ import annotations

from django.contrib.auth.password_validation import validate_password
from django.utils import timezone
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import DeviceSession, User, VerificationCode


class UserSummarySerializer(serializers.ModelSerializer):
    """What other members may see about a person."""

    class Meta:
        model = User
        fields = ["id", "full_name", "avatar_url"]


class ProfileSerializer(serializers.ModelSerializer):
    initials = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id", "email", "phone", "full_name", "avatar_url", "country", "preferred_currency",
            "timezone", "locale", "is_email_verified", "is_phone_verified", "verification_level",
            "mfa_enabled", "status", "initials", "created_at",
        ]
        read_only_fields = [
            "id", "is_email_verified", "is_phone_verified", "verification_level", "status", "created_at",
        ]

    def get_initials(self, obj) -> str:
        if obj.full_name:
            parts = [p for p in obj.full_name.split() if p]
            return "".join(p[0].upper() for p in parts[:2])
        return (obj.email or obj.phone or "?")[0].upper()

    def validate_country(self, value):
        return (value or "").upper()[:2]

    def validate_preferred_currency(self, value):
        value = (value or "").upper()
        from django.conf import settings

        if value not in settings.KOLO["SUPPORTED_CURRENCIES"]:
            raise serializers.ValidationError("That currency is not supported yet.")
        return value


class RegisterSerializer(serializers.Serializer):
    email = serializers.EmailField(required=False, allow_blank=True)
    phone = serializers.CharField(required=False, allow_blank=True, max_length=20)
    password = serializers.CharField(write_only=True, trim_whitespace=False)
    full_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    country = serializers.CharField(required=False, allow_blank=True, max_length=2)
    preferred_currency = serializers.CharField(required=False, max_length=3, default="NGN")
    timezone = serializers.CharField(required=False, allow_blank=True, max_length=64)

    def validate(self, attrs):
        if not attrs.get("email") and not attrs.get("phone"):
            raise serializers.ValidationError(
                {"email": "Provide an email address or a phone number."}, code="identifier_required"
            )
        phone = (attrs.get("phone") or "").strip()
        if phone and not phone.startswith("+") or (phone and not phone[1:].isdigit()):
            raise serializers.ValidationError(
                {"phone": "Use international format, for example +2348012345678."}, code="phone_invalid"
            )
        validate_password(attrs["password"])
        return attrs


class VerifySerializer(serializers.Serializer):
    code = serializers.CharField(max_length=10)
    purpose = serializers.ChoiceField(choices=VerificationCode.Purpose.choices, default=VerificationCode.Purpose.SIGNUP)


class ResendSerializer(serializers.Serializer):
    channel = serializers.ChoiceField(choices=VerificationCode.Channel.choices)
    purpose = serializers.ChoiceField(choices=VerificationCode.Purpose.choices, default=VerificationCode.Purpose.SIGNUP)


class LoginSerializer(serializers.Serializer):
    identifier = serializers.CharField(help_text="Email address or phone number")
    password = serializers.CharField(write_only=True, trim_whitespace=False)
    device_name = serializers.CharField(required=False, allow_blank=True, max_length=120)
    platform = serializers.ChoiceField(required=False, choices=["ios", "android", "web"], default="android")
    app_version = serializers.CharField(required=False, allow_blank=True, max_length=20)
    push_token = serializers.CharField(required=False, allow_blank=True, max_length=255)


class RefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField(required=False, allow_blank=True)
    all_devices = serializers.BooleanField(default=False)


class PasswordChangeSerializer(serializers.Serializer):
    current_password = serializers.CharField(trim_whitespace=False)
    new_password = serializers.CharField(trim_whitespace=False)

    def validate_new_password(self, value):
        validate_password(value)
        return value


class PasswordResetRequestSerializer(serializers.Serializer):
    identifier = serializers.CharField()


class PasswordResetConfirmSerializer(serializers.Serializer):
    identifier = serializers.CharField()
    code = serializers.CharField(max_length=10)
    new_password = serializers.CharField(trim_whitespace=False)

    def validate_new_password(self, value):
        validate_password(value)
        return value


class DeviceSessionSerializer(serializers.ModelSerializer):
    is_current = serializers.SerializerMethodField()

    class Meta:
        model = DeviceSession
        fields = [
            "id", "device_name", "platform", "app_version", "ip_address", "last_seen_at",
            "revoked_at", "created_at", "is_current",
        ]
        read_only_fields = fields

    def get_is_current(self, obj) -> bool:
        current = self.context.get("current_session_id")
        return str(obj.pk) == str(current) if current else False


class PushTokenSerializer(serializers.Serializer):
    push_token = serializers.CharField(max_length=255)


class KoloTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Added claims the mobile app uses to render before its first request."""

    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token["name"] = user.full_name or ""
        token["cur"] = user.preferred_currency
        token["ver"] = user.verification_level
        return token

    def validate(self, attrs):
        data = super().validate(attrs)
        data["user"] = ProfileSerializer(self.user).data
        return data
