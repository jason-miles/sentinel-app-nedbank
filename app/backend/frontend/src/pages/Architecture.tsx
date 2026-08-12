// Reference Architecture — brand-native recreations of the Databricks solution
// architecture (fraud/AML) + the medallion Lakehouse platform (AWS/Azure). All
// colour comes from CSS vars so this file renders in each app's own palette.
import { useState, type ReactNode } from "react";

type Item = { label: string; sub?: string };

function Stage({ title, groups }: { title: string; groups: { heading?: string; items: Item[] }[] }) {
  return (
    <div className="arch-stage">
      <h3 className="arch-stage-title">{title}</h3>
      {groups.map((g, i) => (
        <div key={i} className="arch-group">
          {g.heading && <div className="arch-group-heading">{g.heading}</div>}
          {g.items.map((it, j) => (
            <div key={j} className="arch-card">
              <span className="arch-card-dot" aria-hidden />
              <div>
                <div className="arch-card-label">{it.label}</div>
                {it.sub && <div className="arch-card-sub">{it.sub}</div>}
              </div>
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

const APPS: Item[] = [
  { label: "Chief Compliance Officer Dashboard", sub: "Team performance & case statistics insights" },
  { label: "SAR Report & Evidence Reporting Agent", sub: "Auto-generates case disposition, narrative & SAR" },
  { label: "Case Investigation Supervisor Agent", sub: "Complex analysis across specialist agents & tools" },
  { label: "Media & News Reporting Agent", sub: "Scours news / third-party data for customer profiling" },
  { label: "Policy Expert Agent", sub: "Answers on federal regulation & compliance docs" },
];

export function Architecture() {
  const [tab, setTab] = useState<"solution" | "aws" | "azure">("solution");
  return (
    <div className="arch">
      <div className="arch-head">
        <h1 className="page-title">Reference Architecture</h1>
        <p className="page-sub">
          End-to-end financial-crime intelligence on the Databricks Data Intelligence Platform —
          from governed ingestion to a multi-agent SAR workflow, all under one governance plane.
        </p>
      </div>
      <div className="tabs">
        <button className={tab === "solution" ? "active" : ""} onClick={() => setTab("solution")}>Solution Architecture</button>
        <button className={tab === "aws" ? "active" : ""} onClick={() => setTab("aws")}>Platform — AWS</button>
        <button className={tab === "azure" ? "active" : ""} onClick={() => setTab("azure")}>Platform — Azure</button>
      </div>
      {tab === "solution" ? <SolutionArch /> : <PlatformArch cloud={tab} />}
    </div>
  );
}

function SolutionArch() {
  return (
    <>
      <div className="arch-flow">
        <Stage title="Data Sources" groups={[
          { heading: "Structured", items: [
            { label: "Customers" }, { label: "Transactions" }, { label: "Case Management History" }] },
          { heading: "Semi-structured", items: [{ label: "SAR Records" }] },
          { heading: "Unstructured", items: [
            { label: "News & Negative Media" }, { label: "Customer Correspondence" },
            { label: "Global Sanctions & PEP Watchlists" }] },
        ]} />

        <div className="arch-arrow" aria-hidden>→</div>

        <Stage title="Ingest & ETL" groups={[
          { items: [
            { label: "Lakeflow Connect", sub: "Managed ingestion" },
            { label: "Business Rules", sub: "Declarative detection" },
            { label: "ML Model", sub: "Risk scoring" }] },
        ]} />

        <div className="arch-arrow" aria-hidden>→</div>

        <Stage title="Storage" groups={[
          { items: [
            { label: "Databricks Volume", sub: "Documents & PDFs" },
            { label: "Delta", sub: "Medallion Lakehouse" },
            { label: "Vector Search", sub: "Adverse-media RAG" },
            { label: "Alerts & Risk Scores", sub: "gold.fraud_alerts" }] },
        ]} />

        <div className="arch-arrow" aria-hidden>→</div>

        <Stage title="Agent Serving & Orchestration" groups={[
          { items: [
            { label: "External MCP" }, { label: "Knowledge Assistant" },
            { label: "AI/BI Genie", sub: "NL → governed SQL" },
            { label: "Custom LLM" }, { label: "Real-Time Scoring" },
            { label: "Multi-Agent Supervisor", sub: "Genie / Serving Endpoint / MCP" },
            { label: "AI/BI Dashboards" }] },
        ]} />

        <div className="arch-arrow" aria-hidden>→</div>

        <div className="arch-stage arch-apps">
          <h3 className="arch-stage-title">Databricks Apps <span className="arch-apps-sub">Secure data &amp; AI apps</span></h3>
          <div className="arch-group">
            {APPS.map((a, i) => (
              <div key={i} className="arch-card arch-app-card">
                <span className="arch-card-dot" aria-hidden />
                <div>
                  <div className="arch-card-label">{a.label}</div>
                  {a.sub && <div className="arch-card-sub">{a.sub}</div>}
                </div>
              </div>
            ))}
            <div className="arch-card arch-lakebase">
              <span className="arch-card-dot" aria-hidden />
              <div>
                <div className="arch-card-label">Lakebase</div>
                <div className="arch-card-sub">Real-time transaction DB</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="arch-bands">
        <div className="arch-band"><b>Unified, end-to-end governance</b><span>Tables · AI Models · Files · Notebooks · Dashboards</span></div>
        <div className="arch-band"><b>All Formats</b><span>Delta Lake · Iceberg · Parquet</span></div>
        <div className="arch-band"><b>All Clouds</b><span>AWS · Azure · Google Cloud</span></div>
        <div className="arch-band"><b>Any Model</b><span>OpenAI · Anthropic · Gemini · Meta</span></div>
      </div>
    </>
  );
}

// ── Platform Architecture — the classic Databricks medallion Lakehouse, per cloud.
// Rendered as a real SVG diagram: dashed group boxes, node icons, and coloured
// data-flow arrows (purple = ingest, green = ETL/serving, orange = inference).
const CLOUD: Record<string, {
  name: string; ingest: string; storage: string; serving: string; bi: string;
}> = {
  aws: { name: "AWS", ingest: "Amazon Kinesis", storage: "Amazon S3",
    serving: "MLflow Serving / AWS ECS", bi: "Tableau · Databricks SQL · Looker" },
  azure: { name: "Azure", ingest: "Azure Event Hubs", storage: "ADLS Gen2",
    serving: "MLflow / Azure ML", bi: "Tableau · Redash · Power BI" },
};

// ---- small inline icons (stroke uses currentColor so they inherit brand accent) ----
const IconDelta = ({ c = "#00add4" }: { c?: string }) => (
  <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden><path d="M12 3 L21 20 H3 Z" fill="none" stroke={c} strokeWidth="1.8" strokeLinejoin="round" /><path d="M12 9 L16.5 18 H7.5 Z" fill={c} opacity="0.85" /></svg>
);
const IconStack = ({ c = "currentColor" }: { c?: string }) => (
  <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden><g fill={c}><path d="M12 3 4 7l8 4 8-4z" opacity="0.9" /><path d="M4 12l8 4 8-4" fill="none" stroke={c} strokeWidth="1.6" /><path d="M4 16.5l8 4 8-4" fill="none" stroke={c} strokeWidth="1.6" /></g></svg>
);
const IconFlow = ({ c = "currentColor" }: { c?: string }) => (
  <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden><g fill="none" stroke={c} strokeWidth="1.7"><circle cx="6" cy="6" r="2.4" /><circle cx="18" cy="12" r="2.4" /><circle cx="6" cy="18" r="2.4" /><path d="M8.4 6H14a3 3 0 0 1 3 3v.6M8 17.4l7-4.2" /></g></svg>
);
const IconDb = ({ c = "currentColor" }: { c?: string }) => (
  <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden><g fill="none" stroke={c} strokeWidth="1.6"><ellipse cx="12" cy="5.5" rx="7" ry="2.6" /><path d="M5 5.5v13c0 1.4 3.1 2.6 7 2.6s7-1.2 7-2.6v-13" /><path d="M5 12c0 1.4 3.1 2.6 7 2.6s7-1.2 7-2.6" /></g></svg>
);
const IconChart = ({ c = "currentColor" }: { c?: string }) => (
  <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden><g fill={c}><rect x="4" y="12" width="3.4" height="8" rx="1" /><rect x="10.3" y="7" width="3.4" height="13" rx="1" opacity="0.8" /><rect x="16.6" y="4" width="3.4" height="16" rx="1" opacity="0.6" /></g></svg>
);

// One diagram node: icon tile + label, absolutely positioned inside the SVG canvas.
function Node({ x, y, w = 150, h = 54, title, sub, icon, tone = "plain" }:
  { x: number; y: number; w?: number; h?: number; title: string; sub?: string; icon: ReactNode; tone?: string }) {
  return (
    <div className={`pnode pnode-${tone}`} style={{ left: x, top: y, width: w, minHeight: h }}>
      <span className="pnode-ico">{icon}</span>
      <span className="pnode-txt"><b>{title}</b>{sub && <em>{sub}</em>}</span>
    </div>
  );
}

function PlatformArch({ cloud }: { cloud: "aws" | "azure" }) {
  const c = CLOUD[cloud];
  const acc = "var(--accent)";
  // canvas coordinate system (scales responsively via viewBox + CSS)
  return (
    <>
      <p className="arch-cloud-title">Databricks + {c.name} — Lakehouse Platform</p>

      <div className="pdiagram" role="img"
        aria-label={`Databricks on ${c.name} medallion Lakehouse: batch and streaming sources ingest into Bronze, Silver and Gold Delta Lake tables, feeding Databricks Machine Learning and Databricks SQL.`}>
        {/* connector layer */}
        <svg className="pdiagram-svg" viewBox="0 0 1120 520" preserveAspectRatio="xMidYMid meet">
          <defs>
            <marker id={`ar-g-${cloud}`} markerWidth="9" markerHeight="9" refX="6" refY="3" orient="auto"><path d="M0 0 L6 3 L0 6 z" fill="#12b76a" /></marker>
            <marker id={`ar-p-${cloud}`} markerWidth="9" markerHeight="9" refX="6" refY="3" orient="auto"><path d="M0 0 L6 3 L0 6 z" fill="#8a5cf6" /></marker>
            <marker id={`ar-o-${cloud}`} markerWidth="9" markerHeight="9" refX="6" refY="3" orient="auto"><path d="M0 0 L6 3 L0 6 z" fill="#f79009" /></marker>
          </defs>
          {/* dashed group boxes */}
          <rect className="pgroup" x="286" y="12" width="520" height="196" rx="8" />
          <text className="pgroup-t" x="300" y="34">Databricks Machine Learning</text>
          <rect className="pgroup" x="286" y="228" width="520" height="220" rx="8" />
          <text className="pgroup-t" x="300" y="250">Databricks Data Engineering</text>
          <rect className="pgroup" x="846" y="228" width="268" height="220" rx="8" />
          <text className="pgroup-t" x="860" y="250">Databricks SQL</text>

          {/* purple: batch + streaming sources -> ingest -> bronze */}
          <path className="pf" stroke="#8a5cf6" markerEnd={`url(#ar-p-${cloud})`} d="M154 98 H160 V314 H168" />
          <path className="pf" stroke="#8a5cf6" markerEnd={`url(#ar-p-${cloud})`} d="M154 290 H160 V314 H168" />
          <path className="pf" stroke="#8a5cf6" markerEnd={`url(#ar-p-${cloud})`} d="M278 314 H290 V342 H300" />
          {/* green ETL: bronze -> silver -> gold */}
          <path className="pf" stroke="#12b76a" markerEnd={`url(#ar-g-${cloud})`} d="M450 342 H490" />
          <path className="pf" stroke="#12b76a" markerEnd={`url(#ar-g-${cloud})`} d="M640 342 H650" />
          {/* green feedback: silver -> notebooks (up the bronze/silver gap channel x=470) */}
          <path className="pf" stroke="#12b76a" markerEnd={`url(#ar-g-${cloud})`} d="M490 330 H470 V112 H450" />
          {/* green ML chain: notebooks -> tracker -> registry */}
          <path className="pf" stroke="#12b76a" markerEnd={`url(#ar-g-${cloud})`} d="M450 112 H490" />
          <path className="pf" stroke="#12b76a" markerEnd={`url(#ar-g-${cloud})`} d="M640 112 H650" />
          {/* orange dotted: registry -> serving -> back to gold (inference) */}
          <path className="pf pf-dot" stroke="#f79009" markerEnd={`url(#ar-o-${cloud})`} d="M800 112 H812" />
          <path className="pf pf-dot" stroke="#f79009" markerEnd={`url(#ar-o-${cloud})`} d="M840 206 V342 H800" />
          {/* green: gold -> Databricks SQL (through the DE/SQL gap channel x=826) */}
          <path className="pf" stroke="#12b76a" markerEnd={`url(#ar-g-${cloud})`} d="M800 342 H826 V298 H858" />
        </svg>

        {/* section labels (left) */}
        <div className="plabel" style={{ left: 6, top: 78 }}>Batch Data</div>
        <div className="plabel" style={{ left: 6, top: 270 }}>Streaming Data</div>

        {/* sources + ingest */}
        <Node x={24} y={70} w={130} title="Structured" sub="LoB · CRM · On-prem DB" icon={<IconDb c={acc} />} />
        <Node x={24} y={262} w={130} title="Streaming" sub="POS · IoT · Telemetry" icon={<IconFlow c={acc} />} />
        <Node x={168} y={286} w={110} title="Ingest" sub={c.ingest} icon={<IconFlow c="#8a5cf6" />} tone="ingest" />

        {/* ML row (inside ML box 286–806) */}
        <Node x={300} y={84} w={150} title="Notebooks" sub="ML Runtime" icon={<IconStack c={acc} />} tone="brand" />
        <Node x={490} y={84} w={150} title="MLflow" sub="Tracking" icon={<IconFlow c={acc} />} tone="brand" />
        <Node x={650} y={84} w={150} title="MLflow" sub="Registry" icon={<IconFlow c={acc} />} tone="brand" />
        <Node x={812} y={150} w={120} title="Serving" sub={c.serving} icon={<IconStack c="#f79009" />} tone="serve" />

        {/* medallion row (inside DE box 286–806) */}
        <Node x={300} y={314} w={150} title="Raw · Bronze" sub={`Delta · ${c.storage}`} icon={<IconDelta />} tone="bronze" />
        <Node x={490} y={314} w={150} title="Refined · Silver" sub="Delta · conformed" icon={<IconDelta />} tone="silver" />
        <Node x={650} y={314} w={150} title="Enriched · Gold" sub="Delta · business" icon={<IconDelta />} tone="gold" />

        {/* SQL box contents (846–1114) */}
        <Node x={858} y={270} w={248} title="BI/SQL Connectors" sub="Data Catalog · Security" icon={<IconChart c={acc} />} tone="brand" />
        <Node x={858} y={330} w={248} title="Dashboards & Alerts" sub="SQL Editor & Query Catalog" icon={<IconChart c={acc} />} tone="brand" />
        <Node x={858} y={390} w={248} title="BI Tools" sub={c.bi} icon={<IconChart c={acc} />} tone="brand" />
      </div>

      <div className="plegend" aria-hidden>
        <span><i style={{ background: "#8a5cf6" }} />Ingest</span>
        <span><i style={{ background: "#12b76a" }} />ETL &amp; serving</span>
        <span><i className="dot" style={{ background: "#f79009" }} />Inference feedback</span>
      </div>

      <div className="arch-bands">
        <div className="arch-band"><b>Open Delta Lake</b><span>ACID · time travel · unified batch + streaming</span></div>
        <div className="arch-band"><b>Unity Catalog governance</b><span>Lineage · access control · audit</span></div>
        <div className="arch-band"><b>{c.name} native</b><span>{c.storage} · {c.ingest} · {c.serving.split(" / ")[0]}</span></div>
        <div className="arch-band"><b>Any Model</b><span>MLflow · OpenAI · Anthropic · Meta</span></div>
      </div>
    </>
  );
}
