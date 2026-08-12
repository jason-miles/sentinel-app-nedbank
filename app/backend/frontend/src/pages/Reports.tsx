import { useEffect, useState } from "react";
import { getConfig } from "../api";
import { Loading, ErrorState } from "../components/ui";

export function Reports() {
  const [cfg, setCfg] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const load = () => { setErr(false); getConfig().then((c) => { setErr(false); setCfg(c); setLoading(false); }).catch(() => { setErr(true); setLoading(false); }); };
  useEffect(() => { load(); }, []);
  if (loading) return <Loading what="reports" />;
  if (err) return <ErrorState what="reports" onRetry={() => { setLoading(true); load(); }} />;

  const embed = cfg?.dashboard_embed_url;
  return (
    <>
      <h1 className="page-title">Reports</h1>
      <p className="page-sub">Embedded Databricks AI/BI dashboard — executive KPIs, alert trends, and team performance.</p>
      {embed ? (
        <div className="panel" style={{ padding: 0, overflow: "hidden" }}>
          <iframe title="Nedbank Sentinel — Executive Overview" src={embed}
            style={{ width: "100%", height: "80vh", border: "none" }} />
        </div>
      ) : (
        <div className="panel">
          <p className="muted">Dashboard not configured. Set SENTINEL_DASHBOARD_ID + DATABRICKS_HOST in app.yaml.</p>
          {cfg?.dashboard_url && <a className="btn" href={cfg.dashboard_url} target="_blank" rel="noreferrer">Open dashboard ↗</a>}
        </div>
      )}
      {cfg?.dashboard_url && (
        <p className="muted" style={{ marginTop: 10, fontSize: 12 }}>
          If the embed is blank, the workspace may require enabling dashboard embedding for this domain — <a href={cfg.dashboard_url} target="_blank" rel="noreferrer">open the dashboard directly ↗</a>.
        </p>
      )}
    </>
  );
}
