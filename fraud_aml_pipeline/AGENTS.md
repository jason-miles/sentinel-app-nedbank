# Declarative Automation Bundles Project — Nedbank Fraud & AML

This project uses Declarative Automation Bundles (formerly Databricks Asset Bundles) for deployment.

## Prerequisites

Install the Databricks CLI (>= v0.288.0) if not already installed:
- macOS: `brew tap databricks/tap && brew install databricks`

Verify: `databricks -v`

## For AI Agents

Read the `databricks-core` skill for CLI basics, authentication, and deployment workflow.
Read the `databricks-pipelines` skill for pipeline-specific guidance.

If skills are not available, install them: `databricks experimental aitools skills install`

## This pipeline

Lakeflow Declarative Pipeline (SQL, serverless) for the Nedbank Wealth & Banking
Fraud & AML demo. Bronze is a raw landing zone (seeded by data/ scripts in the parent
repo). This pipeline builds:
- bronze/  — transactions_stream: near-real-time Auto Loader ingestion (STREAMING
             TABLE) from the landing volume (see "Streaming lane" below).
- silver/  — conform, dedupe, entity resolution (materialized views)
- gold/    — the 8 alert families + impossible-travel unioned into fraud_alerts,
             plus entity_network, customer_360, alert_feedback.

Default catalog/schema: elexon_app_for_settlement_acc_catalog / nedbank_fraud_aml_gold.
Silver datasets use fully-qualified names to publish into nedbank_fraud_aml_silver.

## Streaming lanes (near-real-time hot-path)

Two Auto Loader streaming lanes land JSON in the UC Volume
`nedbank_fraud_aml_bronze.landing/<lane>/` and ingest incrementally via `read_files`
STREAMING TABLEs in `transformations/bronze/`:

  * `transactions/`      -> `bronze.transactions_stream`      -> unioned into
    `silver.transactions`      -> `detect_rapid_movement` / `detect_circular_flow`.
  * `card_transactions/` -> `bronze.card_transactions_stream` -> unioned into
    `silver.card_transactions` -> `detect_impossible_travel`.

Each silver MV UNIONs the streaming table with its historical batch table and refs
the streaming table by published FQN, so Lakeflow builds a real dependency edge (the
hot-path is correct on a plain incremental run) and streamed events flow through the
existing detectors, app, and Genie space with zero downstream changes.

Demo instrument `data/stream/drop_transactions.py`:
  * `--scenario layering`          -> `rapid_movement` alert.
  * `--scenario impossible_travel` -> `impossible_travel` alert (JHB->London taps).
  * `--scenario normal`            -> benign noise, no alert.
Drop a file, then a plain (incremental) pipeline run surfaces the fresh alert in
`gold.fraud_alerts` within seconds. Both lanes verified end-to-end 2026-07-20.

NOTE: each lane's `landing/<lane>/` folder must exist before `read_files` starts
(`databricks fs mkdir dbfs:/Volumes/.../landing/<lane>`), and the streaming table
must be initialized once with `--full-refresh-all` after it is first added.

### Self-driving mode (file-arrival trigger)

`resources/fraud_stream_trigger.job.yml` defines job `fraud_aml_stream_trigger`,
a file-arrival trigger on the `landing/` root that runs the pipeline INCREMENTALLY
(full_refresh: false) whenever a file lands — so the demo self-drives (drop a file,
alert appears in ~2 min) WITHOUT a 24/7 continuous cluster. Verified 2026-07-20: a
drop auto-triggered a run (no manual `bundle run`) that fired the alert.

GOTCHA: bundle `mode: development` deploys triggers PAUSED. After deploy, unpause:
`databricks jobs update --json '{"job_id":<id>,"new_settings":{"trigger":{...,"pause_status":"UNPAUSED"}}}'`
(the trigger also needs an initial baseline scan — the very first drop may not fire;
the next one does). Latency ~1-2 min (poll interval + the 60s settle/debounce).

Deploy: `databricks bundle deploy -t dev --profile fevm-elexon-app-for-settlement-acc`
Run:    `databricks bundle run fraud_aml_pipeline_etl -t dev --profile fevm-elexon-app-for-settlement-acc`

## --full-refresh-all: needed for a first/clean build, NOT for the streaming hot-path

Most silver and gold datasets publish to *different schemas* (nedbank_fraud_aml_silver
/ _gold) and reference each other by fully-qualified name. Lakeflow does not build a
dependency edge across FQN refs to *materialized views / static tables*, so on a first
or clean build a plain incremental run can execute datasets before their upstreams are
populated (entity resolution came out empty this way). For a first build or after a
clean, run with `--full-refresh-all` so all datasets recompute in one ordered pass:

`databricks bundle run fraud_aml_pipeline_etl --full-refresh-all -t dev --profile fevm-elexon-app-for-settlement-acc`

However, the **transaction hot-path is now dependency-correct incrementally**:
`silver.transactions` references the in-pipeline STREAMING TABLE
`bronze.transactions_stream` by its published FQN, and Lakeflow DOES build an edge to a
streaming table, so a plain run (no flag) orders
`transactions_stream -> silver.transactions -> detect_rapid_movement/circular_flow ->
fraud_alerts` correctly. Verified 2026-07-20: a plain incremental run picks up a
newly-dropped file and fires the alert. So for the streaming demo, just run:

`databricks bundle run fraud_aml_pipeline_etl -t dev --profile fevm-elexon-app-for-settlement-acc`

All 9 alert families are verified to fire against the planted scenarios after a full refresh.
