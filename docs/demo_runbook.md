# Nedbank Sentinel — Demo Runbook

**App:** https://nedbank-sentinel-7474654808133980.aws.databricksapps.com
**Audience:** Nedbank Wealth & Banking (SQL-skilled team) + ICIB stakeholders
**Duration:** ~12–15 min · **One-line pitch:** *AI-augmented AML — investigations from hours to minutes, on one governed Lakehouse.*

---

## 0. Pre-flight (before the room)

- [ ] App is RUNNING: `databricks apps get nedbank-sentinel --profile fevm-elexon-app-for-settlement-acc`
- [ ] Pipeline fresh: `databricks bundle run fraud_aml_pipeline_etl --full-refresh-all -t dev --profile ...` (all 9 families fire)
- [ ] Warehouse `elexon-anamoly-app` (d0305022e6c3db8e) is running / can auto-start
- [ ] Logged in to the app; **View As = Sarah Chen** (AML Transaction Monitoring)
- [ ] Genie space "Fraud & AML Analyst" reachable (Ask Sentinel returns an answer)
- [ ] Browser zoomed so KPI tiles + charts are legible on the shared screen

---

## 1. Landing (30s) — set the frame

**Show:** the landing page — Nedbank | Sentinel hero, 90% / 50% / $10M+ band, two entry cards.
**Say:** "Sentinel is Nedbank's CDP and financial-crime intelligence platform on Databricks.
Two doors: an **executive view** for the CCO, and an **analyst workspace**. Everything is one
governed Lakehouse underneath — do less, get more with Unity Catalog."

---

## 2. Executive Overview (3 min) — the CCO story

**Click:** Enter Executive View.
**Show / say:**
- **KPI row** — "Case volume, average investigation hours, false-positive rate, past-due
  alerts — real-time operational intelligence across the whole program."
- **✦ AI Executive Briefing** → click **Generate Briefing**. "This is a Databricks
  Foundation-Model-authored narrative of the program state — the CCO's morning brief,
  on demand." *(Wait ~5s for the ai_query response.)*
- **Daily new / Outstanding charts** — "Volume trends and where the backlog is due."
- **Case Resolution Flow / Alerts by Scenario / Priority×Status heatmap** — "Where cases
  come from, which team works them, and how they resolve — bottlenecks are visible."
- **Team Performance tab** — "Turnaround by team; here's where we'd tune detection to cut
  the hours spent on no-action cases."

---

## 3. Alert Investigation (4 min) — the analyst story (marquee)

**Click:** Alert Investigation (still as Sarah Chen).
**Show / say:**
- **My Queue** — "Sarah's queue: criticality counts, her weekly scenario mix, and a
  priority-ranked Active Alerts list. She knows exactly where to spend her time."
- Pick a **critical** row → click the **✦** button. "One click: an AI *why-this-matters +
  next-step* on the alert, without leaving the queue."
- Click **Investigate** on that row → the Investigation page.
  - "Traditionally Sarah logs into 10+ systems to correlate this. Here it's one page:
    flagged transactions, entity relationships, case notes."
  - **✦ AI Risk Triage** → **Run AI Triage**. "Model-augmented risk score, recommended
    action, and rationale — this is the 75%-fewer-false-positives story."
  - **Multi-Agent Assistant** → pick the **Investigation** agent, ask *"Summarize the risk
    and recommend an action."* "A fleet of specialized agents — policy, adverse media,
    investigation, SAR drafting — coordinated by a supervisor."
  - **Decision panel** → click **Proceed to SAR Filing**.

---

## 4. SAR Filing (2 min) — hours to minutes

**On the SAR page:**
- "The case metadata is pre-populated by the agents. The **narrative is AI-generated** to
  our institution's SAR format." *(Narrative appears via ai_query.)*
- Edit a sentence to show it's fully editable → **Generate PDF & Submit SAR**.
- "Submitted — and pushed to the backend audit trail. Completely traceable for the
  regulator. Three-to-six hours of work, done in minutes."

---

## 5. Graph Explorer (2 min) — network intelligence

**Click:** Graph Explorer.
- "The relationship graph across customers, accounts, counterparties, and watchlist hits —
  this is how we surface rings and related parties the legacy Tabular/SQL stack can't express."
- Click a **suggestion chip** (e.g. *"customers flagged for structuring cash deposits"*).
- "Natural-language graph search, with an AI analysis panel and ranked matched entities."

---

## 6. Ask Sentinel (2 min) — Genie, self-service

**Click:** Ask Sentinel.
- "This is Databricks **Genie** — the SQL-skilled team asks questions in plain English and
  gets governed answers **plus the SQL** behind them."
- Ask a chip: *"Which scenarios have the most alerts?"* → show answer + result table →
  expand **View generated SQL**. "Governed, explainable, and the team can own the SQL."

---

## 7. Close (1 min)

**Say:** "One governed Lakehouse. SQL-authored declarative detection your team owns, a fleet
of AI agents that cut investigations from hours to minutes, natural-language self-service via
Genie, and a tested Managed-DR posture. That's *do less, get more* — versus stitching Fabric
+ AI Foundry together. Everything you saw is live on Databricks today."

---

## Reset between runs
- Feedback/actions/SARs are append-only write-backs — harmless to accumulate.
- To reset to a clean state: re-run `--full-refresh-all` (regenerates gold; write-back
  tables persist their audit trail by design).
- Persona: reset **View As → Sarah Chen** for a consistent queue.

## Fallback if AI latency is high
- `ai_query` / Genie calls take ~5–20s. If the room is impatient, pre-click **Generate**
  before narrating, or use the pre-captured screenshots in `docs/` App Screenshots.
