// Demo / Story Mode — a hands-free guided walk of the three "wow" scenarios
// (detect → document → anticipate). Renders a "▶ Play Demo" control in the top bar;
// when playing, a narration overlay steps through the story and auto-navigates the
// app to the right page for each beat. Read-only: it only routes + narrates, it never
// mutates data. Purely client-side, so it works identically on every branded build.
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

type Step = {
  title: string;
  beat: string;          // "DETECT" | "DOCUMENT" | "ANTICIPATE" | "OVERVIEW"
  route: string;
  say: string;
  tip?: string;          // optional "what to point at" hint
};

// The narration is brand-neutral (no bank name) so the same steps ship to all three
// builds; case IDs + planted subjects are identical across builds.
const STEPS: Step[] = [
  {
    title: "Welcome to Sentinel",
    beat: "OVERVIEW",
    route: "/exec",
    say: "Sentinel is a fraud & AML copilot on one governed Databricks Lakehouse — detection, investigation, regulator-ready filing, and analytics. Let's walk three real scenarios: detect, document, then anticipate.",
    tip: "Executive Overview: live KPIs — case volume, false-positive rate, ZAR monitored, team performance.",
  },
  {
    title: "1 · A routine alert",
    beat: "DETECT",
    route: "/investigation/CASE-90001",
    say: "An analyst picks up what looks like a minor alert — a few cash deposits, each just under the R25,000 reporting threshold. Classic structuring. Notice the AI Risk score agrees this is high-risk.",
    tip: "CASE-90001 (Lerato Sithole) — 3 sub-threshold cash-ins; AI Risk vs Rules score; grounded policy citations.",
  },
  {
    title: "1 · The hidden mule network",
    beat: "DETECT",
    route: "/graph",
    say: "Entity resolution is the reveal. This one account shares a device fingerprint, IP and address with six others — all opened within three weeks — each forwarding ~90% within 48 hours to one aggregator that remits cross-border. Three siblings were previously closed as false positives in isolation. Sentinel sees the network.",
    tip: "Graph Explorer — search “Motaung” (the aggregator). 7-account cluster + cross-border cash-out.",
  },
  {
    title: "1 · Real-time detection",
    beat: "DETECT",
    route: "/investigation",
    say: "Detection is live. Click “⚡ Simulate live transaction” on the queue: a fresh suspicious transaction streams in and a new critical alert lands at the top of the analyst's queue in seconds — no overnight batch. This is streaming detection on the Lakehouse.",
    tip: "My Queue → ⚡ Simulate live transaction — a new critical case appears instantly.",
  },
  {
    title: "2 · STR drafted in seconds",
    beat: "DOCUMENT",
    route: "/sar/CASE-90001",
    say: "The multi-agent workflow auto-gathers the evidence pack and drafts a regulator-format STR — grounded in retrieved adverse media and the bank's own AML policy and FATF typologies, with a schema-valid goAML XML ready for the Financial Intelligence Centre. Hours of analyst work in seconds.",
    tip: "SAR Filing — multi-agent trace, cited narrative, “✓ goAML schema valid (12/12)”.",
  },
  {
    title: "3 · Proactive typology sweep",
    beat: "ANTICIPATE",
    route: "/compliance",
    say: "Now the proactive moment. A compliance manager describes a brand-new FATF typology in plain English — third-party processors layering through gaming merchants — and Sentinel finds exposure that never tripped a single rule. This isn't a chatbot on a case tool; it's anticipation.",
    tip: "Compliance → Impossible Travel & typology surfaces; two gaming accounts, net ≈ 0, never alerted.",
  },
  {
    title: "AI you can defend",
    beat: "ANTICIPATE",
    route: "/compliance",
    say: "Every model, feature, agent tool-call and filing is governed by one Unity Catalog plane — a registered model with a measured false-positive reduction, drift monitored, lineage end-to-end. The governance answer, built in. That's Sentinel.",
    tip: "Compliance → Model Governance: registered UC model, AUC, ~40%+ fewer false positives, drift stable.",
  },
];

