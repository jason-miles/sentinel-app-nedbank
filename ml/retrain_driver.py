# Databricks notebook source
# MAGIC %md
# MAGIC # Nedbank Sentinel — SAR-propensity model: train + register + score (serverless driver)
# MAGIC Trains the GBT on `gold.ml_alert_features` → `ml_sar_labels.sar_filed`, logs to MLflow,
# MAGIC registers to Unity Catalog, batch-scores every case into `gold.ml_alert_scores`, and
# MAGIC writes the governance metrics into `gold.ml_model_metrics`. Replaces the SQL surrogate
# MAGIC (`08_ml_scores_fallback.sql`) with the real registered model — identical table schemas.
# MAGIC
# MAGIC Applies the serverless `typing_extensions` path-fix documented in `ml/train_sar_model.py`.

# COMMAND ----------
# DBTITLE 1,Dependency fix — install to a target dir and evict the preloaded stub
import sys, subprocess, importlib
TGT = "/tmp/ml_libs"
subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "--target", TGT,
                "mlflow-skinny>=2.15", "scikit-learn>=1.3", "pandas>=2.0",
                "cloudpickle", "skops", "typing_extensions>=4.10"], check=True)
sys.path.insert(0, TGT)
# evict any preloaded stubs so the freshly installed versions win
for m in [k for k in list(sys.modules) if k == "typing_extensions" or k.startswith("mlflow")]:
    del sys.modules[m]
import typing_extensions  # noqa: F401
print("typing_extensions loaded from:", typing_extensions.__file__)

# COMMAND ----------
# DBTITLE 1,Train GBT + log to MLflow + register to UC
import mlflow, mlflow.sklearn, pandas as pd
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
NUMERIC = ["risk_score", "amount_log", "days_open", "investigation_hours",
           "num_accounts", "total_balance", "current_risk_rating", "recent_alerts"]
CATEGORICAL = ["scenario", "priority"]
FEATURES = NUMERIC + CATEGORICAL

feat = spark.table(f"{CATALOG}.{SCHEMA}.ml_alert_features")
lab = spark.table(f"{CATALOG}.{SCHEMA}.ml_sar_labels").select("case_id", "sar_filed")
pdf = feat.join(lab, "case_id").toPandas()
X, y = pdf[FEATURES], pdf["sar_filed"].astype(int)
X_tr, X_te, y_tr, y_te, base_tr, base_te = train_test_split(
    X, y, pdf["risk_score"], test_size=0.30, random_state=42, stratify=y)

pre = ColumnTransformer([("cat", OneHotEncoder(handle_unknown="ignore"), CATEGORICAL)],
                        remainder="passthrough")
clf = Pipeline([("pre", pre),
                ("gbt", GradientBoostingClassifier(n_estimators=200, max_depth=3,
                                                   learning_rate=0.05, random_state=42))])

mlflow.set_registry_uri("databricks-uc")
mlflow.set_experiment("/Users/jason.miles@databricks.com/nedbank_sentinel_sar_model")
with mlflow.start_run(run_name="sar_propensity_gbt") as run:
    clf.fit(X_tr, y_tr)
    proba = clf.predict_proba(X_te)[:, 1]
    pred = (proba >= 0.5).astype(int)
    auc = roc_auc_score(y_te, proba); prec = precision_score(y_te, pred, zero_division=0)
    rec = recall_score(y_te, pred, zero_division=0); f1 = f1_score(y_te, pred, zero_division=0)
    k = int(y_te.sum())
    te = pd.DataFrame({"y": y_te.values, "proba": proba, "rule": base_te.values})
    model_fp = int((te.nlargest(k, "proba")["y"] == 0).sum())
    rule_fp = int((te.nlargest(k, "rule")["y"] == 0).sum())
    fp_reduction = (rule_fp - model_fp) / rule_fp if rule_fp else 0.0
    mlflow.log_params({"n_estimators": 200, "max_depth": 3, "learning_rate": 0.05,
                       "n_features": len(FEATURES), "n_train": len(X_tr)})
    mlflow.log_metrics({"roc_auc": auc, "precision": prec, "recall": rec, "f1": f1,
                        "alert_budget_k": k, "model_false_positives": model_fp,
                        "rules_false_positives": rule_fp,
                        "fp_reduction_pct": round(fp_reduction * 100, 1)})
    sig = infer_signature(X_te, proba)
    mlflow.sklearn.log_model(clf, name="model", signature=sig, input_example=X_te.head(3),
                             registered_model_name=MODEL_NAME)
    RUN_ID = run.info.run_id
    METRICS = dict(roc_auc=auc, precision=prec, recall=rec, f1=f1, model_fp=model_fp,
                   rules_fp=rule_fp, fp_reduction_pct=round(fp_reduction*100, 1),
                   n_features=len(FEATURES), n_labelled=len(pdf),
                   positive_rate=float(y.mean()))
