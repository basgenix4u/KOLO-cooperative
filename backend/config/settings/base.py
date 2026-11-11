"""
Base settings for KOLO.

Environment-driven, so the same code runs a laptop, a CI runner and Render.
Nothing secret is ever committed: every credential arrives as an environment
variable and the defaults here are safe-for-development only.
"""

from datetime import timedelta
from pathlib import Path

import environ

# backend/config/settings/base.py -> backend/
BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env(
    DJANGO_DEBUG=(bool, False),
    DJANGO_ALLOWED_HOSTS=(list, ["localhost", "127.0.0.1"]),
    CORS_ALLOWED_ORIGINS=(list, []),
    FINANCIAL_ENV=(str, "sandbox"),
    PAYMENT_PROVIDER=(str, "mock"),
    # Where the mock provider's hosted-checkout page lives. Development only:
    # production refuses to run with the mock provider, so this can never point
    # a real member at a sandbox page.
    MOCK_CHECKOUT_BASE=(str, "http://localhost:8000/mock-checkout"),
    OTP_PROVIDER=(str, "console"),
    # Shared secret for provider callbacks. A webhook signature is the only
    # authentication those requests have, so production must supply a real one.
    KOLO_WEBHOOK_SECRET=(str, "dev-only-mock-webhook-secret"),
    OTP_TTL_SECONDS=(int, 600),
    OTP_MAX_ATTEMPTS=(int, 5),
    OTP_RESEND_COOLDOWN_SECONDS=(int, 60),
)

# Load .env if present (local development only; production uses real env vars).
environ.Env.read_env(BASE_DIR / ".env")

SECRET_KEY = env("DJANGO_SECRET_KEY", default="dev-only-insecure-key-change-me")
DEBUG = env("DJANGO_DEBUG")
ALLOWED_HOSTS = env("DJANGO_ALLOWED_HOSTS")

DJANGO_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
]

THIRD_PARTY_APPS = [
    "rest_framework",
    "corsheaders",
    "drf_spectacular",
    "channels",
]

LOCAL_APPS = [
    "apps.common",
    "apps.accounts",
    "apps.groups",
    "apps.savings",
    "apps.ledger",
    "apps.payments",
    "apps.loans",
    "apps.governance",
    "apps.comms",
    "apps.documents",
    "apps.notifications",
    "apps.support",
]

INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "apps.common.middleware.RequestIDMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

# ---------------------------------------------------------------------------
# Database — PostgreSQL only. Money and concurrency are core requirements; a
# SQLite fallback would hide locking and constraint behaviour that production
# depends on.
# ---------------------------------------------------------------------------
DATABASES = {"default": env.db("DATABASE_URL", default="postgres://kolo:kolo_dev_password@127.0.0.1:5432/kolo")}
DATABASES["default"]["ATOMIC_REQUESTS"] = False  # transactions are explicit, not implicit
DATABASES["default"]["CONN_MAX_AGE"] = env.int("DB_CONN_MAX_AGE", default=60)

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

AUTH_USER_MODEL = "accounts.User"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 10},
    },
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
    "DEFAULT_PAGINATION_CLASS": "apps.common.pagination.StandardPagination",
    "PAGE_SIZE": 20,
    "DEFAULT_FILTER_BACKENDS": ["rest_framework.filters.SearchFilter", "rest_framework.filters.OrderingFilter"],
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "DEFAULT_THROTTLE_CLASSES": ["apps.common.throttling.ScopedBurstThrottle"],
    "DEFAULT_THROTTLE_RATES": {
        "auth": "10/min",
        "otp": "5/min",
        "payment": "20/min",
        "read": "240/min",
        "write": "60/min",
    },
    "EXCEPTION_HANDLER": "apps.common.exceptions.api_exception_handler",
    "TEST_REQUEST_DEFAULT_FORMAT": "json",
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=env.int("ACCESS_TOKEN_MINUTES", default=15)),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=env.int("REFRESH_TOKEN_DAYS", default=30)),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "UPDATE_LAST_LOGIN": True,
    "ALGORITHM": "HS256",
    "SIGNING_KEY": env("JWT_SIGNING_KEY", default=SECRET_KEY),
    "AUTH_HEADER_TYPES": ("Bearer",),
    "USER_ID_FIELD": "id",
    "USER_ID_CLAIM": "sub",
    "TOKEN_OBTAIN_SERIALIZER": "apps.accounts.serializers.KoloTokenObtainPairSerializer",
}

SPECTACULAR_SETTINGS = {
    "TITLE": "KOLO API",
    "DESCRIPTION": "Digital infrastructure for collective savings and cooperative finance.",
    "VERSION": "1.0.0",
    "SERVE_INCLUDE_SCHEMA": False,
    "COMPONENT_SPLIT_REQUEST": True,
    "SORT_OPERATIONS": False,
}

CORS_ALLOWED_ORIGINS = env("CORS_ALLOWED_ORIGINS")
CORS_ALLOW_CREDENTIALS = True
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])

# ---------------------------------------------------------------------------
# Redis / cache / channels
# ---------------------------------------------------------------------------
REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379/0")

CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": REDIS_URL,
        "OPTIONS": {"CLIENT_CLASS": "django_redis.client.DefaultClient", "IGNORE_EXCEPTIONS": True},
        "KEY_PREFIX": "kolo",
    }
}

CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {"hosts": [REDIS_URL]},
    }
}

CELERY_BROKER_URL = env("CELERY_BROKER_URL", default=REDIS_URL)
CELERY_RESULT_BACKEND = env("CELERY_RESULT_BACKEND", default=REDIS_URL)
CELERY_TASK_ALWAYS_EAGER = env.bool("CELERY_TASK_ALWAYS_EAGER", default=False)
CELERY_TASK_EAGER_PROPAGATES = True
CELERY_TASK_ACKS_LATE = True
CELERY_TASK_TIME_LIMIT = 300
CELERY_BEAT_SCHEDULE = {
    "sweep-expired-authorisations": {"task": "apps.savings.tasks.sweep_expired_requests", "schedule": 300.0},
    "remind-upcoming-contributions": {"task": "apps.savings.tasks.remind_upcoming_obligations", "schedule": 3600.0},
    "advance-due-rotations": {"task": "apps.savings.tasks.advance_due_rotations", "schedule": 900.0},
    "mark-overdue-loans": {"task": "apps.loans.tasks.mark_overdue_installments", "schedule": 3600.0},
    "deliver-outbox": {"task": "apps.common.tasks.dispatch_pending_outbox", "schedule": 120.0},
}

# ---------------------------------------------------------------------------
# Domain configuration
# ---------------------------------------------------------------------------
# `sandbox` refuses to move real money: payment, payout and loan activation are
# gated behind explicit, audited operator actions. Never flip to `production`
# without a licensed partner agreement in place.
FINANCIAL_ENV = env("FINANCIAL_ENV")
PAYMENT_PROVIDER = env("PAYMENT_PROVIDER")
MOCK_CHECKOUT_BASE = env("MOCK_CHECKOUT_BASE")
OTP_PROVIDER = env("OTP_PROVIDER")

KOLO_WEBHOOK_SECRET = env("KOLO_WEBHOOK_SECRET")

KOLO = {
    "OTP_TTL_SECONDS": env("OTP_TTL_SECONDS"),
    "OTP_MAX_ATTEMPTS": env("OTP_MAX_ATTEMPTS"),
    "OTP_RESEND_COOLDOWN_SECONDS": env("OTP_RESEND_COOLDOWN_SECONDS"),
    # Rotation payouts require a second, different officer to authorise.
    "REQUIRE_DUAL_CONTROL_PAYOUTS": env.bool("REQUIRE_DUAL_CONTROL_PAYOUTS", default=True),
    "DEFAULT_CURRENCY": env("DEFAULT_CURRENCY", default="NGN"),
    "SUPPORTED_CURRENCIES": env.list("SUPPORTED_CURRENCIES", default=["NGN", "USD", "GBP", "EUR", "KES", "GHS", "ZAR"]),
    "MAX_UPLOAD_BYTES": env.int("MAX_UPLOAD_BYTES", default=10 * 1024 * 1024),
    # Lending stays off until a licensed arrangement exists. This flag is the
    # single switch; see apps/loans/services.lending_enabled.
    "LENDING_ENABLED": env.bool("LENDING_ENABLED", default=False),
}

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"  # store UTC; clients render in the member's own zone
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "media/"
MEDIA_ROOT = Path(env("MEDIA_ROOT", default=str(BASE_DIR / "media")))

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}

# ---------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_HTTPONLY = False
X_FRAME_OPTIONS = "DENY"
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "strict-origin-when-cross-origin"

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {
            "format": '{"level":"%(levelname)s","logger":"%(name)s","msg":%(message)r,"time":"%(asctime)s","request_id":"%(request_id)s"}',
        },
        "plain": {"format": "%(levelname)s %(name)s %(message)s"},
    },
    "filters": {"request_id": {"()": "apps.common.logging.RequestIDFilter"}},
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "json" if not DEBUG else "plain",
            "filters": ["request_id"],
        }
    },
    "root": {"handlers": ["console"], "level": env("LOG_LEVEL", default="INFO")},
    "loggers": {
        "django.db.backends": {"level": "WARNING", "handlers": ["console"], "propagate": False},
        # Financial and security events get their own logger so they can be
        # forwarded to an alerting sink without shipping all application noise.
        "kolo.audit": {"level": "INFO", "handlers": ["console"], "propagate": False},
        "kolo.security": {"level": "INFO", "handlers": ["console"], "propagate": False},
    },
}

SENTRY_DSN = env("SENTRY_DSN", default="")
if SENTRY_DSN:  # pragma: no cover - wiring, exercised by deployment
    import sentry_sdk
    from sentry_sdk.integrations.celery import CeleryIntegration
    from sentry_sdk.integrations.django import DjangoIntegration

    sentry_sdk.init(
        dsn=SENTRY_DSN,
        integrations=[DjangoIntegration(), CeleryIntegration()],
        traces_sample_rate=env.float("SENTRY_TRACES_RATE", default=0.05),
        send_default_pii=False,
        environment=env("SENTRY_ENVIRONMENT", default="development"),
    )
