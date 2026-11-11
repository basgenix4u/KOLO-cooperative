from rest_framework.throttling import ScopedRateThrottle


class ScopedBurstThrottle(ScopedRateThrottle):
    """Rate limits keyed by authenticated user, else by IP.

    OTP and authentication endpoints are the ones that matter: they are the
    cheapest place for an attacker to burn money or guess a code.
    """

    scope_attr = "throttle_scope"

    def get_cache_key(self, request, view):
        ident = request.user.pk if request.user and request.user.is_authenticated else self.get_ident(request)
        scope = getattr(view, "throttle_scope", None)
        if scope is None:
            return None  # not a throttled view
        return self.cache_format % {"scope": scope, "ident": ident}
