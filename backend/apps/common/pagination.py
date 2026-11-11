from rest_framework.pagination import LimitOffsetPagination
from rest_framework.response import Response


class StandardPagination(LimitOffsetPagination):
    """Limit/offset with a `meta` block the mobile client can page with."""

    default_limit = 20
    max_limit = 100

    def get_paginated_response(self, data):
        return Response(
            {
                "data": data,
                "meta": {
                    "count": self.count,
                    "limit": self.limit,
                    "offset": self.offset,
                    "next": self.get_next_link(),
                    "previous": self.get_previous_link(),
                },
            }
        )
