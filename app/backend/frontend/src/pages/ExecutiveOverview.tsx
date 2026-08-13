import { useEffect, useState } from "react";
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell,
} from "recharts";
import {
  getExecSummary, getTeamPerformance, execBriefing,
} from "../api";
import { ErrorState, num, LiveControls, SkelPage, SkelChart } from "../components/ui";

const TEAL = "#006341";   // Nedbank signature green for primary series
const GOLD = "#0a7a53";   // Nedbank green shade for secondary series

export function ExecutiveOverview() {
  const [tab, setTab] = useState<"alerts" | "team">("alerts");
  return (
    <>
      <h1 className="page-title">Executive Overview</h1>
      <p className="page-sub">Real-time operational intelligence across the AML program.</p>
      <div className="tabs">
        <button className={tab === "alerts" ? "active" : ""} onClick={() => setTab("alerts")}>Alerts Overview</button>
        <button className={tab === "team" ? "active" : ""} onClick={() => setTab("team")}>Team Performance</button>
      </div>
      {tab === "alerts" ? <AlertsOverview /> : <TeamPerformance />}
    </>
  );
}

function Kpi({ label, value, tone, delta, prev }: any) {
  return (
    <div className={`kpi ${tone || ""}`}>
      <div className="label">{label}</div>
      <div className="value">{value}</div>
      {delta !== undefined && (
        <div className="delta"><span className={delta < 0 ? "down" : "up"}>{delta < 0 ? "▼" : "▲"} {Math.abs(delta)}%</span> {prev}</div>
      )}
    </div>
  );
}

const EXEC_REFRESH_MS = 20000;

