import { useEffect, useState } from "react";
import { useParams, useNavigate, Link } from "react-router-dom";
import { sarEvidence, sarOrchestrate, sarSubmit, goamlUrl, goamlValidate } from "../api";
import { Loading, usePersona, money } from "../components/ui";

const AGENT_LABEL: Record<string, string> = {
  transaction_analysis: "Transaction Analysis",
  adverse_media: "Adverse Media & Screening",
  policy: "Policy & Typology",
};

export function SarFiling() {
  const { caseId } = useParams();
  const nav = useNavigate();
  const { current } = usePersona();
  const [sar, setSar] = useState<any>(null);      // evidence pack (fast, SQL only)
  const [agents, setAgents] = useState<any>(null); // agent trace + narrative (slow LLM)
  const [narrative, setNarrative] = useState("");
  const [busy, setBusy] = useState(false);         // agents in flight
  const [agentErr, setAgentErr] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [valid, setValid] = useState<any>(null);
  const [approver, setApprover] = useState("");
  const [submitErr, setSubmitErr] = useState("");

  // Phase 2 (slow): run the multi-agent orchestration in the background.
  const run = () => {
    setBusy(true); setAgentErr("");
    sarOrchestrate({ case_id: caseId }).then((r) => {
      setAgents(r); setNarrative(r.narrative || ""); setBusy(false);
    }).catch(() => { setBusy(false); setAgentErr("Agent workflow failed — retry."); });
  };
  useEffect(() => {
    // Phase 1 (fast): render the evidence pack immediately, then kick off agents.
    sarEvidence(caseId!).then((r) => setSar(r)).catch(() => setSar(null));
    run();
    goamlValidate(caseId!).then(setValid).catch(() => setValid(null));
  }, [caseId]);

  async function submit() {
    setSubmitErr("");
    const r: any = await sarSubmit({
      case_id: caseId, customer_name: sar.customer_name, scenario: sar.scenario,
      narrative, decision: "SAR Filed", filed_by: current?.analyst_name, approved_by: approver,
    });
    if (r && r.ok === false) { setSubmitErr(r.error || "SAR filing rejected."); return; }
    setSubmitted(true);
  }

  // Render as soon as the (fast) evidence pack is in — the slow agent workflow
  // streams into its own panels below, so the user never stares at a blank spinner.
  if (!sar) return <Loading what="evidence pack" />;

  const ev = sar.evidence || {};
  return (
    <>
      <Link to={`/investigation/${caseId}`} className="muted">← Back to Investigation</Link>
      <h1 className="page-title" style={{ marginTop: 8 }}>STR Filing</h1>
      <p className="page-sub">Suspicious Transaction Report (FIC · s29 FIC Act) · case <span className="mono">{caseId}</span> · multi-agent orchestration + goAML output</p>

      <div className="grid-2">
        <div className="panel">
          <h3 className="left">Auto-Gathered Evidence Pack <span className="muted" style={{ fontWeight: 400, fontSize: 12 }}>(assembled by agents)</span></h3>
          <div className="kv"><span className="k">Customer</span><span>{sar.customer_name}</span></div>
          <div className="kv"><span className="k">Scenario</span><span>{sar.scenario}</span></div>
          <div className="kv"><span className="k">Amount</span><span>{money(sar.amount)}</span></div>
          <div className="kv"><span className="k">Flagged txns</span><span>{(ev.transactions || []).length}</span></div>
          <div className="kv"><span className="k">Counterparties</span><span>{(ev.network || []).length}</span></div>
          <div className="kv"><span className="k">Watchlist hits</span><span style={{ color: (ev.screening || []).length ? "var(--critical)" : undefined }}>{(ev.screening || []).length}</span></div>
          <div className="kv"><span className="k">Adverse media</span><span>{(ev.adverse_media || []).length} retrieved</span></div>
          <div className="kv"><span className="k">Policy refs</span><span>{(ev.policy || []).length} retrieved</span></div>
          <div className="kv"><span className="k">pKYC band</span><span>{ev.pkyc?.risk_band || "—"}</span></div>
        </div>
        <div className="panel">
          <h3 className="left">Filing Details</h3>
          <div className="kv"><span className="k">Filed by</span><span>{current?.analyst_name}</span></div>
          <div className="kv"><span className="k">Team</span><span>{current?.team_name}</span></div>
          <div className="kv"><span className="k">Decision</span><span>STR Filed (FIC)</span></div>
          <div className="kv"><span className="k">Format</span><span>goAML STR (UN/UNODC)</span></div>
        </div>
      </div>

      {(ev.adverse_media || []).length > 0 && (
        <div className="panel">
          <h3 className="left">Grounded Adverse Media <span className="muted" style={{ fontWeight: 400, fontSize: 12 }}>(vector-search retrieved — cited in the narrative)</span></h3>
          <table>
            <thead><tr><th>Headline</th><th>Source</th><th>Published</th><th>Relevance</th></tr></thead>
            <tbody>
              {ev.adverse_media.map((a: any, i: number) => (
                <tr key={i}>
                  <td>{a.headline}</td>
                  <td className="muted">{a.source}</td>
                  <td className="muted mono">{a.published_at}</td>
                  <td><span style={{ fontWeight: 700, color: a.score >= 0.7 ? "var(--critical)" : "var(--navy)" }}>{a.score != null ? a.score.toFixed(2) : "—"}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {(ev.policy || []).length > 0 && (
        <div className="panel">
          <h3 className="left">Grounded Policy &amp; Typology <span className="muted" style={{ fontWeight: 400, fontSize: 12 }}>(bank AML policy + FATF — vector-search retrieved, cited in the narrative)</span></h3>
          <table>
            <thead><tr><th>Reference</th><th>Type</th><th>Jurisdiction</th><th>Relevance</th></tr></thead>
            <tbody>
              {ev.policy.map((d: any, i: number) => (
                <tr key={i}>
                  <td>{d.title}</td>
                  <td className="muted">{d.doc_type}</td>
                  <td className="muted mono">{d.jurisdiction}</td>
                  <td><span style={{ fontWeight: 700, color: "var(--navy)" }}>{d.score != null ? d.score.toFixed(2) : "—"}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className="panel">
        <h3 className="left">Multi-Agent Trace {busy && <span className="muted" style={{ fontWeight: 400, fontSize: 12 }}>· agents running…</span>}</h3>
        {busy && !agents && (
          <div className="route-loading" style={{ padding: "20px 0" }}>Specialist agents analysing evidence (transaction, adverse-media, policy)…</div>
        )}
        {agentErr && (
          <div className="explain" style={{ borderLeft: "3px solid var(--critical)" }}>{agentErr}</div>
        )}
        {(agents?.agent_trace || []).map((t: any, i: number) => (
          <div key={i} className="explain" style={{ marginBottom: 8, borderLeft: "3px solid var(--accent)" }}>
            <span className="muted" style={{ fontWeight: 700, marginRight: 8 }}>✦ {AGENT_LABEL[t.agent] || t.agent}</span>{t.finding}
          </div>
        ))}
        {agents && (
          <div className="explain" style={{ borderLeft: "3px solid var(--navy)" }}>
            <span className="muted" style={{ fontWeight: 700, marginRight: 8 }}>▣ Supervisor synthesis</span>
            feeds the narrative below.
          </div>
        )}
      </div>

      <div className="panel">
        <h3 className="left">SAR Narrative <span className="muted" style={{ fontWeight: 400, fontSize: 12 }}>(supervisor-synthesised, editable)</span></h3>
        <textarea aria-label="SAR narrative" value={narrative} onChange={(e) => setNarrative(e.target.value)}
          placeholder={busy ? "Supervisor is synthesising the narrative from the specialist findings…" : "SAR narrative"}
          style={{ width: "100%", minHeight: 240, lineHeight: 1.6 }} />
        <div style={{ display: "flex", gap: 10, marginTop: 12, flexWrap: "wrap" }}>
          <button className="btn ghost" onClick={run} disabled={busy}>{busy ? "Re-running agents…" : "↻ Re-run agents"}</button>
          <a className="btn ghost" href={goamlUrl(caseId!, narrative)} download>⤓ Download goAML XML</a>
          {valid && (
            <span className="badge" title={(valid.issues || []).join("; ")}
              style={{ alignSelf: "center", background: valid.valid ? "var(--navy)" : "var(--critical)", color: "#fff" }}>
              {valid.valid ? "✓ goAML schema valid" : "✗ goAML issues"} ({valid.checks_passed}/{valid.checks_total})
            </span>
          )}
          <button className="btn" onClick={submit}
            disabled={submitted || busy || !narrative.trim() || !approver.trim() || approver.trim().toLowerCase() === (current?.analyst_name || "").toLowerCase()}>
            {submitted ? "✓ SAR Filed" : busy ? "Awaiting narrative…" : "File SAR"}
          </button>
        </div>
        <div style={{ marginTop: 12, display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
          <span className="k" style={{ fontWeight: 600 }}>Four-eyes approver</span>
          <input aria-label="Four-eyes approver name" value={approver} onChange={(e) => setApprover(e.target.value)}
            placeholder="second approver (must differ from filer)" style={{ minWidth: 280 }} />
          <span className="muted" style={{ fontSize: 12 }}>
            Filing requires a second, distinct approver — {current?.analyst_name} is the filer.
          </span>
        </div>
        {submitErr && <div className="explain" style={{ marginTop: 10, borderLeft: "3px solid var(--critical)" }}>{submitErr}</div>}
        {valid && !valid.valid && (valid.issues || []).length > 0 && (
          <ul className="muted" style={{ margin: "10px 0 0", fontSize: 12 }}>
            {valid.issues.map((iss: string, i: number) => <li key={i}>{iss}</li>)}
          </ul>
        )}
        {submitted && (
          <div className="explain" style={{ marginTop: 14 }}>
            SAR filed and captured in the audit trail — traceable end-to-end. The goAML XML is ready for FIC submission.
            <div style={{ marginTop: 8 }}><button className="btn sm ghost" onClick={() => nav("/investigation")}>Return to Queue</button></div>
          </div>
        )}
      </div>
    </>
  );
}
