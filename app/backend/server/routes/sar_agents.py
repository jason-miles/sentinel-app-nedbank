"""Multi-agent SAR orchestration + goAML XML (NEXT_STEPS #4).

A supervisor pattern over Mosaic AI (ai_query) specialist agents with a SHARED,
auto-gathered evidence pack:

  1. gather_evidence() assembles the full evidence pack for a case from the real
     gold/silver tables (case, flagged transactions, counterparty network, prior
     alerts, sanctions/watchlist hits, perpetual-KYC risk) — cutting the analyst's
     manual correlation to ~zero.
  2. Specialist agents (transaction-analysis, adverse-media, policy) each reason over
     that shared context and return a finding.
  3. The supervisor synthesises a regulator-ready SAR narrative citing the findings.
  4. build_goaml_xml() emits a goAML-format (UN/UNODC standard) SAR XML from the case
     + evidence — a real structured filing artifact, not just a narrative + "PDF".

All ai_query prompts are bound as parameters (never string-interpolated into SQL).
"""
import html
import xml.etree.ElementTree as ET
from typing import Optional
from fastapi import APIRouter, Response
from pydantic import BaseModel

from ..db import fetch_all, ai_query
from ..config import CATALOG, GOLD_SCHEMA, SILVER_SCHEMA, get_workspace_client

router = APIRouter(prefix="/api/sar", tags=["sar-agents"])


def _num(v, default: float = 0.0) -> float:
    """Coerce a value to float. The Databricks SQL Statement Execution API returns
    every column as a STRING (result.data_array is all text), so numeric fields
    like amount/risk_score arrive as e.g. '19850.00'. Guard against None/''/bad
    values so downstream round()/f-string formatting never crashes."""
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


ADVERSE_MEDIA_INDEX = f"{CATALOG}.{GOLD_SCHEMA}.adverse_media_index"
AML_KNOWLEDGE_INDEX = f"{CATALOG}.{GOLD_SCHEMA}.aml_knowledge_index"


def retrieve_adverse_media(query: str, k: int = 3) -> list:
    """Vector-search the adverse-media corpus for evidence relevant to the subject.
    Grounds the SAR narrative in actual retrieved articles (RAG) rather than a
    metadata-only prompt. Best-effort: returns [] on any failure so SAR still works."""
    try:
        w = get_workspace_client()
        r = w.vector_search_indexes.query_index(
            index_name=ADVERSE_MEDIA_INDEX,
            columns=["article_id", "headline", "source", "published_at"],
            query_text=query, num_results=k,
        )
        rows = (r.result.data_array or []) if r.result else []
        out = []
        for row in rows:
            # columns order: article_id, headline, source, published_at, score
            out.append({"article_id": row[0], "headline": row[1], "source": row[2],
                        "published_at": row[3],
                        "score": round(float(row[4]), 3) if len(row) > 4 and row[4] is not None else None})
        return out
    except Exception:
        return []


def retrieve_policy(query: str, k: int = 3) -> list:
    """Vector-search the AML knowledge corpus (bank policy, escalation matrix,
    typology guides, FATF references) for material relevant to the detected
    typology. Grounds the policy agent's SAR recommendation in the bank's own rules
    and 'why this matters'. Best-effort: returns [] on any failure."""
    try:
        w = get_workspace_client()
        r = w.vector_search_indexes.query_index(
            index_name=AML_KNOWLEDGE_INDEX,
            columns=["doc_id", "doc_type", "title", "jurisdiction", "source"],
            query_text=query, num_results=k,
        )
        rows = (r.result.data_array or []) if r.result else []
        out = []
        for row in rows:
            # columns order: doc_id, doc_type, title, jurisdiction, source, score
            out.append({"doc_id": row[0], "doc_type": row[1], "title": row[2],
                        "jurisdiction": row[3], "source": row[4],
                        "score": round(float(row[5]), 3) if len(row) > 5 and row[5] is not None else None})
        return out
    except Exception:
        return []

# Reporting-entity constants for the goAML header (the filing institution).
RE = {
    "id": "NEDBANK-ZA",
    "name": "Nedbank Limited",
    "type": "BANK",
    "country": "ZA",
    "contact": "Financial Crime Intelligence Unit",
}


