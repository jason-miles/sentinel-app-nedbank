# Nedbank Sentinel on Databricks — Deck Source (NotebookLM)

> **How to use this file:** Load it into Google NotebookLM as a source, then prompt:
> *"Create a professional slide deck from this document. One slide per `## Slide`
> heading. Use the bullet points as slide content and the 'Speaker notes' as the
> presenter script."* Audience: **Nedbank data & platform engineering** (technical),
> with financial-crime stakeholders in the room. Tone: architecture-led, evidence-
> backed, vendor-displacement aware (incumbent: Azure AI Foundry + Microsoft Fabric).

---

## Slide 1 — Title

**Nedbank Sentinel**
CDP & Financial Crime Intelligence Platform on the Databricks Data Intelligence Platform

- One governed Lakehouse for AML detection, investigation, and regulatory reporting
- Built SQL-first; GenAI and ML native; deployed and running today

**Speaker notes:** Sentinel is a working demo — not slideware. Every capability shown
is deployed on Databricks and exercised against realistic synthetic data. The thesis:
the entire AML value chain — ingest, detect, investigate, decide, report, govern — can
live on one platform, replacing a fragmented Data Vault + Tabular + Fabric estate.

---

## Slide 2 — The problem: AML is a data-integration problem

- Financial crime detection fails at the seams between systems, not within them
- Legacy estate: siloed feeds, batch-only, weak lineage, rules that over-alert
- Regulators now expect **near-real-time** monitoring, explainable models, and a
  defensible audit trail for every decision and every model
- Analysts drown in false positives; investigations are manual correlation

**Speaker notes:** Frame AML as a data problem. The hard part isn't any single
detection rule — it's unifying customers, accounts, transactions, third parties,
sanctions lists and adverse media into one governed, current view, then acting on it
with an audit trail. That is precisely what a Lakehouse + Unity Catalog is for.

---

## Slide 3 — Architecture at a glance

- **Unity Catalog** — one governance plane: catalogs, schemas, grants, lineage,
  masking, row-level security, audit
- **Medallion (SQL-first, Lakeflow Declarative Pipelines):** Bronze (raw + streaming)
  → Silver (conform, dedupe, **entity resolution**) → Gold (detection + case mgmt)
- **Intelligence layer:** Vector Search, `ai_query` (Llama), MLflow model, Genie
- **Serving:** a Databricks App (React + FastAPI), a Genie space, and jobs — all
  reading the same governed gold tables

**Speaker notes:** Walk left to right. The key architectural point for this audience:
there is exactly one copy of the data and one permission model. The app, the Genie NL
interface, the ML model, and the pipeline all bind to the same Unity Catalog objects —
no extracts, no copies, no second security model to reconcile.

---

## Slide 4 — Near-real-time ingestion (streaming)

- **Auto Loader streaming tables** ingest transaction + card-tap feeds from a UC
  Volume landing zone as files arrive
- Streaming feeds are UNIONed into the batch Silver, so **detectors, app, and Genie
  see new events with zero downstream change**
- A **file-arrival triggered job** makes it self-driving: drop a file → alert
  surfaces in ~2 minutes, no manual run, no 24/7 cluster cost
- Demonstrated: a layering scenario and an "impossible travel" card scenario both
  fire alerts end-to-end

**Speaker notes:** This is the marquee technical story and directly answers the
"faster payments need faster compliance" regulatory trend. The design choice worth
calling out: streaming and batch share one Silver table via a UNION, and the detectors
were untouched — that's the Lakehouse letting you evolve ingestion without a rewrite.

---

## Slide 5 — Entity resolution: the ontology "key"

- Silver resolves customers + third parties to a stable `entity_id`
- Deterministic keys (national ID / tax number, namespaced) + fuzzy fallback
  (soundex(name) + city)
- Every alert, case, and graph edge hangs off the resolved entity — the backbone of
  network analysis and UBO discovery

**Speaker notes:** Entity resolution is where most AML programs win or lose. Doing it
in Silver, in SQL, under Unity Catalog governance means the "who is this really"
question has one auditable answer that every downstream surface inherits.

---

## Slide 6 — Detection: 9 typology families

- Rules-based detection in SQL → one common `fraud_alerts` schema: rapid movement,
  circular flow, structuring, dormant reactivation, frequency spike, risk-rating
  change, UBO change, account takeover, impossible travel
- A tunable `alert_config` table so thresholds are governed, not hard-coded
- **Data-quality expectations (Lakeflow) on every dataset** — invariants enforced and
  surfaced as pipeline DQ metrics

**Speaker notes:** The rules are deliberately transparent SQL — auditable and owned by
a SQL-skilled team. The point for engineers: detection is declarative pipeline code
under version control with data-quality gates, not a black box.

---

## Slide 7 — Supervised ML: fewer false positives, provably

- Gradient-boosted **SAR-propensity model** trained via **MLflow**, registered to the
  **Unity Catalog Model Registry**, batch-scored into gold
- Displayed "AI Risk" blends the model score with the rules score (rules as a floor)
- **15.8% fewer false positives at an equal alert budget** vs rules-only, measured on
  a held-out test set
- **Feature-drift monitoring** + a scheduled retrain job = ongoing validation

**Speaker notes:** This makes the "reduce false positives" claim real and measurable,
not marketing. And it's governed: the model is a first-class UC asset with a registry
version, logged metrics, and drift tracking — the model-risk-management evidence a
regulator will ask for.

---

## Slide 8 — Multi-agent investigation + regulator-grade SAR

