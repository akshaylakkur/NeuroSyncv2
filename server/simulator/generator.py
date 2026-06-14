"""
NeuroSync Simulation — Message Generator

Produces 1000+ diverse, realistic messages across multiple sentiment
categories, channels (Discord, Gmail), senders, and stress levels.
Messages are deterministic per-seed so simulations are reproducible.
"""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass
class SimMessage:
    """A single simulated message ready for the MessageStore."""

    id: str
    text: str
    sender: str
    channel: str
    timestamp: str
    raw_type: str
    metadata: dict[str, Any] = field(default_factory=dict)


# ------------------------------------------------------------------
# Template banks
# ------------------------------------------------------------------

DISCORD_SENDERS = [
    "alex_dev", "sarah_pm", "mike_ops", "jordan_sec", "taylor_qa",
    "casey_backend", "riley_frontend", "quinn_ml", "avery_data",
    "dakota_sre", "skyler_mobile", "reese_devops", "peyton_arch",
    "morgan_cxo", "cameron_design", "sydney_support", "jordan_lead",
    "hayden_infra", "emerson_fullstack", "logan_platform", "dakota_db",
    "parker_cloud", "micah_embedded", "corey_network", "drew_product",
]

GMAIL_SENDERS = [
    "alex@company.com", "sarah@company.com", "mike@company.com",
    "jordan@company.com", "taylor@company.com", "casey@company.com",
    "riley@company.com", "quinn@company.com", "avery@company.com",
    "dakota@company.com", "skyler@company.com", "reese@company.com",
    "peyton@company.com", "morgan@company.com", "cameron@company.com",
    "sydney@company.com", "jordan@company.com", "hayden@company.com",
    "emerson@company.com", "logan@company.com",
]

# Templates grouped by sentiment/stress level
DISCORD_TEMPLATES: dict[str, list[str]] = {
    "crisis": [
        "🚨 PRODUCTION IS DOWN — all users getting 500s on login",
        "SECURITY BREACH: unauthorized access detected in payment service",
        "DATA LOSS: yesterday's backups failed, 6h of transactions gone",
        "P0 incident — payment gateway returning failures globally",
        "INFRASTRUCTURE COMPROMISED — attacker gained root on db-primary",
        "FIRE DRILL: actual fire in datacenter east-1, evacuating now",
        "SEV1: API gateway completely unresponsive, no traffic flowing",
        "DATABASE CORRUPTION detected on shard-03, investigating",
        "CRITICAL: customer PII exposed in logs for past 48 hours",
        "OUTAGE: CDN edge nodes failing across all regions",
    ],
    "high_stress": [
        "Deploy just failed for the 3rd time today — this is blocking the release",
        "Customer escalation: enterprise client threatening to churn if not fixed by EOD",
        "CI/CD pipeline broken, all PRs blocked, can't merge anything",
        "Load tests are failing with memory leaks — launch is tomorrow 😰",
        "The migration script just wiped the staging DB... anyone have a backup?",
        "URGENT: compliance audit findings due in 2 hours and we're not ready",
        "Performance degradation in search service — latency up 400%",
        "Mobile app crashing on launch for iOS 18 users — need hotfix NOW",
        "Auth service intermittently rejecting tokens — users locked out",
        "The new feature is completely broken in production but already announced",
        "We have a memory leak eating 2GB/hour and I can't find it",
        "SSL cert expired on prod and nobody noticed until customers started complaining",
        "Redis cluster split-brain causing cache inconsistencies",
        "Kubernetes pod evictions spiking — resource limits too tight",
        "Third-party API we depend on just deprecated their endpoint with 24h notice",
    ],
    "moderate_stress": [
        "Anyone else seeing intermittent 504s from the user-service?",
        "The PR has been open for 3 days with no reviews — can someone take a look?",
        "Test flakiness is getting worse, same test passes locally but fails in CI",
        "Need to refactor the monolith before we can ship the new feature",
        "Dependency upgrade broke our build — pinning to old version for now",
        "Monitoring alert firing for high CPU on worker-07 but seems fine?",
        "The documentation for the new API is incomplete, causing confusion",
        "Code review feedback is extensive — need another round of changes",
        "Sprint goals at risk if we don't close these two tickets today",
        "Dev environment is slow again, Docker builds taking 20+ minutes",
        "Flaky integration test in payment module — intermittent timeout",
        "Need to coordinate with security team before we can enable the flag",
        "Database migration might lock the users table — need off-hours window",
        "The feature flag isn't working as expected in staging",
        "API rate limits are tighter than expected, might need caching layer",
    ],
    "low_stress": [
        "Daily standup notes: backend team merged 4 PRs, on track",
        "Just updated the README with new setup instructions",
        "Renamed the module to match our naming convention — no functional changes",
        "Small typo fix in error messages, sending for review",
        "Refactored the utility function for better readability",
        "Looking into adding metrics for the new endpoint",
        "Planning to update dependencies next sprint",
        "Investigating a minor CSS issue on the settings page",
        "Created a ticket to track the tech debt from last quarter",
        "Updated the runbook with the new rollback procedure",
    ],
    "positive": [
        "🎉 Release v2.4.0 is LIVE — great work everyone!",
        "Thanks @alex_dev for the quick fix on that bug, really appreciate it",
        "Customer NPS jumped to 72 after the redesign — amazing results",
        "Just solved the perf issue — response time dropped from 2s to 120ms 🔥",
        "Team lunch today at 1pm to celebrate the launch!",
        "The new dashboard looks incredible, kudos to design team",
        "Thanks to everyone who stayed late to get this shipped 🙏",
        "Load tests all passing with flying colors — we're ready for Black Friday",
        "Zero incidents this week — stability is looking great",
        "Just got a shoutout from the CEO in all-hands for the migration work",
        "The refactor cleaned up 2000 lines of legacy code — feels so good",
        "Our error rate is the lowest it's been in 6 months 📉",
        "Demo went perfectly, client signed the renewal on the spot",
        "Hackathon project won internal prize — might ship it for real",
        "Just onboarded 3 new engineers, team is growing fast",
    ],
    "neutral": [
        "Has anyone seen the docs for the new auth flow?",
        "Meeting rescheduled to 3pm today",
        "Out of office tomorrow, back Monday",
        "The staging URL is https://staging.company.internal",
        "Reminder: deploy freeze starts Friday at 6pm",
        "VPN access request processed — check your email",
        "Office hours for platform team moved to Thursdays",
        "New laptop policy update in #announcements",
        "Looking for volunteers for the interview panel",
        "Team offsite planning doc is open for suggestions",
    ],
}

