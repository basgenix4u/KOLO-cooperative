from django.urls import path

from . import views

app_name = "documents"

urlpatterns = [
    path("", views.DocumentListView.as_view(), name="list"),
    path("upload/", views.DocumentUploadView.as_view(), name="upload"),
    path("<uuid:document_id>/", views.DocumentDownloadView.as_view(), name="download"),
    path("<uuid:document_id>/content/", views.DocumentContentView.as_view(), name="content"),
]
