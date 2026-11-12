"""Authentication endpoints."""

from __future__ import annotations

import logging

from django.conf import settings
from django.utils import timezone
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken as JWTRestRefreshToken

from apps.accounts.models import DeviceSession, VerificationCode
from apps.accounts.serializers import (
    DeviceSessionSerializer,
    LoginSerializer,
    LogoutSerializer,
    PasswordChangeSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
    ProfileSerializer,
    PushTokenSerializer,
    RefreshSerializer,
    RegisterSerializer,
    ResendSerializer,
    VerifySerializer,
)
from apps.accounts.services import (
    assert_not_locked,
    change_password,
    hash_token,
    issue_refresh_token,
    issue_verification,
    record_attempt,
    register,
    request_password_reset,
    reset_password,
    revoke_all_sessions,
    rotate_refresh_token,
    verify_code,
)
from apps.common.exceptions import NotFoundError, DomainError, PermissionDeniedError
from apps.common.throttling import ScopedBurstThrottle

logger = logging.getLogger("kolo.security")


def _client_ip(request):
    forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
    return forwarded.split(",")[0].strip() if forwarded else request.META.get("REMOTE_ADDR")


def _token_payload(user, raw_refresh, device_id=None):
    access = JWTRestRefreshToken.for_user(user).access_token
    return {
        "access": str(access),
        "refresh": raw_refresh,
        "device_id": str(device_id) if device_id else None,
        "user": ProfileSerializer(user).data,
    }


class RegisterView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "auth"

    @extend_schema(request=RegisterSerializer, responses={201: OpenApiResponse(description="Account created")})
    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        user = register(
            email=data.get("email") or None,
            phone=data.get("phone") or None,
            password=data["password"],
            full_name=data.get("full_name", ""),
            country=data.get("country", ""),
            preferred_currency=data.get("preferred_currency", "NGN"),
            timezone_name=data.get("timezone") or "UTC",
            request=request,
        )
        return Response(
            {
                "data": {
                    "user": ProfileSerializer(user).data,
                    "verification_sent": True,
                    "channels": [c for c in ["email" if user.email else "", "phone" if user.phone else ""] if c],
                }
            },
            status=status.HTTP_201_CREATED,
        )


class VerifyView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "otp"

    @extend_schema(request=VerifySerializer)
    def post(self, request):
        serializer = VerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        verify_code(
            user=request.user,
            code=serializer.validated_data["code"],
            purpose=serializer.validated_data["purpose"],
        )
        request.user.refresh_from_db()
        return Response({"data": {"user": ProfileSerializer(request.user).data}})


class ResendView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "otp"

    @extend_schema(request=ResendSerializer)
    def post(self, request):
        serializer = ResendSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        issue_verification(
            user=request.user,
            channel=serializer.validated_data["channel"],
            purpose=serializer.validated_data["purpose"],
            request=request,
        )
        return Response({"data": {"sent": True}})


class LoginView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "auth"

    @extend_schema(request=LoginSerializer)
    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        identifier = data["identifier"].strip()

        # Refuse early on a locked identifier, before any password work.
        assert_not_locked(identifier)

        from django.contrib.auth import authenticate

        user = authenticate(request, username=identifier.lower() if "@" in identifier else identifier,
                            password=data["password"])
        if user is None:
            record_attempt(identifier, succeeded=False, ip=_client_ip(request))
            # One message for both cases: a distinct "no such account" is an
            # enumeration oracle.
            raise PermissionDeniedError("Those sign-in details are not correct.", code="invalid_credentials")
        if not user.is_active:
            raise PermissionDeniedError("This account is not active.", code="account_inactive")

        record_attempt(identifier, succeeded=True, ip=_client_ip(request))
        device = DeviceSession.objects.create(
            user=user,
            device_name=data.get("device_name", "")[:120],
            platform=data.get("platform", ""),
            app_version=data.get("app_version", "")[:20],
            push_token=data.get("push_token", "")[:255],
            ip_address=_client_ip(request),
            user_agent=request.META.get("HTTP_USER_AGENT", "")[:255],
        )
        user.last_login_ip = _client_ip(request)
        user.save(update_fields=["last_login_ip"])
        raw_refresh, _ = issue_refresh_token(user=user, device=device)

        logger.info('{"event":"login_success","user":"%s","platform":"%s"}', user.pk, data.get("platform", ""))
        return Response({"data": _token_payload(user, raw_refresh, device.pk)})


