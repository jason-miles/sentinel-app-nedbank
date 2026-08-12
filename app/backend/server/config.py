"""Dual-mode auth + workspace client for the Nedbank Fraud & AML app.

Follows the Valterra pattern: WorkspaceClient uses auto-injected service-principal
credentials when running as a Databricks App, and a local CLI profile otherwise.
"""
import os
from databricks.sdk import WorkspaceClient

# Physical location of the medallion (co-located schemas — see repo README).
CATALOG = os.environ.get("FRAUD_CATALOG", "elexon_app_for_settlement_acc_catalog")
GOLD_SCHEMA = os.environ.get("FRAUD_GOLD_SCHEMA", "nedbank_fraud_aml_gold")
SILVER_SCHEMA = os.environ.get("FRAUD_SILVER_SCHEMA", "nedbank_fraud_aml_silver")

IS_DATABRICKS_APP = bool(os.environ.get("DATABRICKS_APP_NAME"))


def get_workspace_client() -> WorkspaceClient:
    """Remote: auto-injected SP credentials. Local: CLI profile."""
    if IS_DATABRICKS_APP:
        return WorkspaceClient()
    profile = os.environ.get("DATABRICKS_PROFILE", "fevm-elexon-app-for-settlement-acc")
    return WorkspaceClient(profile=profile)