const BEAT_COLOR: Record<string, string> = {
  OVERVIEW: "var(--muted)", DETECT: "var(--critical)", DOCUMENT: "var(--accent)", ANTICIPATE: "var(--navy)",
};

export function StoryMode() {
  const [playing, setPlaying] = useState(false);
  const [i, setI] = useState(0);
  const nav = useNavigate();

  // Auto-play: when playing and not paused, advance after the step's dwell time.
  // Kiosk-friendly — reads the narration then moves on. Manual controls still work.
  const AUTO_MS = 11000; // ~11s per beat (enough to read the narration)
  const [paused, setPaused] = useState(false);

  // On each step, navigate to its route.
  useEffect(() => {
    if (!playing) return;
    nav(STEPS[i].route);
  }, [playing, i, nav]);

  // Auto-advance timer (skipped when paused or on the last step).
  useEffect(() => {
    if (!playing || paused) return;
    if (i >= STEPS.length - 1) return;
    const t = setTimeout(() => setI((n) => Math.min(n + 1, STEPS.length - 1)), AUTO_MS);
    return () => clearTimeout(t);
  }, [playing, paused, i]);

  // Esc closes; Space toggles pause; arrows step.
  useEffect(() => {
    if (!playing) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setPlaying(false);
      if (e.key === " ") { e.preventDefault(); setPaused((p) => !p); }
      if (e.key === "ArrowRight") { setPaused(true); setI((n) => Math.min(n + 1, STEPS.length - 1)); }
      if (e.key === "ArrowLeft") { setPaused(true); setI((n) => Math.max(n - 1, 0)); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [playing]);

  function start() { setI(0); setPaused(false); setPlaying(true); }
  function stop() { setPlaying(false); }
  function next() { setPaused(true); if (i < STEPS.length - 1) setI(i + 1); else stop(); }
  function prev() { setPaused(true); setI(Math.max(0, i - 1)); }

  if (!playing) {
    return (
      <button className="btn sm story-play" onClick={start} title="Play the guided demo"
        aria-label="Play the guided demo">▶ Play Demo</button>
    );
  }

  const s = STEPS[i];
  return (
    <div className="story-overlay" role="dialog" aria-label="Guided demo" aria-live="polite">
      <div className="story-card">
        {/* auto-advance progress bar (re-keys each step to restart the animation) */}
        {!paused && i < STEPS.length - 1 && (
          <div key={i} className="story-progress"><span style={{ animationDuration: `${AUTO_MS}ms` }} /></div>
        )}
        <div className="story-head">
          <span className="story-beat" style={{ background: BEAT_COLOR[s.beat] }}>{s.beat}</span>
          <span className="story-step">Step {i + 1} / {STEPS.length}</span>
          <button className="story-x" onClick={stop} aria-label="End demo">✕</button>
        </div>
        <h3 className="story-title">{s.title}</h3>
        <p className="story-say">{s.say}</p>
        {s.tip && <p className="story-tip">▸ {s.tip}</p>}
        <div className="story-controls">
          <button className="btn ghost sm" onClick={prev} disabled={i === 0}>◂ Back</button>
          <button className="btn ghost sm" onClick={() => setPaused((p) => !p)}
            title={paused ? "Resume auto-play" : "Pause"} aria-label={paused ? "Resume" : "Pause"}>
            {paused ? "▶ Auto" : "❚❚ Pause"}
          </button>
          <div className="story-dots">
            {STEPS.map((_, n) => (
              <span key={n} className={`story-dot ${n === i ? "on" : ""}`} onClick={() => { setPaused(true); setI(n); }} />
            ))}
          </div>
          <button className="btn sm" onClick={next}>{i < STEPS.length - 1 ? "Next ▸" : "Finish"}</button>
        </div>
      </div>
    </div>
  );
}
