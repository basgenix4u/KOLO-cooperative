from django.urls import path

from . import views

app_name = "support"

urlpatterns = [
    path("disputes/", views.DisputeListCreateView.as_view(), name="disputes"),
    path("cases/", views.SupportCaseListCreateView.as_view(), name="cases"),
    path("cases/<uuid:case_id>/messages/", views.SupportMessageView.as_view(), name="case-messages"),
]