- **Evidence auto-gathering**: on case open, the pack assembles itself — flagged
  transactions, counterparty network, sanctions/watchlist hits, perpetual-KYC risk,
  and **vector-search-retrieved adverse media**
- **Multi-agent supervisor** (Mosaic AI `ai_query`): specialist agents (transaction
  analysis, adverse media, policy) reason over shared evidence; a supervisor
  synthesises a **grounded, source-cited SAR narrative**
- **goAML-format STR XML** output with structural validation (UN/UNODC standard)
- **Four-eyes approval** + a case **state machine** — bank workflow controls, audited

**Speaker notes:** This is where GenAI earns its place: it collapses hours of manual
correlation into a pre-assembled, cited evidence pack, and outputs a real regulatory
filing artifact — not just a narrative blob. The four-eyes gate and state machine show
this is built for a regulated process, not a chatbot demo.

---

## Slide 9 — GenAI you can trust: eval + guardrails

- Every SAR is scored by an **LLM-as-judge** (groundedness + completeness) and a
  deterministic **PII/length guardrail**; results persist for audit
- Genie space is **curated** (glossary, join guidance, certified queries) so NL
  answers are accurate
- Answers the regulator's question directly: *"How is your AI validated?"*

**Speaker notes:** The differentiator vs a generic LLM bolt-on is that every GenAI
surface has an evaluation and guardrail record stored in Unity Catalog. Validation is
a data asset, not a promise.

---

## Slide 10 — Bank-grade governance (Unity Catalog)

- **PII column masking** — masked by default; cleartext only for an entitled group;
  applies uniformly across app, Genie, and ad-hoc SQL
- **Row-level security** — analysts see only their team's cases (direct queriers)
- **Immutable audit trail** — every case read, decision, and SAR action stamped with
  acting user + timestamp
- One permission model, enforced everywhere the data is touched

**Speaker notes:** The headline: governance is enforced at the data layer, so it can't
be bypassed by going around the app. Masking, RLS, and audit are UC primitives — the
same controls a bank already expects, applied once and inherited by every surface.

---

## Slide 11 — The application

- Databricks App (React + FastAPI), single process, no data leaves the platform
- Executive Overview, Alert Investigation queue, Case Investigation, SAR Filing,
  interactive Graph Explorer (Cytoscape), Ask Sentinel (Genie), Compliance
- **Live-refreshing** queue + exec (near-real-time), SLA tracking, dark mode,
  accessibility, embedded AI/BI dashboard

**Speaker notes:** The app is thin — it's a view over governed gold tables and Genie.
That's the point: the intelligence lives in the platform, so the UI is replaceable and
every number on screen is traceable to a governed table.

---

## Slide 12 — Engineering rigor: bundle, CI/CD, tests

- Deployed via **Databricks Asset Bundles**; one bundle for app + pipeline + jobs
- **CI/CD** (GitHub Actions): tests + bundle validate on PR, deploy on merge
- **32 backend unit/route tests + 6 Playwright end-to-end tests** — covering the SAR
  four-eyes gate, goAML validation, model governance, and audit surfaces
- Data-quality expectations on every medallion dataset

**Speaker notes:** For a platform team, this is the trust signal: the demo is built
like production software — versioned, tested, bundle-deployed, with a green test
pyramid guarding the compliance-critical paths.

---

## Slide 13 — Why Databricks (vs Azure AI Foundry + Microsoft Fabric)

- **One platform, one governance plane** — not Fabric for data + Foundry for AI +
  a separate security model to reconcile
- Streaming, SQL detection, ML (MLflow/UC registry), Vector Search, Genie NL, and the
  serving app **all on the same governed data** — no extracts, no copies
- Lineage, masking, RLS, and audit are native UC primitives, not bolt-ons
- SQL-first: a SQL-skilled team owns it; Python confined to the app shell

**Speaker notes:** Keep this crisp and factual. The displacement argument is
consolidation: fewer moving parts, one lineage graph, one permission model, and AI
that sits natively next to the governed data instead of across an integration seam.

---

## Slide 14 — Outcomes & what's next

- **Delivered & running:** near-real-time detection, ML with measured FP reduction,
  multi-agent SAR + goAML output, bank-grade governance, full test/CI coverage
- **Business outcomes:** faster investigations, fewer false positives, defensible
  audit + model governance, lower total cost via consolidation
- **Next:** production data volumes, on-behalf-of auth, live Model Serving endpoint,
  Agent Bricks tool-calling, goAML XSD + FIC submission connector

**Speaker notes:** Close on outcomes the audience cares about and an honest roadmap.
Sentinel already demonstrates the full value chain on one platform; the "next" list is
the path from demo-grade to production, all of which the platform natively supports.

---

## Appendix — Facts to keep the deck accurate

- Medallion: `bronze` / `silver` / `gold` schemas in Unity Catalog
- 9 detection families → `gold.fraud_alerts`; case mgmt in `sherlock_*`
- Streaming: Auto Loader tables + file-arrival triggered job (self-driving)
- ML: `sar_propensity_gbt` in the UC Model Registry; 15.8% fewer FPs at equal budget
- SAR: multi-agent + vector-search adverse media + goAML STR XML + 4-eyes + validation
- Governance: PII column masks, RLS row filter, immutable audit log, LLM eval record
- Tests: 32 pytest + 6 Playwright e2e; DQ expectations on every dataset
- Incumbent being displaced: Azure AI Foundry + Microsoft Fabric
