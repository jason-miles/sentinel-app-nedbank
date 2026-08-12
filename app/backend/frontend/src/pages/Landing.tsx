import { useNavigate } from "react-router-dom";
import { HeroLogo } from "../components/Logo";

export function Landing() {
  const nav = useNavigate();
  return (
    <div className="landing">
      <HeroLogo />

      <div className="stat-band">
        <div className="s"><div className="n">90%</div><div className="l">Faster Investigations</div></div>
        <div className="s"><div className="n">40%+</div><div className="l">Fewer False Positives</div></div>
        <div className="s"><div className="n">R1bn+</div><div className="l">Fraud Losses Prevented</div></div>
        <div className="s"><div className="n">12M+</div><div className="l">Nedbank Clients Protected</div></div>
      </div>

      <div className="entry-cards">
        <div className="entry">
          <div className="ico">📊</div>
          <h2>Executive Dashboard</h2>
          <div className="role">Chief Compliance Officer View</div>
          <p className="muted">Real-time operational intelligence across your entire AML program. Monitor KPIs, track team performance, and ensure regulatory compliance with unified dashboards.</p>
          <ul>
            <li>Enterprise risk metrics</li>
            <li>Compliance deadlines</li>
            <li>Team performance analytics</li>
            <li>SAR conversion tracking</li>
          </ul>
          <button type="button" className="cta" onClick={() => nav("/exec")}>Enter Executive View →</button>
        </div>

        <div className="entry hl">
          <div className="ico">🔍</div>
          <h2>Alert Investigation</h2>
          <div className="role">AML Analyst Workspace</div>
          <p className="muted">AI-powered investigation workspace with multi-agent assistance. Analyse alerts, gather evidence, and make STR decisions in minutes instead of hours.</p>
          <ul>
            <li>Intelligent alert prioritisation</li>
            <li>Automated evidence gathering</li>
            <li>AI investigation assistant</li>
            <li>One-click STR (goAML) generation for the FIC</li>
          </ul>
          <button type="button" className="cta" onClick={() => nav("/investigation")}>Enter Investigation View →</button>
        </div>
      </div>

      <div className="footer-band">
        <div className="f"><div className="l">Powered by</div><div className="v">Databricks on AWS</div></div>
        <div className="f"><div className="l">Card Payments</div><div className="v">15,000+ / min</div></div>
        <div className="f"><div className="l">Regulator</div><div className="v">FIC · FICA · SARB PA</div></div>
        <div className="f"><div className="l">Data Governance</div><div className="v">Unity Catalog · POPIA</div></div>
      </div>
    </div>
  );
}
