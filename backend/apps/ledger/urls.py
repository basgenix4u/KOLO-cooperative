from django.urls import path

from . import views

app_name = "ledger"

urlpatterns = [
    path("accounts/", views.AccountListView.as_view(), name="accounts"),
    path("transactions/", views.TransactionListView.as_view(), name="transactions"),
    path("transactions/<str:reference>/", views.TransactionDetailView.as_view(), name="transaction"),
    path("statements/", views.StatementView.as_view(), name="statement"),
]
