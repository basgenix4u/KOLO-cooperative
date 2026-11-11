from django.urls import path

from . import views

app_name = "notifications"

urlpatterns = [
    path("", views.NotificationListView.as_view(), name="list"),
    path("read/", views.NotificationReadView.as_view(), name="read-all"),
    path("<uuid:notification_id>/read/", views.NotificationReadView.as_view(), name="read"),
    path("preferences/", views.PreferenceView.as_view(), name="preferences"),
]
