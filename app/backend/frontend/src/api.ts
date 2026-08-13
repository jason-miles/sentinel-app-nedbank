// SherlockAML API client.
export async function apiGet<T = any>(path: string): Promise<T> {
  const res = await fetch(path);
  if (!res.ok) throw new Error(`${path} -> ${res.status}`);
  return res.json();
}
export async function apiPost<T = any>(path: string, body: unknown): Promise<T> {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${path} -> ${res.status}`);
  return res.json();
}

// POST that streams a text/plain body, invoking onChunk for each token batch as it
// arrives. Powers the live-typing AI panels. Returns the full accumulated text.
export async function apiPostStream(path: string, body: unknown, onChunk: (soFar: string) => void): Promise<string> {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok || !res.body) throw new Error(`${path} -> ${res.status}`);
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let text = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    text += decoder.decode(value, { stream: true });
    onChunk(text);
  }
  return text;
}

const S = "/api/sherlock";
// App config (dashboard embed etc.)
export const getConfig = () => apiGet(`/api/config`);
// Personas
export const getPersonas = () => apiGet(`${S}/personas`);
// Executive
export const getExecKpis = () => apiGet(`${S}/exec/kpis`);
export const getDailyNew = () => apiGet(`${S}/exec/daily-new`);
export const getOutstanding = () => apiGet(`${S}/exec/outstanding`);
export const getByScenario = () => apiGet(`${S}/exec/by-scenario`);
export const getPriorityStatus = () => apiGet(`${S}/exec/priority-status`);
export const getResolutionFlow = () => apiGet(`${S}/exec/resolution-flow`);
export const getTeamPerformance = () => apiGet(`${S}/exec/team-performance`);
// Investigation
export const getQueue = (analystId: string, priority = "", scenario = "") => {
  const qs = new URLSearchParams();
  if (priority) qs.set("priority", priority);
  if (scenario) qs.set("scenario", scenario);
  const s = qs.toString();
  return apiGet(`${S}/queue/${encodeURIComponent(analystId)}${s ? `?${s}` : ""}`);
};
export const getCase = (caseId: string, actor = "") =>
  apiGet(`${S}/case/${encodeURIComponent(caseId)}${actor ? `?actor=${encodeURIComponent(actor)}` : ""}`);
export const addNote = (b: any) => apiPost(`${S}/case/note`, b);
export const caseAction = (b: any) => apiPost(`${S}/case/action`, b);
export const caseTransition = (b: any) => apiPost(`${S}/case/transition`, b);
export const caseReassign = (b: any) => apiPost(`${S}/case/reassign`, b);
// Agent + SAR
export const agentChat = (b: any) => apiPost(`${S}/agent/chat`, b);
export const agentChatStream = (b: any, onChunk: (t: string) => void) => apiPostStream(`${S}/agent/chat/stream`, b, onChunk);
export const sarGenerate = (b: any) => apiPost(`${S}/sar/generate`, b);
export const sarSubmit = (b: any) => apiPost(`${S}/sar/submit`, b);
export const sarEvidence = (caseId: string) =>
  apiGet(`/api/sar/evidence/${encodeURIComponent(caseId)}`);
export const sarOrchestrate = (b: any) => apiPost(`/api/sar/orchestrate`, b);
export const goamlUrl = (caseId: string, narrative = "") =>
  `/api/sar/goaml/${encodeURIComponent(caseId)}?narrative=${encodeURIComponent(narrative.slice(0, 1200))}`;
export const goamlValidate = (caseId: string) =>
  apiGet(`/api/sar/goaml/validate/${encodeURIComponent(caseId)}`);
// Graph
export const getGraph = (q = "", limit = 12) =>
  apiGet(`${S}/graph?limit=${limit}${q ? `&q=${encodeURIComponent(q)}` : ""}`);

// Advanced AML (sanctions screening, pKYC, peer anomaly)
const A = "/api/aml";
export const getScreening = (confidence = "", limit = 200) =>
  apiGet(`${A}/screening?limit=${limit}${confidence ? `&confidence=${confidence}` : ""}`);
export const getScreeningSummary = () => apiGet(`${A}/screening/summary`);
export const getPkyc = (minRisk = 0, limit = 100) => apiGet(`${A}/pkyc?min_risk=${minRisk}&limit=${limit}`);
export const getPkycSummary = () => apiGet(`${A}/pkyc/summary`);
export const getAnomalies = (limit = 100) => apiGet(`${A}/anomalies?limit=${limit}`);
export const getModelGovernance = () => apiGet(`${A}/model-governance`);
export const getModelDrift = () => apiGet(`${A}/model-drift`);
export const getLlmEval = () => apiGet(`${A}/llm-eval`);
export const getAudit = (limit = 100) => apiGet(`${A}/audit?limit=${limit}`);
export const getAuditSummary = () => apiGet(`${A}/audit/summary`);
// Impossible-travel alerts (geospatial card-tap velocity)
export const getImpossibleTravel = () => apiGet(`/api/impossible-travel`);
// Live-transaction simulation (real-time demo beat)
export const simLiveAlert = () => apiPost(`/api/sim/live-alert`, {});

// GenAI
const G = "/api/genai";
export const genieAsk = (b: any) => apiPost(`${G}/ask`, b);
export const execBriefing = () => apiGet(`${G}/exec-briefing`);
export const caseTriage = (b: any) => apiPost(`${G}/triage`, b);
export const caseTriageStream = (b: any, onChunk: (t: string) => void) => apiPostStream(`${G}/triage/stream`, b, onChunk);
export const casePrioritize = (b: any) => apiPost(`${G}/prioritize`, b);
