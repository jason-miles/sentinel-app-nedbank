import React, { createContext, useContext, useEffect, useState } from "react";
import { getPersonas } from "../api";

export function Sev({ s }: { s: string }) {
  return <span className={`badge sev-${s}`}>{s}</span>;
}
// ── Skeleton loaders ───────────────────────────────────────────────────────
// Structured placeholders that mirror the real layout so a page reads as
// "content arriving" instead of a blank screen — makes the demo feel instant.
export function Skel({ w = "100%", h = 12, style = {} }: { w?: number | string; h?: number | string; style?: React.CSSProperties }) {
  return <div className="skel" style={{ width: w, height: h, ...style }} aria-hidden="true" />;
}
export function SkelKpis({ n = 5 }: { n?: number }) {
  return (
    <div className="skel-kpis" role="status" aria-label="Loading metrics">
      {Array.from({ length: n }).map((_, i) => (
        <div className="skel-kpi" key={i}><Skel w={70} h={11} /><Skel w={90} h={28} /></div>
      ))}
    </div>
  );
}
export function SkelTable({ rows = 6, title }: { rows?: number; title?: string }) {
  return (
    <div className="skel-panel" role="status" aria-label={`Loading ${title || "data"}`}>
      {title ? <Skel w={180} h={16} style={{ marginBottom: 16 }} /> : null}
      {Array.from({ length: rows }).map((_, i) => <div className="skel skel-row" key={i} aria-hidden="true" />)}
    </div>
  );
}
export function SkelChart({ title }: { title?: string }) {
  return (
    <div className="skel-panel" role="status" aria-label={`Loading ${title || "chart"}`}>
      {title ? <Skel w={160} h={16} style={{ marginBottom: 16 }} /> : null}
      <div className="skel skel-chart" aria-hidden="true" />
    </div>
  );
}
// Full-page queue/dashboard skeleton: KPI band + chart + table.
export function SkelPage({ kpis = 5, rows = 6 }: { kpis?: number; rows?: number }) {
  return (
    <div aria-busy="true">
      <Skel w={260} h={26} style={{ marginBottom: 22 }} />
      <SkelKpis n={kpis} />
      <SkelChart />
      <SkelTable rows={rows} />
    </div>
  );
}
// Shown when a fetch fails — a clear message + inline Retry, never a blank panel.
export function ErrorState({ what = "data", onRetry }: { what?: string; onRetry?: () => void }) {
  return (
    <div className="state-msg state-err" role="alert">
      <span>Couldn’t load {what}.</span>
      {onRetry && <button type="button" className="btn sm ghost" onClick={onRetry}>↻ Retry</button>}
    </div>
  );
}
// Shown when a fetch succeeds but returns nothing — distinguishes empty from broken.
export function EmptyState({ what = "records" }: { what?: string }) {
  return <div className="state-msg state-empty" role="status">No {what} found.</div>;
}
export function num(v: any): number {
  const n = Number(v);
  return isNaN(n) ? 0 : n;
}
export function money(v: any): string {
  return "$" + num(v).toLocaleString("en-US", { maximumFractionDigits: 0 });
}
export function fmtDate(v: any): string {
  if (!v) return "—";
  try { return new Date(v).toLocaleDateString("en-US", { dateStyle: "medium" }); }
  catch { return String(v); }
}

// Live-refresh helpers, shared by the queue + exec overview.
export function sinceLabel(ts: number): string {
  const s = Math.max(0, Math.round((Date.now() - ts) / 1000));
  if (s < 5) return "just now";
  if (s < 60) return `${s}s ago`;
  return `${Math.round(s / 60)}m ago`;
}
export function LiveDot({ on }: { on: boolean }) {
  return <span style={{ display: "inline-block", width: 8, height: 8, borderRadius: "50%",
    background: on ? "var(--low)" : "var(--muted)", marginRight: 4,
    boxShadow: on ? "0 0 0 3px color-mix(in srgb, var(--low) 25%, transparent)" : "none" }} />;
}
export function LiveControls({ live, updatedAt, onToggle }: { live: boolean; updatedAt: number | null; onToggle: () => void }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 12, fontSize: 12 }}>
      <span className="muted"><LiveDot on={live} /> {live ? "Live" : "Paused"}{updatedAt ? ` · updated ${sinceLabel(updatedAt)}` : ""}</span>
      <button className="btn sm ghost" onClick={onToggle}>{live ? "Pause" : "Resume"}</button>
    </div>
  );
}

// ── Persona ("View As") context ──────────────────────────────────────────
export type Persona = { analyst_id: string; analyst_name: string; team_id: string; team_name: string };
type Ctx = { personas: Persona[]; current?: Persona; setCurrent: (p: Persona) => void };
const PersonaCtx = createContext<Ctx>({ personas: [], setCurrent: () => {} });
export const usePersona = () => useContext(PersonaCtx);

export function PersonaProvider({ children }: { children: React.ReactNode }) {
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [current, setCurrent] = useState<Persona>();
  useEffect(() => {
    getPersonas().then((ps: Persona[]) => {
      setPersonas(ps);
      const sarah = ps.find((p) => p.analyst_name === "Sarah Chen") || ps[0];
      setCurrent(sarah);
    }).catch(() => {});
  }, []);
  return <PersonaCtx.Provider value={{ personas, current, setCurrent }}>{children}</PersonaCtx.Provider>;
}
