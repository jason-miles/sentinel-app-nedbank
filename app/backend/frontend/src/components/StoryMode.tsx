// Play the Demo — a hands-free guided walk of the three "wow" scenarios
// (detect → document → anticipate). Renders a "▶ Play the Demo" control in the top bar;
// when playing, a narration overlay steps through the story and auto-navigates the app
// to the right page for each beat, and can fire optional read-only UI actions. It never
// mutates data. Purely client-side, so it works identically on every branded build.
// Formatting mirrors the MCB Customer 360 demo: spaced key-point bullets + an "On screen"
// hint, generous spacing, and a longer dwell so the bullets are readable during auto-play.
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

type Step = {
  title: string;
  beat: string;          // "DETECT" | "DOCUMENT" | "ANTICIPATE" | "OVERVIEW"
  route: string;
  say: string;
  points?: string[];     // key detail bullets, shown spaced for readability
  tip?: string;          // "On screen" — what to point at
  action?: string;       // optional side-effect the step performs (e.g. fire the live sim)
  dwell?: number;        // optional auto-advance override (ms) — e.g. the SAR step needs
                         // longer so the multi-agent narrative (~17s) renders before moving on
};

// The narration is brand-neutral (no bank name) so the same steps ship to all three
// builds; case IDs + planted subjects are identical across builds.
const STEPS: Step[] = [
  {
    title: "Welcome to Sentinel",
    beat: "OVERVIEW",
    route: "/exec",
    say: "Sentinel is a fraud & AML copilot on one governed Databricks Lakehouse — detection, investigation, regulator-ready filing, and analytics. We'll walk three real scenarios, live: detect, document, then anticipate.",
    points: [
      "Scenario 1 · Detect — a critical mule-aggregation alert, its hidden network, and a live streaming alert",
      "Scenario 2 · Document — a multi-agent STR drafted in seconds with goAML XML",
      "Scenario 3 · Anticipate — a proactive FATF typology sweep that no rule caught",
      "One Lakehouse, one Unity Catalog governance plane, end to end",
    ],
    tip: "Executive Overview — live KPIs: case volume, false-positive rate, ZAR monitored, team performance.",
  },
  {
    title: "1 · A critical alert",
    beat: "DETECT",
    route: "/investigation/CASE-90002",
    say: "An analyst picks up a critical alert — one account takes rapid inflows from seven others, then pushes a large sum straight out by cross-border SWIFT. The AI Risk score puts it right at the top of the queue.",
    points: [
      "Seven ~R40k inflows aggregate into one account within hours",
      "R260k then leaves by SWIFT to an offshore shell (Onyx Capital, Mauritius)",
      "AI Risk score reprioritises it above look-alike false positives",
      "Grounded policy citations explain the 'why' next to the score",
    ],
    tip: "CASE-90002 (Kabelo Motaung) — rapid mule aggregation → cross-border cash-out; AI Risk 96.",
  },
  {
    title: "1 · The hidden mule network",
    beat: "DETECT",
    route: "/graph?q=Motaung%20mule%20network",
    say: "Entity resolution is the reveal — and it's on screen now. This account shares a device fingerprint, IP and address with six others, all opened within three weeks, each forwarding ~90% within 48 hours to one aggregator that remits cross-border. Three siblings were previously closed as false positives in isolation. Sentinel sees the whole network.",
    points: [
      "Seven accounts linked by shared device, IP and address",
      "All opened within three weeks; ~90% forwarded within 48 hours",
      "Funnelled to one aggregator that remits cross-border",
      "Three siblings had been closed as false positives — in isolation",
    ],
    tip: "The graph opened straight to the Motaung cluster — 7 linked accounts + cross-border cash-out.",
  },
  {
    title: "1 · Real-time detection",
    beat: "DETECT",
    route: "/investigation",
    action: "sim-live-alert",
    say: "Detection is live. Watch — a fresh suspicious transaction just streamed in and a new critical alert lands at the top of the queue in seconds, no overnight batch. This is streaming detection on the Lakehouse.",
    points: [
      "A new critical case appears at the top of the queue in seconds",
      "No overnight batch — streaming detection on the Lakehouse",
      "The analyst is working the freshest risk first, automatically",
    ],
    tip: "A new critical case just appeared at the top of the queue — triggered live.",
  },
  {
    title: "2 · STR drafted in seconds",
    beat: "DOCUMENT",
    route: "/sar/CASE-90002",
    dwell: 30000,  // the multi-agent narrative takes ~27s to render — hold so it lands
    say: "Watch the multi-agent workflow run: it auto-gathers the evidence pack and drafts a regulator-format STR — grounded in retrieved adverse media and the bank's own AML policy and FATF typologies, with a schema-valid goAML XML ready for the Financial Intelligence Centre. Hours of analyst work in seconds.",
    points: [
      "Specialist agents gather the evidence pack automatically",
      "Narrative is grounded in retrieved adverse media + AML policy + FATF typologies",
      "Schema-valid goAML XML, ready to file with the FIC",
      "Hours of analyst work compressed into seconds",
    ],
    tip: "SAR Filing — multi-agent trace, cited narrative, “✓ goAML schema valid (12/12)”.",
  },
  {
    title: "3 · Proactive typology sweep",
    beat: "ANTICIPATE",
    route: "/compliance",
    say: "Now the proactive moment. A compliance manager describes a brand-new FATF typology in plain English — third-party processors layering through gaming merchants — and Sentinel finds exposure that never tripped a single rule. This isn't a chatbot on a case tool; it's anticipation.",
    points: [
      "Describe a new FATF typology in plain English — no new rule to code",
      "Sentinel surfaces matching exposure across the book",
      "Two gaming accounts, net flow ≈ 0, that never tripped an alert",
      "Reactive alert-handling becomes proactive anticipation",
    ],
    tip: "Compliance → typology exposure; two gaming accounts, net ≈ 0, never alerted.",
  },
  {
    title: "3 · Impossible travel",
    beat: "ANTICIPATE",
    route: "/compliance?tab=travel",
    say: "And Sentinel watches physics, not just patterns. Impossible travel: one card tapped in two cities too far apart to be a real journey. Divide the distance between the taps by the time between them — an implied speed above ~900 km/h simply can't be flown. That's a cloned or compromised card, on screen the instant it happens.",
    points: [
      "Geospatial velocity on card taps — haversine distance ÷ elapsed time",
      "New York → Johannesburg minutes apart implies thousands of km/h — physically impossible",
      "A strong card-cloning / account-takeover signal no static threshold expresses cleanly",
      "Each red arc on the world map is a live alert, tagged with its implied speed",
    ],
    tip: "Compliance → Impossible Travel — the world map: red arcs converge on SA cities, each labelled with its impossible km/h.",
  },
  {
    title: "AI you can defend",
    beat: "ANTICIPATE",
    route: "/compliance?tab=model",
    say: "Every model, feature, agent tool-call and filing is governed by one Unity Catalog plane — a registered model with a measured false-positive reduction, drift monitored, lineage end-to-end. The governance answer, built in. That's Sentinel.",
    points: [
      "Registered Unity Catalog model with a measured false-positive reduction",
      "Drift monitored; feature and model lineage end-to-end",
      "Every agent tool-call and filing is governed and audited",
      "The regulator's governance question — answered by design",
    ],
    tip: "Compliance → Model Governance: registered UC model, AUC, ~40%+ fewer false positives, drift stable.",
  },
];

