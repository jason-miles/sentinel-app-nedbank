"""Unit tests for the model/rules AI-risk blend (roadmap #2/#5)."""
from server.scoring import blend_ai_risk


def test_blend_basic():
    # 0.70*0.8 + 0.30*0.5 = 0.71 -> 71.0
    assert blend_ai_risk(0.8, 0.5) == 71.0


def test_rules_act_as_floor():
    # model near zero but rules high -> never below the rules score
    assert blend_ai_risk(0.0, 0.9) == 90.0


def test_clamped_range():
    assert blend_ai_risk(2.0, 2.0) == 100.0
    assert blend_ai_risk(-1.0, -1.0) == 0.0


def test_weights_configurable():
    assert blend_ai_risk(1.0, 0.0, model_w=1.0, rules_w=0.0) == 100.0
