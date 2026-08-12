# Nedbank Sentinel — Deployment Guide + Director's Notes

This is the Nedbank build of the Sentinel Fraud & AML app (alongside the Investec and
Capitec builds). It is a **fully isolated** deployment: its own bundle name, schemas,
app name, pipeline/job names, and Genie/dashboard IDs, so it runs alongside the other
builds without collision.

> **All data is synthetic — DEMO DATA.** Names, IDs, and entities are fabricated. The
> planted typologies are textbook patterns from public FATF guidance; nothing here is a
> real evasion technique or a real person/company.

---

## 0. What makes this build "Nedbank"

| Dimension            | Value |
|----------------------|-------|
| Brand                | Nedbank deep blue `#003b5c` + signature red `#e2001a` (light + dark themes, logo, favicon) |
| Market framing       | Mass-market retail bank; **Nedbank** account tiers; ZAR; SA metro + township footprint |
| Regulatory framing   | **FICA / FIC** (STRs & CTRs to the Financial Intelligence Centre via **goAML**), **SARB** Prudential Authority, **POPIA**, **NCA** |
| Filing institution   | `Nedbank Limited` (goAML reporting entity `NEDBANK-ZA`) |
| Bundle name          | `nedbank_sentinel` |
| Nested pipeline bundle | `nedbank_fraud_aml_pipeline` |
| App name             | `nedbank-fraud-aml` |
| Schemas              | `nedbank_fraud_aml_bronze` / `_silver` / `_gold` in `elexon_app_for_settlement_acc_catalog` |
| Pipeline / jobs      | `nedbank_fraud_aml_pipeline_etl`, `nedbank_fraud_aml_daily_report`, `nedbank_fraud_aml_stream_trigger`, `nedbank_fraud_ml_retrain` |

### Detection families (10)
The nine inherited families (rapid movement, frequency spike, circular ring, dormant
reactivation, risk-rating jump, adverse media, UBO change, account takeover, impossible
travel) **plus** a new **cash structuring** rule (`detect_structuring`) keyed to the SA
R25,000 Cash Threshold Report (CTR) limit.

### New capability surfaces added for the Nedbank brief
- **Actual-vs-declared turnover** (`declared_monthly_turnover` on customers → surfaced in
  `customer_360` and scored in `pkyc_customer_risk`) — the flagship CDD signal.
- **AML knowledge + SAR corpus** (`bronze.aml_knowledge`, `bronze.sar_narratives`) with
  vector indexes → the SAR "policy" agent cites bank policy + FATF (`retrieve_policy`).
- **Retrospective typology sweep** (`gold.typology_exposure`, `/api/aml/typology-sweep`)
  for the gaming/third-party-processor layering typology.
- **Merchant categories, device/IP, cross-border flags** on transactions for the above.

---

## 1. Prerequisites
- Databricks CLI ≥ 0.288.0, authenticated to the workspace profile
  `fevm-elexon-app-for-settlement-acc`.
- A running SQL warehouse (setup uses Serverless Starter).
- `ALL PRIVILEGES` on `elexon_app_for_settlement_acc_catalog` (no `CREATE CATALOG`
  needed — the medallion is co-located as prefixed schemas; see README).