const BEAT_COLOR: Record<string, string> = {
  OVERVIEW: "var(--muted)", DETECT: "var(--critical)", DOCUMENT: "var(--accent)", ANTICIPATE: "var(--navy)",
};

// Longer default dwell so the detail bullets are readable during hands-free auto-play.
const AUTO_MS = 16000;

export function StoryMode() {
  const [playing, setPlaying] = useState(false);
  const [i, setI] = useState(0);
  const [paused, setPaused] = useState(false);
  const nav = useNavigate();

  // On each step, navigate to its route and fire any side-effect action. The destination
  // page must mount and attach its listener before the event fires; on a slow first mount
  // a single delayed dispatch can miss. So we re-dispatch a short burst (0.4s → 2.4s) —
  // listeners are idempotent, so extra fires are harmless, and a late-mounting page still
  // catches one. This makes the live-alert beat reliable regardless of navigation speed.
  useEffect(() => {
    if (!playing) return;
    nav(STEPS[i].route);
    const action = STEPS[i].action;
    if (!action) return;
    const fire = () => window.dispatchEvent(new CustomEvent(`sentinel:${action}`));
    const timers = [400, 900, 1600, 2400].map((ms) => setTimeout(fire, ms));
    return () => timers.forEach(clearTimeout);
  }, [playing, i, nav]);

  // Auto-advance timer (skipped when paused or on the last step). A step may override
  // the dwell (e.g. the SAR step waits for the multi-agent narrative to render).
  const dwell = STEPS[i].dwell || AUTO_MS;
  useEffect(() => {
    if (!playing || paused || i >= STEPS.length - 1) return;
    const t = setTimeout(() => setI((n) => Math.min(n + 1, STEPS.length - 1)), dwell);
    return () => clearTimeout(t);
  }, [playing, paused, i, dwell]);

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
        aria-label="Play the guided demo">▶ Play the Demo</button>
    );
  }

  const s = STEPS[i];
  const last = i === STEPS.length - 1;
  return (
    <div className="story-overlay" role="dialog" aria-label="Guided demo" aria-live="polite">
      <div className="story-card">
        {/* auto-advance progress bar (re-keys each step to restart the animation) */}
        {!paused && !last && (
          <div key={i} className="story-progress"><span style={{ animationDuration: `${dwell}ms` }} /></div>
        )}
        <div className="story-head">
          <span className="story-beat" style={{ background: BEAT_COLOR[s.beat] }}>{s.beat}</span>
          <span className="story-step">Step {i + 1} of {STEPS.length}</span>
          <button className="story-x" onClick={stop} aria-label="End demo">✕</button>
        </div>

        <div className="story-body">
          <h3 className="story-title">{s.title}</h3>
          <p className="story-say">{s.say}</p>

          {s.points && s.points.length > 0 && (
            <ul className="story-points">
              {s.points.map((p, n) => (
                <li key={n}><span className="story-bullet" />{p}</li>
              ))}
            </ul>
          )}

          {s.tip && (
            <div className="story-tip"><span className="story-tip-label">On screen:</span> {s.tip}</div>
          )}
        </div>

        <div className="story-controls">
          <button className="btn ghost sm" onClick={prev} disabled={i === 0}>◂ Back</button>
          <button className="btn ghost sm" onClick={() => setPaused((p) => !p)}
            title={paused ? "Resume auto-play" : "Pause"} aria-label={paused ? "Resume" : "Pause"}>
            {paused ? "▶ Auto-play" : "❚❚ Pause"}
          </button>
          <div className="story-dots">
            {STEPS.map((_, n) => (
              <span key={n} className={`story-dot ${n === i ? "on" : ""}`}
                onClick={() => { setPaused(true); setI(n); }} role="button" aria-label={`Go to step ${n + 1}`} />
            ))}
          </div>
          <button className="btn sm" onClick={next}>{last ? "Finish" : "Next ▸"}</button>
        </div>
      </div>
    </div>
  );
}
