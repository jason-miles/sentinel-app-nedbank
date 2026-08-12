import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from "recharts";
import { getQueue, casePrioritize } from "../api";
import { Sev, Loading, ErrorState, usePersona, num, money, LiveControls } from "../components/ui";

// Nedbank tonal palette: deep-blue shades + signature red + muted blue-grey.
const SCEN_COLORS: Record<string, string> = {
  "Cash Structuring Detection": "#006341", "Dormant Account Reactivation": "#0a7a53",
  "Rapid Fund Movement": "#3fae7e", "Related Account Movement": "#044a33",
  "Round Dollar Pattern": "#7fae97", "PEP/Sanctions Alert": "#b42318",
  "High-Risk Geography Transfer": "#b54708", "Beneficiary Mismatch": "#5f7369",
  "Third-Party Deposit Pattern": "#aecabb",
};

const REFRESH_MS = 20000; // near-real-time queue refresh cadence

export function AlertInvestigation() {
  const nav = useNavigate();
  const { current } = usePersona();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const [live, setLive] = useState(true);
  const [updatedAt, setUpdatedAt] = useState<number | null>(null);
  const [, setTick] = useState(0); // ticks so the "updated Ns ago" label stays fresh
  const [fPriority, setFPriority] = useState("");
  const [fScenario, setFScenario] = useState("");

  // Initial load (with spinner) whenever persona or filters change.
  const load = () => {
    if (!current) return;
    setLoading(true); setErr(false);
    getQueue(current.analyst_id, fPriority, fScenario).then((d) => { setErr(false); setData(d); setUpdatedAt(Date.now()); setLoading(false); }).catch(() => { setErr(true); setLoading(false); });
  };
  useEffect(() => { load(); }, [current, fPriority, fScenario]);

  // Live polling — silent refresh (no spinner), pausable. Respects active filters.
  useEffect(() => {
    if (!current || !live) return;
    const id = setInterval(() => {
      getQueue(current.analyst_id, fPriority, fScenario).then((d) => { setData(d); setUpdatedAt(Date.now()); }).catch(() => {});
    }, REFRESH_MS);
    return () => clearInterval(id);
  }, [current, live, fPriority, fScenario]);

  // Keep the "updated Ns ago" label fresh between refreshes.
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 10000);
    return () => clearInterval(id);
  }, []);

  if (err && !data) return <ErrorState what="my queue" onRetry={load} />;
  if (loading || !data) return <Loading what="my queue" />;
  const k = data.kpis || {};

  // pivot weekly -> stacked by scenario
  const weeks: Record<string, any> = {};
  const scenarios = new Set<string>();
  (data.weekly || []).forEach((r: any) => {
    const wk = new Date(r.week).toLocaleDateString("en-US", { month: "short", day: "numeric" });
    weeks[wk] = weeks[wk] || { week: `Week of ${wk}` };
    weeks[wk][r.scenario] = num(r.alerts);
    scenarios.add(r.scenario);
  });
  const weekData = Object.values(weeks);

  return (
    <>
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", flexWrap: "wrap", gap: 8 }}>
        <h1 className="page-title">My Queue — {current?.analyst_name}</h1>
        <LiveControls live={live} updatedAt={updatedAt} onToggle={() => setLive((v) => !v)} />
      </div>
      <p className="page-sub">{current?.team_name}</p>

      <div className="kpis">
        <div className="kpi"><div className="label"><span className="dot" style={{ background: "var(--critical)" }} />Critical</div><div className="value navy">{k.critical || 0}</div></div>
        <div className="kpi"><div className="label"><span className="dot" style={{ background: "var(--medium)" }} />High</div><div className="value navy">{k.high || 0}</div></div>
        <div className="kpi"><div className="label">Total Alerts</div><div className="value navy">{k.total || 0}</div></div>
        <div className="kpi"><div className="label">New Alerts</div><div className="value" style={{ color: "var(--royal)" }}>{k.new_alerts || 0}</div></div>
      </div>

      <div className="panel">
        <h3 className="left">Daily Alerts by Scenario — {current?.analyst_name}</h3>
        <ResponsiveContainer width="100%" height={320}>
          <BarChart data={weekData} margin={{ left: 0, right: 20, top: 10, bottom: 10 }}>
            <XAxis dataKey="week" tick={{ fill: "#6b7794", fontSize: 11 }} />
            <YAxis tick={{ fill: "#6b7794", fontSize: 10 }} />
            <Tooltip />
            <Legend wrapperStyle={{ fontSize: 11 }} />
            {[...scenarios].map((s) => (
              <Bar key={s} dataKey={s} stackId="a" fill={SCEN_COLORS[s] || "#94a3b8"} />
            ))}
          </BarChart>
        </ResponsiveContainer>
      </div>

      <div className="panel">
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 8 }}>
          <h3 className="left" style={{ margin: 0 }}>Active Alerts {(fPriority || fScenario) ? `(${(data.active_alerts || []).length} filtered)` : ""}</h3>
          <div style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 12 }}>
            <select aria-label="Filter by priority" value={fPriority} onChange={(e) => setFPriority(e.target.value)}>
              <option value="">All priorities</option>
              <option value="critical">Critical</option>
              <option value="high">High</option>
              <option value="medium">Medium</option>
              <option value="low">Low</option>
            </select>
            <select aria-label="Filter by scenario" value={fScenario} onChange={(e) => setFScenario(e.target.value)}>
              <option value="">All scenarios</option>
              {Object.keys(SCEN_COLORS).map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
            {(fPriority || fScenario) && <button className="btn sm ghost" onClick={() => { setFPriority(""); setFScenario(""); }}>Clear</button>}
          </div>
        </div>
        <table>
          <thead><tr><th scope="col">Alert ID</th><th scope="col">Customer</th><th scope="col">Scenario</th><th scope="col">Rules Score</th><th scope="col">AI Risk</th><th scope="col">Priority</th><th scope="col">Amount</th><th scope="col">Days</th><th scope="col">SLA</th><th scope="col">Action</th></tr></thead>
          <tbody>
            {(data.active_alerts || []).map((a: any) => <AlertRow key={a.case_id} a={a} nav={nav} />)}
          </tbody>
        </table>
      </div>
    </>
  );
}