GMAIL_SUBJECTS: dict[str, list[str]] = {
    "crisis": [
        "URGENT: Production outage - immediate action required",
        "SECURITY ALERT: Potential data breach investigation",
        "SEV1 Incident declared - all hands on deck",
        "EMERGENCY: Payment system failure affecting all customers",
        "CRITICAL: Database integrity compromised - immediate response needed",
    ],
    "high_stress": [
        "Escalation: Enterprise client threatening contract termination",
        "Compliance deadline approaching - documentation incomplete",
        "Performance degradation in core service - SLA at risk",
        "Urgent: SSL certificate expires in 48 hours",
        "Incident retrospective required for last week's outage",
        "Budget overrun - need to justify Q3 infrastructure spend",
        "Customer escalated to CEO - need resolution plan by EOD",
    ],
    "moderate_stress": [
        "Weekly status update - some risks identified",
        "Code review backlog growing - need more reviewers",
        "Sprint planning - capacity concerns for next iteration",
        "Dependency audit findings - moderate issues found",
        "Team availability update - multiple PTOs next week",
        "Test coverage report - below target in two modules",
    ],
    "low_stress": [
        "Weekly team update - all milestones on track",
        "Reminder: Submit expense reports by Friday",
        "New hire onboarding schedule - please review",
        "Office maintenance scheduled for this weekend",
        "Team lunch invitation for tomorrow",
        "Updated coding standards document - please review",
    ],
    "positive": [
        "Congratulations on successful product launch!",
        "Great quarterly results - bonus pool approved",
        "Customer success story - positive feedback from major client",
        "Team recognition - outstanding work on migration project",
        "Promotions announced - well deserved!",
        "Company all-hands recap - exciting roadmap ahead",
    ],
    "neutral": [
        "Meeting notes from yesterday's architecture review",
        "Updated runbook for the deployment process",
        "Quarterly planning session - save the date",
        "IT security training mandatory by end of month",
        "New policy update - remote work guidelines",
    ],
}

