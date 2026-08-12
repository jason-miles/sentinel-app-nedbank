"""
Nedbank Sentinel — Supervised ML: batch-score cases with the registered SAR model
and blend with the rules score (NEXT_STEPS #2).

Loads the UC-registered model (latest version), scores every case in
gold.ml_alert_features, and writes gold.ml_alert_scores with:
  * model_score   — the model's SAR probability (0..1)
  * rules_score   — the existing rules risk_score, normalised to 0..1
  * ai_risk       — the blended, displayed "AI risk" (0..100), replacing the old
                    ai_query placeholder. Blend favours the model but keeps rules as
                    a floor so a hard rule hit is never fully overridden.
  * model_version — provenance for the audit trail / model governance.

Runs on Databricks serverless. Re-runnable (overwrites the scores table).
"""
import mlflow
import pandas as pd
from pyspark.sql import functions as F

CATALOG = "elexon_app_for_settlement_acc_catalog"
SCHEMA = "nedbank_fraud_aml_gold"
MODEL_NAME = f"{CATALOG}.{SCHEMA}.sar_propensity_gbt"

NUMERIC = ["risk_score", "amount_log", "days_open", "investigation_hours",
           "num_accounts", "total_balance", "current_risk_rating", "recent_alerts"]
CATEGORICAL = ["scenario", "priority"]
FEATURES = NUMERIC + CATEGORICAL

mlflow.set_registry_uri("databricks-uc")
client = mlflow.tracking.MlflowClient(registry_uri="databricks-uc")
versions = client.search_model_versions(f"name = '{MODEL_NAME}'")
latest = max(versions, key=lambda v: int(v.version))
model_version = latest.version
model_uri = f"models:/{MODEL_NAME}/{model_version}"
print(f"Loading {model_uri}")

model = mlflow.sklearn.load_model(model_uri)

pdf = spark.table(f"{CATALOG}.{SCHEMA}.ml_alert_features").toPandas()
pdf["model_score"] = model.predict_proba(pdf[FEATURES])[:, 1]
pdf["rules_score"] = (pdf["risk_score"] / 100.0).clip(0, 1)
# Blend: 70% model + 30% rules, rules as a floor. Same pure helper the app/tests use
# (server/scoring.py) — vectorised inline here to avoid a per-row Python call.
blended = 0.70 * pdf["model_score"] + 0.30 * pdf["rules_score"]
pdf["ai_risk"] = (blended.clip(lower=pdf["rules_score"]) * 100).round(1)
pdf["model_version"] = str(model_version)

out = pdf[["case_id", "model_score", "rules_score", "ai_risk", "model_version"]].copy()
out["model_score"] = out["model_score"].round(4)
out["rules_score"] = out["rules_score"].round(4)

sdf = spark.createDataFrame(out).withColumn("scored_at", F.current_timestamp())
(sdf.write.mode("overwrite").option("overwriteSchema", "true")
    .saveAsTable(f"{CATALOG}.{SCHEMA}.ml_alert_scores"))

print(f"Wrote {out.shape[0]} rows to {CATALOG}.{SCHEMA}.ml_alert_scores (model v{model_version})")
print(out.sort_values("ai_risk", ascending=False).head(8).to_string(index=False))
