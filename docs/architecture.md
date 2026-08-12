# Nedbank Sentinel — Architecture Overview

**CDP & Financial Crime Intelligence Platform on the Databricks Data Intelligence Platform.**
One governed Lakehouse replacing a legacy Data-Vault + Tabular + feed-back-to-SQL estate.

---

## 1. End-to-end architecture

```
 On-prem / BU workloads
        │  Express Route (ingress unchanged)
        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                        UNITY CATALOG  (one governance plane)                  │
 │  catalogs · schemas · grants · lineage · glossary · metric views · audit      │
 │                                                                               │
 │  BRONZE ─ raw landed feeds (Auto Loader / LF Connect; federated foreign cats) │
 │    │   customers, accounts, transactions, card_transactions, third_parties,   │
 │    │   risk_ratings, beneficial_ownership, auth_events, adverse_media, KYC docs│
 │    ▼                                                                          │
 │  SILVER ─ Lakeflow Declarative Pipeline (SQL): conform · dedupe · ENTITY      │
 │    │   RESOLUTION (deterministic NID/TAX keys + fuzzy soundex+city) → entities│
 │    ▼                                                                          │
 │  GOLD ─ detection + marts (materialized views + case mgmt)                    │
 │    │   9 detection families → fraud_alerts · entity_network · customer_360    │
 │    │   sherlock_cases/analysts/teams · exec KPI views · adverse_media (ai)    │
 │    │   write-backs: alert_feedback · case_notes · case_actions · sar_filings  │
 │    ▼                                                                          │
 │  INTELLIGENCE ─ Vector Search index (adverse media) · ai_query (Llama 3.3)    │
 │                 · ai_parse_document / ai_extract (KYC) · Genie space          │
 └───────────────────────────────┬───────────────────────────────────────────────┘
                                  │
        ┌─────────────────────────┼──────────────────────────┐
        ▼                         ▼                          ▼
   Databricks App           Genie space              Scheduled Lakeflow Job
   "Nedbank Sentinel"      "Fraud & AML Analyst"    fraud_aml_daily_report
   React + FastAPI          NL → governed SQL        (full-refresh + email)
   3 views + Ask + agents
```

---

## 2. Layers in detail

### Bronze — landing reality (as-is)
Raw feeds from on-prem + BU workloads via Express Route. Legacy Data Vault and Tabular
models are ingested here; federated sources read in place through UC foreign catalogs.
Native feeds via Auto Loader. **Nothing about the network posture changes.**

### Silver — conform + the ontology "key"
A **Lakeflow Declarative Pipeline (SQL, serverless)** conforms and deduplicates bronze, then
runs **entity resolution** — the customer-stated *key* to identifying fraudulent clients and
their related parties. Deterministic keys (namespaced `NID:` / `TAX:`) plus a fuzzy
`soundex(name)+city` fallback resolve customers **and** third parties to one stable
`entity_id`. This is what lets Sentinel say *"this customer and this third party are the same
beneficial owner."*

### Gold — detection + case management
- **9 detection families** authored as SQL rules → `fraud_alerts`: rapid movement, frequency
  change, **circular flow (recursive CTE)**, dormant reactivation, risk-rating change,
  adverse media, UBO change, account takeover, **impossible travel (geospatial)**.
  Thresholds live in a tunable `alert_config` so the room can tune live.
- **Case-management layer**: `sherlock_cases` (SLA, priority, status, team/analyst),
  `sherlock_analysts` (6 personas), `sherlock_teams` (4 teams), exec KPI/flow/team views.
- **Write-backs** (app-owned Delta tables): feedback, notes, actions, SAR filings — the
  regulatory audit trail.

### Intelligence — GenAI
- **Genie space** "Fraud & AML Analyst" — NL→governed-SQL, surfaced in-app as **Ask Sentinel**
  via the Genie Conversation API.
- **`ai_query`** (Llama 3.3 70B) — adverse-media risk summaries, executive briefing, per-case
  AI triage, smart alert prioritization, multi-agent assistant, SAR narrative generation.
- **Vector Search** — semantic adverse-media screening over the ingested corpus.
- **`ai_parse_document` / `ai_extract`** — KYC / source-of-funds document processing.

---

## 3. Application

**Databricks App "Nedbank Sentinel"** — React + FastAPI, served as a single process (all
data access through UC; app holds no business logic beyond presentation + write-backs).

| View | Purpose |
|------|---------|
| **Executive Overview** | CCO KPIs, trends, resolution flow, team performance, AI briefing |
| **Alert Investigation** | Per-analyst queue → investigation page (evidence, notes, flagged txns, entity links, multi-agent chat, AI triage, escalate/dismiss/proceed-to-SAR) |
| **SAR Filing** | AI-generated narrative → PDF → submit → audit trail |
| **Graph Explorer** | Force-directed knowledge graph + NL search + matched entities |
| **Ask Sentinel** | Genie NL analytics (answer + SQL + results) |

