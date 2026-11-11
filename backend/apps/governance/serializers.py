from rest_framework import serializers

from .models import Ballot, Proposal, Resolution


class ProposalSerializer(serializers.ModelSerializer):
    votes_for = serializers.SerializerMethodField()
    votes_against = serializers.SerializerMethodField()
    my_vote = serializers.SerializerMethodField()
    eligible_voters = serializers.SerializerMethodField()

    class Meta:
        model = Proposal
        fields = ["id", "kind", "title", "description", "status", "requires_quorum", "quorum_percent",
                  "pass_threshold_percent", "is_secret", "opens_at", "closes_at", "votes_for",
                  "votes_against", "my_vote", "eligible_voters", "resolution_text", "created_at"]

    def get_votes_for(self, obj) -> int:
        return obj.ballots.filter(choice=True).count()

    def get_votes_against(self, obj) -> int:
        return obj.ballots.filter(choice=False).count()

    def get_my_vote(self, obj):
        user = self.context.get("request").user if self.context.get("request") else None
        if not user or not user.is_authenticated:
            return None
        # "Did I vote?" is answered from the receipt, never from the ballot,
        # so a secret ballot stays secret even in this response.
        return obj.receipts.filter(voter=user).exists()

    def get_eligible_voters(self, obj) -> int:
        return obj.group.memberships.filter(status="active").count()


class ProposalCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Proposal
        fields = ["kind", "title", "description", "requires_quorum", "quorum_percent",
                  "pass_threshold_percent", "is_secret", "opens_at", "closes_at", "resolution_text"]


class BallotCreateSerializer(serializers.Serializer):
    in_favour = serializers.BooleanField()
    comment = serializers.CharField(required=False, allow_blank=True, max_length=300)


class ResolutionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Resolution
        fields = ["id", "proposal_id", "passed", "votes_for", "votes_against", "eligible_voters",
                  "quorum_met", "text", "published_at"]
