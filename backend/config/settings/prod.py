"""Production. Assumes TLS terminates at the platform proxy (Render does this)."""

from .base import *  # noqa: F401,F403

DEBUG = False
ALLOWED_HOSTS = env("DJANGO_ALLOWED_HOSTS")  # noqa: F405

SECURE_SSL_REDIRECT = True
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])  # noqa: F405

# Refuse to boot with the development fallbacks in place: a production deploy
# that silently signs tokens with a known key is worse than one that fails.
if SECRET_KEY == "dev-only-insecure-key-change-me":
    raise RuntimeError("DJANGO_SECRET_KEY must be set in production")
if PAYMENT_PROVIDER == "mock":
    raise RuntimeError("PAYMENT_PROVIDER=mock cannot run with FINANCIAL_ENV=production")
if KOLO_WEBHOOK_SECRET == "dev-only-mock-webhook-secret":  # noqa: F405
    # An unsigned webhook secret means anyone who can POST can mark payments
    # paid. Refuse to serve rather than run with a public secret.
    raise RuntimeError("KOLO_WEBHOOK_SECRET must be set to a real secret in production")
if FINANCIAL_ENV != "production":
    raise RuntimeError("prod settings require FINANCIAL_ENV=production; sandbox must use dev/test settings")
