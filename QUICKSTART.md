# NexusIQ — Quick Start

Six commands. One required edit. Done.

---

## Prerequisites

- Docker Engine + Compose v2 plugin ([install](https://docs.docker.com/engine/install/))
- An OpenAI API key (default provider)
- `bash`, `curl`, `git` on the host

---

## Steps

### 1. Copy the env file

```bash
cp .env.example .env
```

### 2. Set your OpenAI API key

Open `.env` and fill in:

```
OPENAI_API_KEY=sk-...
```

This is the only required edit. Everything else has safe defaults.

### 3. Install (builds images, generates secrets)

```bash
./install.sh
```

First run takes 5–15 minutes (Rust build). Subsequent runs use cache.

### 4. Start the stack

```bash
./start.sh
```

Starts Postgres, AEON-IQ, and the Nexus daemon in the background.

### 5. Verify

```bash
./doctor.sh
```

Every line should show `PASS`. If anything shows `FAIL`, see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### 6. Connect your MCP client

```bash
./generate-mcp-config.sh
```

Writes `mcp/claude-desktop.json`, `mcp/cursor.json`, `mcp/openhands.json`,
and `mcp/generic-mcp.json` with absolute paths baked in.

Paste the contents of the appropriate file into your MCP client config, then
restart the client. The `nexusiq` server will appear in the tools list.

---

You are done. NexusIQ is running locally. Your MCP client can now invoke
`nexus_execute_proof` and related tools.

To run the end-to-end example:

```bash
./run-live-example.sh
```

---

## What is running

| Service | Where |
|---|---|
| AEON-IQ REST API | `http://127.0.0.1:8080` |
| Postgres (pgvector) | Internal only — not host-accessible |
| Nexus daemon | Unix socket (container-internal) |
| Nexus MCP server | Launched on demand via `connect-mcp.sh` — no port |

For more detail see [README.md](README.md) and [ARCHITECTURE.md](ARCHITECTURE.md).
