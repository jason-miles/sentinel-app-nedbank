"""Unit tests for the SAR guardrail (roadmap #8)."""
from server.routes.sar_eval import check_guardrail

LONG = "x" * 200


def test_passes_clean_narrative():
    ok, note = check_guardrail("This is a sufficiently long SAR narrative. " + LONG)
    assert ok is True


def test_rejects_too_short():
    ok, note = check_guardrail("Too short.")
    assert ok is False
    assert "short" in note


def test_rejects_raw_pii_id():
    # 13-digit SA ID number embedded in an otherwise long narrative
    text = "Subject national id 8001015009087 was flagged. " + LONG
    ok, note = check_guardrail(text)
    assert ok is False
    assert "PII" in note


def test_allows_normal_amounts():
    # short digit groups (amounts, dates) must NOT trip the PII rule
    text = "Moved 750000 then 727500 on 2026-07-19 across 3 accounts. " + LONG
    ok, note = check_guardrail(text)
    assert ok is True
