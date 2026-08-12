# Managed Disaster Recovery Posture — Nedbank Sentinel

**Audience:** Champion / Platform owner (Walter Kielblock) · Compliance & Risk
**Purpose:** Articulate the resilience story for the Sentinel CDP & Financial Crime
Intelligence Platform on Databricks. Resilience is a named decision criterion; this
document states the DR architecture, replication mechanics, and the RTO/RPO commitments.

---

## 1. Why this matters

AML/financial-crime monitoring is a regulated, always-on control. An outage that stalls
alert generation or blocks SAR filing is both an operational and a **regulatory** exposure.
Sentinel is architected so that a full regional failure degrades gracefully and recovers
within a stated, testable window — **without** the legacy multi-model, feed-back-to-SQL
sprawl that made the current estate fragile.

The "do less, get more with Unity Catalog" narrative is also the resilience narrative:
**one governance plane** to replicate, **one lineage graph** to restore, **one permission
model** to re-establish — instead of reconciling Data Vault, Tabular models, and downstream
SQL databases independently.

---

## 2. Topology: primary + secondary region

```
        ┌──────────────────────── PRIMARY REGION (eu-central-1) ───────────────────────┐
        │                                                                               │
Express │   Auto Loader / LF Connect      Unity Catalog metastore (primary)             │
Route   │   ┌───────────┐   ┌──────────┐  ┌───────────────────────────────────────┐    │
─────────►  │  Bronze   │──►│  Silver  │─►│  Gold: fraud_alerts, cases, customer_360│    │
(ingress)│  └───────────┘   └──────────┘  └───────────────────────────────────────┘    │
        │        │  Lakeflow Declarative Pipeline (SQL, serverless)     │  Genie · App  │
        │        ▼                                                       ▼               │
        │   Delta Deep Clone / managed replication ───────────────┐    Databricks App   │
        └─────────────────────────────────────────────────────────┼───────────────────┘
                                                                    │  (async replication)
        ┌──────────────────────── SECONDARY REGION (eu-west-1) ─────▼───────────────────┐
        │   UC metastore (replica) · replicated Delta tables · standby pipeline + app   │
        └───────────────────────────────────────────────────────────────────────────────┘
```

- **Ingress unchanged.** On-prem + BU workloads continue to land via **Express Route**;
  DR does not change network posture (an explicit non-goal). On failover, ingress is
  re-pointed to the secondary region's landing endpoints.
- **Compute is serverless.** Lakeflow pipelines and the Databricks App run on serverless
  compute, so there is **no cluster fleet to rebuild** in the secondary region — capacity
  is provisioned on demand at failover.

---

## 3. What is replicated, and how

| Layer | Mechanism | Notes |
|-------|-----------|-------|
| **UC metastore & governance** | Metastore replication (managed) | Catalogs, schemas, grants, lineage, glossary, metric views. One plane to restore. |
| **Delta tables (bronze/silver/gold)** | **Deep Clone** (incremental) + managed table replication | `CREATE TABLE ... DEEP CLONE ...` incremental refresh to the secondary metastore; only changed files ship. |
| **Detection logic** | Git + Databricks Asset Bundle | The Lakeflow pipeline is code (`fraud_aml_pipeline/`) in GitHub; redeploy to the secondary workspace via `databricks bundle deploy`. No state to migrate. |
| **Genie space & app** | Bundle / config replication | Genie space serialized config + app source (bundle) redeploy from Git; SP grants re-applied from IaC. |
| **App write-backs** (alert_feedback, case_notes, case_actions, sar_filings, SARs) | Deep Clone (frequent) | Audit-critical — replicated on the tightest cadence (see RPO). |

**Key point for the room:** because detection is **SQL-authored declarative code** and the
app is **stateless** (all state in UC), DR is mostly *data replication + code redeploy* —
there is no bespoke application state or orchestration engine to recover.

---

## 4. RTO / RPO commitments

| Tier | Data set | RPO (max data loss) | RTO (max downtime) |
|------|----------|---------------------|--------------------|
| **1 — Audit / SAR** | `sar_filings`, `case_actions`, `alert_feedback` | **≤ 5 min** (continuous Deep Clone) | **≤ 30 min** |
| **2 — Case & alert marts** | `fraud_alerts`, `sherlock_cases`, `customer_360`, `entity_network` | **≤ 15 min** | **≤ 1 hour** |
| **3 — Raw & derived** | bronze, silver, VS index | **≤ 1 hour** (rebuildable from bronze) | **≤ 4 hours** (pipeline full-refresh) |

- **Tier 3 is rebuildable**, not just replicated: silver/gold are declarative MVs, so a
  secondary-region `databricks bundle run --full-refresh-all` regenerates them from bronze.
- The audit tier (SARs, decisions) carries the tightest RPO because it is the regulatory
  system of record.

---

## 5. Failover procedure (summary)

1. **Detect** — regional health alarms; monitoring confirms primary unavailability.
2. **Promote** — secondary UC metastore replica becomes authoritative; verify latest
   Deep Clone watermark on Tier-1 tables.
3. **Redeploy** — `databricks bundle deploy -t dr` + `bundle run --full-refresh-all` for
   the pipeline; `databricks apps deploy` for Sentinel; re-apply SP grants + Genie space.
4. **Re-point ingress** — Express Route / Auto Loader to secondary landing.
5. **Validate** — run the planted-scenario smoke test (all 9 detection families fire),
   confirm Ask Sentinel / Genie responds, confirm SAR write-back.
6. **Communicate** — notify compliance; log the failover in the audit trail.

**Failback** reverses the flow once the primary region is healthy and re-synced.

---

## 6. Testing & governance

- **DR drills** are scheduled (quarterly recommended) and scripted; the planted-scenario
  suite doubles as the failover validation test.
- Every failover/failback is **auditable** — logged to the same UC-governed tables that
  carry the SAR audit trail.
- Because governance lives in UC, **access controls survive failover** unchanged — no
  re-permissioning drift between regions.

---

## 7. One-line summary for the champion

> *Sentinel runs on one governed Lakehouse. DR is data replication (Deep Clone) plus a
> code redeploy from Git — no fragile orchestration state, serverless compute with nothing
> to rebuild, and a tested ≤30-minute RTO / ≤5-minute RPO on the audit tier. Do less, get
> more — including when a region goes down.*
