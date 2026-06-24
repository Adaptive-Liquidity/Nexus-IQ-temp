# NexusIQ Self-Host Kit

Run the NexusIQ WASM sandbox runtime with AEON-IQ memory on your own machine.
No Rust toolchain needed — everything builds and runs inside Docker.

---

## Quickstart

```bash
cp .env.example .env
# Edit .env: set OPENAI_API_KEY=<your key>
./install.sh
./start.sh
./doctor.sh
./generate-mcp-config.sh
# Paste the generated config into your MCP client
./run-live-example.sh
```

That is the complete setup sequence. The rest of this document explains what
each step does and how to configure the stack for your environment.

---

## What NexusIQ is

NexusIQ is a self-contained local runtime that combines:

- **Nexus** — a WASM sandbox hypervisor built with the `aeon-memory` feature.
  It executes WASM modules in isolated, capability-gated WASI environments,
  produces cryptographically-bound Proof Capsules, supports snapshot/rollback,
  and can negotiate or deny capability access.
- **AEON-IQ** — a persistent memory plane (`memoryos` Rust/Axum service).
  It stores episodic memories as vector embeddings (via pgvector), runs
  semantic recall against them, records MemoryEvidence tied to proofs, and
  maintains an agent timeline.
- Together: WASM execution with a memory plane. Proof Capsules are attached to
  each execution. Timeline events are written to AEON and queryable via its API.

---

## What this kit runs

Four Docker services, all on an isolated internal network:

```
 ┌───────────────────────────────────────────────────────────────┐
 │  host (you)                                                   │
 │                                                               │
 │  MCP client ──── connect-mcp.sh ─── stdin/stdout ──┐         │
 │  (Claude Desktop / Cursor / OpenHands)              │         │
 │                                               ┌─────▼──────┐ │
 │  curl / browser ─── 127.0.0.1:8080 ─────────▶│   aeon     │ │
 │                                               │ (REST API) │ │
 └───────────────────────────────────────────────┴─────┬───┬──┘ │
                                                       │   │
 ┌─ Docker internal network (nexusiq) ─────────────────│───│────┐
 │                                                     │   │    │
 │  ┌────────────────┐   unix socket  ┌────────────┐   │   │    │
 │  │  nexus-mcp     │◀──────────────▶│nexus-agentd│   │   │    │
 │  │  (STDIO only;  │                │(long-lived │   │   │    │
 │  │  on-demand)    │                │ daemon)    │   │   │    │
 │  └────────────────┘                └────────────┘   │   │    │
 │                                         │           │   │    │
 │  ┌─────────────────────────────────────────────┐    │   │    │
 │  │  postgres (pgvector, internal only, no port)│◀───┘   │    │
 │  └─────────────────────────────────────────────┘        │    │
 │             ▲                                            │    │
 │             └──────────────────────────────────────────┘    │
 └─────────────────────────────────────────────────────────────┘
```

| Service | Role | Host exposure |
|---|---|---|
| `postgres` | pgvector storage for AEON-IQ | None (internal only) |
| `aeon` | AEON-IQ REST API | `127.0.0.1:8080` |
| `nexus-agentd` | Nexus execution daemon | Unix socket (shared volume) |
| `nexus-mcp` | STDIO MCP server | None — launched on demand |

`nexus-mcp` is **not** a long-running port. MCP clients launch it via
`connect-mcp.sh` which runs `docker compose run --rm -T nexus-mcp` and speaks
JSON-RPC 2.0 over its stdin/stdout. There is no HTTP MCP endpoint.

---

## System requirements

