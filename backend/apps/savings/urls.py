from django.urls import path

from . import views

app_name = "savings"

urlpatterns = [
    path("programmes/", views.ProgrammeListCreateView.as_view(), name="programmes"),
    path("programmes/<uuid:programme_id>/", views.ProgrammeDetailView.as_view(), name="programme"),
    path("programmes/<uuid:programme_id>/status/", views.ProgrammeTransitionView.as_view(), name="programme-status"),
    path("programmes/<uuid:programme_id>/participants/", views.ProgrammeParticipantView.as_view(), name="participants"),
    path("programmes/<uuid:programme_id>/rotation/", views.RotationOrderView.as_view(), name="rotation"),
    path("programmes/<uuid:programme_id>/cycles/", views.ProgrammeCycleView.as_view(), name="cycles"),
    path("programmes/<uuid:programme_id>/contributions/", views.ContributionCreateView.as_view(), name="contribute"),
    path("programmes/<uuid:programme_id>/contributions/offline/", views.OfflineContributionView.as_view(), name="contribute-offline"),
    path("programmes/<uuid:programme_id>/withdrawals/", views.WithdrawalListCreateView.as_view(), name="withdrawals"),
    path("cycles/<uuid:cycle_id>/approve/", views.CycleApproveView.as_view(), name="cycle-approve"),
    path("cycles/<uuid:cycle_id>/execute/", views.CycleExecuteView.as_view(), name="cycle-execute"),
    path("withdrawals/<uuid:withdrawal_id>/decide/", views.WithdrawalDecisionView.as_view(), name="withdrawal-decide"),
    path("withdrawals/<uuid:withdrawal_id>/execute/", views.WithdrawalExecuteView.as_view(), name="withdrawal-execute"),
    path("obligations/", views.MyObligationView.as_view(), name="obligations"),
    path("contributions/", views.MyContributionView.as_view(), name="contributions"),
    path("campaigns/", views.CampaignListCreateView.as_view(), name="campaigns"),
    path("groups/<slug:slug>/summary/", views.ProgrammeSummaryView.as_view(), name="group-summary"),
]
