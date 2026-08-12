"""Case state machine (NEXT_STEPS #4).

Pure, dependency-free transition rules so they are unit-testable and reused by the
API. Enforces valid case lifecycle transitions; the app rejects anything not allowed
here and audits every move.

Lifecycle:
    new ─▶ assigned ─▶ in_progress ─▶ escalated ─▶ closed
                          │   │            │
                          │   └────────────┴─▶ closed   (dismiss / file & close)
                          └─▶ escalated
Terminal: closed (no outgoing transitions).
"""

TRANSITIONS = {
    "new":         {"assigned"},
    "assigned":    {"in_progress", "escalated"},
    "in_progress": {"escalated", "closed"},
    "escalated":   {"closed", "in_progress"},   # can send back for more work
    "closed":      set(),                        # terminal
}

STATUSES = set(TRANSITIONS.keys())


def can_transition(current: str, target: str) -> bool:
    """True iff moving current→target is a valid lifecycle transition."""
    return target in TRANSITIONS.get(current, set())


def transition_error(current: str, target: str) -> str:
    """Human-readable reason a transition is rejected (empty string if allowed)."""
    if current not in STATUSES:
        return f"unknown current status '{current}'"
    if target not in STATUSES:
        return f"unknown target status '{target}'"
    if not can_transition(current, target):
        allowed = sorted(TRANSITIONS[current]) or ["(terminal — no transitions)"]
        return f"cannot move {current} → {target}; allowed from {current}: {', '.join(allowed)}"
    return ""