def _one(sql: str, params):
    rows = fetch_all(sql, params)
    return rows[0] if rows else None


def gather_evidence(case_id: str) -> dict:
    """Auto-assemble the full evidence pack for a case from real tables."""
    p = [{"name": "cid", "value": case_id}]
    case = _one(f"""
SELECT case_id, alert_num, customer_id, customer_name, scenario, priority, status,
       team_name, analyst_name, risk_score, amount, days_open
FROM {GOLD_SCHEMA}.sherlock_cases WHERE case_id = :cid
""", p)
    if not case:
        return {}
    cust = case.get("customer_id")
    cp = [{"name": "cust", "value": cust}]

    # After the case row, the 4 SQL lookups + the vector-search are all independent.
    # The Statement Execution API adds ~1.5s fixed overhead per call, so running
    # them sequentially costs ~8s; fan them out concurrently so the evidence pack
    # comes back in roughly one round-trip (~2s).
    def _txns():
        return fetch_all(f"""
SELECT t.transaction_id, t.amount, t.direction, t.channel, t.txn_ts, t.counterparty_id
FROM {SILVER_SCHEMA}.transactions t
JOIN {SILVER_SCHEMA}.accounts a ON a.account_id = t.account_id
WHERE a.customer_id = :cust
ORDER BY t.amount DESC LIMIT 10
""", cp) if cust else []

    def _network():
        return fetch_all(f"""
SELECT DISTINCT t.counterparty_id, tp.full_name, tp.country, tp.entity_kind
FROM {SILVER_SCHEMA}.transactions t
JOIN {SILVER_SCHEMA}.accounts a ON a.account_id = t.account_id
LEFT JOIN {SILVER_SCHEMA}.third_parties tp ON tp.third_party_id = t.counterparty_id
WHERE a.customer_id = :cust AND t.counterparty_id IS NOT NULL
LIMIT 10
""", cp) if cust else []

    def _screening():
        # sanctions / watchlist hits for this subject (by name)
        return fetch_all(f"""
SELECT watch_name, list_type, list_source, severity, confidence, match_score
FROM {GOLD_SCHEMA}.sanctions_screening_hits
WHERE entity_name = :name
ORDER BY match_score DESC LIMIT 10
""", [{"name": "name", "value": case.get("customer_name")}])

    def _pkyc():
        return _one(f"""
SELECT dynamic_risk, risk_band, edd_review_required, risk_drivers,
       alert_count, severe_alerts, sanction_hits, media_hits
FROM {GOLD_SCHEMA}.pkyc_customer_risk WHERE customer_id = :cust
""", cp) if cust else None

    # RAG: retrieve adverse-media evidence relevant to the subject + typology.
    def _media():
        return retrieve_adverse_media(f"{case.get('customer_name')} {case.get('scenario')}", k=3)

    # RAG: retrieve bank AML policy / typology / FATF references for the scenario.
    def _policy():
        return retrieve_policy(f"{case.get('scenario')} typology reporting obligation", k=3)

    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=6) as pool:
        f_txns = pool.submit(_txns)
        f_network = pool.submit(_network)
        f_screening = pool.submit(_screening)
        f_pkyc = pool.submit(_pkyc)
        f_media = pool.submit(_media)
        f_policy = pool.submit(_policy)

    return {"case": case, "transactions": f_txns.result(), "network": f_network.result(),
            "screening": f_screening.result(), "pkyc": f_pkyc.result(),
            "adverse_media": f_media.result(), "policy": f_policy.result()}


