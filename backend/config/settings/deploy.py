"""Deployed sandbox. Real hosts, real TLS, still no real money.

Neither `dev` nor `prod` fits a hosted demonstration build: `prod` refuses to boot
unless FINANCIAL_ENV=production with a live payment provider, and `dev` trusts every
host and every origin. This module keeps the strict transport of `prod` and the
sandbox financial posture of `dev`, and refuses anything in between.
"""

from .base import *  # noqa: F401,F403

DEBUG = False

ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS")  # noqa: F405

SECURE_SSL_REDIRECT = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = 3600
SECURE_HSTS_INCLUDE_SUBDOMAINS = False

CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])  # noqa: F405

if SECRET_KEY == "dev-only-insecure-key-change-me":  # noqa: F405
    raise RuntimeError("DJANGO_SECRET_KEY must be set for a deployed build")
if KOLO_WEBHOOK_SECRET == "dev-only-mock-webhook-secret":  # noqa: F405
    raise RuntimeError("KOLO_WEBHOOK_SECRET must be set for a deployed build")
if FINANCIAL_ENV != "sandbox":
    raise RuntimeError("deploy settings are for the hosted sandbox; use prod for real money")
