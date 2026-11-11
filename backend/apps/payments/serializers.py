from rest_framework import serializers

from .models import Disbursement, PaymentIntent, ReconciliationItem, ReconciliationRun


class PaymentIntentSerializer(serializers.ModelSerializer):
    class Meta:
        model = PaymentIntent
        fields = ["id", "reference", "purpose", "amount_minor", "currency", "status", "checkout_url",
                  "provider", "provider_reference", "created_at", "confirmed_at", "failure_message"]


class IntentCreateSerializer(serializers.Serializer):
    purpose = serializers.ChoiceField(choices=PaymentIntent.Purpose.choices)
    amount_minor = serializers.IntegerField(min_value=1)
    currency = serializers.CharField(max_length=3)
    source_id = serializers.CharField(required=False, allow_blank=True)
    idempotency_key = serializers.CharField(required=False, allow_blank=True, max_length=120)
    callback_url = serializers.URLField(required=False, allow_blank=True)


class VerifySerializer(serializers.Serializer):
    reference = serializers.CharField()


class DisbursementSerializer(serializers.ModelSerializer):
    class Meta:
        model = Disbursement
        fields = ["id", "reference", "amount_minor", "currency", "status", "provider_reference",
                  "destination_account_name", "created_at", "completed_at", "failure_message"]


class ReconciliationItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = ReconciliationItem
        fields = ["id", "kind", "provider_reference", "internal_reference", "internal_amount_minor",
                  "provider_amount_minor", "currency", "detail", "resolution"]


class ReconciliationRunSerializer(serializers.ModelSerializer):
    items = ReconciliationItemSerializer(many=True, read_only=True)

    class Meta:
        model = ReconciliationRun
        fields = ["id", "provider", "currency", "period_start", "period_end", "status", "matched_count",
                  "mismatch_count", "missing_count", "notes", "completed_at", "created_at", "items"]