GMAIL_BODIES: dict[str, list[str]] = {
    "crisis": [
        "At {time}, monitoring detected complete failure of the {system} service. Error rate is 100%. Customers cannot access {feature}. We need all hands immediately.",
        "Our security team detected anomalous access patterns in the {system} database. Preliminary investigation suggests unauthorized access to approximately {num} records. Law enforcement has been notified.",
        "The primary {system} cluster experienced a catastrophic failure. Failover did not complete successfully. RPO is currently unknown. Emergency response team assemble in war room.",
    ],
    "high_stress": [
        "Our largest enterprise client ({company}) has escalated their concerns regarding {issue} to executive leadership. They have given us until {time} tomorrow to provide a detailed remediation plan or they will initiate contract termination proceedings.",
        "The Q3 infrastructure spend is projected to exceed budget by {pct}%. Finance is requiring detailed justification for the {system} scaling costs by end of week.",
        "During the post-mortem for last week's {system} incident, we identified {num} critical gaps in our monitoring and alerting. Each requires a mitigation plan within 48 hours.",
    ],
    "moderate_stress": [
        "This week's sprint velocity is below target. The {feature} implementation is taking longer than estimated. We may need to descope {num} stories to maintain the release date.",
        "The quarterly security audit identified {num} moderate-severity findings in the {system} module. While not immediately exploitable, these should be addressed in the next maintenance window.",
        "Our test coverage for the {system} module is currently at {pct}%, below our {threshold}% target. Please prioritize adding tests for the new {feature} functionality.",
    ],
    "low_stress": [
        "The weekly metrics show all systems operating within normal parameters. No action required at this time.",
        "Just a friendly reminder that expense reports for last month are due by Friday. Please submit through the portal.",
        "We're updating our internal documentation. If you have feedback on the {system} runbook, please add comments by next week.",
    ],
    "positive": [
        "I wanted to personally thank the team for the exceptional work on the {feature} launch. Customer feedback has been overwhelmingly positive, with NPS increasing by {num} points.",
        "Following the successful migration of {system} to the new infrastructure, we've seen a {pct}% improvement in response times and a {num}% reduction in infrastructure costs. Excellent work.",
        "I'm pleased to announce that our {feature} has been selected as a finalist for the industry innovation awards. This is a tremendous achievement for the team.",
    ],
    "neutral": [
        "Please find attached the minutes from yesterday's architecture review meeting. Action items are assigned and due by {time} next week.",
        "The quarterly planning session is scheduled for next Thursday. Please come prepared with your team's proposed roadmap and resource requirements.",
        "As a reminder, all employees must complete the annual security awareness training by end of month. Access the modules through the learning portal.",
    ],
}

FILLER_WORDS = {
    "system": ["payment", "auth", "search", "user", "notification", "analytics",
               "recommendation", "billing", "inventory", "messaging", "CDN",
               "database", "cache", "queue", "gateway", "microservice", "ML pipeline"],
    "feature": ["dark mode", "two-factor auth", "real-time sync", "AI assistant",
                "mobile redesign", "API v2", "dashboard widgets", "bulk export",
                "team collaboration", "integrations hub", "search filters",
                "notifications overhaul", "onboarding flow", "analytics dashboard"],
    "company": ["Acme Corp", "Globex", "Soylent Systems", "Initech", "Umbrella",
                "Stark Industries", "Wayne Enterprises", "Cyberdyne", "Massive Dynamic"],
    "time": ["14:00 UTC", "18:00 EST", "09:00 PST", "midnight UTC", "noon"],
    "num": ["12", "47", "150", "2,000", "10,000", "50", "3", "8", "25", "100"],
    "pct": ["15", "23", "8", "42", "67", "31", "55", "12", "89", "5"],
    "threshold": ["80", "85", "90", "75", "95"],
}


def _fill(template: str, rng: random.Random) -> str:
    """Replace placeholders in a template with random values."""
    result = template
    for key, values in FILLER_WORDS.items():
        placeholder = "{" + key + "}"
        while placeholder in result:
            result = result.replace(placeholder, rng.choice(values), 1)
    return result


def _generate_discord_messages(
    count: int, rng: random.Random, start_time: datetime,
) -> list[SimMessage]:
    """Generate Discord-style messages."""
    messages: list[SimMessage] = []

    # Distribution weights per sentiment
    weights = {
        "crisis": 5,
        "high_stress": 20,
        "moderate_stress": 25,
        "low_stress": 15,
        "positive": 25,
        "neutral": 10,
    }

    categories = list(weights.keys())
    cat_weights = [weights[c] for c in categories]

    for i in range(count):
        category = rng.choices(categories, weights=cat_weights, k=1)[0]
        template = rng.choice(DISCORD_TEMPLATES[category])
        text = _fill(template, rng)
        sender = rng.choice(DISCORD_SENDERS)

        # Slightly randomize timestamp within a window
        offset_seconds = rng.randint(0, 3600)
        ts = start_time.astimezone(timezone.utc).isoformat()

        messages.append(SimMessage(
            id=str(uuid.uuid4()),
            text=text,
            sender=sender,
            channel="discord",
            timestamp=ts,
            raw_type="discord",
            metadata={"simulated": True, "category": category, "index": i},
        ))

    return messages


