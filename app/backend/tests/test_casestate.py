"""Unit tests for the case state machine (roadmap #4)."""
from server.casestate import can_transition, transition_error


def test_valid_forward_transitions():
    assert can_transition("new", "assigned")
    assert can_transition("assigned", "in_progress")
    assert can_transition("in_progress", "escalated")
    assert can_transition("escalated", "closed")
    assert can_transition("in_progress", "closed")


def test_invalid_transitions_rejected():
    assert not can_transition("new", "closed")        # can't skip straight to closed
    assert not can_transition("new", "in_progress")   # must be assigned first
    assert not can_transition("closed", "in_progress")  # terminal


def test_terminal_state_has_no_transitions():
    assert transition_error("closed", "assigned") != ""


def test_unknown_status_reported():
    assert "unknown current status" in transition_error("bogus", "closed")
    assert "unknown target status" in transition_error("new", "bogus")


def test_error_message_lists_allowed():
    msg = transition_error("new", "closed")
    assert "assigned" in msg  # tells the caller what IS allowed


def test_allowed_transition_has_no_error():
    assert transition_error("new", "assigned") == ""
