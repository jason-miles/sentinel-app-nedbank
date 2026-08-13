import { useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import cytoscape from "cytoscape";
import { getGraph } from "../api";
import { ErrorState, num, Skel } from "../components/ui";

const CHIPS = [
  "Motaung mule network",
  "high risk customers with offshore connections",
  "customers flagged for structuring cash deposits",
  "watchlist matches with high risk scores",
  "counterparties in high risk jurisdictions",
];
const KIND_COLOR: Record<string, string> = {
  customer: "#006341", alert: "#b42318", account: "#7fae97",
  counterparty: "#044a33", watchlist: "#7a1f1f", other: "#aecabb",
};

export function GraphExplorer() {
  const [params, setParams] = useSearchParams();
  const [q, setQ] = useState(params.get("q") || "");
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);
  const [selected, setSelected] = useState<any>(null);
  const elRef = useRef<HTMLDivElement>(null);
  const cyRef = useRef<cytoscape.Core | null>(null);

  const run = (query = "") => {
    setLoading(true);
    setErr(false);
    getGraph(query, 12).then((d) => { setErr(false); setData(d); setLoading(false); }).catch(() => { setErr(true); setLoading(false); });
  };
  // Deep-linkable: /graph?q=Motaung opens straight to that network (used by Story Mode
  // and shareable links). Re-runs when the URL query changes.
  useEffect(() => {
    const urlQ = params.get("q") || "";
    setQ(urlQ);
    run(urlQ);
  }, [params]);
  const search = (query: string) => { setParams(query ? { q: query } : {}); };

  // (Re)build the Cytoscape graph whenever data changes.
  useEffect(() => {
    if (!data || !elRef.current) return;
    cyRef.current?.destroy();
    const cy = cytoscape({
      container: elRef.current,
      elements: [
        ...data.nodes.map((n: any) => ({
          data: { id: n.id, label: n.kind === "customer" ? n.label : "", kind: n.kind },
        })),
        ...data.edges
          .filter((e: any) => data.nodes.some((n: any) => n.id === e.source) && data.nodes.some((n: any) => n.id === e.target))
          .map((e: any, i: number) => ({ data: { id: `e${i}`, source: e.source, target: e.target } })),
      ],
      style: [
        {
          selector: "node",
          style: {
            "background-color": (n: any) => KIND_COLOR[n.data("kind")] || KIND_COLOR.other,
            width: (n: any) => (n.data("kind") === "customer" ? 26 : 12),
            height: (n: any) => (n.data("kind") === "customer" ? 26 : 12),
            label: "data(label)", "font-size": 10, color: "#1f2d4d",
            "text-valign": "top", "text-margin-y": -4, "min-zoomed-font-size": 7,
          },
        },
        { selector: 'node[kind="customer"]', style: { "border-width": 2, "border-color": "#d1a43a" } },
        { selector: "edge", style: { width: 1, "line-color": "#dbe1ea", "curve-style": "haystack" } },
        { selector: "node:selected", style: { "border-width": 3, "border-color": "#b42318" } },
      ],
      layout: { name: "cose", animate: false, padding: 20, nodeRepulsion: () => 8000, idealEdgeLength: () => 80 } as any,
      minZoom: 0.2, maxZoom: 3, wheelSensitivity: 0.2,
    });
    cy.on("tap", "node", (evt) => {
      const n = evt.target;
      const src = (data.nodes || []).find((x: any) => x.id === n.id());
      setSelected(src ? { ...src, degree: n.degree(false) } : null);
    });
    cy.on("tap", (evt) => { if (evt.target === cy) setSelected(null); });
    cyRef.current = cy;
    return () => { cy.destroy(); cyRef.current = null; };
  }, [data]);

  return (
    <>
      <h1 className="page-title">Graph Explorer</h1>
      <div style={{ display: "flex", gap: 10, marginBottom: 12 }}>
        <input aria-label="Search the knowledge graph" style={{ flex: 1 }} placeholder="Search the knowledge graph with natural language…"
          value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => e.key === "Enter" && search(q)} />
        <button className="btn" onClick={() => search(q)}>Search</button>
      </div>
      <div style={{ marginBottom: 16 }}>
        {CHIPS.map((c) => <button key={c} type="button" className="chip" onClick={() => search(c)}>{c}</button>)}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 360px", gap: 18 }}>
        <div className="panel">
          <h3 className="left" style={{ display: "flex", justifyContent: "space-between" }}>
            <span>Knowledge Graph</span>
            <span className="muted" style={{ fontWeight: 400 }}>{data?.node_count ?? 0} nodes · {data?.edge_count ?? 0} edges · drag / scroll to explore</span>
          </h3>
          {err ? <ErrorState what="graph" onRetry={() => { setLoading(true); run(q); }} />
            : loading ? <Skel w="100%" h={560} style={{ borderRadius: 10 }} /> : (
            <div ref={elRef} style={{ width: "100%", height: 560, background: "var(--graph-bg)", borderRadius: 10 }} />
          )}
          <div style={{ display: "flex", gap: 16, marginTop: 10, flexWrap: "wrap", fontSize: 12 }}>
            {Object.entries(KIND_COLOR).filter(([k]) => k !== "other").map(([k, c]) => (
              <span key={k}><span className="dot" style={{ background: c }} />{k}</span>
            ))}
          </div>
        </div>

        <div>
          {selected && (
            <div className="panel" style={{ borderTop: "3px solid var(--accent)" }}>
              <h3 className="left">Selected Node</h3>
              <div className="kv"><span className="k">Label</span><span>{selected.label || selected.id}</span></div>
              <div className="kv"><span className="k">Type</span><span style={{ textTransform: "capitalize" }}>{selected.kind}</span></div>
              <div className="kv"><span className="k">Connections</span><span>{selected.degree}</span></div>
            </div>
          )}
          <div className="panel">
            <h3 className="left">🕐 AI Analysis</h3>
            <p className="muted" style={{ marginTop: 0 }}>{data?.analysis}</p>
          </div>
          <div className="panel">
            <h3 className="left">Matched Entities ({data?.matched_entities?.length ?? 0})</h3>
            {(data?.matched_entities || []).map((m: any, i: number) => (
              <div key={i} style={{ padding: "10px 0", borderBottom: "1px solid var(--border)" }}>
                <div style={{ display: "flex", justifyContent: "space-between" }}>
                  <strong>{m.name}</strong>
                  <span className="badge sev-high">risk {num(m.score) * 20 || m.score}</span>
                </div>
                <div className="muted" style={{ fontSize: 12 }}>{m.detail}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
  );
}