def _evidence_brief(ev: dict) -> str:
    """Compact, factual context string handed to every agent (shared memory)."""
    c = ev["case"]
    lines = [
        f"Case {c['case_id']} — customer {c['customer_name']} ({c['customer_id']}). "
        f"Scenario: {c['scenario']}. Priority: {c['priority']}. Rules risk {c['risk_score']}/100. "
        f"Amount ZAR {c['amount']}. {c['days_open']} days open. Team {c['team_name']}.",
    ]
    if ev.get("transactions"):
        t = ev["transactions"]
        lines.append(f"{len(t)} flagged transactions; largest ZAR "
                     f"{max(_num(x['amount']) for x in t):,.0f}; directions "
                     f"{sorted(set(x['direction'] for x in t))}.")
    if ev.get("network"):
        cps = [x for x in ev["network"] if x.get("counterparty_id")]
        countries = sorted({x['country'] for x in cps if x.get('country')})
        lines.append(f"{len(cps)} counterparties across {countries or ['n/a']}.")
    if ev.get("screening"):
        s = ev["screening"]
        lines.append(f"{len(s)} sanctions/watchlist hits: "
                     + "; ".join(f"{x['watch_name']} ({x['list_type']}/{x['confidence']})" for x in s[:4]) + ".")
    if ev.get("pkyc"):
        k = ev["pkyc"]
        lines.append(f"Perpetual-KYC dynamic risk {k['dynamic_risk']} band {k['risk_band']}; "
                     f"EDD required: {k['edd_review_required']}; drivers: {k['risk_drivers']}.")
    if ev.get("adverse_media"):
        m = ev["adverse_media"]
        lines.append("Retrieved adverse-media (cite by source): "
                     + "; ".join(f"\"{a['headline']}\" ({a['source']}, {a['published_at']})" for a in m[:3]) + ".")
    if ev.get("policy"):
        p = ev["policy"]
        lines.append("Applicable AML policy / typology / FATF references (cite by title): "
                     + "; ".join(f"\"{d['title']}\" ({d['jurisdiction']})" for d in p[:3]) + ".")
    return " ".join(lines)


def _agent(system: str, brief: str, task: str) -> str:
    prompt = (f"{system}\n\nShared case evidence: {brief}\n\nTask: {task} "
              "Be factual, cite the evidence above, 2-3 sentences.")
    return ai_query(prompt)


SPECIALISTS = [
    ("transaction_analysis",
     "You are the Transaction Analysis agent in an AML SAR team.",
     "Assess the transaction pattern and what makes it consistent with the detected typology."),
    ("adverse_media",
     "You are the Adverse Media & Screening agent in an AML SAR team.",
     "Assess reputational / sanctions / watchlist exposure for this subject."),
    ("policy",
     "You are the AML Policy & Typology agent in an AML SAR team. You have access to "
     "the bank's AML policy, escalation matrix, typology guides and FATF references in "
     "the shared evidence.",
     "State which AML/CFT typology and reporting obligation applies and why a SAR/STR is "
     "warranted, CITING the applicable policy/typology/FATF references by title."),
]


class OrchestrateReq(BaseModel):
    case_id: str


@router.get("/evidence/{case_id}")
def evidence(case_id: str):
    """FAST path: gather + return the evidence pack ONLY (SQL, no LLM). Lets the UI
    render the evidence panel in ~1s while the slow multi-agent /orchestrate call
    (3 specialists + supervisor, ~6s of ai_query) runs in the background."""
    ev = gather_evidence(case_id)
    if not ev:
        return {"detail": "not found"}
    c = ev["case"]
    return {
        "case_id": c["case_id"], "customer_name": c["customer_name"],
        "scenario": c["scenario"], "priority": c["priority"],
        "risk_score": c["risk_score"], "amount": c["amount"],
        "evidence": {
            "transactions": ev["transactions"], "network": ev["network"],
            "screening": ev["screening"], "pkyc": ev["pkyc"],
            "adverse_media": ev.get("adverse_media", []),
            "policy": ev.get("policy", []),
        },
    }


