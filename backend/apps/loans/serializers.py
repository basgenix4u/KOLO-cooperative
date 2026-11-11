from rest_framework import serializers

from .models import Guarantor, Loan, LoanApplication, LoanProduct, Repayment, RepaymentSchedule


class LoanProductSerializer(serializers.ModelSerializer):
    class Meta:
        model = LoanProduct
        fields = ["id", "name", "category", "currency", "min_amount_minor", "max_amount_minor", "interest_bps",
                  "term_months_min", "term_months_max", "requires_guarantors", "requires_member_vote",
                  "min_membership_days", "is_active"]


class LoanApplicationCreateSerializer(serializers.Serializer):
    product_id = serializers.UUIDField()
    amount_minor = serializers.IntegerField(min_value=1)
    term_months = serializers.IntegerField(min_value=1, max_value=60)
    purpose = serializers.CharField(max_length=300)
    guarantor_membership_ids = serializers.ListField(child=serializers.UUIDField(), required=False)


class LoanApplicationSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source="product.name", read_only=True)
    borrower_name = serializers.SerializerMethodField()
    accepted_guarantors = serializers.SerializerMethodField()

    class Meta:
        model = LoanApplication
        fields = ["id", "product_id", "product_name", "borrower_name", "amount_minor", "currency", "term_months",
                  "purpose", "status", "submitted_at", "decided_at", "decision_note", "accepted_guarantors",
                  "created_at"]

    def get_borrower_name(self, obj) -> str:
        return obj.borrower.display_name or obj.borrower.user.full_name

    def get_accepted_guarantors(self, obj) -> int:
        return obj.guarantors.filter(status=Guarantor.Status.ACCEPTED).count()


class GuarantorRespondSerializer(serializers.Serializer):
    accept = serializers.BooleanField()


class ScheduleSerializer(serializers.ModelSerializer):
    class Meta:
        model = RepaymentSchedule
        fields = ["installment_no", "due_date", "amount_minor", "principal_minor", "interest_minor",
                  "paid_minor", "paid_at"]


class LoanSerializer(serializers.ModelSerializer):
    borrower_name = serializers.SerializerMethodField()
    schedule = ScheduleSerializer(many=True, read_only=True)

    class Meta:
        model = Loan
        fields = ["id", "reference", "principal_minor", "currency", "interest_bps", "term_months",
                  "total_repayable_minor", "outstanding_minor", "status", "disbursed_at", "due_date",
                  "borrower_name", "schedule", "created_at"]

    def get_borrower_name(self, obj) -> str:
        return obj.borrower.display_name or obj.borrower.user.full_name


class RepaymentCreateSerializer(serializers.Serializer):
    amount_minor = serializers.IntegerField(min_value=1)


class RepaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Repayment
        fields = ["id", "reference", "amount_minor", "currency", "status", "paid_at", "created_at"]