## 2. Create schemas + seed synthetic data
Run against the warehouse, in order:
```sql
-- foundation (schemas + landing volume)
sql/00_foundation/00_schemas.sql
-- bronze DDL (now includes declared turnover, merchant_category, device/ip,
-- aml_knowledge, sar_narratives)
sql/01_bronze/01_bronze_tables.sql
-- synthetic data (5 files, in order)
data/01_seed_customers_accounts.sql
data/02_seed_transactions.sql
data/03_seed_supporting.sql
data/04_plant_scenarios.sql      -- legacy families + WOW-A mule net + WOW-C gaming + ER dups
data/05_seed_knowledge.sql       -- AML policy/typology/FATF corpus + historical STRs
```
Then the pipeline (step 3) builds silver + gold, and the Sherlock / governance /
intelligence SQL under `sql/05_intelligence` + `sql/06_*` run AFTER it (they read
`gold.fraud_alerts` + `silver.entity_map`). Run order that works end-to-end:
```
# after the pipeline full-refresh (step 3):
sql/05_intelligence/01_metric_views.sql
sql/05_intelligence/02_adverse_media_ai.sql            # ai_query
sql/06_sherlock/01_case_management.sql
sql/06_sherlock/02_cases.sql                           # sherlock_cases (+ hero cases)
sql/06_sherlock/03_exec_views.sql
sql/06_sherlock/04_sanctions_screening.sql
sql/06_sherlock/05_perpetual_kyc.sql                   # turnover-vs-declared signal
sql/06_sherlock/06_peer_anomaly.sql
sql/06_sherlock/07_fold_new_families.sql
sql/06_sherlock/08_typology_sweep.sql                  # WOW-C gaming/TPP exposure
sql/06_sherlock/09_app_writeback_tables.sql            # case notes/actions/SAR filings (+ seed hero notes)
sql/05_intelligence/05_ml_features_labels.sql          # needs sherlock_cases
sql/05_intelligence/06_ml_drift_monitoring.sql
sql/05_intelligence/08_ml_scores_fallback.sql          # ml_alert_scores + ml_model_metrics (queue + governance)
sql/06_governance/01_pii_column_masks.sql
sql/06_governance/02_audit_log.sql
sql/06_governance/03_rls_row_filter.sql                # set the app SP client id first (see file header)
sql/06_governance/05_case_workflow.sql
```
NOTES:
- `03_gold/01_alert_feedback_table.sql` is created inline by `data/04_plant_scenarios.sql`.
- ML: the canonical path trains a GBT in MLflow (`ml/train_sar_model.py` +
  `score_sar_model.py`) on serverless. `08_ml_scores_fallback.sql` builds the SAME two
  tables (`ml_alert_scores`, `ml_model_metrics`) deterministically in pure SQL so the
  analyst queue + model-governance panel work without a cluster; the real job overwrites
  them (schemas match). Metrics are COMPUTED from the labelled set (AUC ~0.75, ~50% FP
  reduction at equal alert budget) — not hardcoded.
- RLS: `03_rls_row_filter.sql` sets a UC row filter on `sherlock_cases`. The app runs as
  ONE service principal, so its client id MUST be in the filter or every case-backed page
  returns 0 rows. Update the id from `databricks apps get nedbank-fraud-aml`.

## 3. Deploy the bundle (app + pipeline + jobs)
```bash
cd fraud_aml_pipeline
databricks bundle deploy -t dev --profile fevm-elexon-app-for-settlement-acc
# The pipeline RESOURCE KEY is `fraud_aml_pipeline_etl` (the nedbank_ prefix is only the
# display name). Streaming lanes need one file each first, or schema inference fails:
databricks fs mkdir dbfs:/Volumes/elexon_app_for_settlement_acc_catalog/nedbank_fraud_aml_bronze/landing/transactions
databricks fs mkdir dbfs:/Volumes/.../landing/card_transactions
python ../data/stream/drop_transactions.py --scenario normal --account ACC00000011 \
  --profile fevm-elexon-app-for-settlement-acc
python ../data/stream/drop_transactions.py --scenario impossible_travel --card CARD00000021 \
  --account ACC00000021 --profile fevm-elexon-app-for-settlement-acc
# first/clean build must be a full refresh so cross-schema MVs order correctly:
databricks bundle run fraud_aml_pipeline_etl --full-refresh-all \
  -t dev --profile fevm-elexon-app-for-settlement-acc
```
All 10 detection families fire against the planted scenarios after a full refresh
(verified: structuring x7 mules, rapid_movement on the aggregator, etc.).

## 4. Genie space + dashboard (LIVE IDs already wired)
The deployed instance uses these (already set in `app/backend/app.yaml` + genai.py):
```
SENTINEL_GENIE_SPACE   = 01f194ad316e127191fec45fdd5fb6bc   # "Nedbank Fraud & AML Analyst"
SENTINEL_DASHBOARD_ID  = 01f194ad41b618fa8342f8a851b45507   # "Nedbank Sentinel — Executive Overview"
```
To recreate in a fresh workspace:
```bash
# Genie (serialized_space payload must have tables sorted by identifier + each
# sample_question needs a 32-hex id — see the space JSON):
databricks genie create-space <warehouse_id> "$(cat serialized_space.json)" \
  --title "Nedbank Fraud & AML Analyst" --description "$(cat description.txt)"
# Dashboard:
databricks lakeview create --display-name "Nedbank Sentinel — Executive Overview" \
  --warehouse-id <wh> --serialized-dashboard "$(cat dashboards/exec_overview.lvdash.json)"
databricks lakeview publish <dashboard_id> --warehouse-id <wh>
```
Then paste both IDs into `app/backend/app.yaml` and redeploy the app.

