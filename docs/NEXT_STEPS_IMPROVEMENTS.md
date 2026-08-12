# Nedbank Sentinel — Next Steps & Improvement Ideas

**For:** any engineer or AI/LLM agent picking up this app.
**Read first:** `BUILD_LOG.md` (what exists and why) and `app/docs/architecture.md`.

This is a **demo-grade** platform: real Databricks primitives, real GenAI, realistic
synthetic data, but built for a stakeholder demo — not production. Below is what to
improve to make it more realistic, enterprise-ready, and bank-grade for AML.

---

## 0. Current state (baseline)

- SQL-first medallion (bronze/silver/gold) on Unity Catalog; Lakeflow declarative
  detection pipeline (9 families) + sanctions screening, pKYC, peer anomaly.
- React + FastAPI Databricks App (Nedbank Sentinel): Executive Overview, Alert
  Investigation, Compliance, Graph Explorer, Ask Sentinel (Genie).
- GenAI: Genie NL analytics, multi-agent assistant, AI triage/briefing/prioritize,
  SAR narrative generation, adverse-media summaries.
- 650 synthetic cases, 6 analysts / 4 teams, planted fraud scenarios.

---

## 1. Data realism & scale (highest impact for "enterprise-ready")

- **Real-scale data**: move from 5K customers / 2.4M txns to tens of millions of
  txns; partition/liquid-cluster the fact tables; validate detection performance and
  cost at scale (this is where the Lakehouse story is won or lost).
- **Streaming ingestion**: replace batch full-refresh with **Structured Streaming /
  Lakeflow streaming tables + Auto Loader** so alerts are near-real-time (matches the
  "faster payments require near-real-time compliance" market trend). Today the
  pipeline requires `--full-refresh-all`; make silver/gold incremental and
  dependency-correct (avoid cross-schema FQN refs that break the DAG).
  - ✅ **DONE (2026-07-20) — transaction hot-path vertical slice.** Auto Loader
    STREAMING TABLE `bronze.transactions_stream` ingests JSON from the UC Volume
    `bronze.landing/transactions/`; `silver.transactions` UNIONs it with the
    historical batch feed, so rapid_movement/circular_flow (+ all detectors), the
    app, and Genie see streamed txns with no downstream change. The hot-path now
    builds a real dependency edge (silver → the in-pipeline streaming table), so a
    plain incremental run — no `--full-refresh-all` — orders correctly and fires the
    alert. Demo instrument: `data/stream/drop_transactions.py`.
  - ✅ **DONE (2026-07-20) — card-transaction lane.** Same pattern:
    `bronze.card_transactions_stream` (Auto Loader) unioned into
    `silver.card_transactions`, feeding `detect_impossible_travel`. Verified: a
    dropped JHB→London two-tap file fires a critical `impossible_travel` alert
    (18,120 km/h) on a plain incremental run. New scenario in the generator:
    `--scenario impossible_travel`.
  - ✅ **DONE (2026-07-20) — self-driving (file-arrival trigger).** Job
    `fraud_aml_stream_trigger` runs the pipeline incrementally on file arrival in
    the `landing/` root, so a dropped file auto-processes (~2 min) with no manual
    run and no 24/7 continuous cluster — the cost-aware "always-on" story for a
    shared workspace. Verified end-to-end.
  - Remaining for full coverage: convert master-table silver
    (customers/accounts/risk/UBO) to AUTO CDC (`APPLY CHANGES`) so master-data
    updates stream too; optionally true continuous mode if always-on latency
    (vs the ~2 min trigger latency) is ever required.
- **Realistic typology injection**: replace hand-planted scenarios with a
  configurable scenario generator (parameterised ring sizes, layering depth,
  smurfing patterns) so detection can be stress-tested.
- **Reference data**: integrate real sanctions/PEP list *formats* (OFAC SDN XML,
  UN Consolidated, EU CFSP) and a proper watchlist refresh cadence, rather than a
  10-row synthetic table.

## 2. Detection quality