@router.post("/orchestrate")
def orchestrate(req: OrchestrateReq):
    """Run the full multi-agent SAR workflow with auto-gathered evidence."""
    ev = gather_evidence(req.case_id)
    if not ev:
        return {"detail": "not found"}
    brief = _evidence_brief(ev)

    # The 3 specialist agents are independent — only the supervisor needs all of
    # them. Run them concurrently (each is a separate ai_query LLM round-trip of a
    # few seconds; sequential = sum, parallel = max) so the workflow finishes in
    # roughly half the time. Order of the trace is preserved to match SPECIALISTS.
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=len(SPECIALISTS)) as pool:
        findings_list = list(pool.map(lambda s: _agent(s[1], brief, s[2]), SPECIALISTS))
    trace = [{"agent": key, "finding": finding}
             for (key, _sys, _task), finding in zip(SPECIALISTS, findings_list)]

    findings = " ".join(f"[{t['agent']}] {t['finding']}" for t in trace)
    supervisor = _agent(
        "You are the AML Multi-Agent Supervisor at Nedbank Limited (South Africa). "
        "You have received findings from your specialist agents (transaction analysis, "
        "adverse media, policy). The output is a Suspicious Transaction Report (STR) for "
        "the Financial Intelligence Centre (FIC) under section 29 of the FIC Act, filed via "
        "goAML.",
        brief,
        "Synthesise a concise, regulator-ready STR narrative (SA/FIC framing) with: (1) summary "
        "of suspicious activity, (2) the pattern/typology detected, (3) why it is suspicious with "
        "reference to the specialist findings, (4) recommended action. Where the evidence lists "
        "retrieved adverse-media articles CITE them by source, and where it lists policy/typology/"
        f"FATF references CITE them by title. Specialist findings: {findings}",
    )
    c = ev["case"]
    return {
        "case_id": c["case_id"], "customer_name": c["customer_name"],
        "scenario": c["scenario"], "priority": c["priority"],
        "risk_score": c["risk_score"], "amount": c["amount"],
        "evidence": {
            "transactions": ev["transactions"], "network": ev["network"],
            "screening": ev["screening"], "pkyc": ev["pkyc"],
            "adverse_media": ev.get("adverse_media", []),
            "policy": ev.get("policy", []),
        },
        # brief is the exact shared context handed to the agents; returned so callers
        # (e.g. the eval harness) can reuse it without re-gathering evidence.
        "evidence_brief": brief,
        "agent_trace": trace,
        "narrative": supervisor,
    }


# ─────────────────────────── goAML SAR XML ────────────────────────────────
def _x(tag: str, val, indent: int = 4) -> str:
    if val is None or val == "":
        return ""
    return f"{' ' * indent}<{tag}>{html.escape(str(val))}</{tag}>\n"


def build_goaml_xml(case_id: str, narrative: str = "") -> str:
    """Gather evidence for a case and emit its goAML SAR XML."""
    ev = gather_evidence(case_id)
    if not ev:
        return "<report/>"
    return goaml_from_evidence(ev, narrative)


def goaml_from_evidence(ev: dict, narrative: str = "") -> str:
    """Pure: emit a goAML-format (UN/UNODC standard) SAR XML from an evidence dict.
    Structure follows goAML's report → reporting-person/entity → activity →
    transaction/involved-parties shape (demo-faithful, not schema-validated).
    Separated from I/O so it is unit-testable without a warehouse."""
    if not ev or not ev.get("case"):
        return "<report/>"
    c = ev["case"]
    txns = ev.get("transactions") or []

    tx_xml = ""
    for t in txns[:10]:
        tx_xml += "      <transaction>\n"
        tx_xml += _x("transactionnumber", t.get("transaction_id"), 8)
        tx_xml += _x("transaction_type", t.get("direction"), 8)
        tx_xml += _x("amount_local", round(_num(t.get("amount")), 2), 8)
        tx_xml += _x("transaction_channel", t.get("channel"), 8)
        tx_xml += _x("date_transaction", str(t.get("txn_ts") or "")[:19], 8)
        tx_xml += _x("counterparty", t.get("counterparty_id"), 8)
        tx_xml += "      </transaction>\n"

    hits = ev.get("screening") or []
    reason = c["scenario"]
    if hits:
        reason += "; watchlist: " + ", ".join(h["watch_name"] for h in hits[:3])

    xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
    xml += '<report xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n'
    xml += _x("rentity_id", RE["id"])
    xml += _x("rentity_branch", RE["contact"])
    xml += _x("submission_code", "E")           # E = electronic
    xml += _x("report_code", "STR")             # STR = suspicious transaction report
    xml += _x("entity_reference", c["case_id"])
    # submission_date is stamped by the FIC submission connector at filing time, not
    # in the draft — intentionally omitted here.
    xml += "  <reporting_person>\n"
    xml += _x("first_name", c.get("analyst_name"), 4)
    xml += _x("entity", RE["name"], 4)
    xml += _x("country", RE["country"], 4)
    xml += "  </reporting_person>\n"
    xml += "  <activity>\n"
    xml += "    <report_indicators>\n"
    xml += _x("indicator", c["scenario"], 6)
    xml += _x("indicator", f"rules_risk_{c['risk_score']}", 6)
    if ev.get("pkyc"):
        xml += _x("indicator", f"pkyc_{ev['pkyc']['risk_band']}", 6)
    xml += "    </report_indicators>\n"
    xml += "    <suspicious_party>\n"
    xml += _x("party_name", c["customer_name"], 6)
    xml += _x("party_reference", c["customer_id"], 6)
    xml += "    </suspicious_party>\n"
    xml += "    <goods_services>\n"
    xml += _x("item_type", "FUNDS", 6)
    xml += _x("total_amount", round(_num(c.get("amount")), 2), 6)
    xml += _x("currency_code", "ZAR", 6)
    xml += "    </goods_services>\n"
    xml += "    <transactions>\n" + tx_xml + "    </transactions>\n"
    xml += _x("reason", reason)
    xml += _x("action", "Escalated to FIC; funds monitored")
    if narrative:
        xml += _x("narrative", narrative)
    xml += "  </activity>\n"
    xml += "</report>\n"
    return xml


