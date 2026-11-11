"""API surface. Everything is versioned under /api/v1."""

from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView


def health(_request):
    """Liveness: cheap, unauthenticated, and honest about the database."""
    from django.db import connection

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        db_ok = True
    except Exception:  # noqa: BLE001
        db_ok = False
    return JsonResponse({"status": "ok" if db_ok else "degraded", "database": db_ok})


def readiness(_request):
    """Readiness: does this instance have what it needs to serve traffic?"""
    from django.core.cache import cache
    from django.db import connection

    checks = {"database": False, "cache": False}
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        checks["database"] = True
    except Exception:  # noqa: BLE001
        pass
    try:
        cache.set("readiness", "1", timeout=5)
        checks["cache"] = cache.get("readiness") == "1"
    except Exception:  # noqa: BLE001
        pass
    ok = all(checks.values())
    return JsonResponse({"status": "ready" if ok else "degraded", **checks}, status=200 if ok else 503)


urlpatterns = [
    path("health/", health, name="health"),
    path("ready/", readiness, name="readiness"),
    path("admin/", admin.site.urls),
    path("api/v1/auth/", include("apps.accounts.urls")),
    path("api/v1/groups/", include("apps.groups.urls")),
    path("api/v1/savings/", include("apps.savings.urls")),
    path("api/v1/payments/", include("apps.payments.urls")),
    path("api/v1/loans/", include("apps.loans.urls")),
    path("api/v1/governance/", include("apps.governance.urls")),
    path("api/v1/comms/", include("apps.comms.urls")),
    path("api/v1/notifications/", include("apps.notifications.urls")),
    path("api/v1/documents/", include("apps.documents.urls")),
    path("api/v1/ledger/", include("apps.ledger.urls")),
    path("api/v1/support/", include("apps.support.urls")),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema"), name="swagger-ui"),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
