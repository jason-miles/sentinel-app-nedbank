import { useEffect, useState } from "react";
import { useParams, useNavigate, Link } from "react-router-dom";
import { getCase, addNote, caseAction, agentChat, agentChatStream, caseTriage, caseTriageStream, caseReassign } from "../api";
import { Sev, ErrorState, usePersona, money, fmtDate, num, SkelPage } from "../components/ui";
import { SlaBadge } from "./AlertInvestigation";

const AGENTS = [
  { id: "supervisor", label: "Supervisor" },
  { id: "policy", label: "Policy Q&A" },
  { id: "adverse_media", label: "Adverse Media" },
  { id: "investigation", label: "Investigation" },
  { id: "sar", label: "SAR Drafting" },
];

export function Investigation() {
  const { caseId } = useParams();
  const nav = useNavigate();
  const { current } = usePersona();
  const [c, setC] = useState<any>(null);
  const [err, setErr] = useState(false);
  const [note, setNote] = useState("");
  const load = () => { setErr(false); return getCase(caseId!, current?.analyst_name).then(setC).catch(() => setErr(true)); };
  useEffect(() => { load(); }, [caseId, current?.analyst_id]);
  if (err && !c) return <ErrorState what="investigation" onRetry={load} />;
  if (!c) return <SkelPage kpis={5} rows={6} />;

  async function act(action: string) {
    await caseAction({ case_id: c.case_id, action, actor: current?.analyst_name });
    if (action === "proceed_sar") { nav(`/sar/${c.case_id}`); return; }
    load();
  }
  async function reassign() {
    const to = window.prompt("Reassign this case to which analyst?");
    if (!to || !to.trim()) return;
    await caseReassign({
      case_id: c.case_id,
      to_analyst_id: "AN_" + to.trim().split(" ")[0].toUpperCase(),
      to_analyst_name: to.trim(), actor: current?.analyst_name,
    });
    load();
  }
  async function saveNote() {
    if (!note.trim()) return;
    await addNote({ case_id: c.case_id, note, author: current?.analyst_name });
    setNote(""); load();
  }

  return (
    <>
      <Link to="/investigation" className="muted">← My Queue</Link>
      <h1 className="page-title" style={{ marginTop: 8 }}>{c.customer_name} <Sev s={c.priority} /></h1>
      <p className="page-sub">{c.scenario} · case <span className="mono">{c.case_id}</span> · {c.team_name}</p>

      {/* Impact banner — the "why this matters" beat. Shows how the AI model reprioritised
          a case a rules-only engine would have buried, especially for structuring/mule. */}
      {c.ai_risk != null && num(c.ai_risk) >= 80 && (
        <div className="impact-banner">
          <span className="impact-ico">✦</span>
          <div>
            <strong>AI caught what siloed rules would miss.</strong>{" "}
            {/^cash structuring/i.test(c.scenario || "")
              ? "Each deposit sat just under the reporting threshold — individually dismissible. Entity resolution linked this account to a wider mule network; sibling accounts had been closed as false positives in isolation."
              : "The served model reprioritised this case above look-alike false positives using network, behavioural and typology signals a fixed-threshold rule can't see."}{" "}
            <span className="impact-metric">Rules {c.risk_score} → AI {c.ai_risk}</span>
          </div>
        </div>
      )}

      <div className="kpis">
        <div className="kpi"><div className="label">Rules Score</div><div className="value" style={{ color: "var(--muted)" }}>{c.risk_score}</div></div>
        <div className="kpi" title={c.model_version ? `Served model v${c.model_version}` : ""}>
          <div className="label">AI Risk ✦</div>
          <div className="value" style={{ color: c.ai_risk != null && num(c.ai_risk) >= 80 ? "var(--critical)" : "var(--navy)" }}>
            {c.ai_risk != null ? c.ai_risk : "—"}
          </div>
        </div>
        <div className="kpi"><div className="label">Amount</div><div className="value navy" style={{ fontSize: 22 }}>{money(c.amount)}</div></div>
        <div className="kpi"><div className="label">Days Open</div><div className="value" style={{ color: num(c.days_open) > 90 ? "var(--critical)" : "var(--navy)" }}>{c.days_open}</div></div>
        <div className="kpi"><div className="label">SLA {c.sla ? `(${c.sla.target_days}d)` : ""}</div>
          <div className="value" style={{ fontSize: 18 }}>{c.sla ? <SlaBadge sla={c.sla} /> : "—"}</div></div>
      </div>

      <div className="grid-2">
        <div>
          <div className="panel">
            <h3 className="left">Flagged Transactions</h3>
            <table>
              <thead><tr><th scope="col">ID</th><th scope="col">Dir</th><th scope="col">Amount</th><th scope="col">Channel</th><th scope="col">Date</th></tr></thead>
              <tbody>
                {(c.flagged_transactions || []).map((t: any) => (
                  <tr key={t.transaction_id}>
                    <td className="mono">{String(t.transaction_id).slice(-8)}</td>
                    <td>{t.direction}</td><td style={{ fontWeight: 600 }}>{money(t.amount)}</td>
                    <td>{t.channel}</td><td className="muted">{fmtDate(t.txn_ts)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="panel">
            <h3 className="left">Entity Relationships</h3>
            {(c.counterparties || []).length === 0 ? <span className="muted">No counterparties.</span> : (
              <table><tbody>
                {c.counterparties.slice(0, 10).map((p: any, i: number) => (
                  <tr key={i}><td>{p.full_name || p.counterparty_id}</td><td className="muted">{p.country || ""}</td></tr>
                ))}
              </tbody></table>
            )}
            <Link to="/graph" className="btn ghost sm" style={{ marginTop: 10, display: "inline-block" }}>Explore Network →</Link>
          </div>
          <div className="panel">
            <h3 className="left">Case Notes</h3>
            <textarea aria-label="Add investigation note" placeholder="Add investigation note…" value={note} onChange={(e) => setNote(e.target.value)} style={{ width: "100%", minHeight: 60, marginBottom: 8 }} />
            <button className="btn sm" onClick={saveNote}>Add Note</button>
            <div style={{ marginTop: 12 }}>
              {(c.notes || []).map((n: any, i: number) => (
                <div className="kv" key={i}><span><strong>{n.author}</strong> · {n.note}</span><span className="muted">{fmtDate(n.created_at)}</span></div>
              ))}
            </div>
          </div>
        </div>

        <div>
          <AiTriage caseId={c.case_id} rulesRisk={c.risk_score} />
          <AgentPanel caseId={c.case_id} />
          <div className="panel">
            <h3 className="left">Decision</h3>
            <p className="muted" style={{ marginTop: 0 }}>Once you've reviewed the evidence and agent guidance, take an action:</p>
            <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              <button className="btn warn" onClick={() => act("escalate")}>⬆ Escalate to Specialist Team</button>
              <button className="btn ghost" onClick={() => act("dismiss")}>✕ Dismiss as False Positive</button>
              <button className="btn" onClick={() => act("proceed_sar")}>→ Proceed to SAR Filing</button>
              <button className="btn ghost" onClick={reassign}>⇄ Reassign</button>
            </div>
            {(c.actions || []).length > 0 && (
              <div style={{ marginTop: 14 }}>
                <div className="muted" style={{ marginBottom: 6 }}>Action history</div>
                {c.actions.map((a: any, i: number) => (
                  <div className="kv" key={i}><span>{a.action} · {a.actor}</span><span className="muted">{fmtDate(a.created_at)}</span></div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </>
  );
}

function AiTriage({ caseId, rulesRisk }: { caseId: string; rulesRisk: any }) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  async function run() {
    setBusy(true); setText("");
    try {
      // Stream tokens so the score + rationale type out live (first token ~2-3s).
      await caseTriageStream({ case_id: caseId }, (soFar) => setText(soFar));
    } catch {
      try { const r = await caseTriage({ case_id: caseId }); setText(r.triage || ""); }
      catch { setText("Triage unavailable."); }
    }
    setBusy(false);
  }
  return (
    <div className="panel" style={{ borderLeft: "3px solid var(--accent)" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h3 className="left" style={{ margin: 0 }}>✦ AI Risk Triage</h3>
        <button className="btn sm" onClick={run} disabled={busy}>{busy && !text ? "Scoring…" : busy ? "Streaming…" : "Run AI Triage"}</button>
      </div>
      {text
        ? <div className="explain" style={{ marginTop: 12, whiteSpace: "pre-line" }}>{text}{busy && <span className="stream-caret" />}</div>
        : <p className="muted" style={{ margin: "10px 0 0" }}>Rules-based risk is <strong>{rulesRisk}</strong>. Run AI triage for a model-augmented risk score, recommended action, and rationale.</p>}
    </div>
  );
}

function AgentPanel({ caseId }: { caseId: string }) {
  const [agent, setAgent] = useState("supervisor");
  const [q, setQ] = useState("");
  const [log, setLog] = useState<any[]>([]);
  const [busy, setBusy] = useState(false);

  async function ask() {
    if (!q.trim() || busy) return;
    const question = q; setQ(""); setBusy(true);
    // Seed the user message + an empty AI bubble, then stream tokens into it.
    let aiIdx = 0;
    setLog((l) => { aiIdx = l.length + 1; return [...l, { who: "You", text: question, kind: "user" }, { who: `${agent} agent`, text: "", kind: "ai", streaming: true }]; });
    const setAi = (t: string, streaming = true) =>
      setLog((l) => l.map((m, i) => (i === aiIdx ? { ...m, text: t, streaming } : m)));
    try {
      await agentChatStream({ agent, question, case_id: caseId }, (soFar) => setAi(soFar, true));
    } catch {
      try {
        const r = await agentChat({ agent, question, case_id: caseId });
        setAi(r.answer, false);
      } catch { setAi("Agent unavailable.", false); }
    } finally {
      setLog((l) => l.map((m, i) => (i === aiIdx ? { ...m, streaming: false } : m)));
    }
    setBusy(false);
  }

  return (
    <div className="panel">
      <h3 className="left">Multi-Agent Assistant</h3>
      <div className="agent-tabs">
        {AGENTS.map((a) => (
          <button key={a.id} className={agent === a.id ? "active" : ""} onClick={() => setAgent(a.id)}>{a.label}</button>
        ))}
      </div>
      <div className="chat-log">
        {log.length === 0 && <div className="muted" style={{ fontSize: 13 }}>Ask the {agent} agent for guidance on this case. It scans the full network of case data and makes a recommendation.</div>}
        {log.map((m, i) => (
          <div key={i} className={`msg ${m.kind}`}>
            <div className="who">{m.who}</div>
            {m.text || (m.streaming ? <span className="muted">Analyzing…</span> : null)}
            {m.streaming && m.text ? <span className="stream-caret" /> : null}
          </div>
        ))}
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        <input id="agent-guidance-q" name="agent-guidance-q" aria-label="Ask the AI agent for guidance" style={{ flex: 1 }} placeholder="Ask for guidance…" value={q}
          onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => e.key === "Enter" && ask()} />
        <button className="btn sm" onClick={ask} disabled={busy}>Ask</button>
      </div>
    </div>
  );
}
