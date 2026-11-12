from rest_framework import serializers

from .models import (
    Contribution, ContributionTarget, FundraisingCampaign, Obligation, Participation, Programme,
    RotationCycle, RotationPosition, WithdrawalRequest,
)


class ProgrammeListSerializer(serializers.ModelSerializer):
    participant_count = serializers.SerializerMethodField()
    collected_minor = serializers.SerializerMethodField()
    expected_minor = serializers.SerializerMethodField()
    progress_percent = serializers.SerializerMethodField()
    # A programme's money sits in its group's pool. Sending the slug lets the
    # client ask for that pool without a second round trip to discover it.
    group_slug = serializers.CharField(source="group.slug", read_only=True)
    group_name = serializers.CharField(source="group.name", read_only=True)

    class Meta:
        model = Programme
        fields = [
            "id", "name", "type", "status", "currency", "contribution_amount_minor", "frequency",
            "target_amount_minor", "start_date", "end_date", "participant_count", "collected_minor",
            "expected_minor", "progress_percent", "created_at", "group_slug", "group_name",
        ]

    def get_participant_count(self, obj) -> int:
        return obj.participants.filter(status=Participation.Status.ACTIVE).count()

    def get_collected_minor(self, obj) -> int:
        # Verified money only. Never the schedule.
        return obj.collected_total_minor()

    def get_expected_minor(self, obj) -> int:
        return obj.expected_total_minor()

    def get_progress_percent(self, obj) -> float:
        target = obj.target_amount_minor
        if not target:
            return 0.0
        return round(min(100.0, (obj.collected_total_minor() / target) * 100), 1)


class ProgrammeDetailSerializer(ProgrammeListSerializer):
    my_participation = serializers.SerializerMethodField()
    my_outstanding_minor = serializers.SerializerMethodField()

    class Meta(ProgrammeListSerializer.Meta):
        fields = ProgrammeListSerializer.Meta.fields + [
            "description", "visibility", "rotation_order_locked", "cycle_length", "requires_dual_approval",
            "allow_late_contributions", "late_fee_minor", "grace_period_days", "my_participation",
            "my_outstanding_minor",
        ]

    def get_my_participation(self, obj):
        participation = self.context.get("my_participation")
        if not participation:
            return None
        return {
            "id": str(participation.pk),
            "status": participation.status,
            "amount_minor": participation.amount_minor,
            "joined_at": participation.joined_at,
        }

    def get_my_outstanding_minor(self, obj) -> int:
        participation = self.context.get("my_participation")
        if not participation:
            return 0
        return sum(
            obligation.outstanding_minor
            for obligation in obligation_rows(participation)
        )


def obligation_rows(participation):
    return participation.obligations.filter(
        status__in=[Obligation.Status.PENDING, Obligation.Status.PARTIALLY_PAID, Obligation.Status.OVERDUE]
    )


class ProgrammeCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Programme
        fields = [
            "name", "description", "type", "visibility", "currency", "contribution_amount_minor",
            "frequency", "custom_interval_days", "target_amount_minor", "start_date", "end_date",
            "contribution_day", "cycle_length", "requires_dual_approval",
        ]

    def validate(self, attrs):
        programme_type = attrs.get("type")
        amount = attrs.get("contribution_amount_minor") or 0
        if programme_type == "rotational" and amount <= 0:
            raise serializers.ValidationError(
                {"contribution_amount_minor": "A rotational programme needs a fixed contribution amount."}
            )
        if attrs.get("frequency") == "custom" and not attrs.get("custom_interval_days"):
            raise serializers.ValidationError(
                {"custom_interval_days": "Say how many days between contributions."}
            )
        return attrs


class ParticipantAddSerializer(serializers.Serializer):
    membership_ids = serializers.ListField(child=serializers.UUIDField(), min_length=1)
    amount_minor = serializers.IntegerField(required=False, min_value=1)


class RotationOrderSerializer(serializers.Serializer):
    participation_ids = serializers.ListField(child=serializers.UUIDField(), min_length=2)