Auth: dual-mode — app service principal in production (granted least-privilege SELECT/MODIFY
on the relevant schemas, CAN_USE on the warehouse, CAN_RUN on the Genie space); CLI profile
for local dev.

---

## 4. Governance, lineage & DR

- **Unity Catalog** is the single governance plane: one permission model, lineage across all
  entities, glossary + metric views so Genie and the app reconcile.
- **Design Canvas** — the Lakeflow pipeline renders as a Bronze→Silver→Gold DAG a SQL-skilled
  audience can read, de-risking the "we're not Python people" anxiety.
- **Managed DR** — primary + secondary region, Deep Clone replication, ≤30-min RTO /
  ≤5-min RPO on the audit tier. See [`managed_dr_posture.md`](managed_dr_posture.md).

---

## 5. Competitive framing (vs Microsoft Fabric + AI Foundry)

| Dimension | Sentinel on Databricks | Fabric + AI Foundry |
|-----------|------------------------|---------------------|
| Data plane | One governed Lakehouse (UC) | Split OneLake / warehouse / semantic model surfaces |
| Detection | SQL-authored declarative pipelines the team owns | Stitched Foundry + Fabric orchestration |
| Semantics | Genie NL + metric views — one answer layer | Multiple semantic surfaces to reconcile |
| Graph / geospatial | Native (recursive CTE, H3/ST_) | Awkward across two products |
| Ownership | Existing SQL skills are enough | Python/ML skill gap |

**Through-line:** *do less, get more — and your existing SQL skills are enough.*

---

## 6. Repository map

```
sql/                 versioned DDL/logic (foundation, silver, gold, intelligence, governance)
data/                synthetic data seeder + planted fraud scenarios; data/stream/ file-drop generator
fraud_aml_pipeline/  Lakeflow Declarative Pipeline bundle (deployed) + jobs
ml/                  SAR-propensity model: train + batch-score scripts (MLflow → UC registry)
app/backend/         FastAPI + React (Nedbank Sentinel Databricks App) + tests/ + frontend/e2e/
dashboards/          Lakeview AI/BI dashboard JSON (exec overview)
genie/               Genie space curation (glossary + certified queries)
resources/           root-bundle app + retrain-job resources; databricks.yml unifies deploy
.github/workflows/   CI (pytest + build + bundle validate) + deploy on merge
docs/                architecture · ci_cd · managed_dr_posture · demo_runbook · App Screenshots
```

## 7. Platform enhancements (post-v1)

Delivered on top of the v1 baseline (each is deployed & verified; see BUILD_LOG / git):

- **Streaming ingestion (near-real-time).** Auto Loader STREAMING TABLEs
  `bronze.transactions_stream` + `bronze.card_transactions_stream` from a UC Volume
  landing zone, UNIONed into the batch silver so detectors/app/Genie see streamed
  events unchanged. A file-arrival **triggered job** (`fraud_aml_stream_trigger`)
  makes it self-driving: drop a file → alert surfaces in ~2 min, no manual run.
  Instrument: `data/stream/drop_transactions.py` (layering / impossible_travel).
- **Supervised ML detection.** GBT SAR-propensity model (`ml/`) trained via MLflow,
  registered to the **UC Model Registry**, batch-scored into `gold.ml_alert_scores`
  (model/rules blend → the app's "AI Risk"). Governance surface in the Compliance
  tab: validation metrics + **15.8% fewer false positives** at equal alert budget,
  **feature-drift monitoring** (`ml_feature_baseline`/`ml_drift_metrics`), and a
  weekly retrain job. Feature/label + drift SQL in `sql/05_intelligence/`.
- **Bank-grade governance** (`sql/06_governance/`): UC **column masks** on PII
  (masked-by-default), a **row filter** for team entitlement, an immutable
  **audit_log** (case reads/decisions/SAR actions), and an **LLM eval + guardrail**
  record for the SAR GenAI surface. Lakeflow **data-quality expectations** on every
  medallion dataset.
- **Multi-agent SAR + goAML.** Supervisor over specialist agents with an
  auto-gathered evidence pack (incl. **vector-search adverse media**); goAML-format
  **STR XML** output with structural validation; a **four-eyes** approval gate and a
  case **state machine** (`server/casestate.py`). See `server/routes/sar_agents.py`,
  `sar_eval.py`.
- **App/UX.** Cytoscape Graph Explorer, dark mode, live-refreshing queue + exec,
  server-side queue filtering, embedded AI/BI dashboard (Reports), an accessibility
  pass, SLA tracking + reassignment.
- **CI/CD & tests.** pytest (backend, mocked DB) + Playwright e2e; GitHub Actions;
  a root `databricks.yml` consolidating app + pipeline + jobs (migration pending —
  see NEXT_STEPS #6).
