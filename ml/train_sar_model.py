"""
Nedbank Sentinel — Supervised ML: train the SAR-propensity model (NEXT_STEPS #2).

Trains a gradient-boosted classifier on gold.ml_alert_features -> ml_sar_labels.sar_filed,
logs metrics (ROC-AUC, precision/recall, and the false-positive-reduction comparison
vs the rules-only risk_score baseline) to MLflow, and registers the model to the Unity
Catalog Model Registry so it can be batch-scored via the pipeline.

Runs on Databricks serverless. IMPORTANT dependency note: the serverless base image
ships an old `typing_extensions` that shadows pip upgrades on sys.path, which breaks
modern mlflow/pydantic-core (ImportError: cannot import name 'Sentinel'/'deprecated').
The fix (applied by the launcher, not this file) is to pip install to a dedicated
--target dir, then `sys.path.insert(0, TGT)` and evict the preloaded stub modules
before importing mlflow. Use `mlflow-skinny` to avoid the heavy opentelemetry chain.
SQL is the source of truth; this reads the two gold tables built by
sql/05_intelligence/05_ml_features_labels.sql.
"""
import mlflow
import mlflow.sklearn
import pandas as pd
from mlflow.models.signature import infer_signature
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score, precision_score, recall_score, f1_score

CATALOG = "elexon_app_for_settlement_acc_catalog"
SCHEMA = "nedbank_fraud_aml_gold"
MODEL_NAME = f"{CATALOG}.{SCHEMA}.sar_propensity_gbt"

# Features the model is allowed to see (is_planted_fraud is EXCLUDED — it is only a
# label seed, never a feature, or the model would trivially cheat).
NUMERIC = ["risk_score", "amount_log", "days_open", "investigation_hours",
           "num_accounts", "total_balance", "current_risk_rating", "recent_alerts"]
CATEGORICAL = ["scenario", "priority"]
FEATURES = NUMERIC + CATEGORICAL

# ── Load from the gold tables ─────────────────────────────────────────────
feat = spark.table(f"{CATALOG}.{SCHEMA}.ml_alert_features")
lab = spark.table(f"{CATALOG}.{SCHEMA}.ml_sar_labels").select("case_id", "sar_filed")
pdf = feat.join(lab, "case_id").toPandas()

X = pdf[FEATURES]
y = pdf["sar_filed"].astype(int)
# keep the rules baseline (risk_score) aligned to the same split for a fair comparison
X_tr, X_te, y_tr, y_te, base_tr, base_te = train_test_split(
    X, y, pdf["risk_score"], test_size=0.30, random_state=42, stratify=y
)

# ── Model: one-hot the categoricals + GBT ─────────────────────────────────
pre = ColumnTransformer(
    [("cat", OneHotEncoder(handle_unknown="ignore"), CATEGORICAL)],
    remainder="passthrough",
)
clf = Pipeline([
    ("pre", pre),
    ("gbt", GradientBoostingClassifier(n_estimators=200, max_depth=3,
                                       learning_rate=0.05, random_state=42)),
])

mlflow.set_registry_uri("databricks-uc")
mlflow.set_experiment(f"/Users/jason.miles@databricks.com/nedbank_sentinel_sar_model")

with mlflow.start_run(run_name="sar_propensity_gbt") as run:
    clf.fit(X_tr, y_tr)
    proba = clf.predict_proba(X_te)[:, 1]
    pred = (proba >= 0.5).astype(int)

    auc = roc_auc_score(y_te, proba)
    prec = precision_score(y_te, pred, zero_division=0)
    rec = recall_score(y_te, pred, zero_division=0)
    f1 = f1_score(y_te, pred, zero_division=0)

    # ── False-positive-reduction story ────────────────────────────────────
    # Fix an "alert budget": flag the same NUMBER of cases both ways (top-K by the
    # model's probability vs top-K by the rules risk_score) and compare how many are
    # false positives. This is the "fewer false positives at equal workload" claim.
    k = int(y_te.sum())  # budget = number of true positives in the test set
    te = pd.DataFrame({"y": y_te.values, "proba": proba, "rule": base_te.values})
    model_flagged = te.nlargest(k, "proba")
    rule_flagged = te.nlargest(k, "rule")
    model_fp = int((model_flagged["y"] == 0).sum())
    rule_fp = int((rule_flagged["y"] == 0).sum())
    fp_reduction = (rule_fp - model_fp) / rule_fp if rule_fp else 0.0

    mlflow.log_params({"n_estimators": 200, "max_depth": 3, "learning_rate": 0.05,
                       "n_features": len(FEATURES), "n_train": len(X_tr)})
    mlflow.log_metrics({
        "roc_auc": auc, "precision": prec, "recall": rec, "f1": f1,
        "alert_budget_k": k, "model_false_positives": model_fp,
        "rules_false_positives": rule_fp, "fp_reduction_pct": round(fp_reduction * 100, 1),
    })

    sig = infer_signature(X_te, proba)
    mlflow.sklearn.log_model(
        clf, name="model", signature=sig,
        input_example=X_te.head(3),
        registered_model_name=MODEL_NAME,
    )
    print(f"RUN {run.info.run_id}")
    print(f"AUC={auc:.3f} precision={prec:.3f} recall={rec:.3f} f1={f1:.3f}")
    print(f"At equal alert budget K={k}: model FP={model_fp} vs rules FP={rule_fp} "
          f"-> {fp_reduction*100:.1f}% fewer false positives")
    print(f"Registered: {MODEL_NAME}")
