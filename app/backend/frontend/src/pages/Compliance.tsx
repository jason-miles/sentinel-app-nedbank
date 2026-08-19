import { useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { getScreening, getPkyc, getPkycSummary, getAnomalies, getModelGovernance, getModelDrift, getLlmEval, getAudit, getImpossibleTravel } from "../api";
import { ErrorState, num, money, SkelTable, SkelKpis } from "../components/ui";
import { WORLD_LAND_PATH } from "../worldPath";

function Badge({ s }: { s: string }) {
  const map: Record<string, string> = { confirmed: "critical", probable: "high", possible: "medium",
    critical: "critical", high: "high", medium: "medium", low: "low" };
  return <span className={`badge sev-${map[s] || "medium"}`}>{s}</span>;
}

const TABS = ["screening", "pkyc", "anomaly", "travel", "model", "audit"] as const;
type Tab = typeof TABS[number];

export function Compliance() {
  // Tab is URL-driven (?tab=travel) so it's deep-linkable and the guided demo ("Play the
  // Demo") can open a specific surface — e.g. Impossible Travel or Model Governance.
  const [params, setParams] = useSearchParams();
  const raw = params.get("tab");
  const tab: Tab = raw && (TABS as readonly string[]).includes(raw) ? (raw as Tab) : "screening";
  const setTab = (t: Tab) => setParams(t === "screening" ? {} : { tab: t }, { replace: true });
  return (
    <>
      <h1 className="page-title">Compliance & Risk</h1>
      <p className="page-sub">Sanctions & watchlist screening · perpetual KYC · behavioural peer-group anomaly detection · impossible travel · model governance · audit trail.</p>
      <div className="tabs">
        <button className={tab === "screening" ? "active" : ""} onClick={() => setTab("screening")}>Sanctions Screening</button>
        <button className={tab === "pkyc" ? "active" : ""} onClick={() => setTab("pkyc")}>Perpetual KYC</button>
        <button className={tab === "anomaly" ? "active" : ""} onClick={() => setTab("anomaly")}>Peer Anomalies</button>
        <button className={tab === "travel" ? "active" : ""} onClick={() => setTab("travel")}>Impossible Travel</button>
        <button className={tab === "model" ? "active" : ""} onClick={() => setTab("model")}>Model Governance</button>
        <button className={tab === "audit" ? "active" : ""} onClick={() => setTab("audit")}>Audit Trail</button>
      </div>
      {tab === "screening" && <Screening />}
      {tab === "pkyc" && <Pkyc />}
      {tab === "anomaly" && <Anomaly />}
      {tab === "travel" && <ImpossibleTravel />}
      {tab === "model" && <ModelGovernance />}
      {tab === "audit" && <AuditTrail />}
    </>
  );
}

function AuditTrail() {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const load = () => { setErr(false); getAudit(150).then((r) => { setErr(false); setRows(r); setLoading(false); }).catch(() => { setErr(true); setLoading(false); }); };
  useEffect(() => { load(); }, []);
  if (loading) return <SkelTable rows={8} title="audit trail" />;
  if (err) return <ErrorState what="audit trail" onRetry={() => { setLoading(true); load(); }} />;
  const label: Record<string, string> = {
    case_open: "Case opened", note_add: "Note added", case_action: "Case action",
    sar_submit: "SAR filed", sar_generate: "SAR drafted",
  };
  return (
    <>
      <div className="kpis">
        <div className="kpi"><div className="label">Audit Events</div><div className="value navy">{rows.length}</div></div>
        <div className="kpi"><div className="label">SAR Filings</div><div className="value red">{rows.filter((r) => r.action === "sar_submit").length}</div></div>
        <div className="kpi"><div className="label">Case Actions</div><div className="value navy">{rows.filter((r) => r.action === "case_action").length}</div></div>
        <div className="kpi"><div className="label">Distinct Actors</div><div className="value navy">{new Set(rows.map((r) => r.actor)).size}</div></div>
      </div>
      <div className="panel">
        <h3 className="left">Defensible Audit Trail — every read, decision & SAR action, stamped with acting user + timestamp</h3>
        {rows.length === 0
          ? <p className="muted" style={{ margin: "10px 0 0" }}>No audit events yet. Open a case, add a note, or file a SAR to generate an entry.</p>
          : <table>
              <thead><tr><th scope="col">Timestamp</th><th scope="col">Actor</th><th scope="col">Action</th><th scope="col">Case</th><th scope="col">Detail</th><th scope="col">Source</th></tr></thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={i}>
                    <td className="mono" style={{ whiteSpace: "nowrap" }}>{String(r.event_ts).replace("T", " ").slice(0, 19)}</td>
                    <td>{r.actor}</td>
                    <td><span className="badge">{label[r.action] || r.action}</span></td>
                    <td className="mono">{r.case_id || "—"}</td>
                    <td className="muted">{r.detail}</td>
                    <td className="muted">{r.source}</td>
                  </tr>
                ))}
              </tbody>
            </table>}
      </div>
    </>
  );
}