class ObligationSerializer(serializers.ModelSerializer):
    programme_name = serializers.CharField(source="programme.name", read_only=True)
    outstanding_minor = serializers.IntegerField(read_only=True)

    class Meta:
        model = Obligation
        fields = ["id", "programme_id", "programme_name", "due_date", "amount_minor", "paid_minor",
                  "outstanding_minor", "status"]


class ContributionSerializer(serializers.ModelSerializer):
    programme_name = serializers.CharField(source="programme.name", read_only=True)

    class Meta:
        model = Contribution
        fields = ["id", "reference", "programme_id", "programme_name", "amount_minor", "currency", "status",
                  "source", "confirmed_at", "created_at"]


class ContributionCreateSerializer(serializers.Serializer):
    """Starting a contribution; the money arrives through a payment intent."""

    obligation_id = serializers.UUIDField(required=False)
    amount_minor = serializers.IntegerField(min_value=1)
    idempotency_key = serializers.CharField(required=False, allow_blank=True, max_length=120)
    callback_url = serializers.URLField(required=False, allow_blank=True)


class RotationCycleSerializer(serializers.ModelSerializer):
    beneficiary_name = serializers.SerializerMethodField()
    shortfall_minor = serializers.IntegerField(read_only=True)

    class Meta:
        model = RotationCycle
        fields = ["id", "sequence", "status", "period_start", "period_end", "expected_total_minor",
                  "collected_total_minor", "payout_amount_minor", "shortfall_minor", "beneficiary_name",
                  "paid_at", "ledger_reference"]

    def get_beneficiary_name(self, obj) -> str | None:
        if not obj.beneficiary_id:
            return None
        return obj.beneficiary.membership.display_name or obj.beneficiary.membership.user.full_name


class RotationPositionSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()

    class Meta:
        model = RotationPosition
        fields = ["id", "position", "name"]

    def get_name(self, obj) -> str:
        membership = obj.participation.membership
        return membership.display_name or membership.user.full_name or "Member"


class WithdrawalCreateSerializer(serializers.Serializer):
    amount_minor = serializers.IntegerField(min_value=1)
    reason = serializers.ChoiceField(choices=WithdrawalRequest.Reason.choices, default="other")
    beneficiary_participation_id = serializers.UUIDField(required=False)
    note = serializers.CharField(required=False, allow_blank=True, max_length=500)


class WithdrawalSerializer(serializers.ModelSerializer):
    requested_by_name = serializers.CharField(source="requested_by.full_name", read_only=True)
    approvals_count = serializers.SerializerMethodField()

    class Meta:
        model = WithdrawalRequest
        fields = ["id", "programme_id", "amount_minor", "currency", "reason", "note", "status",
                  "requested_by_name", "approvals_count", "created_at", "executed_at"]

    def get_approvals_count(self, obj) -> int:
        return obj.approval_records.filter(approved=True).count()


class OfflineContributionSerializer(serializers.Serializer):
    participation_id = serializers.UUIDField()
    amount_minor = serializers.IntegerField(min_value=1)
    note = serializers.CharField(required=False, allow_blank=True, max_length=300)


class CampaignSerializer(serializers.ModelSerializer):
    progress_percent = serializers.SerializerMethodField()

    class Meta:
        model = FundraisingCampaign
        fields = ["id", "title", "description", "beneficiary_name", "target_amount_minor", "currency",
                  "collected_minor", "deadline", "is_public", "status", "progress_percent", "created_at"]

    def get_progress_percent(self, obj) -> float:
        if not obj.target_amount_minor:
            return 0.0
        return round(min(100.0, obj.collected_minor / obj.target_amount_minor * 100), 1)


class CampaignCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = FundraisingCampaign
        fields = ["title", "description", "beneficiary_name", "beneficiary_note", "target_amount_minor",
                  "currency", "deadline", "is_public"]


class TargetSerializer(serializers.ModelSerializer):
    class Meta:
        model = ContributionTarget
        fields = ["id", "name", "target_amount_minor", "currency", "target_date", "achieved_at", "scope"]
