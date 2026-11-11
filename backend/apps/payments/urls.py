from django.urls import path

from . import views

app_name = "payments"

urlpatterns = [
    path("intents/", views.IntentCreateView.as_view(), name="intent-create"),
    path("intents/<str:reference>/", views.IntentDetailView.as_view(), name="intent-detail"),
    path("verify/", views.IntentVerifyView.as_view(), name="verify"),
    path("webhooks/<str:provider>/", views.WebhookView.as_view(), name="webhook"),
    path("reconcile/<slug:slug>/", views.ReconciliationTriggerView.as_view(), name="reconcile"),
]