function AlertRow({ a, nav }: { a: any; nav: any }) {
  const [blurb, setBlurb] = useState("");
  const [busy, setBusy] = useState(false);
  async function ai() {
    setBusy(true);
    try { const r = await casePrioritize({ case_id: a.case_id }); setBlurb(r.blurb || ""); } catch { setBlurb("AI unavailable."); }
    setBusy(false);
  }
  return (
    <>
      <tr>
        <td className="mono">{a.alert_num}</td>
        <td>{a.customer_name}</td>
        <td>{a.scenario}</td>
        <td><span style={{ color: "var(--muted)", fontWeight: 600 }}>{a.risk_score}</span></td>
        <td>{a.ai_risk != null
          ? <span title={`Served model v${a.model_version}`} style={{ color: num(a.ai_risk) >= 80 ? "var(--critical)" : "var(--navy)", fontWeight: 800 }}>{a.ai_risk}<span style={{ fontSize: 10, color: "var(--accent)", marginLeft: 3 }}>✦AI</span></span>
          : <span className="muted">—</span>}</td>
        <td><Sev s={a.priority} /></td>
        <td style={{ fontWeight: 600 }}>{money(a.amount)}</td>
        <td style={{ color: num(a.days_open) > 90 ? "var(--critical)" : undefined }}>{a.days_open}</td>
        <td>{a.sla ? <SlaBadge sla={a.sla} /> : <span className="muted">—</span>}</td>
        <td style={{ display: "flex", gap: 6 }}>
          <button className="btn sm ghost" onClick={ai} disabled={busy} title="AI: why this matters">✦</button>
          <button className="btn sm" onClick={() => nav(`/investigation/${a.case_id}`)}>Investigate</button>
        </td>
      </tr>
      {blurb && (
        <tr><td colSpan={10} style={{ background: "var(--canvas)", borderLeft: "3px solid var(--accent)" }}>
          <span className="muted" style={{ fontWeight: 700, marginRight: 8 }}>✦ AI</span>{blurb}
        </td></tr>
      )}
    </>
  );
}

export function SlaBadge({ sla }: { sla: any }) {
  const color: Record<string, string> = { on_track: "var(--navy)", at_risk: "#b54708", breached: "var(--critical)" };
  const label: Record<string, string> = { on_track: "On track", at_risk: "At risk", breached: "Breached" };
  const s = sla.status || "on_track";
  const tip = sla.breached
    ? `${-sla.days_remaining}d over ${sla.target_days}d SLA`
    : `${sla.days_remaining}d left of ${sla.target_days}d SLA`;
  return <span className="badge" title={tip} style={{ background: color[s], color: "#fff" }}>{label[s] || s}</span>;
}
