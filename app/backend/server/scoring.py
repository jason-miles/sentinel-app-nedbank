"""Pure scoring helpers shared by the batch scorer and tests (roadmap #2/#5).

Kept dependency-free (no pandas/sklearn) so it is trivially unit-testable and can be
imported by the app if live blending is ever needed.
"""


def blend_ai_risk(model_score: float, rules_score_0_1: float,
                  model_w: float = 0.70, rules_w: float = 0.30) -> float:
    """Blend the model's SAR probability with the normalised rules score and return a
    0..100 AI-risk. Rules act as a FLOOR: a strong hard-rule hit is never fully
    suppressed by the model. Inputs are clamped to [0,1]."""
    m = min(1.0, max(0.0, float(model_score)))
    r = min(1.0, max(0.0, float(rules_score_0_1)))
    blended = model_w * m + rules_w * r
    blended = max(blended, r)  # rules floor
    return round(min(1.0, max(0.0, blended)) * 100, 1)