## 4b. Vector Search indexes (RAG — SAR policy + adverse-media citations)
```bash
# enable CDF on the sources, then create two DELTA_SYNC indexes on an ONLINE endpoint:
#   gold.adverse_media_index   (source bronze.adverse_media,  pk article_id, embed body)
#   gold.aml_knowledge_index   (source bronze.aml_knowledge,  pk doc_id,     embed body)
# model: databricks-gte-large-en. Until these are READY, the SAR agent's policy +
# adverse-media citations return empty (the rest of the SAR flow still works).
```

## 5. Rebuild the frontend (only if you change UI)
```bash
cd app/backend/frontend && npm install && npm run build
cp -r dist ../webroot     # the app serves built assets from webroot/
```
The committed `webroot/` is already built with Nedbank branding.

## 6. Verify
- `cd app/backend && .venv/bin/python -m pytest -q` → 34 passing (goAML, scoring, SLA,
  casestate, routes, guardrail). Use a **Python 3.12** venv (pydantic-core has no 3.14 wheel).
- App landing page shows the Nedbank blue/red hero; favicon is the blue tile + red "C".

---

## Director's Notes — planted signals → scenario map
Keep this handy while driving the demo. All planted IDs use `FRAUD` / `MULE` / `GAME` /
`DUP` prefixes so they are easy to trace.

### WOW-A — the hidden mule network  (detect)
- **Open:** `CASE-90001` (Lerato Sithole, `CUSTMULE01`) — a lone **cash-structuring**
  alert: 3 sub-threshold cash deposits (~R20.5k–24.5k, each under the R25k CTR).
- **Expand:** entity resolution shows 7 mules (`CUSTMULE01`–`07`) sharing device
  `DEVMULE0001`, IP `197.245.10.5`, and address `88 Recruiter St, Soweto`, all opened
  within a 3-week window. Each forwards ~R40k (≈90%) within 48h to aggregator
  `CUSTMULE00` (Kabelo Motaung, `CASE-90002`), which remits **R260k cross-border SWIFT**
  to `Onyx Capital` (Mauritius, `TPFRAUD01`).
- **Killer line:** 3 sibling mule accounts were previously alerted and **closed as false
  positives in isolation** (see `alert_feedback`) — the siloed-rules failure mode.
- **Fires:** `structuring` on each mule + `rapid_movement` on the aggregator + network
  graph + cross-border flag.

### WOW-B — STR drafted in 90 seconds  (document)
- On any hero case, run **SAR Filing** → multi-agent orchestration. The evidence pack is
  auto-gathered; the **policy agent cites** the bank AML policy + FATF typology guides
  (`aml_knowledge`), the adverse-media agent cites retrieved articles, and the supervisor
  emits a **FIC-format STR narrative** + downloadable **goAML XML** (schema-validated).
- Ask the "why structuring, not legitimate cash business?" follow-up — the evidence brief
  includes actual-vs-declared turnover so the answer is grounded.

### WOW-C — retrospective typology sweep  (anticipate)
- Ask (Genie / typology-sweep): *"third-party payment processors layering through gaming
  merchants — do we have exposure?"* → `/api/aml/typology-sweep` surfaces `CUSTGAME01`
  (Werner Pretorius, `CASE-90003`) and `CUSTGAME02`: ~30 matched card debits to a gaming
  TPP with near-equal payouts back (net ≈ 0), **never tripped a rule** (`never_alerted =
  true`).

### Supporting planted signals (legacy families, individually)
- Rapid movement `ACCFRAUD05`; velocity spike `ACCFRAUD01`; circular ring
  `ACCFRAUD01→02→03→04→01`; dormant reactivation `ACCDORM01`–`05`; risk-rating jump
  `CUSTFRAUD01/02`; adverse media (`Sipho Dlamini`/`Onyx Capital`); UBO change `TPFRAUD01`;
  account takeover `ACCATO01` (Lagos device); impossible travel 3 cards (JHB→London/
  Dubai/New York).
- Messy ER duplicates: `Jan van der Merwe` / `J. v.d. Merwe` / `Johannes vdMerwe`
  (`CUSTDUP01`–`03`, shared national_id → one entity).

### Streaming (optional live drama)
`data/stream/drop_transactions.py --scenario layering|impossible_travel|normal` drops a
JSON file into the landing volume; a plain incremental pipeline run surfaces the fresh
alert in seconds (see `fraud_aml_pipeline/CLAUDE.md`).