- **Supervised ML models**: train gradient-boosted / graph-neural models on labelled
  outcomes (SAR-filed vs dismissed) via MLflow + Unity Catalog model registry; serve
  via Model Serving and blend model score with rules (the app already displays a
  rules score + an ai_query "AI risk" — replace the latter with a real served model).
  - ✅ **DONE (2026-07-20).** GBT (`sar_propensity_gbt`, v2) trained via MLflow,
    registered to UC Model Registry. Feature/label tables in
    `sql/05_intelligence/05_ml_features_labels.sql` (label = multivariate severity×
    amount interaction the rules score can't capture). Batch-scored into
    `gold.ml_alert_scores` (model/rules blend → `ai_risk`); app now shows a real
    "AI Risk ✦" column + KPI (model version tooltip) next to the legacy rules score,
    and the alert queue sorts by it. **At equal alert budget the model flags 15.8%
    fewer false positives than rules-only** (AUC 0.65 — deliberately realistic).
    Chosen serving = batch (SQL-first, no standing endpoint cost). Scripts:
    `ml/train_sar_model.py`, `ml/score_sar_model.py`.
  - ✅ **Model governance surface (2026-07-20).** Compliance page gains a "Model
    Governance" tab (backed by `gold.ml_model_metrics` via `/api/aml/model-governance`)
    showing the validation record regulators ask for: AUC/precision/recall/F1, the
    15.8% FP-reduction narrative, model name/version/registry/run, feature & label
    counts, and the model/rules blend weights.
  - ✅ **Drift monitoring + retrain job (2026-07-20).** `gold.ml_feature_baseline`
    (training-time distribution) + `gold.ml_drift_metrics` (current-vs-baseline
    standardised mean shift, status stable/warning/drift) —
    `sql/05_intelligence/06_ml_drift_monitoring.sql`. Surfaced in the Model
    Governance tab (Feature Drift panel + overall verdict, `/api/aml/model-drift`).
    Scheduled retrain job `resources/fraud_ml_retrain.job.yml` (root bundle) rebuilds
    features/labels + refreshes drift weekly.
  - Remaining: champion/challenger; Lakehouse Monitoring native; Model Serving
    endpoint for live inference if needed.
- **Model risk management**: threshold-tuning workbench, champion/challenger, backtest
  harness, drift monitoring (Lakehouse Monitoring), and an auditable model-governance
  record — regulators require documented model validation.
- **Graph algorithms**: real community detection / centrality / shortest-path over the
  entity graph (GraphFrames) instead of the app-side radial layout; surface rings and
  hidden UBO links algorithmically.
- **Feature store**: move entity/behavioural features into Databricks Feature Store
  for reuse across detection, pKYC, and anomaly models.

## 3. Perpetual KYC & customer risk

- **Event-driven re-rating**: recompute pKYC on triggers (new alert, sanctions hit,
  adverse media, transaction spike) rather than on view read; persist a risk history
  table so **risk trajectory over time** can be charted.
- **CDD/EDD workflow**: turn the `edd_review_required` flag into a real EDD case type
  with its own queue, document-request checklist, and periodic-review scheduling.
- **Risk model transparency**: expose the weight of each pKYC component and let a
  steward tune weights (config table + UI), with change audit.

## 4. Investigation workflow & agents

- **True multi-agent orchestration**: replace the per-agent ai_query calls with a
  Databricks **Agent Bricks / Mosaic AI multi-agent supervisor** (tool-calling agents
  for policy Q&A, adverse media, transaction analysis, SAR drafting) with a shared
  memory of the case; add tool use over the actual gold tables.
  - ✅ **DONE (2026-07-20).** `server/routes/sar_agents.py` — supervisor pattern:
    three specialist agents (transaction analysis, adverse media, policy) reason
    over a SHARED auto-gathered evidence brief; supervisor synthesises the SAR
    citing their findings. `/api/sar/orchestrate` returns evidence + agent trace +
    narrative; SAR Filing page shows the trace. (Next: move to Agent Bricks proper
    with real tool-calling over gold tables + eval harness.)
- **Evidence auto-gathering**: an agent that assembles the full evidence pack
  (transactions, network, prior SARs, KYC docs) on case open, cutting the analyst's
  manual correlation to zero.
  - ✅ **DONE (2026-07-20).** `gather_evidence()` assembles case + flagged
    transactions + counterparty network + sanctions/watchlist hits + perpetual-KYC
    risk from the real tables; surfaced as the "Auto-Gathered Evidence Pack" on the
    SAR Filing page. (Next: prior-SAR history + KYC docs via vector search.)
- **Case state machine**: enforce valid transitions (new→assigned→in_progress→
  escalated/closed) with SLAs, reassignment, four-eyes approval on SAR filing, and
  full audit — today status is a free field.
  - ✅ **DONE (2026-07-20).** State machine in `server/casestate.py` (pure,
    6 unit tests) enforces valid transitions; `POST /api/sherlock/case/transition`
    updates status only on valid moves and audits rejections. **Four-eyes** on SAR
    filing: `/sar/submit` requires an `approved_by` distinct from `filed_by`
    (`sherlock_sar_filings.approved_by` column added) — same-person/missing approval
    is blocked + audited; SAR page has an approver field that gates the File button.
    SQL: `sql/06_governance/05_case_workflow.sql`. Remaining: SLAs, reassignment.
- **Real SAR output**: generate goAML / FinCEN-format XML (not just a narrative +
  "PDF"), with validation against the schema and a submission connector.
  - ✅ **DONE (2026-07-20).** `build_goaml_xml()` emits UN/UNODC goAML-format STR
    XML (report header, reporting entity, activity, suspicious party, transactions,
    indicators, reason) from case + evidence; `/api/sar/goaml/{case_id}` serves a
    download; "Download goAML XML" button on the SAR Filing page. Well-formedness
    validated.
  - ✅ **Schema validation DONE (2026-07-20).** `validate_goaml()` (pure, stdlib
    ElementTree) checks the required goAML STR structure/cardinality/types (12
    checks: report_code=STR, activity, suspicious_party.party_name, ≥1 transaction
    w/ number+numeric amount, currency, numeric total, reason…). Endpoint
    `/api/sar/goaml/validate/{case_id}`; a pass/fail **validation badge + issue
    list** on the SAR page. 3 unit tests. (Next: validate against the OFFICIAL goAML
    XSD via lxml.etree.XMLSchema + a FIC submission connector.)

## 5. Governance, security & compliance (bank-grade)

- **Row/column-level security & masking** on PII (UC row filters + column masks);
  segregate data by BU and analyst entitlement.
  - ✅ **Column masking DONE (2026-07-20).** UC mask functions
    (`mask_email/phone/dob/addr`) applied to bronze customers + third_parties;
    masked by default, cleartext only for the `aml_pii_reviewers` account group.
    Applies uniformly across app/Genie/ad-hoc SQL. ER keys (national_id/tax_number)
    left unmasked by design (would break entity resolution — prod tokenises at
    ingest). SQL: `sql/06_governance/01_pii_column_masks.sql`.
  - ✅ **Row-level security DONE (2026-07-20).** UC ROW FILTER `rls_case_team` on
    `sherlock_cases` keyed on team_id: full visibility for the app SP + the
    `aml_compliance_oversight` group + deploying owner; per-team analyst groups
    (`aml_team_<team_id>`) see only their team; else no rows. Fully enforced for
    direct queriers (Genie/BI/ad-hoc). SQL: `sql/06_governance/03_rls_row_filter.sql`.
    Verified: app SP whitelisted so the app is unbroken (still RUNNING, sees all).
    Per-analyst enforcement through the app needs OBO (deferred).
- **On-behalf-of (OBO) auth** in the app so queries run as the logged-in user (today
  the app uses a single service principal) — required for per-user audit and least
  privilege. *(Deferred — substantial auth rework; see scope note. The audit trail
  below stamps the acting persona in the interim.)*
- **Full audit & lineage**: every read/decision/SAR captured; use UC lineage +
  system tables for a defensible audit trail; retention policies per regulation.
  - ✅ **Audit trail DONE (2026-07-20).** `gold.audit_log` captures case opens,
    notes, case actions, and SAR filings stamped with acting persona + timestamp
    (backend `audit()` helper). Surfaced in the Compliance page "Audit Trail" tab
    (`/api/aml/audit`). SQL: `sql/06_governance/02_audit_log.sql`.
  - Remaining: UC lineage/system-tables integration + retention/immutability policy.
- **Secrets & config**: move IDs/hosts out of `app.yaml` env into Databricks secrets
  / bundle variables; parameterise catalog/schema so the app is account-portable.
- **Real DR drill**: implement and test the `managed_dr_posture.md` plan (Deep Clone
  jobs, secondary-region bundle target, failover runbook automation).

## 6. Application & UX

- **Consolidate to a bundle-deployed app** (databricks.yml `app` resource) so the app,
  pipeline, and job deploy together and grants auto-apply — removes the manual
  sync/deploy + grant steps in the build log.
  - ✅ **DONE (2026-07-20).** Root `databricks.yml` (bundle `nedbank_sentinel`)
    unifies the app (`resources/nedbank_app.app.yml` — adopts the existing
    `nedbank-fraud-aml` app by name) + pipeline + jobs via includes, with dev/prod
    targets and variables. `bundle validate` passes. Migration note in the file:
    cut the live pipeline over from the nested `fraud_aml_pipeline/` bundle
    deliberately, then retire it.
- **Charts/UX**: the Graph Explorer uses a hand-rolled SVG force layout; move to a
  real graph lib (Cytoscape/Sigma) for large graphs; virtualise long tables;
  add server-side pagination/filtering to the alert/case endpoints.
  - ✅ **Server-side queue filtering DONE (2026-07-21).** `/queue/{id}` accepts
    `priority` (validated vs the known set) + `scenario` (parameter-bound) filters;
    the queue has priority/scenario dropdowns + Clear, applied through the live
    poller. Injection-safe (test asserts binding + that a bad priority is dropped).
    Remaining: table virtualisation, pagination.
  - ✅ **Graph lib DONE (2026-07-20).** Graph Explorer rebuilt on cytoscape.js —
    interactive pan/zoom/drag, physics `cose` layout, click-to-select node panel
    (label/type/connections). Same data shape + KIND_COLOR + legend + side panels.
    Remaining: table virtualisation, server-side pagination/filtering.
- **Dark mode** ✅ **DONE (2026-07-20).** `[data-theme="dark"]` CSS-var override
  (flipped surfaces, gold accent retained, brighter severity colours) + a ☾/☀ toggle
  in the top bar persisted to localStorage, defaulting to `prefers-color-scheme`.
  Graph canvas uses `--graph-bg` so it themes too.
- **Real-time updates**: WebSocket/polling so exec KPIs and queues refresh live
  (the screenshots imply a "40s ago" refresh indicator).
  - ✅ **DONE (2026-07-20).** Both the alert queue AND the Executive Overview poll
    every 20s (silent refresh, no spinner) with a shared Live/Pause control +
    "updated Ns ago" indicator (`LiveControls`/`LiveDot`/`sinceLabel` in
    components/ui.tsx). Pairs with the self-driving streaming trigger — a dropped
    file surfaces live. Remaining: WebSocket push (vs polling).
- **Accessibility & i18n**, dark mode, and an embedded AI/BI dashboard on the Reports
  surface (currently a Recharts bar).
  - ✅ **Accessibility pass DONE (2026-07-21).** aria-labels on all form controls
    (search inputs, filters, textareas, persona/approver); chip spans + landing CTAs
    converted to real keyboard-operable `<button>`s; skip-to-content link + `<main>`
    landmark; global `:focus-visible` outline. Remaining: i18n, full WCAG audit.
  - ✅ **Embedded AI/BI dashboard DONE (2026-07-20).** Published Lakeview dashboard
    "Nedbank Sentinel — Executive Overview" (KPI counters + daily-alerts line +
    scenario bar + team-performance table over the exec gold views); embedded via a
    new Reports nav tab (iframe, env-driven `/api/config`, direct-open fallback).
    JSON in `dashboards/exec_overview.lvdash.json`. Remaining: accessibility/i18n,
    dark mode, real graph lib.

## 7. Testing, CI/CD & observability

- **Automated tests**: pytest for backend endpoints, Playwright for the UI (the
  DevHub `web-devloop-tester` pattern), and SQL data-quality **Lakeflow
  expectations** on every dataset.
  - ✅ **DONE (2026-07-20).** pytest suite (`app/backend/tests/`, 13 tests) covering
    goAML XML, evidence brief, AI-risk blend, and route smoke tests with a mocked DB
    (no warehouse). Lakeflow **expectations** added to `fraud_alerts`
    (alert_id/severity/score/alert_type) and `silver.transactions`
    (transaction_id/amount) — verified passing on a live run.
  - ✅ **Expectations on ALL silver datasets (2026-07-21).** PK-non-null (+ domain
    checks) on accounts, customers, card_transactions, risk_ratings, entity_map,
    third_parties, beneficial_ownership, auth_events, adverse_media, entities.
    DROP ROW only on immutable feeds (card_transactions, adverse_media); WARN on the
    master/ER tables (dropping would break entity resolution/joins). Verified: full
    pipeline run COMPLETED clean, no legitimate rows dropped.
  - ✅ **Playwright UI tests DONE (2026-07-20).** `app/backend/frontend/e2e/` +
    `playwright.config.ts` (runs against `vite preview`, API stubbed via route
    interception — no backend/warehouse). Covers landing cards + queue→investigation
    with the breached-SLA badge. Wired into CI as the `e2e` job. **SAR-flow e2e
    added (2026-07-21):** evidence pack + grounded media + goAML validation badge
    (12/12) + four-eyes gate (disabled → same-person blocked → distinct approver
    enables → filed). 3 e2e tests pass. Remaining: expectations on remaining datasets.
- **CI/CD**: GitHub Actions → `databricks bundle validate/deploy` on merge; run Isaac
  Review in CI; block on failing expectations.
  - ✅ **DONE (2026-07-20).** `.github/workflows/ci.yml` (PR: pytest + frontend
    build + `bundle validate`) and `deploy.yml` (merge→main: test → build UI →
    `bundle deploy -t prod`). Setup + required OAuth secrets documented in
    `docs/ci_cd.md`. Remaining: add the M2M service-principal secrets to the GitHub
    repo to activate deploy; wire Isaac Review as a CI job.
- **Observability**: app + pipeline metrics/logs to a monitoring surface; alert on
  pipeline failures, latency, and cost.

## 8. Genie & GenAI depth

- **Genie curation**: add SQL example queries, joins, and a richer glossary to the
  space so NL answers are more accurate; add certified metrics.
  - ✅ **DONE (2026-07-20).** Enriched the "Fraud & AML Analyst" space with a
    glossary (SAR/EDD/pKYC/PEP/UBO/typology), grain & join guidance, and answer
    conventions (applied via the space description, which Genie uses as context) +
    6 improved sample questions mapping to certified queries. Verified: NL question
    "how many customers require EDD review by risk band?" produced correct SQL
    (understood EDD from the glossary). 6 validated example queries saved in
    `genie/fraud_aml_analyst_space.json`. NOTE: the REST serialized_space rejected
    `instructions`/`curated_questions` keys — attach the SQL as certified answers via
    the Genie UI (see `genie/README.md`). Remaining: certified metrics.
- **Grounded SAR & adverse media**: RAG the SAR narrative against actual case
  evidence + policy docs (vector search) rather than a metadata prompt; cite sources.
  - ✅ **DONE (2026-07-20).** The SAR orchestration now vector-searches
    `gold.adverse_media_index` (valterra-vs-endpoint) for the subject+typology and
    folds retrieved articles into the shared evidence brief; the supervisor is
    instructed to cite them by source. Surfaced as a "Grounded Adverse Media" panel
    (headline/source/date/relevance) on the SAR page. `retrieve_adverse_media()` in
    `server/routes/sar_agents.py` (best-effort; app SP granted SELECT on the index).
    Remaining: RAG over policy docs too; source-citation eval.
- **Guardrails & evaluation**: add Mosaic AI guardrails + an eval harness
  (faithfulness/accuracy) for every LLM surface — regulators will ask how the AI is
  validated.
  - ✅ **DONE (2026-07-20) for the SAR surface.** `server/routes/sar_eval.py` runs
    LLM-as-judge groundedness + completeness (ai_query) and a deterministic PII/length
    guardrail per generated SAR; persists to `gold.llm_eval_results`
    (`sql/06_governance/04_llm_eval_results.sql`). Surfaced as an "LLM Evaluation &
    Guardrails" panel in the Model Governance tab (groundedness/completeness/
    guardrail/overall pass rates), and `/api/aml/llm-eval/run` evaluates a case
    on demand. Guardrail is a pure unit-tested function (4 tests).
    Remaining: extend evals to the other LLM surfaces (agent chat, triage); native
    Mosaic AI guardrails/AI Gateway.

---

## Suggested priority order

1. Streaming ingestion + incremental pipeline (realism + the marquee tech story).
2. Supervised ML detection + Model Serving + model governance (the "75% fewer false
   positives" claim needs a real model behind it).
3. RLS/masking + OBO auth + full audit (table stakes for a bank).
4. True Agent Bricks multi-agent + goAML SAR output.
5. Bundle-deploy everything + CI/CD + tests.

## Pointers for an AI agent continuing this work

- The repo is self-contained under `app/`. Start with `app/README.md`,
  `app/docs/architecture.md`, and `BUILD_LOG.md §"How to rebuild"`.
- SQL is the source of truth for data; the Lakeflow bundle is in
  `app/fraud_aml_pipeline/`; the app is `app/app/backend/` (FastAPI + `frontend/`).
- Everything is parameter-light — search for the catalog/schema/warehouse/space IDs
  in the BUILD_LOG "Key IDs" table and replace for a new account.
- Re-run detection with `--full-refresh-all` (known dependency caveat).
