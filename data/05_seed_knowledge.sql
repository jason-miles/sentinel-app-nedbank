-- Nedbank — Fraud & AML SAMPLE DATA · Synthetic seeder (5/5): AML KNOWLEDGE + SAR CORPUS
-- *** NEDBANK DEMO DATA — 100% SYNTHETIC ***
-- Unstructured RAG grounding for the copilot's policy agent and SAR drafting: a
-- Nedbank-branded AML policy + escalation matrix, FATF typology guides, and historical
-- FIC-format STR narratives filed as "Nedbank Limited".
-- ALL content is synthetic DEMO DATA authored for this demo — it paraphrases
-- PUBLIC FATF typologies and the South African FIC Act regime at a high level and
-- contains no real entities, no confidential methods, and no evasion techniques.

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- ══════════════════════════════════════════════════════════════════════════
-- AML KNOWLEDGE CORPUS — bank policy, escalation matrix, typology guides, FATF
-- ══════════════════════════════════════════════════════════════════════════
INSERT OVERWRITE nedbank_fraud_aml_bronze.aml_knowledge
SELECT * FROM VALUES
  ('POL-001','policy','Nedbank AML/CFT Policy — Purpose & Risk-Based Approach','ZA',
   'Nedbank Limited operates a risk-based AML/CFT programme under the Financial Intelligence Centre Act (FICA, Act 38 of 2001) as amended, aligned to FATF Recommendations and supervised by the Prudential Authority (SARB) and the Financial Intelligence Centre (FIC). All business units must identify, assess, monitor and mitigate money-laundering, terrorist-financing and proliferation-financing risk. Customer Due Diligence (CDD) is applied at onboarding and on an ongoing basis; Enhanced Due Diligence (EDD) applies to higher-risk clients, PEPs and unusual activity. Transaction monitoring generates alerts that must be investigated and, where suspicion is not dispelled, escalated for regulatory reporting.',
   'Nedbank AML Policy v4 (synthetic)', current_timestamp()),
  ('POL-002','policy','CDD, KYC Tiers and Expected Turnover','ZA',
   'At onboarding Nedbank records the client''s identity, declared occupation and expected monthly turnover. The declared expected turnover is a control baseline: ongoing monitoring compares ACTUAL throughput against DECLARED turnover, and material, unexplained divergence (e.g. actual >= 3x declared) is a red flag requiring review and, potentially, EDD. KYC tiers (tier1 simplified / tier2 / tier3 EDD) determine the intensity of due diligence. A change in behaviour inconsistent with the client''s profile must be risk-assessed.',
   'Nedbank AML Policy v4 (synthetic)', current_timestamp()),
  ('POL-003','policy','Cash Threshold Reporting (CTR) and Structuring','ZA',
   'Cash transactions at or above the prescribed threshold (R25,000) must be reported to the FIC as a Cash Threshold Report (CTR). Deliberately breaking cash deposits into amounts below the threshold to avoid a CTR is "structuring" (smurfing) and is itself a reportable suspicion. Repeated sub-threshold cash deposits into an account — especially across a short window, from multiple depositors, or into recently opened accounts — must be treated as potential structuring and investigated as a possible money-mule indicator.',
   'Nedbank AML Policy v4 (synthetic)', current_timestamp()),
  ('ESC-001','escalation_matrix','Alert Escalation Matrix','internal',
   'Escalation path: (1) Transaction Monitoring analyst triages the alert within SLA. (2) If suspicion is not dispelled, escalate to the Fraud Investigations or EDD team with an evidence pack. (3) The team lead reviews and, where reasonable grounds for suspicion exist, refers to the Money Laundering Reporting Officer (MLRO). (4) The MLRO decides on a Suspicious Transaction/Activity Report (STR/SAR) to the FIC via goAML. STRs must be filed as soon as possible and within the regulatory period once suspicion is formed. Critical-severity alerts (sanctions hits, active mule networks, PEP with adverse media) are escalated immediately.',
   'Nedbank Escalation Matrix (synthetic)', current_timestamp()),
  ('TYP-001','typology_guide','Typology Guide — Money-Mule Networks','FATF',
   'Money-mule networks recruit individuals (often young, unemployed, or students) to receive and forward illicit funds. Indicators: clusters of recently opened accounts sharing a device, IP, address or contact number; small sub-threshold cash or instant-payment credits followed by rapid forwarding (often >=90% within 24-48h) to a single aggregation account; the aggregator then remits cross-border. Individual accounts often look benign in isolation and may have been closed as false positives — the network only emerges through entity resolution and link analysis. Aligns with FATF guidance on professional money laundering and the misuse of the banking system.',
   'FATF typologies (synthetic paraphrase)', current_timestamp()),
  ('TYP-002','typology_guide','Typology Guide — Structuring / Smurfing','FATF',
   'Structuring splits a large amount into multiple smaller transactions to evade reporting thresholds. Indicators: multiple cash deposits just below the CTR limit; deposits by several parties into one account; patterns of round-number sub-threshold amounts; deposits at multiple branches/ATMs in a short period. Treated as a standalone reportable typology and a frequent first signal of mule activity.',
   'FATF typologies (synthetic paraphrase)', current_timestamp()),
  ('TYP-003','typology_guide','Typology Guide — Trade-Based Money Laundering','FATF',
   'Trade-based money laundering (TBML) disguises illicit proceeds through trade transactions — over/under-invoicing, phantom shipments, multiple invoicing. Indicators: payments to/from high-risk jurisdictions inconsistent with the customer''s stated business; round-dollar cross-border wires; use of shell companies and nominee directors.',
   'FATF typologies (synthetic paraphrase)', current_timestamp()),
  ('TYP-004','typology_guide','Typology Guide — Third-Party Payment Processors & Gaming','FATF',
   'Layering through third-party payment processors (TPPs) and online-gaming merchants: illicit funds are cycled through a gaming or TPP merchant as "bets" and returned as near-equal "winnings" or payouts, giving the money a legitimate-looking source. Indicators: high-frequency card debits to a gaming/TPP merchant matched by near-equal credits back from the same processor; net flow near zero; volumes inconsistent with the customer''s declared profile. These rarely trip amount- or velocity-based rules and are best surfaced by typology/pattern search over merchant categories.',
   'FATF typologies (synthetic paraphrase)', current_timestamp()),
  ('TYP-005','typology_guide','Typology Guide — Romance-Scam Proceeds','FATF',
   'Romance-scam proceeds: victims are manipulated into sending funds that are then laundered through mule accounts. Indicators: an older customer sending recurring instant payments or cross-border remittances to a new beneficiary; sudden dormant-account reactivation to receive and forward funds; explanations that shift over time.',
   'FATF typologies (synthetic paraphrase)', current_timestamp()),
  ('FATF-001','fatf_reference','FATF Recommendations — Reporting & Ongoing Monitoring','FATF',
   'FATF Recommendation 20 requires financial institutions to report suspicious transactions to the national FIU (in South Africa, the FIC). Recommendation 10 requires ongoing CDD and scrutiny of transactions to ensure they are consistent with the institution''s knowledge of the customer, their business and risk profile. Recommendation 1 establishes the risk-based approach. These underpin the bank''s obligation to detect, investigate and report the typologies above.',
   'FATF Recommendations (synthetic paraphrase)', current_timestamp())