function ModelGovernance() {
  const [m, setM] = useState<any>(null);
  const [drift, setDrift] = useState<any>(null);
  const [ev, setEv] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const load = () => {
    setErr(false);
    Promise.all([getModelGovernance(), getModelDrift().catch(() => null), getLlmEval().catch(() => null)])
      .then(([mg, dr, le]) => { setErr(false); setM(mg); setDrift(dr); setEv(le); setLoading(false); })
      .catch(() => { setErr(true); setLoading(false); });
  };
  useEffect(() => { load(); }, []);
  if (loading) return <div aria-busy="true"><SkelKpis n={4} /><SkelTable rows={5} /></div>;
  if (err) return <ErrorState what="model validation record" onRetry={() => { setLoading(true); load(); }} />;
  if (!m || m.model_version == null) return <p className="muted">No registered model metrics found. Train &amp; score the SAR model first.</p>;
  const pct = (x: any) => `${(num(x) * 100).toFixed(1)}%`;
  const driftColor: Record<string, string> = { stable: "var(--navy)", warning: "#b54708", drift: "var(--critical)" };
  return (
    <>
      <div className="kpis">
        <div className="kpi"><div className="label">False Positives ↓</div><div className="value red">{num(m.fp_reduction_pct).toFixed(1)}%</div></div>
        <div className="kpi"><div className="label">ROC-AUC</div><div className="value navy">{num(m.roc_auc).toFixed(3)}</div></div>
        <div className="kpi"><div className="label">Precision</div><div className="value navy">{pct(m.precision)}</div></div>
        <div className="kpi"><div className="label">Recall</div><div className="value navy">{pct(m.recall)}</div></div>
      </div>

      <div className="panel">
        <h3 className="left">Model Validation Record — SAR-propensity classifier</h3>
        <p className="muted" style={{ margin: "4px 0 14px" }}>
          At an equal alert budget, the served model surfaces <strong>{num(m.fp_reduction_pct).toFixed(1)}% fewer false positives</strong> than
          the legacy rules score ({m.model_fp} vs {m.rules_fp} on the held-out test set) — the same true-positive workload, fewer wasted investigations.
          The displayed AI risk blends the model ({pct(m.blend_model_weight)}) with rules ({pct(m.blend_rules_weight)}), with rules as a floor.
        </p>
        <table>
          <tbody>
            <tr><td>Model</td><td className="mono">{m.model_name}</td></tr>
            <tr><td>Version</td><td><span className="badge">v{m.model_version}</span> · {m.governance_status}</td></tr>
            <tr><td>Algorithm</td><td>{m.algorithm}</td></tr>
            <tr><td>Registry</td><td>Unity Catalog Model Registry (MLflow)</td></tr>
            <tr><td>MLflow run</td><td className="mono">{m.run_id}</td></tr>
            <tr><td>Features</td><td>{m.n_features}</td></tr>
            <tr><td>Labelled cases</td><td>{m.n_labelled} ({pct(m.positive_rate)} SAR-filed)</td></tr>
            <tr><td>F1</td><td>{num(m.f1).toFixed(3)}</td></tr>
          </tbody>
        </table>
      </div>

      {drift && (
        <div className="panel">
          <h3 className="left">Feature Drift Monitoring — ongoing validation
            <span className="badge" style={{ marginLeft: 10, background: driftColor[drift.overall_status] || "var(--navy)", color: "#fff" }}>
              {String(drift.overall_status || "stable").toUpperCase()}
            </span>
          </h3>
          <p className="muted" style={{ margin: "4px 0 14px" }}>
            Current feature distribution vs the training baseline (standardised mean shift). A
            <strong> drift</strong> verdict triggers a retrain (scheduled job <span className="mono">fraud_ml_retrain</span>).
          </p>
          <table>
            <thead><tr><th scope="col">Feature</th><th scope="col">Baseline μ</th><th scope="col">Current μ</th><th scope="col">Shift (σ)</th><th scope="col">Status</th></tr></thead>
            <tbody>
              {(drift.features || []).map((f: any, i: number) => (
                <tr key={i}>
                  <td className="mono">{f.feature}</td>
                  <td>{f.baseline_mean}</td>
                  <td>{f.current_mean}</td>
                  <td>{f.mean_shift_sigma}</td>
                  <td><span style={{ color: driftColor[f.drift_status] || "var(--navy)", fontWeight: 700 }}>{f.drift_status}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {ev && ev.summary && num(ev.summary.runs) > 0 && (
        <div className="panel">
          <h3 className="left">LLM Evaluation & Guardrails — SAR narrative
            <span className="badge" style={{ marginLeft: 10, background: num(ev.summary.overall_pass_rate) >= 0.8 ? "var(--navy)" : "#b54708", color: "#fff" }}>
              {pct(ev.summary.overall_pass_rate)} pass
            </span>
          </h3>
          <p className="muted" style={{ margin: "4px 0 14px" }}>
            LLM-as-judge groundedness + completeness and a deterministic PII/length guardrail, run over generated SARs
            ({ev.summary.runs} run{num(ev.summary.runs) === 1 ? "" : "s"}). An auditable record of how the GenAI surface is validated.
          </p>
          <div className="kpis">
            <div className="kpi"><div className="label">Groundedness</div><div className="value navy">{pct(ev.summary.avg_groundedness)}</div></div>
            <div className="kpi"><div className="label">Completeness</div><div className="value navy">{pct(ev.summary.avg_completeness)}</div></div>
            <div className="kpi"><div className="label">Guardrail pass</div><div className="value navy">{pct(ev.summary.guardrail_pass_rate)}</div></div>
            <div className="kpi"><div className="label">Overall pass</div><div className="value" style={{ color: num(ev.summary.overall_pass_rate) >= 0.8 ? "var(--navy)" : "var(--critical)" }}>{pct(ev.summary.overall_pass_rate)}</div></div>
          </div>
        </div>
      )}
    </>
  );
}

function Screening() {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const load = () => { setErr(false); getScreening("", 200).then((r) => { setErr(false); setRows(r); setLoading(false); }).catch(() => { setErr(true); setLoading(false); }); };
  useEffect(() => { load(); }, []);
  if (loading) return <SkelTable rows={8} title="screening hits" />;
  if (err) return <ErrorState what="screening hits" onRetry={() => { setLoading(true); load(); }} />;
  const confirmed = rows.filter((r) => r.confidence === "confirmed").length;
  return (
    <>
      <div className="kpis">
        <div className="kpi"><div className="label">Total Hits</div><div className="value navy">{rows.length}</div></div>
        <div className="kpi"><div className="label">Confirmed</div><div className="value red">{confirmed}</div></div>
        <div className="kpi"><div className="label">Sanctions</div><div className="value navy">{rows.filter((r) => r.list_type === "sanctions").length}</div></div>
        <div className="kpi"><div className="label">PEP</div><div className="value navy">{rows.filter((r) => r.list_type === "pep").length}</div></div>
      </div>
      <div className="panel">
        <h3 className="left">Screening Hits — customers & counterparties vs sanctions / PEP / adverse watchlists</h3>
        <table>
          <thead><tr><th scope="col">Entity</th><th scope="col">Type</th><th scope="col">Watchlist Match</th><th scope="col">List</th><th scope="col">Source</th><th scope="col">Confidence</th><th scope="col">Score</th><th scope="col">Reason</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.screening_id}>
                <td style={{ fontWeight: 600 }}>{r.entity_name}</td>
                <td className="muted">{r.party_type}</td>
                <td>{r.watch_name}</td>
                <td><Badge s={r.list_type} /></td>
                <td className="muted">{r.list_source}</td>
                <td><Badge s={r.confidence} /></td>
                <td>{Number(r.match_score).toFixed(2)}</td>
                <td className="muted" style={{ maxWidth: 260 }}>{r.reason}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

function Pkyc() {
  const [rows, setRows] = useState<any[]>([]);
  const [summary, setSummary] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const load = () => {
    setErr(false);
    Promise.all([getPkyc(20, 100), getPkycSummary()]).then(([r, s]) => { setErr(false); setRows(r); setSummary(s); setLoading(false); }).catch(() => { setErr(true); setLoading(false); });
  };
  useEffect(() => { load(); }, []);
  if (loading) return <SkelTable rows={8} title="perpetual KYC" />;
  if (err) return <ErrorState what="perpetual KYC" onRetry={() => { setLoading(true); load(); }} />;
  const band = (b: string) => num((summary?.bands || []).find((x: any) => x.risk_band === b)?.customers);
  const eddTotal = (summary?.bands || []).reduce((s: number, x: any) => s + num(x.edd_required), 0);
  return (
    <>
      <div className="kpis">
        <div className="kpi"><div className="label">Critical Risk</div><div className="value red">{band("critical")}</div></div>
        <div className="kpi"><div className="label">High Risk</div><div className="value navy">{band("high")}</div></div>
        <div className="kpi"><div className="label">Medium Risk</div><div className="value navy">{band("medium")}</div></div>
        <div className="kpi"><div className="label">EDD Reviews Due</div><div className="value red">{eddTotal}</div></div>
      </div>
      <div className="panel">
        <h3 className="left">Dynamic Customer Risk — continuously recomputed from alerts, sanctions, adverse media, geography & exposure</h3>
        <table>
          <thead><tr><th scope="col">Customer</th><th scope="col">Segment</th><th scope="col">Country</th><th scope="col">Dynamic Risk</th><th scope="col">Band</th><th scope="col">EDD</th><th scope="col">Risk Drivers</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.customer_id}>
                <td style={{ fontWeight: 600 }}>{r.full_name}</td>
                <td className="muted">{r.segment}</td>
                <td>{r.country}</td>
                <td><strong>{r.dynamic_risk}</strong>/100</td>
                <td><Badge s={r.risk_band} /></td>
                <td>{String(r.edd_review_required) === "true" ? <span className="badge sev-high">Required</span> : <span className="muted">—</span>}</td>
                <td className="muted" style={{ maxWidth: 340 }}>{r.risk_drivers || "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

// Professional equirectangular world map (no map lib): real Natural-Earth coastlines
// (WORLD_LAND_PATH) projected with the SAME lon/lat -> x/y transform as the alert arcs,
// an ocean gradient + faint graticule, glowing arcs with a travelling "signal" pulse that
// dramatises the impossible hop, and de-duplicated, halo-outlined, decluttered city labels
// so clustered taps (e.g. Johannesburg / Durban / Cape Town) stay legible.
function TravelMap({ rows }: { rows: any[] }) {
  const W = 720, H = 360;
  const proj = (lat: number, lon: number): [number, number] => [((lon + 180) / 360) * W, ((90 - lat) / 180) * H];

  // Collect arcs and the de-duplicated set of tapped cities across every alert leg.
  const cities = new Map<string, { x: number; y: number; city: string }>();
  const arcs: { id: string; d: string; mx: number; my: number; kmh?: number }[] = [];
  rows.forEach((r, i) => {
    const legs = r.legs || [];
    if (legs.length < 2) return;
    const [ax, ay] = proj(Number(legs[0].lat), Number(legs[0].lon));
    const [bx, by] = proj(Number(legs[1].lat), Number(legs[1].lon));
    ([[ax, ay, legs[0].city], [bx, by, legs[1].city]] as [number, number, string][]).forEach(([x, y, city]) => {
      if (city && !cities.has(city)) cities.set(city, { x, y, city });
    });
    // Curvature scales with distance so long hops bow more (a cleaner, map-like arc).
    const dist = Math.hypot(bx - ax, by - ay);
    const mx = (ax + bx) / 2, my = Math.min(ay, by) - Math.max(24, dist * 0.28);
    arcs.push({ id: `arc-${i}`, d: `M ${ax} ${ay} Q ${mx} ${my} ${bx} ${by}`, mx, my, kmh: Number(r.implied_kmh) || undefined });
  });

  // Greedy label declutter: push a colliding label downward and drop a faint leader line.
  const placed: { x: number; y: number }[] = [];
  const labels = [...cities.values()].sort((a, b) => a.y - b.y || a.x - b.x).map((c) => {
    const lx = c.x + 9; let ly = c.y - 5, guard = 0;
    while (placed.some((p) => Math.abs(p.x - lx) < 60 && Math.abs(p.y - ly) < 12) && guard < 10) { ly += 12; guard++; }
    placed.push({ x: lx, y: ly });
    return { ...c, lx, ly, moved: ly !== c.y - 5 };
  });

  const halo = { paintOrder: "stroke", stroke: "var(--graph-bg)", strokeWidth: 3 } as any;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="travel-map" role="img" preserveAspectRatio="xMidYMid meet"
      aria-label="Impossible-travel card taps on a world map">
      <defs>
        <linearGradient id="arcGrad" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor="var(--accent)" stopOpacity="0.2" />
          <stop offset="55%" stopColor="var(--critical)" stopOpacity="0.95" />
          <stop offset="100%" stopColor="var(--critical)" stopOpacity="0.95" />
        </linearGradient>
        <radialGradient id="oceanGrad" cx="50%" cy="40%" r="75%">
          <stop offset="0%" stopColor="var(--panel)" />
          <stop offset="100%" stopColor="var(--graph-bg)" />
        </radialGradient>
        <filter id="arcGlow" x="-20%" y="-40%" width="140%" height="180%">
          <feGaussianBlur stdDeviation="1.5" result="b" />
          <feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge>
        </filter>
      </defs>

      <rect x="0" y="0" width={W} height={H} fill="url(#oceanGrad)" />
      {[-120, -60, 0, 60, 120].map((lon) => <line key={`v${lon}`} x1={proj(0, lon)[0]} y1={0} x2={proj(0, lon)[0]} y2={H} stroke="var(--border)" strokeWidth="0.5" opacity="0.45" />)}
      {[-60, -30, 0, 30, 60].map((lat) => <line key={`h${lat}`} x1={0} y1={proj(lat, 0)[1]} x2={W} y2={proj(lat, 0)[1]} stroke="var(--border)" strokeWidth="0.5" opacity="0.45" />)}
      <path d={WORLD_LAND_PATH} fill="var(--panel-2)" stroke="var(--border)" strokeWidth="0.6" strokeLinejoin="round" opacity="0.96" />

      {arcs.map((a) => (
        <g key={a.id}>
          <path id={a.id} d={a.d} fill="none" stroke="url(#arcGrad)" strokeWidth="1.8" strokeLinecap="round" filter="url(#arcGlow)" />
          <circle r="2.6" fill="#fff">
            <animateMotion dur="2.4s" repeatCount="indefinite" rotate="auto"><mpath href={`#${a.id}`} /></animateMotion>
          </circle>
          {a.kmh && (
            <text x={a.mx} y={a.my - 4} fontSize="8.5" textAnchor="middle" fill="var(--critical)"
              style={{ ...halo, fontWeight: 700 }}>{a.kmh.toLocaleString()} km/h</text>
          )}
        </g>
      ))}

      {labels.map((c) => (
        <g key={c.city}>
          {c.moved && <line x1={c.x} y1={c.y} x2={c.lx - 2} y2={c.ly - 3} stroke="var(--border)" strokeWidth="0.6" />}
          <circle cx={c.x} cy={c.y} r="7" fill="var(--critical)" opacity="0.18" />
          <circle cx={c.x} cy={c.y} r="3.4" fill="var(--critical)" stroke="#fff" strokeWidth="0.8" />
          <text x={c.lx} y={c.ly} fontSize="10" fill="var(--text)" style={halo}>{c.city}</text>
        </g>
      ))}
    </svg>
  );
}

function ImpossibleTravel() {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const load = () => { setErr(false); getImpossibleTravel().then((r) => { setRows(r); setLoading(false); }).catch(() => { setErr(true); setLoading(false); }); };
  useEffect(() => { load(); }, []);
  if (loading) return <SkelTable rows={6} title="impossible-travel alerts" />;
  if (err) return <ErrorState what="impossible-travel alerts" onRetry={() => { setLoading(true); load(); }} />;
  return (
    <div className="panel">
      <h3 className="left">Impossible Travel — one card tapped in two places too far apart to be physical</h3>
      <p className="muted" style={{ marginTop: 0 }}>Geospatial velocity on card taps (haversine km ÷ elapsed time). An implied speed above ~900 km/h can't be a real journey — a strong card-compromise / cloning signal.</p>
      {rows.length > 0 && <TravelMap rows={rows} />}
      {rows.length === 0 && <span className="muted">No impossible-travel alerts.</span>}
      {rows.map((r) => {
        const legs = r.legs || [];
        const a = legs[0] || {}; const b = legs[1] || {};
        return (
          <div key={r.alert_id} className="explain" style={{ marginBottom: 12, borderLeft: "3px solid var(--critical)" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
              <span style={{ fontWeight: 700 }}>{a.city || r.from_city}</span>
              <span className="muted">{a.country || ""} {a.merchant ? `· ${a.merchant}` : ""}</span>
              <span style={{ color: "var(--critical)", fontWeight: 700 }}>→</span>
              <span style={{ fontWeight: 700 }}>{b.city || r.to_city}</span>
              <span className="muted">{b.country || ""} {b.merchant ? `· ${b.merchant}` : ""}</span>
              <span className="badge sev-critical" style={{ marginLeft: "auto" }}>{Number(r.implied_kmh).toLocaleString()} km/h</span>
            </div>
            <div className="muted" style={{ marginTop: 6, fontSize: 12 }}>
              Card <span className="mono">{r.account_id}</span> · score {Number(r.score).toFixed(2)} · {r.explanation}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Anomaly() {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const load = () => { setErr(false); getAnomalies(100).then((r) => { setErr(false); setRows(r); setLoading(false); }).catch(() => { setErr(true); setLoading(false); }); };
  useEffect(() => { load(); }, []);
  if (loading) return <SkelTable rows={8} title="peer anomalies" />;
  if (err) return <ErrorState what="peer anomalies" onRetry={() => { setLoading(true); load(); }} />;
  return (
    <>
      <div className="panel">
        <h3 className="left">Behavioural Peer-Group Anomalies — customers behaving unlike their segment peers (unsupervised, 3σ+)</h3>
        <p className="muted" style={{ marginTop: 0 }}>Catches novel typologies fixed thresholds miss — the false-positive-reduction story.</p>
        <table>
          <thead><tr><th scope="col">Customer</th><th scope="col">Segment</th><th scope="col">Txns (90d)</th><th scope="col">Peer Avg</th><th scope="col">Anomaly σ</th><th scope="col">Severity</th><th scope="col">Explanation</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.customer_id}>
                <td style={{ fontWeight: 600 }}>{r.full_name}</td>
                <td className="muted">{r.segment}</td>
                <td>{r.txn_count}</td>
                <td className="muted">{Number(r.peer_avg_txns).toFixed(0)}</td>
                <td><strong>{Number(r.anomaly_score).toFixed(1)}σ</strong></td>
                <td><Badge s={r.severity} /></td>
                <td className="muted" style={{ maxWidth: 400 }}>{r.explanation}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
