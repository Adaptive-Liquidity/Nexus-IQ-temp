# NexusIQ Troubleshooting

Run `./doctor.sh` first. It checks every subsystem live and prints `PASS` or
`FAIL` with a plain-English description. Diagnose from there.

---

## Docker not running

**Symptom:** `./install.sh` or `./start.sh` prints "Docker daemon is not
reachable" or "docker: command not found".

**Fix:** Start Docker Desktop (macOS/Windows) or `sudo systemctl start docker`
(Linux). Verify with `docker info`.

---

## Port 8080 already in use

**Symptom:** `./start.sh` fails with "address already in use" or AEON's health
check never passes.

**Fix:** Find and stop whatever is using 8080:

```bash
lsof -i :8080       # macOS/Linux
netstat -ano | findstr :8080   # Windows PowerShell
```

Or change the port in `.env`:

```
AEON_PORT=8081
```

Then restart: `./stop.sh && ./start.sh`. If you change the port, regenerate
MCP configs: `./generate-mcp-config.sh`.

---

## Missing or invalid OPENAI_API_KEY

**Symptom:** `./doctor.sh` shows `WARN no provider key for
UPSTREAM_PROVIDER=openai`. Memory writes and recall fail with HTTP 4xx or an
embedding error. `nexus_execute_proof` still works — it does not need a key.

**Fix:** Set a valid key in `.env`:

```
OPENAI_API_KEY=sk-...
```

Then restart AEON only (the key is read at startup):

```bash
docker compose restart aeon
```

---

## AEON build is slow on first run

**Symptom:** `./install.sh` appears to hang at the `Building images` step for
many minutes.

**Explanation:** The first build compiles AEON-IQ and Nexus from Rust source.
This is normal and can take 5–15 minutes depending on CPU speed and whether
you have `sccache` configured. Subsequent runs use Docker's layer cache and
are fast.

**What to do:** Wait. You can follow progress in another terminal:

```bash
docker compose build --progress plain
```

---

## vendor/ not populated (clone failed)

**Symptom:** `./install.sh` prints "Failed to clone Nexus" or "Could not clone
AEON-IQ" and exits.

**Fix:** If you have local checkouts of the repos, point the installer at them:

```bash
NEXUSIQ_VENDOR_NEXUS=/path/to/Nexus \
NEXUSIQ_VENDOR_AEON=/path/to/AEON-IQ \
./install.sh
```

The installer will symlink those directories into `./vendor/` instead of
cloning. The source must contain the expected Dockerfiles.

---

## MCP client cannot find connect-mcp.sh

**Symptom:** The MCP client shows an error like "command not found" or fails
to launch the server.

**Fix:** The `command` in the MCP config must be an **absolute path**. Run:

```bash
./generate-mcp-config.sh
```

This bakes the absolute path into the generated config. If you moved the kit
directory after generating the config, re-run the script and repaste the
updated JSON.

If your client still fails, manually set the full path:

```json
{
  "mcpServers": {
    "nexusiq": {
      "command": "/home/you/nexusiq/connect-mcp.sh",
      "args": [],
      "env": {
        "NEXUSIQ_SELFHOST_DIR": "/home/you/nexusiq"
      }
    }
  }
}
```

---

## agentd socket missing

**Symptom:** `./doctor.sh` reports `FAIL nexus-agentd not live (no daemon ping,
socket file absent)`.

**Fix:** Check whether `nexus-agentd` is running and healthy:

```bash
docker compose ps nexus-agentd
./logs.sh nexus-agentd
```

Common causes:
- AEON was not healthy when `nexus-agentd` started (it depends on AEON).
  Restart: `docker compose restart nexus-agentd`.
- The image build failed or was not run. Re-run `./install.sh`.

---

## How to read logs

```bash
./logs.sh aeon            # follow AEON-IQ logs
./logs.sh nexus-agentd    # follow the Nexus daemon logs
./logs.sh nexus-mcp       # logs from the last MCP session
./logs.sh postgres        # Postgres logs
./logs.sh                 # follow all services
```

Increase verbosity by setting `RUST_LOG=debug` in `.env` and restarting the
affected service.

---

## How to reset

**Soft reset** — stop the stack, wipe all volumes, restart fresh. This deletes
all stored memories, timeline events, and Postgres data:

```bash
./reset.sh
```

**Manual reset** — stop, remove volumes, re-run install:

```bash
./stop.sh
docker compose down -v
./install.sh
./start.sh
```

**Rotate secrets only** — blank out the secret lines in `.env` (leave keys
like `OPENAI_API_KEY` intact), then re-run:

```bash
./scripts/generate-secrets.sh
docker compose restart
```

---

## nexus-mcp handshake fails in doctor

**Symptom:** `FAIL nexus-mcp handshake failed (no tools listed over
connect-mcp.sh)`.

**Check in order:**
1. Is `nexus-agentd` healthy? (`docker compose ps nexus-agentd`)
2. Does the `agentd_run` volume exist and contain the socket?
   (`docker compose exec nexus-agentd test -S /run/nexus/nexus-agentd.sock`)
3. Is the `nexus-mcp` image built? (`docker compose build nexus-mcp`)
4. Check logs: `./logs.sh nexus-agentd`

---

## ALLOW_UNAUTH_MANAGEMENT is true

**Symptom:** `./doctor.sh` prints `FAIL ALLOW_UNAUTH_MANAGEMENT is truthy —
management plane auth is disabled`.

**Fix:** Set it to `false` in `.env`:

```
ALLOW_UNAUTH_MANAGEMENT=false
```

Then restart AEON: `docker compose restart aeon`. Never leave this enabled in
any real deployment.