AS t(doc_id, doc_type, title, jurisdiction, body, source, _ingested_at);

-- ══════════════════════════════════════════════════════════════════════════
-- HISTORICAL SAR/STR NARRATIVES — house-style few-shot corpus (synthetic)
-- ══════════════════════════════════════════════════════════════════════════
INSERT OVERWRITE nedbank_fraud_aml_bronze.sar_narratives
SELECT * FROM VALUES
  ('STR-2025-0001', DATE'2025-11-14','money_mule','Lindiwe Mahlangu','filed',
   'Nedbank Limited files this STR under section 29 of the FIC Act. The subject, a Nedbank retail client, received seven sub-threshold cash deposits (each below R25,000) over four days and forwarded approximately 91% of the aggregate to a single third-party account within 48 hours. The receiving account subsequently remitted funds cross-border. Entity resolution linked the subject to five further accounts sharing a device fingerprint and residential address, three of which had previously been alerted and closed as false positives in isolation. The pattern is consistent with a money-mule network (FATF professional money-laundering typology). Suspicion could not be dispelled; funds were placed under monitoring and the matter escalated to the MLRO.',
   current_timestamp()),
  ('STR-2025-0002', DATE'2025-12-02','structuring','Pieter Nel','filed',
   'This report concerns repeated cash deposits structured below the R25,000 CTR threshold. Over a seven-day period the client made multiple ATM and branch cash deposits ranging from R19,500 to R24,800, aggregating materially above the threshold while each individual deposit avoided a CTR. The declared occupation and expected monthly turnover (R12,000) were materially inconsistent with observed throughput. No legitimate source of funds was evidenced. The activity is consistent with structuring/smurfing and is reported accordingly.',
   current_timestamp()),
  ('STR-2026-0003', DATE'2026-01-19','tpp_gaming_layering','Rethabile Moloi','escalated',
   'This report concerns suspected layering through an online-gaming third-party payment processor. The client conducted high-frequency card debits to a gaming/TPP merchant, each followed within hours by near-equal credits described as payouts, producing a net flow close to zero and volumes inconsistent with the client''s profile. The activity did not trigger amount- or velocity-based rules and was identified through a retrospective typology review of merchant-category patterns. The matter was escalated for enhanced due diligence and MLRO review.',
   current_timestamp()),
  ('STR-2026-0004', DATE'2026-02-08','sanctions','Onyx Capital (nominee)','filed',
   'This report concerns a customer whose resolved entity matched a sanctions/watchlist designation with high confidence and who was named in adverse media relating to a cross-border laundering probe. Beneficial-ownership records for a linked nominee company changed shortly before a large outbound remittance. The combination of a confirmed screening hit, adverse media and an ownership change immediately preceding fund movement establishes reasonable grounds for suspicion. Reported to the FIC.',
   current_timestamp()),
  ('STR-2026-0005', DATE'2026-03-11','romance_scam','Susan Coetzee','filed',
   'This report concerns suspected romance-scam proceeds. A long-standing client reactivated a dormant savings pocket to receive funds and immediately forwarded recurring instant payments to a newly added beneficiary, later remitting cross-border. Explanations for the payments were inconsistent across interactions. The pattern is consistent with a victim being used to launder or transmit scam proceeds. Suspicion could not be dispelled and the matter is reported.',
   current_timestamp())
AS t(sar_id, filed_at, typology, subject_name, disposition, narrative, _ingested_at);