function AlertsOverview() {
  const [kpis, setKpis] = useState<any>(null);
  const [daily, setDaily] = useState<any[]>([]);
  const [outstanding, setOutstanding] = useState<any[]>([]);
  const [scenario, setScenario] = useState<any[]>([]);
  const [ps, setPs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const [live, setLive] = useState(true);
  const [updatedAt, setUpdatedAt] = useState<number | null>(null);
  const [, setTick] = useState(0);

  const refresh = () =>
    getExecSummary()
      .then((r: any) => {
        setErr(false);
        setKpis(r.kpis);
        setDaily((r.daily_new || []).map((x: any) => ({ d: x.d, alerts: num(x.alerts) })));
        setOutstanding((r.outstanding || []).map((x: any) => ({ due: x.due_date, alerts: num(x.alerts) })));
        setScenario((r.by_scenario || []).map((x: any) => ({ scenario: x.scenario, alerts: num(x.alerts) })));
        setPs(r.priority_status || []);
        setUpdatedAt(Date.now());
        setLoading(false);
      }).catch(() => { setErr(true); setLoading(false); });

  useEffect(() => { refresh(); }, []);
  useEffect(() => {
    if (!live) return;
    const id = setInterval(refresh, EXEC_REFRESH_MS);
    return () => clearInterval(id);
  }, [live]);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 10000);
    return () => clearInterval(id);
  }, []);

  if (loading) return <SkelPage kpis={6} rows={5} />;
  if (err && !kpis) return <ErrorState what="executive dashboard" onRetry={() => { setLoading(true); refresh(); }} />;

  return (
    <>
      <div style={{ display: "flex", justifyContent: "flex-end", marginBottom: 8 }}>
        <LiveControls live={live} updatedAt={updatedAt} onToggle={() => setLive((v) => !v)} />
      </div>
      <AiBriefing />
      <div className="kpis">
        <Kpi label="Transaction Amount (ZAR)" tone="green" value={`R${num(kpis.transaction_amount_m).toLocaleString()}m`} delta={-21.87} prev="R208.19m" />
        <Kpi label="Case Volume" tone="green" value={kpis.case_volume} delta={-30.06} prev="163" />
        <Kpi label="Upcoming Deadlines" tone="green" value={kpis.upcoming_deadlines} delta={-13.46} prev="52" />
        <Kpi label="Avg. Investigation Hours" tone="red" value={kpis.avg_investigation_hours} delta={9.73} prev="4.21" />
        <Kpi label="False Positive Rate" tone="green" value={`${kpis.false_positive_rate}%`} delta={-13.75} prev="28.4%" />
        <Kpi label="Past Due Alerts" tone="red" value={kpis.past_due_alerts} delta={0} prev={kpis.past_due_alerts} />
      </div>

      <div className="grid-2">
        <div className="panel">
          <h3>Daily Volume of New Alerts</h3>
          <ResponsiveContainer width="100%" height={280}>
            <AreaChart data={daily} margin={{ left: 0, right: 10, top: 6, bottom: 0 }}>
              <defs><linearGradient id="g1" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={TEAL} stopOpacity={0.6} /><stop offset="100%" stopColor={TEAL} stopOpacity={0.05} />
              </linearGradient></defs>
              <XAxis dataKey="d" tick={{ fill: "#6b7794", fontSize: 10 }} minTickGap={40} />
              <YAxis tick={{ fill: "#6b7794", fontSize: 10 }} />
              <Tooltip />
              <Area type="monotone" dataKey="alerts" stroke={TEAL} strokeWidth={2} fill="url(#g1)" />
            </AreaChart>
          </ResponsiveContainer>
        </div>
        <div className="panel">
          <h3>Outstanding Volume of Alerts</h3>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={outstanding} margin={{ left: 0, right: 10, top: 6, bottom: 0 }}>
              <XAxis dataKey="due" tick={{ fill: "#6b7794", fontSize: 10 }} minTickGap={30} />
              <YAxis tick={{ fill: "#6b7794", fontSize: 10 }} />
              <Tooltip />
              <Bar dataKey="alerts" fill={TEAL} radius={[3, 3, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="grid-2">
        <div className="panel">
          <h3 className="left">Alerts by Scenario</h3>
          <ResponsiveContainer width="100%" height={320}>
            <BarChart data={scenario} layout="vertical" margin={{ left: 60, right: 30, top: 6, bottom: 6 }}>
              <XAxis type="number" tick={{ fill: "#6b7794", fontSize: 10 }} />
              <YAxis type="category" dataKey="scenario" tick={{ fill: "#1f2d4d", fontSize: 11 }} width={150} />
              <Tooltip />
              <Bar dataKey="alerts" fill={TEAL} radius={[0, 4, 4, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
        <div className="panel">
          <h3 className="left">Alerts by Priority and Status</h3>
          <Heatmap data={ps} />
        </div>
      </div>
    </>
  );
}

function AiBriefing() {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  async function run() {
    setBusy(true);
    try { const r = await execBriefing(); setText(r.briefing || ""); } catch { setText("AI briefing unavailable."); }
    setBusy(false);
  }
  return (
    <div className="panel" style={{ borderLeft: "3px solid var(--accent)" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h3 className="left" style={{ margin: 0 }}>✦ AI Executive Briefing</h3>
        <button className="btn sm" onClick={run} disabled={busy}>{busy ? "Generating…" : text ? "Regenerate" : "Generate Briefing"}</button>
      </div>
      {text && <div className="explain" style={{ marginTop: 14 }}>{text}</div>}
      {!text && !busy && <p className="muted" style={{ marginBottom: 0 }}>Generate an AI-authored summary of the AML program's current state, powered by Databricks Foundation Model APIs.</p>}
    </div>
  );
}

function Heatmap({ data }: { data: any[] }) {
  const priorities = ["low", "medium", "high", "critical"];
  const statuses = ["assigned", "closed", "escalated", "in_progress", "new"];
  const get = (p: string, s: string) => num(data.find((r) => r.priority === p && r.status === s)?.alerts);
  const max = Math.max(1, ...data.map((r) => num(r.alerts)));
  const color = (v: number) => {
    const t = v / max;
    const r = Math.round(255 - t * (255 - 140)), g = Math.round(240 - t * (240 - 30)), b = Math.round(235 - t * (235 - 25));
    return `rgb(${r},${g},${b})`;
  };
  return (
    <table>
      <thead><tr><th scope="col"></th>{statuses.map((s) => <th scope="col" key={s} style={{ textAlign: "center" }}>{s}</th>)}</tr></thead>
      <tbody>
        {priorities.map((p) => (
          <tr key={p}>
            <td style={{ fontWeight: 700, textTransform: "capitalize" }}>{p}</td>
            {statuses.map((s) => {
              const v = get(p, s);
              return <td key={s} style={{ textAlign: "center", background: color(v), color: v / max > 0.55 ? "#fff" : "#1f2d4d", fontWeight: 600 }}>{v}</td>;
            })}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function TeamPerformance() {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const load = () => { setErr(false); getTeamPerformance().then((r) => { setRows(r); setLoading(false); }).catch(() => { setErr(true); setLoading(false); }); };
  useEffect(() => { load(); }, []);
  if (loading) return <SkelChart title="team performance" />;
  if (err) return <ErrorState what="team performance" onRetry={() => { setLoading(true); load(); }} />;
  const data = rows.map((r) => ({ team: r.team_name, hours: num(r.avg_hours), cases: num(r.cases), closed: num(r.closed), past_due: num(r.past_due) }));
  return (
    <>
      <div className="panel">
        <h3 className="left">Average Turnaround Hours by Team</h3>
        <ResponsiveContainer width="100%" height={300}>
          <BarChart data={data} margin={{ left: 0, right: 20, top: 10, bottom: 30 }}>
            <XAxis dataKey="team" tick={{ fill: "#6b7794", fontSize: 10 }} angle={-12} textAnchor="end" height={50} />
            <YAxis tick={{ fill: "#6b7794", fontSize: 10 }} />
            <Tooltip />
            <Bar dataKey="hours" radius={[2, 2, 0, 0]}>{data.map((_, i) => <Cell key={i} fill={GOLD} />)}</Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
      <div className="panel">
        <h3 className="left">Team Breakdown</h3>
        <table>
          <thead><tr><th scope="col">Team</th><th scope="col">Cases</th><th scope="col">Closed</th><th scope="col">Past Due</th><th scope="col">Avg Hours</th><th scope="col">Avg Risk</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.team_name}>
                <td style={{ fontWeight: 600 }}>{r.team_name}</td>
                <td>{r.cases}</td><td>{r.closed}</td>
                <td style={{ color: num(r.past_due) > 100 ? "var(--critical)" : undefined }}>{r.past_due}</td>
                <td>{r.avg_hours}</td><td>{r.avg_risk}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
