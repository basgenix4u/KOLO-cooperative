"""OTP delivery, behind a provider-independent interface.

Nothing in the domain layer knows which vendor sends the code. Swapping
providers is an environment change, and an unavailable provider degrades to the
console provider in development instead of breaking sign-up.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Protocol

from django.conf import settings

logger = logging.getLogger("kolo.security")


@dataclass(frozen=True)
class OtpMessage:
    destination: str
    channel: str  # "phone" | "email"
    code: str
    purpose: str


class OtpProvider(Protocol):
    name: str

    def send(self, message: OtpMessage) -> None: ...


class ConsoleOtpProvider:
    """Development provider.

    Prints the code to the server log. Refuses to run in production: a
    production deployment that logs OTPs is a credential leak by design.
    """

    name = "console"

    def send(self, message: OtpMessage) -> None:
        if settings.FINANCIAL_ENV == "production":
            raise RuntimeError("ConsoleOtpProvider must never be used in production")
        logger.warning(
            '{"event":"otp_issued","channel":"%s","destination":"%s","purpose":"%s","code":"%s","note":"development provider"}',
            message.channel,
            _mask(message.destination),
            message.purpose,
            message.code,
        )


class TwilioSmsProvider:
    """SMS via Twilio. Activated by credentials; never assumed to be live."""

    name = "twilio"

    def send(self, message: OtpMessage) -> None:
        from twilio.rest import Client  # imported lazily: optional dependency

        client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
        client.messages.create(
            to=message.destination,
            from_=settings.TWILIO_FROM_NUMBER,
            body=f"Your KOLO code is {message.code}. It expires in "
            f"{settings.KOLO['OTP_TTL_SECONDS'] // 60} minutes. Never share it.",
        )


class EmailOtpProvider:
    """Email codes use the configured mail backend (Render/SES/SMTP)."""

    name = "email"

    def send(self, message: OtpMessage) -> None:
        from django.core.mail import send_mail

        send_mail(
            subject="Your KOLO verification code",
            message=(
                f"Your KOLO code is {message.code}.\n\n"
                f"It expires in {settings.KOLO['OTP_TTL_SECONDS'] // 60} minutes. "
                "If you did not request it, ignore this message and consider changing your password."
            ),
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[message.destination],
            fail_silently=False,
        )


_PROVIDERS: dict[str, OtpProvider] = {
    "console": ConsoleOtpProvider(),
    "twilio": TwilioSmsProvider(),
    "email": EmailOtpProvider(),
}


def get_provider(channel: str) -> OtpProvider:
    """Pick a provider for the channel, honouring the environment setting."""
    configured = (settings.OTP_PROVIDER or "console").lower()
    if channel == "email":
        return _PROVIDERS["email"]
    if configured == "twilio" and getattr(settings, "TWILIO_ACCOUNT_SID", ""):
        return _PROVIDERS["twilio"]
    if configured == "twilio":
        logger.error('{"event":"otp_provider_unconfigured","provider":"twilio","fallback":"console"}')
    return _PROVIDERS["console"]


def send_otp(message: OtpMessage) -> None:
    get_provider(message.channel).send(message)


def _mask(value: str) -> str:
    if "@" in value:
        name, _, domain = value.partition("@")
        return f"{name[:2]}***@{domain}"
    return value[:-4] + "****" if len(value) > 4 else "****"