print(f"RUN {RUN_ID}  AUC={auc:.3f} P={prec:.3f} R={rec:.3f}  FP {model_fp} vs {rule_fp} "
      f"-> {fp_reduction*100:.1f}% fewer")

# COMMAND ----------
# DBTITLE 1,Batch-score every case -> gold.ml_alert_scores (real model)
from pyspark.sql import functions as F
client = mlflow.tracking.MlflowClient(registry_uri="databricks-uc")
latest = max(client.search_model_versions(f"name = '{MODEL_NAME}'"), key=lambda v: int(v.version))
mv = latest.version
model = mlflow.sklearn.load_model(f"models:/{MODEL_NAME}/{mv}")

sc = spark.table(f"{CATALOG}.{SCHEMA}.ml_alert_features").toPandas()
sc["model_score"] = model.predict_proba(sc[FEATURES])[:, 1]
sc["rules_score"] = (sc["risk_score"] / 100.0).clip(0, 1)
blended = 0.70 * sc["model_score"] + 0.30 * sc["rules_score"]
sc["ai_risk"] = (blended.clip(lower=sc["rules_score"]) * 100).round(1)
sc["model_version"] = str(mv)
out = sc[["case_id", "model_score", "rules_score", "ai_risk", "model_version"]].copy()
out["model_score"] = out["model_score"].round(4); out["rules_score"] = out["rules_score"].round(4)
(spark.createDataFrame(out).withColumn("scored_at", F.current_timestamp())
 .write.mode("overwrite").option("overwriteSchema", "true")
 .saveAsTable(f"{CATALOG}.{SCHEMA}.ml_alert_scores"))
print(f"Wrote {len(out)} rows to ml_alert_scores (model v{mv})")

# COMMAND ----------
# DBTITLE 1,Write governance metrics -> gold.ml_model_metrics (from the real run)
metrics_row = spark.createDataFrame([(
    "sar_propensity_gbt", str(mv), "GradientBoostedTrees (MLflow, UC-registered)", RUN_ID,
    float(round(METRICS["roc_auc"], 3)), float(round(METRICS["precision"], 3)),
    float(round(METRICS["recall"], 3)), float(round(METRICS["f1"], 3)),
    int(METRICS["model_fp"]), int(METRICS["rules_fp"]),
    float(round((METRICS["rules_fp"] - METRICS["model_fp"]) / METRICS["rules_fp"] * 100, 1)
          if METRICS["rules_fp"] else 0.0),
    int(METRICS["n_features"]), int(METRICS["n_labelled"]),
    float(round(METRICS["positive_rate"], 4)), 0.70, 0.30, "validated",
)], schema="model_name string, model_version string, algorithm string, run_id string, "
           "roc_auc double, precision double, recall double, f1 double, model_fp int, "
           "rules_fp int, fp_reduction_pct double, n_features int, n_labelled int, "
           "positive_rate double, blend_model_weight double, blend_rules_weight double, "
           "governance_status string").withColumn("trained_at", F.current_timestamp())
(metrics_row.write.mode("overwrite").option("overwriteSchema", "true")
 .saveAsTable(f"{CATALOG}.{SCHEMA}.ml_model_metrics"))
print("Wrote ml_model_metrics for model v" + str(mv))
