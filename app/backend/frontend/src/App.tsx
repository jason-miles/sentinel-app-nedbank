import { lazy, Suspense, useEffect, useState } from "react";
import { NavLink, Route, Routes, useLocation } from "react-router-dom";
import { PersonaProvider, usePersona } from "./components/ui";
import { BrandMark } from "./components/Logo";

// Theme: persisted to localStorage, defaulting to the OS preference.
function useTheme(): [string, () => void] {
  const [theme, setTheme] = useState<string>(() => {
    const saved = localStorage.getItem("sentinel-theme");
    if (saved) return saved;
    return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  });
  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem("sentinel-theme", theme);
  }, [theme]);
  return [theme, () => setTheme((t) => (t === "dark" ? "light" : "dark"))];
}
// Landing is eager — it's the instant first paint. Every routed page is lazy so
// heavy deps (cytoscape on Graph, recharts on the chart pages) split into their
// own chunks and only download when that page is actually visited.
import { Landing } from "./pages/Landing";
const ExecutiveOverview = lazy(() => import("./pages/ExecutiveOverview").then((m) => ({ default: m.ExecutiveOverview })));
const AlertInvestigation = lazy(() => import("./pages/AlertInvestigation").then((m) => ({ default: m.AlertInvestigation })));
const Investigation = lazy(() => import("./pages/Investigation").then((m) => ({ default: m.Investigation })));
const SarFiling = lazy(() => import("./pages/SarFiling").then((m) => ({ default: m.SarFiling })));
const GraphExplorer = lazy(() => import("./pages/GraphExplorer").then((m) => ({ default: m.GraphExplorer })));
const AskSentinel = lazy(() => import("./pages/AskSentinel").then((m) => ({ default: m.AskSentinel })));
const Compliance = lazy(() => import("./pages/Compliance").then((m) => ({ default: m.Compliance })));
const Reports = lazy(() => import("./pages/Reports").then((m) => ({ default: m.Reports })));
const Architecture = lazy(() => import("./pages/Architecture").then((m) => ({ default: m.Architecture })));

function TopBar() {
  const { personas, current, setCurrent } = usePersona();
  const [theme, toggleTheme] = useTheme();
  return (
    <div className="topbar">
      <BrandMark />
      <nav className="nav-pills">
        <NavLink to="/exec" className={({ isActive }) => (isActive ? "active" : "")}>Executive Overview</NavLink>
        <NavLink to="/investigation" className={({ isActive }) => (isActive ? "active" : "")}>Alert Investigation</NavLink>
        <NavLink to="/compliance" className={({ isActive }) => (isActive ? "active" : "")}>Compliance</NavLink>
        <NavLink to="/graph" className={({ isActive }) => (isActive ? "active" : "")}>Graph Explorer</NavLink>
        <NavLink to="/reports" className={({ isActive }) => (isActive ? "active" : "")}>Reports</NavLink>
        <NavLink to="/architecture" className={({ isActive }) => (isActive ? "active" : "")}>Architecture</NavLink>
        <NavLink to="/ask" className={({ isActive }) => (isActive ? "active" : "")}>Ask Sentinel</NavLink>
      </nav>
      <button className="theme-toggle" onClick={toggleTheme}
        title={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"} aria-label="Toggle theme">
        {theme === "dark" ? "☀" : "☾"}
      </button>
      <div className="viewas">
        View As:
        <select aria-label="View as analyst persona" value={current?.analyst_id || ""}
          onChange={(e) => { const p = personas.find((x) => x.analyst_id === e.target.value); if (p) setCurrent(p); }}>
          {personas.map((p) => (
            <option key={p.analyst_id} value={p.analyst_id}>{p.analyst_name} ({p.team_name})</option>
          ))}
        </select>
      </div>
    </div>
  );
}

function Shell() {
  const loc = useLocation();
  if (loc.pathname === "/") return <Landing />;
  return (
    <>
      <a href="#main-content" className="skip-link">Skip to main content</a>
      <TopBar />
      <main id="main-content" className="page">
        <Suspense fallback={<div className="route-loading" role="status" aria-live="polite">Loading…</div>}>
          <Routes>
            <Route path="/exec" element={<ExecutiveOverview />} />
            <Route path="/investigation" element={<AlertInvestigation />} />
            <Route path="/investigation/:caseId" element={<Investigation />} />
            <Route path="/sar/:caseId" element={<SarFiling />} />
            <Route path="/graph" element={<GraphExplorer />} />
            <Route path="/ask" element={<AskSentinel />} />
            <Route path="/compliance" element={<Compliance />} />
            <Route path="/reports" element={<Reports />} />
            <Route path="/architecture" element={<Architecture />} />
          </Routes>
        </Suspense>
      </main>
    </>
  );
}

export function App() {
  return (
    <PersonaProvider>
      <Routes>
        <Route path="/*" element={<Shell />} />
      </Routes>
    </PersonaProvider>
  );
}
