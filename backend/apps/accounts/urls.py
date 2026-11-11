from django.urls import path

from . import views

app_name = "accounts"

urlpatterns = [
    path("register/", views.RegisterView.as_view(), name="register"),
    path("verify/", views.VerifyView.as_view(), name="verify"),
    path("resend/", views.ResendView.as_view(), name="resend"),
    path("login/", views.LoginView.as_view(), name="login"),
    path("refresh/", views.RefreshView.as_view(), name="refresh"),
    path("logout/", views.LogoutView.as_view(), name="logout"),
    path("me/", views.MeView.as_view(), name="me"),
    path("password/change/", views.PasswordChangeView.as_view(), name="password-change"),
    path("password/reset/", views.PasswordResetRequestView.as_view(), name="password-reset"),
    path("password/reset/confirm/", views.PasswordResetConfirmView.as_view(), name="password-reset-confirm"),
    path("sessions/", views.SessionListView.as_view(), name="sessions"),
    path("sessions/<uuid:session_id>/", views.SessionRevokeView.as_view(), name="session-revoke"),
    path("push-token/", views.PushTokenView.as_view(), name="push-token"),
    path("deactivate/", views.DeactivateView.as_view(), name="deactivate"),
]
