from django.urls import path

from . import views

app_name = "groups"

urlpatterns = [
    path("", views.GroupListCreateView.as_view(), name="list-create"),
    path("invitations/", views.InvitationListView.as_view(), name="invitations"),
    path("invitations/accept/", views.InvitationAcceptView.as_view(), name="invitation-accept"),
    path("<slug:slug>/", views.GroupDetailView.as_view(), name="detail"),
    path("<slug:slug>/archive/", views.GroupArchiveView.as_view(), name="archive"),
    path("<slug:slug>/members/", views.GroupMemberListView.as_view(), name="members"),
    path("<slug:slug>/members/<uuid:member_id>/role/", views.GroupMemberRoleView.as_view(), name="member-role"),
    path("<slug:slug>/members/<uuid:member_id>/", views.GroupMemberRemoveView.as_view(), name="member-remove"),
    path("<slug:slug>/leave/", views.GroupLeaveView.as_view(), name="leave"),
    path("<slug:slug>/join/", views.GroupJoinView.as_view(), name="join"),
    path("<slug:slug>/requests/", views.GroupRequestListView.as_view(), name="requests"),
    path("<slug:slug>/requests/<uuid:request_id>/review/", views.GroupRequestReviewView.as_view(), name="request-review"),
    path("<slug:slug>/invitations/", views.GroupInviteView.as_view(), name="invite"),
    path("<slug:slug>/announcements/", views.GroupAnnouncementView.as_view(), name="announcements"),
]
