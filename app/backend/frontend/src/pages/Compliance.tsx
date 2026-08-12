import { useEffect, useState } from "react";
import { getScreening, getPkyc, getPkycSummary, getAnomalies, getModelGovernance, getModelDrift, getLlmEval, getAudit } from "../api";
import { Loading, ErrorState, num, money } from "../components/ui";

function Badge({ s }: { s: string }) {
  const map: Record<string, string> = { confirmed: "critical", probable: "high", possible: "medium",
    critical: "critical", high: "high", medium: "medium", low: "low" };
  return <span className={`badge sev-${map[s] || "medium"}`}>{s}</span>;
}

export function Compliance() {
  const [tab, setTab] = useState<"screening" | "pkyc" | "anomaly" | "model" | "audit">("screening");
  return (
    <>
      <h1 className="page-title">Compliance & Risk</h1>
      <p className="page-sub">Sanctions & watchlist screening · perpetual KYC · behavioural peer-group anomaly detection · model governance · audit trail.</p>
      <div className="tabs">
        <button className={tab === "screening" ? "active" : ""} onClick={() => setTab("screening")}>Sanctions Screening</button>
        <button className={tab === "pkyc" ? "active" : ""} onClick={() => setTab("pkyc")}>Perpetual KYC</button>
        <button className={tab === "anomaly" ? "active" : ""} onClick={() => setTab("anomaly")}>Peer Anomalies</button>
        <button className={tab === "model" ? "active" : ""} onClick={() => setTab("model")}>Model Governance</button>
        <button className={tab === "audit" ? "active" : ""} onClick={() => setTab("audit")}>Audit Trail</button>
      </div>
      {tab === "screening" && <Screening />}
      {tab === "pkyc" && <Pkyc />}
      {tab === "anomaly" && <Anomaly />}
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
  if (loading) return <Loading what="audit trail" />;
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
              <thead><tr><th>Timestamp</th><th>Actor</th><th>Action</th><th>Case</th><th>Detail</th><th>Source</th></tr></thead>
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
  if (loading) return <Loading what="model validation record" />;
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
            <thead><tr><th>Feature</th><th>Baseline μ</th><th>Current μ</th><th>Shift (σ)</th><th>Status</th></tr></thead>
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
  if (loading) return <Loading what="screening hits" />;
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
          <thead><tr><th>Entity</th><th>Type</th><th>Watchlist Match</th><th>List</th><th>Source</th><th>Confidence</th><th>Score</th><th>Reason</th></tr></thead>
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
  if (loading) return <Loading what="perpetual KYC" />;
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
          <thead><tr><th>Customer</th><th>Segment</th><th>Country</th><th>Dynamic Risk</th><th>Band</th><th>EDD</th><th>Risk Drivers</th></tr></thead>
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

function Anomaly() {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const load = () => { setErr(false); getAnomalies(100).then((r) => { setErr(false); setRows(r); setLoading(false); }).catch(() => { setErr(true); setLoading(false); }); };
  useEffect(() => { load(); }, []);
  if (loading) return <Loading what="peer anomalies" />;
  if (err) return <ErrorState what="peer anomalies" onRetry={() => { setLoading(true); load(); }} />;
  return (
    <>
      <div className="panel">
        <h3 className="left">Behavioural Peer-Group Anomalies — customers behaving unlike their segment peers (unsupervised, 3σ+)</h3>
        <p className="muted" style={{ marginTop: 0 }}>Catches novel typologies fixed thresholds miss — the false-positive-reduction story.</p>
        <table>
          <thead><tr><th>Customer</th><th>Segment</th><th>Txns (90d)</th><th>Peer Avg</th><th>Anomaly σ</th><th>Severity</th><th>Explanation</th></tr></thead>
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