- **Docker Engine** 24+ with the **Compose v2 plugin** (`docker compose`)
  - Docker Desktop (macOS/Windows) or Docker Engine on Linux both work
  - [Install Docker](https://docs.docker.com/engine/install/)
  - [Install Compose plugin](https://docs.docker.com/compose/install/)
- **~4 GB RAM** available to Docker
- **Disk**: ~3 GB for images; a few MB per proof/memory stored
- **An LLM provider API key** (OpenAI by default; see [Configuring the LLM provider](#configuring-the-llm-provider))
- `bash`, `curl`, `git` on the host (standard on macOS/Linux; WSL2 on Windows)
- `jq` or `python3` for the live example script (either works)

---

## 5-minute quickstart

### 1. Copy the env file and set your API key

```bash
cp .env.example .env
```

Open `.env` and set:

```
OPENAI_API_KEY=sk-...
```

That is the only required edit for the default OpenAI provider.

### 2. Run the installer

```bash
./install.sh
```

The installer:
- Checks for Docker and the Compose plugin
- Generates secrets (Postgres password, management API key, HMAC key, agentd
  auth token) and writes them into `.env`
- Clones the Nexus and AEON-IQ source trees into `./vendor/` (or links your
  local checkouts if you set `NEXUSIQ_VENDOR_NEXUS` / `NEXUSIQ_VENDOR_AEON`)
- Builds Docker images locally (no prebuilt images are published yet)
- Creates `./data/{proofs,timeline,modules,logs}`
- Bakes a sample WASM module into `./data/modules/sample_tool.wasm`

The first build can take 5–15 minutes depending on machine speed (Rust
compilation). Subsequent runs use the Docker layer cache.

### 3. Start the stack

```bash
./start.sh
```

Starts `postgres`, `aeon`, and `nexus-agentd` in the background and waits for
all three to report healthy. `nexus-mcp` is not started here — it runs on
demand.

### 4. Verify everything is up

```bash
./doctor.sh
```

Runs a suite of live checks (Docker daemon, service health, AEON API auth,
agentd socket, MCP handshake, data directory writability, provider key
presence). Every check prints `PASS` or `FAIL`. Fix any `FAIL` lines before
proceeding; see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### 5. Connect your MCP client

```bash
./generate-mcp-config.sh
```

Writes ready-to-paste JSON configs with absolute paths baked in to `./mcp/`:

```
mcp/claude-desktop.json
mcp/cursor.json
mcp/openhands.json
mcp/generic-mcp.json
```

Paste the contents of the appropriate file into your MCP client config (see
[Connecting MCP clients](#connecting-mcp-clients) below).

### 6. Run the live example

```bash
./run-live-example.sh
```

Exercises the full end-to-end flow against the running stack. See
[Running the live example](#running-the-live-example).

---

## Configuring the LLM provider

AEON-IQ uses an LLM for two tasks: **embedding** memories (semantic storage)
and **extracting** structured data from them. The default provider is OpenAI.

### OpenAI (default)

Use `.env.example` or `.env.openai.example`. Set:

```
UPSTREAM_PROVIDER=openai
OPENAI_API_KEY=sk-...
```

Default models: `text-embedding-3-small` (1536 dimensions), `gpt-4o-mini`
extractor. These are configured in `.env.openai.example`.

### Anthropic

```bash
cp .env.anthropic.example .env
```

Then set `OPENAI_API_KEY` to your **Anthropic** API key. (AEON-IQ uses a
single upstream-key variable regardless of provider.)

Note: Anthropic does not serve embeddings. The Anthropic preset points the
embedding lane at OpenAI — you will need an OpenAI key for embeddings and an
Anthropic key for chat/extraction. See `.env.anthropic.example` for details.

### Gemini

```bash
cp .env.gemini.example .env
```

Set `OPENAI_API_KEY` to your Google AI / Gemini API key.

Important: Gemini's default embedding model (`text-embedding-004`) produces
768-dimensional vectors, but AEON-IQ's pgvector column is hard-coded to
`vector(1536)`. If you use a 768-dim model you must also change the schema.
See `.env.gemini.example` for the full note.

### Ollama (ADVANCED / EXPERIMENTAL)

```bash
cp .env.ollama.example .env
```

Ollama local models do **not** produce 1536-dim vectors. You must change
AEON-IQ's pgvector schema (`migrations/0001_initial.sql`) to match your chosen
model's dimension **before the database is first initialized**. Changing the
schema after data exists requires dropping and re-migrating the embedding
column.

See `.env.ollama.example` for the full warning and procedure. This path is not
supported for first-time users.

---

## Starting and stopping the stack

```bash
./start.sh         # start postgres, aeon, nexus-agentd (detached)
./stop.sh          # stop the stack (data volumes preserved)
./logs.sh aeon     # follow logs for a specific service
./logs.sh          # follow all service logs
```

To restart after a config change:

```bash
./stop.sh && ./start.sh
```

To update (after pulling new kit files):

```bash
./stop.sh
./install.sh       # rebuilds images with any source changes
./start.sh
```

---

## Verifying with doctor

```bash
./doctor.sh
```

Each line is `PASS <check>` or `FAIL <check>`. Warnings (`WARN`) are
advisory and do not cause a non-zero exit. The script exits non-zero if any
check fails.

Checks run:
- `.env` present and readable
- Docker daemon running, Compose plugin available
- All four Compose services defined
- Postgres healthy (`pg_isready`)
- AEON `/health` returns 200
- AEON management API authenticated (key required, 401/403 without)
- `nexus-agentd` live (socket present)
- `nexus-mcp` handshake (initialize + tools/list)
- `data/proofs` and `data/timeline` writable
- No mock/synthetic flags active
- Provider key present (warning only if missing)

---

## Connecting MCP clients

MCP transport is **STDIO only**. Clients launch `connect-mcp.sh`, which starts
a `nexus-mcp` container per session. There is no HTTP MCP port.

Run this once after install:

```bash
./generate-mcp-config.sh
```

It writes configs with absolute paths into `./mcp/`.

### Claude Desktop

Paste the contents of `mcp/claude-desktop.json` into:

| Platform | Config path |
|---|---|
| macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Windows | `%APPDATA%\Claude\claude_desktop_config.json` |
| Linux | `~/.config/Claude/claude_desktop_config.json` |

Restart Claude Desktop. `nexusiq` should appear in the tools list.

### Cursor

Paste `mcp/cursor.json` into:
- Per-project: `<project>/.cursor/mcp.json`
- Global: `~/.cursor/mcp.json`

### OpenHands

Paste `mcp/openhands.json` contents into Settings → MCP, key `nexusiq`.

### Any other MCP client

Use `mcp/generic-mcp.json`. The server entry specifies:
- `command`: absolute path to `connect-mcp.sh`
- `env.NEXUSIQ_SELFHOST_DIR`: absolute path to the kit directory
- Transport: STDIO

If your client cannot find `connect-mcp.sh`, use its absolute path.

---

## Running the live example

```bash
./run-live-example.sh
```

Runs five steps live against the running stack:

1. **(a) Write a memory** — POSTs an episodic memory to AEON-IQ via the
   management API. Requires a provider key for embedding.
2. **(b) Recall** — semantic search over stored memories. Requires a provider
   key for embedding.
3. **(c) Execute + proof** — calls `nexus_execute_proof` via `connect-mcp.sh`
   on `sample_tool.wasm`. Does **not** require a provider key.
4. **(d) Extract proof capsule** — writes the returned Proof Capsule to
   `data/proofs/<capsule_id>.json`.
5. **(e) Timeline** — POSTs the execution event to AEON-IQ's timeline.

Steps (a), (b), and (e) fail cleanly if no provider key is set. Step (c) runs
regardless. See [ARCHITECTURE.md](ARCHITECTURE.md) and
[examples/expected_user_flow.md](examples/expected_user_flow.md) for a
narrated walk-through.

---

## Viewing proof capsules

Proof Capsules are written to `./data/proofs/` on the host as
`<capsule_id>.json` files.

```bash
ls -la data/proofs/
cat data/proofs/<capsule_id>.json
```

Each capsule contains the module path, execution result, a capability grant
record, a timestamp, and a cryptographic binding. Treat these files as
execution metadata — they may contain details about what modules ran.

---

## Viewing timeline events

Timeline events are stored in AEON-IQ's Postgres and queryable via the
management API. The `MANAGEMENT_API_KEY` from `.env` is required.

```bash
# Query timeline at or before a given time
curl -fsS \
  -H "X-Management-Key: $MANAGEMENT_API_KEY" \
  "http://127.0.0.1:8080/api/v1/agents/nexusiq/timeline/at?timestamp=<ISO8601>"

# Stats (memory counts, etc.)
curl -fsS \
  -H "X-Management-Key: $MANAGEMENT_API_KEY" \
  http://127.0.0.1:8080/api/v1/stats

# Search memories
curl -fsS -X POST http://127.0.0.1:8080/api/v1/memories/search \
  -H "X-Management-Key: $MANAGEMENT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"nexusiq","query":"what did Nexus execute?","limit":5}'
```

---

## Stop / update / uninstall

```bash
# Stop (preserves volumes and data)
./stop.sh

# Update
./stop.sh && git pull && ./install.sh && ./start.sh

# Full reset (removes volumes and all stored data — irreversible)
./reset.sh
```

---

## Known limitations

- No prebuilt images are published yet. `./install.sh` always builds from
  source (first build: 5–15 min).
- Ollama support requires a manual schema change and is experimental.
- The AEON pgvector column is fixed at `vector(1536)`. Non-1536-dim embedding
  models require a schema migration.
- Anthropic does not provide an embeddings API; a separate embeddings provider
  is required when using the Anthropic preset.
- `nexus-mcp` is single-session per container invocation — each MCP client
  session launches a fresh container.
- `nexus daemon ping` is not yet implemented in all builds; the health check
  falls back to checking socket presence.

---

## Security notes

See [SECURITY.md](SECURITY.md) for the full security reference.

Short version:
- All host ports are bound to `127.0.0.1` only.
- Postgres is not published to the host at all.
- Secrets are auto-generated by `install.sh` and stored only in `.env`.
- Do not commit `.env`.
- Do not expose the AEON API (`127.0.0.1:8080`) or Postgres to the network
  without a reverse proxy and TLS.
- Proof Capsules and timeline events contain execution metadata — treat them
  as sensitive.

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
