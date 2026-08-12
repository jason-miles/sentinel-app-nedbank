# Nedbank Sentinel — Live Demo Walkthrough (≈ 6.5 min)

**App:** https://nedbank-sentinel-7474654808133980.aws.databricksapps.com
**Audience:** Nedbank data/platform + financial-crime. **Goal:** show the full AML
value chain on one governed Databricks platform. **Total: ~6m30s.**

**Pre-flight (before you start):**
- App open on the **Landing** page; warehouse warm (open the app once ~2 min prior).
- A terminal ready in `data/stream/` for the file-drop (Step 2). Optional but high-impact.
- "View As" persona = **Sarah Chen** (Fraud Investigations).

---

### 0 · Hook (0:30)
> "This is Nedbank Sentinel — a working AML platform on Databricks. Everything you'll
> see runs on one governed Lakehouse: ingestion, detection, ML, investigation, the
> regulatory filing, and the controls around it. No extracts, no second security model."

Click **Enter Investigation View**.

---

### 1 · The analyst queue — detection + ML in one view (1:00)
On **Alert Investigation**:
- "These alerts come from 9 SQL detection families running as a governed Lakeflow
  pipeline." Point at the **Rules Score** column.
- Point at the **AI Risk ✦** column: "This is a gradient-boosted model in the Unity
  Catalog registry, blended with the rules — **15.8% fewer false positives** at the
  same alert workload."
- Point at the **SLA** badge + the **Live** indicator (top-right): "The queue
  refreshes live, and every case carries an SLA."
- Use the **priority = critical** filter: "Server-side filtering — the queue only
  pulls what the analyst needs."

---

### 2 · Near-real-time, self-driving (1:00)  *(optional — highest impact)*
> "Faster payments need faster compliance. Watch a brand-new transaction become an alert."

In the terminal:
```
python drop_transactions.py --scenario layering --account ACC00000031
```
> "That dropped a JSON file into a Unity Catalog volume. Auto Loader streams it in, a
> file-arrival job runs the pipeline — no manual step, no always-on cluster. In ~2
> minutes it surfaces here as a `rapid_movement` alert."

*(Don't wait live — keep moving; call back to it at the end, or pre-run it 2 min before.)*

---

### 3 · Investigate — agents do the correlation (1:30)
Click **Investigate** on a critical case (e.g. **Marco Silva**):
- "The evidence pack assembled itself — flagged transactions, the counterparty
  network, sanctions hits, perpetual-KYC risk." Scroll the panels.
- Point at **AI Risk** KPI + **SLA** tile.
- Click **Explore Network** → **Graph Explorer**: "The entity network — drag and zoom;
  resolved entities link customers to counterparties and watchlist hits." (Pan once.)

---

### 4 · The money shot — multi-agent SAR + goAML (1:30)
Back on the case, click **Proceed to SAR Filing**:
- "A multi-agent supervisor — transaction, adverse-media, and policy specialists —
  reasoned over the shared evidence, including **vector-search-retrieved adverse
  media**, and drafted this SAR, **citing its sources**."
- Point at the **✓ goAML schema valid (12/12)** badge: "Real UN/UNODC goAML STR XML,
  structurally validated — not just a PDF." Click **Download goAML XML** (show it).
- Point at **Four-eyes approver**: "Filing is blocked until a second, distinct person
  approves — a bank control, fully audited." Enter a different name → **File SAR**.

---

### 5 · Governance & trust — the regulator's questions (1:00)
Go to **Compliance → Model Governance**:
- "'How is your AI validated?' — here: model metrics, the FP-reduction, **feature-drift
  monitoring**, and an **LLM eval + guardrail** record for the SAR narrative."

Click **Audit Trail**:
- "Every case read, decision, and SAR action — stamped with who and when. Immutable."

> "And PII is column-masked, cases are row-filtered by team — all Unity Catalog
> primitives, enforced at the data layer, inherited by every surface."

---

### 6 · Close (0:30)
> "One platform: streaming ingestion, SQL detection, a governed ML model, multi-agent
> investigation, regulator-grade goAML output, and bank-grade governance — replacing a
> Fabric-plus-Foundry estate with one Lakehouse and one permission model. It's built
> like production: bundle-deployed, CI/CD, 38 tests green."

*(If you pre-ran Step 2: refresh the queue — "and there's our streamed alert, live.")*

---

## Timing cheat-sheet
| Step | Screen | Time |
|---|---|---|
| 0 Hook | Landing | 0:30 |
| 1 Queue | Alert Investigation | 1:00 |
| 2 Streaming | terminal + queue | 1:00 |
| 3 Investigate | Case + Graph | 1:30 |
| 4 SAR + goAML | SAR Filing | 1:30 |
| 5 Governance | Compliance | 1:00 |
| 6 Close | — | 0:30 |
| **Total** | | **6:30** |

**If short on time:** drop Step 2 (do it as a pre-run callback) → **5:30**.
**Backup:** if the warehouse is cold, the first screen may pause a few seconds — keep
talking through the hook while it warms.