def _generate_gmail_messages(
    count: int, rng: random.Random, start_time: datetime,
) -> list[SimMessage]:
    """Generate Gmail-style email messages."""
    messages: list[SimMessage] = []

    weights = {
        "crisis": 5,
        "high_stress": 20,
        "moderate_stress": 25,
        "low_stress": 15,
        "positive": 25,
        "neutral": 10,
    }

    categories = list(weights.keys())
    cat_weights = [weights[c] for c in categories]

    for i in range(count):
        category = rng.choices(categories, weights=cat_weights, k=1)[0]
        subject = rng.choice(GMAIL_SUBJECTS[category])
        body_template = rng.choice(GMAIL_BODIES[category])
        body = _fill(body_template, rng)
        sender = rng.choice(GMAIL_SENDERS)
        text = f"Subject: {subject}\n\n{body}"

        offset_seconds = rng.randint(0, 3600)
        ts = start_time.astimezone(timezone.utc).isoformat()

        messages.append(SimMessage(
            id=str(uuid.uuid4()),
            text=text,
            sender=sender,
            channel="gmail",
            timestamp=ts,
            raw_type="gmail",
            metadata={"simulated": True, "category": category, "index": i},
        ))

    return messages


class MessageGenerator:
    """Generates realistic message pools for simulation."""

    def __init__(self, seed: int | None = None) -> None:
        self._rng = random.Random(seed)
        self._pool: list[SimMessage] = []
        self._index = 0

    def generate_pool(self, total_messages: int = 1000) -> list[SimMessage]:
        """Generate a shuffled pool of messages."""
        now = datetime.now(timezone.utc)

        # Split between Discord and Gmail
        discord_count = int(total_messages * 0.6)
        gmail_count = total_messages - discord_count

        discord_msgs = _generate_discord_messages(discord_count, self._rng, now)
        gmail_msgs = _generate_gmail_messages(gmail_count, self._rng, now)

        self._pool = discord_msgs + gmail_msgs
        self._rng.shuffle(self._pool)
        self._index = 0

        return list(self._pool)

    def next_batch(
        self, batch_size: int, channel_filter: str | None = None,
    ) -> list[SimMessage]:
        """Get the next batch of messages from the pool, optionally filtered by channel."""
        if not self._pool:
            self.generate_pool()

        available = self._pool[self._index:]
        if channel_filter:
            available = [m for m in available if m.channel == channel_filter]

        batch = available[:batch_size]
        self._index = min(self._index + batch_size, len(self._pool))

        # Wrap around if we've exhausted the pool
        if not batch and self._index >= len(self._pool):
            self._index = 0
            return self.next_batch(batch_size, channel_filter)

        return batch

    def next_batch_weighted(
        self, batch_size: int, category_weights: dict[str, float],
    ) -> list[SimMessage]:
        """Get a batch with messages distributed by category weights.

        Scans through the pool and collects messages of each target category
        in proportion to the given weights. Messages are consumed sequentially
        from the pool — no random access, so the pool advances predictably.
        """
        if not self._pool:
            self.generate_pool()
        if batch_size <= 0:
            return []

        # Normalise weights into target counts per category
        total_weight = sum(category_weights.values()) or 1.0
        targets: dict[str, int] = {}
        for cat, w in category_weights.items():
            targets[cat] = max(0, int(batch_size * w / total_weight))

        # Remaining slots go to the highest-weighted category
        allocated = sum(targets.values())
        if allocated < batch_size and category_weights:
            best_cat = max(category_weights, key=category_weights.get)
            targets[best_cat] = targets.get(best_cat, 0) + (batch_size - allocated)

        # Scan through remaining pool and collect messages by category
        batch: list[SimMessage] = []
        remaining_pool = self._pool[self._index:]
        for msg in remaining_pool:
            if len(batch) >= batch_size:
                break
            cat = msg.metadata.get("category", "neutral")
            needed = targets.get(cat, 0)
            if needed > 0:
                batch.append(msg)
                targets[cat] = needed - 1
                self._index += 1

        # If we didn't fill the batch (pool too small), take whatever's left
        if len(batch) < batch_size:
            remaining = self._pool[self._index:]
            for msg in remaining:
                if len(batch) >= batch_size:
                    break
                batch.append(msg)
                self._index += 1

        # Wrap around if exhausted
        if not batch and self._index >= len(self._pool):
            self._index = 0
            return self.next_batch_weighted(batch_size, category_weights)

        return batch

    @property
    def remaining(self) -> int:
        return max(0, len(self._pool) - self._index)

    @property
    def total(self) -> int:
        return len(self._pool)


def generate_1000_messages(seed: int = 42) -> list[SimMessage]:
    """Convenience: generate exactly 1000 messages."""
    gen = MessageGenerator(seed=seed)
    return gen.generate_pool(1000)
