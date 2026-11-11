from django.urls import path

from . import views

app_name = "governance"

urlpatterns = [
    path("groups/<slug:slug>/proposals/", views.ProposalListCreateView.as_view(), name="proposals"),
    path("proposals/<uuid:proposal_id>/", views.ProposalDetailView.as_view(), name="proposal"),
    path("proposals/<uuid:proposal_id>/open/", views.ProposalOpenView.as_view(), name="open"),
    path("proposals/<uuid:proposal_id>/close/", views.ProposalCloseView.as_view(), name="close"),
    path("proposals/<uuid:proposal_id>/vote/", views.BallotView.as_view(), name="vote"),
]
