from django.urls import path

from . import views

app_name = "loans"

urlpatterns = [
    path("groups/<slug:slug>/products/", views.ProductListView.as_view(), name="products"),
    path("groups/<slug:slug>/applications/", views.ApplicationListCreateView.as_view(), name="applications"),
    path("groups/<slug:slug>/loans/", views.LoanListView.as_view(), name="group-loans"),
    path("applications/<uuid:application_id>/decide/", views.ApplicationDecisionView.as_view(), name="decide"),
    path("guarantors/<uuid:guarantor_id>/respond/", views.GuarantorRespondView.as_view(), name="guarantor-respond"),
    path("loans/<uuid:loan_id>/disburse/", views.LoanDisburseView.as_view(), name="disburse"),
    path("loans/<uuid:loan_id>/repay/", views.RepaymentCreateView.as_view(), name="repay"),
    path("mine/", views.MyLoanListView.as_view(), name="mine"),
]