class RefreshView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "auth"

    @extend_schema(request=RefreshSerializer)
    def post(self, request):
        serializer = RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user, raw_refresh, record = rotate_refresh_token(raw_token=serializer.validated_data["refresh"])
        return Response({"data": _token_payload(user, raw_refresh, record.device_id)})


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(request=LogoutSerializer)
    def post(self, request):
        serializer = LogoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload = serializer.validated_data

        if payload.get("all_devices"):
            revoke_all_sessions(request.user, reason="Member signed out everywhere")
        elif payload.get("refresh"):
            from apps.accounts.models import RefreshToken as StoredRefresh

            StoredRefresh.objects.filter(
                token_hash=hash_token(payload["refresh"]), user=request.user
            ).update(revoked_at=timezone.now())
        else:
            revoke_all_sessions(request.user, reason="Member signed out")
        return Response({"data": {"signed_out": True}})


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(responses=ProfileSerializer)
    def get(self, request):
        return Response({"data": ProfileSerializer(request.user).data})

    @extend_schema(request=ProfileSerializer, responses=ProfileSerializer)
    def patch(self, request):
        serializer = ProfileSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response({"data": serializer.data})


class PasswordChangeView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "auth"

    @extend_schema(request=PasswordChangeSerializer)
    def post(self, request):
        serializer = PasswordChangeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        change_password(
            user=request.user,
            current_password=serializer.validated_data["current_password"],
            new_password=serializer.validated_data["new_password"],
            request=request,
        )
        return Response({"data": {"changed": True, "sessions_revoked": True}})


class PasswordResetRequestView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "otp"

    @extend_schema(request=PasswordResetRequestSerializer)
    def post(self, request):
        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        request_password_reset(serializer.validated_data["identifier"], request=request)
        # Always the same answer, whether or not the account exists.
        return Response({"data": {"sent": True}})


class PasswordResetConfirmView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedBurstThrottle]
    throttle_scope = "otp"

    @extend_schema(request=PasswordResetConfirmSerializer)
    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        reset_password(identifier=data["identifier"], code=data["code"], new_password=data["new_password"],
                       request=request)
        return Response({"data": {"reset": True}})


class SessionListView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(responses=DeviceSessionSerializer(many=True))
    def get(self, request):
        sessions = DeviceSession.objects.filter(user=request.user, revoked_at__isnull=True)
        return Response({"data": DeviceSessionSerializer(sessions, many=True).data})


class SessionRevokeView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, session_id):
        updated = DeviceSession.objects.filter(pk=session_id, user=request.user).update(revoked_at=timezone.now())
        if not updated:
            raise DomainError("That session is not available.", code="session_not_found")
        from apps.accounts.models import RefreshToken as StoredRefresh

        StoredRefresh.objects.filter(user=request.user, device_id=session_id, revoked_at__isnull=True).update(
            revoked_at=timezone.now()
        )
        return Response({"data": {"revoked": True}})


class PushTokenView(APIView):
    """Register the device's FCM token after login or token refresh."""

    permission_classes = [IsAuthenticated]

    @extend_schema(request=PushTokenSerializer)
    def post(self, request):
        serializer = PushTokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        device_id = request.data.get("device_id")
        # Previously this reported success unconditionally. A device id that
        # matched nothing — a stale id after reinstall, or a device belonging to
        # somebody else — got `{"registered": true}` and the member silently
        # never received a notification again. Say what happened instead.
        updated = DeviceSession.objects.filter(
            pk=device_id if device_id else None, user=request.user, revoked_at__isnull=True
        ).update(push_token=serializer.validated_data["push_token"][:255], last_seen_at=timezone.now())
        if not updated:
            raise NotFoundError(
                "That device session is no longer valid. Sign in again to receive notifications.",
                code="device_not_found",
            )
        return Response({"data": {"registered": True}})


class DeactivateView(APIView):
    """Deactivation is the member's decision, and it ends every session."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        password = request.data.get("password", "")
        if not password or not request.user.check_password(password):
            raise PermissionDeniedError("Confirm your password to continue.", code="password_incorrect")
        request.user.mark_deactivated()
        return Response({"data": {"deactivated": True}})
