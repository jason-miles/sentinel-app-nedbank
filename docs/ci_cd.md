# CI/CD — Nedbank Sentinel (roadmap #5)

## Activation checklist (one-time)

Do these in order to turn CI/CD on:

1. **Create an M2M service principal** (Account Console → *User management →
   Service principals → Add*; name e.g. `sp-sentinel-cicd`). Add it to the
   `fevm-elexon-app-for-settlement-acc` workspace.
2. **Generate an OAuth secret** for that SP (SP → *Secrets → Generate secret*).
   Copy the **Client ID** and **Secret** — the secret is shown **once**.
3. **Add the three GitHub repo secrets** (repo → *Settings → Secrets and variables →
   Actions → New repository secret*):
   - `DATABRICKS_HOST` = `https://fevm-elexon-app-for-settlement-acc.cloud.databricks.com`
   - `DATABRICKS_CLIENT_ID` = the SP's client id
   - `DATABRICKS_CLIENT_SECRET` = the SP's OAuth secret
4. **Grant the SP access** (run the block in "SP grants" below as an admin).
5. **Restore the workflow files** to `main` (see "Restore workflows") — needs a
   git token with the `workflow` scope.
6. Open a test PR → the CI jobs run; merge → deploy runs.

---

Two GitHub Actions workflows drive the project:

## `.github/workflows/ci.yml` — PR gate (no deploy)
Runs on every pull request to `main`:
- **test-backend** — `pytest` over `app/backend/tests` (goAML XML, evidence brief,
  AI-risk blend, route smoke tests with a mocked DB — no warehouse needed).
- **build-frontend** — `npm ci && npm run build` to catch UI/TS breakage.
- **bundle-validate** — `databricks bundle validate -t prod` (needs the secrets below).

## `.github/workflows/deploy.yml` — deploy on merge to `main`
- Re-runs the backend tests, then builds the React UI into `webroot/` and runs
  `databricks bundle deploy -t prod`, shipping the **app + pipeline + jobs** together.
- `concurrency: deploy-prod` prevents overlapping deploys.

> ⚠️ **Do the bundle migration first.** The root bundle names the pipeline
> `nedbank_sentinel/…`, distinct from the live nested `fraud_aml_pipeline` bundle —
> so the **first** `bundle deploy -t prod` creates a *second* pipeline unless you cut
> over first (see "Migration note" below). Recommended sequence: (a) do the migration
> manually with a human present, then (b) enable this workflow. Until then, keep
> `deploy.yml` parked on the `ci-workflows` branch (only `ci.yml` — the PR gate — is
> safe to enable immediately, and it never deploys).

## Required repo secrets
Add under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DATABRICKS_HOST` | `https://fevm-elexon-app-for-settlement-acc.cloud.databricks.com` |
| `DATABRICKS_CLIENT_ID` | OAuth service-principal client id (M2M) |
| `DATABRICKS_CLIENT_SECRET` | OAuth service-principal secret |

The app's own runtime service principal (`982e92ba-…`) is separate and already granted.

## SP grants (run as a workspace admin)

Give the CI/CD service principal the UC + resource access it needs to deploy. Replace
`<CICD_SP_APP_ID>` with the new SP's application id:

```sql
-- UC: read/write the medallion + governance tables
GRANT USE CATALOG ON CATALOG elexon_app_for_settlement_acc_catalog TO `<CICD_SP_APP_ID>`;
GRANT USE SCHEMA, SELECT, MODIFY ON SCHEMA elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze TO `<CICD_SP_APP_ID>`;
GRANT USE SCHEMA, SELECT, MODIFY ON SCHEMA elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver TO `<CICD_SP_APP_ID>`;
GRANT USE SCHEMA, SELECT, MODIFY, CREATE TABLE, CREATE FUNCTION ON SCHEMA elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold TO `<CICD_SP_APP_ID>`;
```
Also grant `CAN_MANAGE` on the app, pipeline, and jobs (Workspace UI → each resource →
Permissions), and `CAN_USE` on the app warehouse `d0305022e6c3db8e`.

## Restore workflows

The two `.github/workflows/*.yml` were parked on the `ci-workflows` branch (a push
token without the `workflow` scope can't push them). With a `workflow`-scoped token:

```sh
git checkout main
git checkout ci-workflows -- .github/workflows/
git commit -m "Restore CI workflow files"
git push          # requires: gh auth refresh -h github.com -s workflow
```

## Isaac Review in CI (recommended, per NEXT_STEPS #7)
Add a job that runs `isaac review` on the PR diff and blocks on findings — Databricks'
recommended code-review pipeline. Kept out of the default workflow here because it
needs the internal Isaac tooling available on the runner.

## Migration note (bundle consolidation)
The root `databricks.yml` unifies the app + pipeline + jobs. The pipeline currently
also has a nested bundle at `fraud_aml_pipeline/databricks.yml`. Cut over deliberately:
deploy once from the root (`databricks bundle deploy -t prod`), confirm the pipeline +
app adopt cleanly, then retire the nested bundle. Do not run both bundles against the
same resources.
