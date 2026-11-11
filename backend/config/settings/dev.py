"""Local development. Lenient about transport, still real about money."""

from .base import *  # noqa: F401,F403

DEBUG = True
ALLOWED_HOSTS = ["*"]

# Local Flutter web / hot-reload clients talk to this API from another origin.
CORS_ALLOW_ALL_ORIGINS = DEBUG
CSRF_TRUSTED_ORIGINS = ["http://localhost:8000", "http://127.0.0.1:8000", "http://localhost:3000"]

EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"
