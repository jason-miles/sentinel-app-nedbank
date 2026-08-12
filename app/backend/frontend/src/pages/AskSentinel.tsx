import { useState } from "react";
import { genieAsk } from "../api";

const SUGGESTIONS = [
  "Which scenarios have the most alerts?",
  "How many critical alerts are past due?",
  "Show alert volume by team",
  "What is the average investigation time by scenario?",
  "Which customers have the highest risk scores?",
];

type Turn = { q: string; answer?: string; sql?: string; columns?: string[]; rows?: any[]; loading?: boolean; error?: string };

export function AskSentinel() {
  const [q, setQ] = useState("");
  const [turns, setTurns] = useState<Turn[]>([]);
  const [conv, setConv] = useState<string | undefined>();
  const [busy, setBusy] = useState(false);

  async function ask(question: string) {
    if (!question.trim() || busy) return;
    setBusy(true); setQ("");
    setTurns((t) => [...t, { q: question, loading: true }]);
    try {
      const r = await genieAsk({ question, conversation_id: conv });
      if (r.conversation_id) setConv(r.conversation_id);
      setTurns((t) => t.map((x, i) => i === t.length - 1
        ? { q: question, answer: r.answer, sql: r.sql, columns: r.columns, rows: r.rows, error: r.ok ? undefined : r.error }
        : x));
    } catch {
      setTurns((t) => t.map((x, i) => i === t.length - 1 ? { q: question, error: "Request failed." } : x));
    }
    setBusy(false);
  }

  return (
    <>
      <h1 className="page-title">Ask Sentinel</h1>
      <p className="page-sub">Natural-language analytics over the AML program, powered by Databricks Genie — governed answers with the SQL behind them.</p>

      <div className="panel">
        <div style={{ display: "flex", gap: 10 }}>
          <input aria-label="Ask Sentinel question" style={{ flex: 1 }} placeholder="Ask a question about alerts, cases, teams, or customers…"
            value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => e.key === "Enter" && ask(q)} />
          <button className="btn" onClick={() => ask(q)} disabled={busy}>{busy ? "Thinking…" : "Ask Genie"}</button>
        </div>
        <div style={{ marginTop: 12 }}>
          {SUGGESTIONS.map((s) => <button key={s} type="button" className="chip" onClick={() => ask(s)}>{s}</button>)}
        </div>
      </div>

      {turns.slice().reverse().map((t, i) => (
        <div className="panel" key={turns.length - 1 - i}>
          <div className="msg user"><div className="who">Question</div>{t.q}</div>
          {t.loading && <div className="msg ai"><div className="who">Genie</div>Analyzing your question and generating SQL…</div>}
          {t.error && <div className="msg ai"><div className="who">Genie</div><span style={{ color: "var(--critical)" }}>{t.error}</span></div>}
          {t.answer && (
            <>
              <div className="msg ai"><div className="who">Genie</div>{t.answer}</div>
              {t.rows && t.rows.length > 0 && (
                <div style={{ overflowX: "auto", marginTop: 10 }}>
                  <table>
                    <thead><tr>{(t.columns || []).map((c) => <th key={c}>{c}</th>)}</tr></thead>
                    <tbody>
                      {t.rows.slice(0, 20).map((r, ri) => (
                        <tr key={ri}>{(t.columns || []).map((c) => <td key={c}>{String(r[c])}</td>)}</tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
              {t.sql && (
                <details style={{ marginTop: 10 }}>
                  <summary className="muted" style={{ cursor: "pointer" }}>View generated SQL</summary>
                  <pre className="mono" style={{ background: "var(--canvas)", padding: 12, borderRadius: 3, overflowX: "auto", whiteSpace: "pre-wrap" }}>{t.sql}</pre>
                </details>
              )}
            </>
          )}
        </div>
      ))}
    </>
  );
}
