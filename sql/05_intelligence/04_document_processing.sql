-- Phase 3 Intelligence: Document processing (PRD §8).
-- KYC packs / source-of-funds letters land in the documents Volume. In
-- production, ai_parse_document OCRs/parses PDFs; here the demo corpus is text,
-- so we read it directly and run ai_extract to pull the KYC fields (names,
-- amounts, jurisdictions, PEP terms). Extracted fields feed entity resolution
-- and adverse-media matching.
--
-- For real PDFs the first step is:
--   SELECT path, ai_parse_document(content) AS parsed
--   FROM READ_FILES('/Volumes/.../documents/*.pdf', format => 'binaryFile');

CREATE OR REPLACE TABLE elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.document_extractions AS
WITH docs AS (
  SELECT
    _metadata.file_path AS file_path,
    CAST(content AS STRING) AS doc_text
  FROM READ_FILES(
    '/Volumes/elexon_app_for_settlement_acc_catalog/nedbank_fraud_aml_bronze/documents/*.txt',
    format => 'text',
    wholeText => true
  )
)
SELECT
  file_path,
  ai_extract(
    doc_text,
    array('client_name', 'national_id', 'tax_number', 'source_of_funds',
          'pep_status', 'beneficial_owner', 'jurisdictions', 'amount', 'risk_assessment')
  ) AS extracted,
  doc_text
FROM docs;
