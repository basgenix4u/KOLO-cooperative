"""Ledger read endpoints. Read-only by design: money moves through services."""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework.generics import ListAPIView, RetrieveAPIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.exceptions import PermissionDeniedError
from apps.groups.models import Group, Membership, Permission as GroupPermission
from apps.groups.permissions import membership_for, require_permission

from . import services as ledger
from .models import Account, JournalTransaction
from .serializers import AccountSerializer, TransactionSerializer


def _visible_account_ids(user):
    """Account ids this user may read.

    Scope rules, applied in one place:
      * a member sees their own holdings,
      * an officer with finance access sees their group's and its programmes',
      * nobody sees another group's money.
    """
    from django.db.models import Q

    memberships = Membership.objects.filter(user=user, status=Membership.Status.ACTIVE)
    member_rows = list(memberships.values_list("pk", "group_id", "role"))

    if not member_rows:
        return Account.objects.none().values_list("pk", flat=True)

    member_ids = [row[0] for row in member_rows]
    officer_group_ids = [
        m.group_id for m in memberships if "finance.view" in m.permissions
    ]

    visible = Q(scope_type="member", scope_id__in=member_ids)
    if officer_group_ids:
        programme_ids = list(
            Group.objects.filter(pk__in=officer_group_ids).values_list("programmes__pk", flat=True)
        )
        visible |= Q(scope_type="group", scope_id__in=officer_group_ids)
        visible |= Q(scope_type="programme", scope_id__in=[p for p in programme_ids if p])

    return Account.objects.filter(visible).values_list("pk", flat=True)


class AccountListView(APIView):
    """Accounts the caller is entitled to see."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        group_slug = request.query_params.get("group")
        if group_slug:
            group = get_object_or_404(Group, slug=group_slug)
            require_permission(request.user, group, GroupPermission.FINANCE_VIEW)

        accounts = Account.objects.filter(pk__in=list(_visible_account_ids(request.user)))
        return Response({"data": AccountSerializer(accounts.distinct().order_by("code"), many=True).data})


class TransactionListView(ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = TransactionSerializer

    def get_queryset(self):
        account_ids = list(_visible_account_ids(self.request.user))
        if not account_ids:
            return JournalTransaction.objects.none()
        return (
            JournalTransaction.objects.filter(entries__account_id__in=account_ids)
            .prefetch_related("entries__account")
            .distinct()
            .order_by("-created_at")
        )


class TransactionDetailView(RetrieveAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = TransactionSerializer
    lookup_field = "reference"
    queryset = JournalTransaction.objects.prefetch_related("entries__account")


class StatementView(APIView):
    """A member's statement inside one group: their own money, their own view."""

    permission_classes = [IsAuthenticated]

    def get(self, request, ):
        group = get_object_or_404(Group, slug=request.query_params.get("group", ""))
        membership = membership_for(request.user, group)
        if not membership:
            raise PermissionDeniedError("You are not a member of this group.", code="not_a_member")

        account = Account.objects.filter(scope_type="member", scope_id=membership.pk).first()
        entries = (
            account.entries.select_related("transaction", "account").order_by("-created_at")[:200]
            if account else []
        )
        return Response({
            "data": {
                "group_id": str(group.pk),
                "currency": account.currency if account else group.currency,
                "balance_minor": ledger.natural_balance(account) if account else 0,
                "entries": [
                    {
                        "reference": entry.transaction.reference,
                        "kind": entry.transaction.kind,
                        "description": entry.transaction.description or entry.memo,
                        "amount_minor": entry.amount_minor,
                        "posted_at": entry.transaction.posted_at,
                    }
                    for entry in entries
                ],
            }
        })
