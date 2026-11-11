"""Test settings: deterministic, fast, no external services required."""

from .base import *  # noqa: F401,F403

DEBUG = False
ALLOWED_HOSTS = ["*"]

# Real PostgreSQL (not SQLite): row locking, deferred constraints and
# transactional behaviour are part of what these tests must prove.
DATABASES["default"]["NAME"] = env("TEST_DATABASE_NAME", default="kolo_test")  # noqa: F405

CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}
CELERY_TASK_ALWAYS_EAGER = True
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]

KOLO["OTP_PROVIDER"] = "console"  # noqa: F405
PAYMENT_PROVIDER = "mock"
FINANCIAL_ENV = "sandbox"

LOGGING["root"]["level"] = "ERROR"  # noqa: F405
LOGGING["loggers"]["kolo.audit"]["level"] = "ERROR"  # noqa: F405
