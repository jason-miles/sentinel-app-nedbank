# Nedbank Sentinel — Executive Deck Source (NotebookLM)

> **How to use:** Load into Google NotebookLM as a source and prompt:
> *"Create a concise executive slide deck from this document — one slide per `## Slide`
> heading, bullets as slide content, 'Speaker notes' as the script. Keep it visual and
> high-level."* Audience: **Nedbank executives / C-suite** (MLRO, CRO, CDO, CFO lens).
> Tone: outcomes, risk, and cost — not architecture. ~8 slides, ~5-minute read.

---

## Slide 1 — Title

**Nedbank Sentinel**
Turning financial-crime compliance into a competitive advantage — on Databricks

- One platform for AML detection, investigation, and regulatory reporting
- Working today, not a concept

**Speaker notes:** Sentinel is a live, working platform — everything here is
demonstrable. The message for leadership: modernising AML isn't just a cost of doing
business; done right it lowers risk, cuts cost, and speeds the business up.

---

## Slide 2 — Why this matters now

- Faster payments + rising regulatory expectations = compliance must be **near-real-time**
- Legacy AML: too many false positives, slow manual investigations, weak audit trail
- Regulators increasingly ask: *"prove your models and your decisions"*
- Fragmented tooling (data in one place, AI in another) multiplies cost and risk

**Speaker notes:** Set the stakes in business terms. The status quo is expensive
(analyst time lost to false positives), risky (gaps regulators probe), and slow. The
market is moving to real-time; the compliance function has to move with it.

---

## Slide 3 — The outcomes (headline)

- **~16% fewer false positives** at the same alert workload — analyst time back
- **Investigations in minutes, not hours** — evidence assembled automatically
- **Near-real-time detection** — alerts within ~2 minutes of a transaction
- **Defensible by design** — every decision, model, and AI output is audited

**Speaker notes:** Lead with outcomes. These four are the business case: efficiency
(fewer false positives), speed (minutes not hours), timeliness (real-time), and
defensibility (audit + model governance). Everything else supports these.

---

## Slide 4 — Fewer false positives, provably

- A governed machine-learning model scores every alert alongside the existing rules
- **15.8% fewer false positives** at an equal alert budget, measured on held-out data
- Result: analysts spend time on real risk, not noise — direct capacity gain
- The model is monitored for drift and retrained on a schedule

**Speaker notes:** False positives are the single biggest hidden cost in AML. A
measured 15.8% reduction at the same workload is real analyst capacity returned — and
because it's governed and monitored, it's a controlled improvement, not a black box.

---

## Slide 5 — From alert to filed report, faster

- Evidence gathers itself: transactions, network, sanctions hits, adverse media
- AI drafts a **regulator-ready Suspicious Activity Report**, citing its sources
- Output is a **standard goAML filing**, validated — ready for the regulator
- **Four-eyes approval** enforced: no SAR filed without a second sign-off

**Speaker notes:** This collapses the most labour-intensive part of AML. The analyst
reviews and approves rather than assembles. And the controls a bank requires —
second-person approval, a real filing format, a full audit — are built in, not bolted
on.

---

## Slide 6 — Trust, governance & the regulator

- Every case read, decision, and SAR action is **logged with who and when**
- PII is masked by default; analysts see only the cases they're entitled to
- The AI is **validated and guardrailed** — with an evidence record on file
- Answers the examiner directly: *"how is your AI governed?"* — here it is

**Speaker notes:** For a regulated institution this is the make-or-break slide.
Governance isn't a policy document — it's enforced in the platform and evidenced. That
turns audit and model-risk reviews from a scramble into a query.

---

## Slide 7 — One platform, lower total cost

- Detection, AI, investigation, reporting, and governance on **one Databricks platform**
- Replaces a fragmented estate (data in Microsoft Fabric, AI in Azure Foundry, +
  separate security) — fewer moving parts, one permission model
- Less integration, less duplication, less risk of things falling between systems
- Owned by the existing team — built SQL-first

**Speaker notes:** The cost story is consolidation. One platform means one copy of the
data, one security model, one lineage graph — and AI that lives next to the governed
data instead of across an expensive, risky integration seam. Fewer vendors, lower TCO.

---

## Slide 8 — Where we are & what's next

- **Today:** a working platform demonstrating the full AML value chain, end to end
- **Proven:** measured false-positive reduction, real-time detection, goAML output,
  bank-grade governance
- **Next:** scale to production volumes, per-user access controls, live model serving,
  regulator submission connector
- **Ask:** align on a production path and the priority use cases

**Speaker notes:** Close on momentum and a clear ask. Sentinel already de-risks the
decision — the capability is proven on the platform. The conversation now is about the
path to production and where to point it first.

---

## Appendix — Numbers to keep accurate
- 15.8% fewer false positives at equal alert budget (held-out test set)
- Near-real-time: alert within ~2 min of a dropped transaction (self-driving pipeline)
- Regulatory output: goAML (UN/UNODC) STR XML, structurally validated
- Controls: four-eyes SAR approval, PII masking, row-level security, immutable audit
- AI governance: model registry + drift monitoring + LLM eval/guardrail record
- Consolidation target: Microsoft Fabric + Azure AI Foundry → one Databricks Lakehouse
