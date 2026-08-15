# Sentinel + MCB — Demo Ops & Warm-Up Handoff

> For any future engineer/AI: how the 4 demo apps are kept fast for meetings, and the
> full performance work already shipped. Companion to [SENTINEL_HANDOFF.md](SENTINEL_HANDOFF.md)
> (architecture) and [SENTINEL_COMPLETED_WORK.md](SENTINEL_COMPLETED_WORK.md) (task log).
> Last updated 2026-08-15.

## The 4 demo apps
| App | URL | Warehouse ID | Warehouse auto-stop |
|-----|-----|--------------|---------------------|
| Capitec Sentinel | https://capitec-fraud-aml-7474654808133980.aws.databricksapps.com | 10fbc0a24b3e418c | 60 min |
| Nedbank Sentinel | https://nedbank-fraud-aml-7474654808133980.aws.databricksapps.com | eeee8ab1661ce350 | 60 min |
| Investec Sentinel | https://investec-fraud-aml-7474654808133980.aws.databricksapps.com | e227fa247dd5bedd | 60 min |
| MCB Customer 360 | https://mcb-customer-360-7474654808133980.aws.databricksapps.com | dcb1c3dd8d1570d6 | 240 min |

> ⚠️ **investec-fraud-aml is hands-off** — no deploy/edit/delete of the app without
> explicit re-authorization. Warming its *warehouse* via the job below is fine.

## Why warm-ups exist
Serverless SQL warehouses cold-start ~15-30s after idle. A cold first click in front of
a customer/boss reads as "slow". Warming = fire cheap read-only queries so the warehouse
is hot, plus fill the app's in-process TTL cache, before the session.

## Layer 1 — server-side warm Jobs (primary; no laptop needed)
Native Databricks Jobs, one per app. **Schedule: `0 0 9,11,13 ? * MON-FRI`,
timezone `Africa/Johannesburg` → 09:00 / 11:00 / 13:00 SAST, weekdays.** UNPAUSED.
Fire server-side regardless of whether any laptop is on.

| App | Job name | Job ID |
|-----|----------|--------|
| Capitec | `[Capitec] Prime demo (warm warehouse & caches)` | 904514902417610 |
| Nedbank | `[Nedbank] Prime demo (warm warehouse & caches)` | 940799723574121 |
| Investec | `[Investec] Prime demo (warm warehouse & caches)` | 222788104794952 |
| MCB | `[MCB] Prime demo (warm warehouse & caches)` | 657733045157540 |

- Sentinel warm SQL: `/Workspace/Users/jason.miles@databricks.com/sentinel-warm/<bank>_warm.sql`
  (read-only reads of `<bank>_fraud_aml_gold`; created via Jobs API, NOT bundle-managed).
- MCB warm SQL: `src/ops/warm.sql` in the mcb-customer-360 repo (bundle-managed in its
  `databricks.yml` — redeploy with `databricks bundle deploy -t dev`).
- Manual fire any job:
  `databricks jobs run-now <JOB_ID> --profile fevm-elexon-app-for-settlement-acc`
- Change schedule (Sentinel jobs, API-managed): `databricks jobs update --profile fevm-elexon-app-for-settlement-acc --json '{"job_id":<ID>,"new_settings":{"schedule":{"quartz_cron_expression":"<cron>","timezone_id":"Africa/Johannesburg","pause_status":"UNPAUSED"}}}'`
  (job_id goes INSIDE the JSON; `--json` forbids a positional job id).

## Layer 2 — laptop crontab + manual script (fills app caches too)
`/Users/jason.miles/vibe-coding-repos/__PRIME-DEMOS/prime_apps.sh` hits every app's HTTP
endpoints (all 4 apps) — this warms the warehouse **and** fills the app's in-process TTL
cache (the jobs only warm the warehouse). Also runs the MCB demo preflight (roles/Genie/avatar).
- Manual (guaranteed, ~60s): `bash /Users/jason.miles/vibe-coding-repos/__PRIME-DEMOS/prime_apps.sh`
- macOS `crontab -l` has scheduled fires; logs to `/tmp/prime_demos.log`.
- Caveat: macOS cron only fires if the Mac is on and awake; may need Full Disk Access.
  The manual command is the always-works fallback.

## Belt-and-braces before any high-stakes demo
1. The 09/11/13 SAST jobs keep warehouses hot on weekdays automatically.
2. Still, ~1-2 min before the session, run `prime_apps.sh` once — it also fills the app
   TTL caches (jobs don't) and runs MCB's role preflight.

## Performance work already shipped (all 3 Sentinel apps + template)
Server-side: TTL cache (`cached_fetch_all`, env `FRAUD_CACHE_TTL`), parallel query fan-out
(`parallel()`), combined `/exec/summary` (1 call vs 5), `alerts/summary` single ROLLUP,
fire-and-forget audit writes, poll backoff, in-app warehouse keep-warm loop + startup prime.
LLM: `ai_stream()` SSE token streaming for AI Triage + Multi-Agent panels; Claude Sonnet 4.5
via `FRAUD_LLM_ENDPOINT`. Frontend: lazy routes, skeleton loaders, `apiGet` retry, gzip
(-67% bundle), immutable asset cache. Measured warm latency ~0.8-2.7s across endpoints.
Full detail + patterns in SENTINEL_HANDOFF.md §6. 38 backend tests pass on all 3 + template.

## Repos (push targets)
- capitec-sentinel-app → `github.com/jason-miles/sentinel-app-capitec-bank` (remote `public`)
- nedbank-sentinel-app-v2 → `github.com/jason-miles/sentinel-app-nedbank` (`origin`)
- investec-sentinel-app-v2 → `github.com/jason-miles/sentinel-app-investec` (`origin`)
- sentinel-app (unified template) → `github.com/jason-miles/sentinel-app` (`origin`)
- mcb-customer-360 → its own repo (bundle-managed)
