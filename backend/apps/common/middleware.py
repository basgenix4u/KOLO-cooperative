import uuid

from .logging import request_id_var


class RequestIDMiddleware:
    """Attach an id to every request so one log line can be traced end to end.

    Also echoes it back: when a member reports a problem, the reference in their
    message is enough to find the exact request without asking for a timestamp.
    """

    HEADER = "X-Request-ID"

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        incoming = request.headers.get(self.HEADER, "")
        request_id = incoming if _looks_like_id(incoming) else uuid.uuid4().hex
        request.request_id = request_id
        token = request_id_var.set(request_id)
        try:
            response = self.get_response(request)
        finally:
            request_id_var.reset(token)
        response[self.HEADER] = request_id
        return response


def _looks_like_id(value: str) -> bool:
    return 8 <= len(value) <= 64 and all(c.isalnum() or c in "-_" for c in value)
