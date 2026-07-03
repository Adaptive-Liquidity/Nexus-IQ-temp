# Operations

## Stack lifecycle

- `./install.sh`  
  prepares `.env`, generates secrets, vendors sources, builds images, and creates data dirs.
- `./start.sh`  
  starts `postgres`, `aeon`, `nexus-agentd` and waits for health.
- `./stop.sh`  
  stops services (data retained).
- `./restart.sh`  
  stop then start.
- `./logs.sh [service]`  
  follow logs (all services or one).
- `./doctor.sh`  
  full health and auth verification.
- `./reset.sh`  
  stop and remove all volumes (data wipe; .env preserved).
- `./uninstall.sh`  
  remove stack + images + optional `.env` / `vendor` / `data`.
- `./scripts/wait-for-health.sh`  
  used by start path.
- `./scripts/print-urls.sh`  
  prints expected endpoints.

`nexus-mcp` is not always-on. It is `--profile tools` and starts via MCP session.

## Verification flows

Use scripts in this order for a clean live verification:

```bash
./doctor.sh
./scripts/smoke-nexus-execute.sh
./scripts/smoke-memory-recall.sh
./scripts/smoke-proof-capsule.sh
./scripts/smoke-timeline.sh
./run-live-example.sh
./verify-live-stack.sh   # doctor + live example
```

Memory-based smoke checks require a valid provider key; MCP proof checks do not.

## Key provisioning and rotation

Core secrets used by runtime:

- `MANAGEMENT_API_KEY`
- `NEXUS_AEON_HMAC_KEY`
- `NEXUS_AGENTD_AUTH_TOKEN`

To rotate secrets:

1. Clear these values in `.env` (leave provider keys if unchanged).
2. Run `./scripts/generate-secrets.sh`.
3. Restart with `./stop.sh && ./start.sh`.

If the DB password rotates, use full stack recreation (`./reset.sh`) or a fresh `install.sh`.

Validation:

- `./scripts/validate-env.sh` validates required values and cross-wire constraints.

## Postgres + pgvector backup/restore

Data is internal only and not exposed on host ports.

Backup:

```bash
docker compose exec -T postgres pg_dump -U nexusiq -d nexusiq > /tmp/nexusiq.sql
```

Restore (service down window recommended):

```bash
cat /tmp/nexusiq.sql | docker compose exec -T postgres psql -U nexusiq -d nexusiq
```

## HNSW maintenance

There is no bundled pgvector maintenance CLI in the root kit scripts, but ANN index upkeep should be done explicitly:

- Run ANN/HNSW rebuild/reindex tasks during maintenance windows, before long `VACUUM` windows on heavy workloads.
- Keep this as a worker-only job, not request-path inline work.
- Serialize maintenance with a lock to prevent concurrent index writes.

Example pattern:

```bash
docker compose exec -T postgres psql -U nexusiq -d nexusiq -c "REINDEX INDEX CONCURRENTLY <hnsw_index_name>;"
```

If index maintenance collides with ongoing writes, choose conservative timings and monitor query impact.


## AEON-IQ role split (proxy vs worker)

The stack runs AEON-IQ as two services sharing one database:

| Service | `MEMORYOS_ROLE` | Runs | Pool budget |
|---|---|---|---|
| `aeon` | `proxy` | request serving only (chat proxy + management API) | `DB_MAX_CONNECTIONS` (default 20) |
| `aeon-worker` | `worker` | archival, extraction outbox, RMK/AMP sweeps, HNSW maintenance; serves `/health` + `/metrics` only, no host port | `WORKER_DB_MAX_CONNECTIONS` (default 5) |

Rationale: background sweeps over large corpora previously shared the hot
path's connection pool and produced a measured p99 latency tail. The split
caps background work at its own small budget so it can never starve request
serving. To run everything in one container (small machines), remove
`aeon-worker` and set `MEMORYOS_ROLE=all` (or unset it) on `aeon`.
