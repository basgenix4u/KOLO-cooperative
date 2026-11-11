from rest_framework import serializers

from .models import Account, JournalEntry, JournalTransaction


class AccountSerializer(serializers.ModelSerializer):
    balance_minor = serializers.SerializerMethodField()

    class Meta:
        model = Account
        fields = ["id", "code", "name", "type", "currency", "scope_type", "balance_minor", "is_withdrawable"]

    def get_balance_minor(self, obj) -> int:
        # Derived from entries, never the cached column: a report must not be
        # able to disagree with the ledger. Shown in the account's natural sign.
        from . import services as ledger

        return ledger.natural_balance(obj)


class EntrySerializer(serializers.ModelSerializer):
    account_code = serializers.CharField(source="account.code", read_only=True)
    account_name = serializers.CharField(source="account.name", read_only=True)

    class Meta:
        model = JournalEntry
        fields = ["id", "account_code", "account_name", "amount_minor", "currency", "memo"]


class TransactionSerializer(serializers.ModelSerializer):
    entries = EntrySerializer(many=True, read_only=True)

    class Meta:
        model = JournalTransaction
        fields = ["id", "reference", "kind", "status", "currency", "description", "source_type",
                  "source_id", "posted_at", "created_at", "entries"]