@router.get("/goaml/{case_id}")
def goaml(case_id: str, narrative: str = ""):
    """Download the goAML SAR XML for a case."""
    xml = build_goaml_xml(case_id, narrative)
    return Response(
        content=xml, media_type="application/xml",
        headers={"Content-Disposition": f'attachment; filename="SAR_goAML_{case_id}.xml"'},
    )


# ─────────────────── goAML structural validation ─────────────────────────
# Encodes the goAML STR report's required structure/cardinality/types (matching the
# UN/UNODC goAML schema shape we emit). Production step: validate against the OFFICIAL
# goAML XSD via lxml.etree.XMLSchema — swap this pure check for that when the XSD +
# lxml are available. Kept dependency-free (stdlib ElementTree) and unit-testable.
def validate_goaml(xml: str) -> dict:
    issues = []
    checks = [
        # (label, predicate over root)
        ("well-formed XML", None),
        ("root element is <report>", lambda r: r.tag == "report"),
        ("rentity_id present", lambda r: (r.findtext("rentity_id") or "").strip() != ""),
        ("report_code == 'STR'", lambda r: (r.findtext("report_code") or "") == "STR"),
        ("entity_reference present", lambda r: (r.findtext("entity_reference") or "").strip() != ""),
        ("activity block present", lambda r: r.find("activity") is not None),
        ("suspicious_party.party_name present",
         lambda r: (r.findtext("activity/suspicious_party/party_name") or "").strip() != ""),
        ("goods_services.currency_code present",
         lambda r: (r.findtext("activity/goods_services/currency_code") or "").strip() != ""),
        ("total_amount is numeric",
         lambda r: _is_num(r.findtext("activity/goods_services/total_amount"))),
        ("at least one transaction",
         lambda r: len(r.findall("activity/transactions/transaction")) >= 1),
        ("every transaction has number + numeric amount",
         lambda r: all((t.findtext("transactionnumber") or "").strip() != ""
                       and _is_num(t.findtext("amount_local"))
                       for t in r.findall("activity/transactions/transaction"))),
        ("reason present", lambda r: (r.findtext("activity/reason") or "").strip() != ""),
    ]
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as e:
        return {"valid": False, "checks_total": len(checks), "checks_passed": 0,
                "issues": [f"not well-formed: {e}"]}

    passed = 1  # well-formed already succeeded
    for label, pred in checks[1:]:
        try:
            ok = bool(pred(root))
        except Exception:
            ok = False
        if ok:
            passed += 1
        else:
            issues.append(f"failed: {label}")
    return {"valid": len(issues) == 0, "checks_total": len(checks),
            "checks_passed": passed, "issues": issues}


def _is_num(v) -> bool:
    if v is None or str(v).strip() == "":
        return False
    try:
        float(v)
        return True
    except ValueError:
        return False


@router.get("/goaml/validate/{case_id}")
def goaml_validate(case_id: str, narrative: str = ""):
    """Validate the case's goAML XML against the required STR structure."""
    xml = build_goaml_xml(case_id, narrative)
    return validate_goaml(xml)
