#!/usr/bin/env bash
#
# connect-mcp.sh — user-facing MCP launcher for NexusIQ.
#
# MCP clients (Claude Desktop, Cursor, OpenHands, …) execute this script and
# speak JSON-RPC 2.0 to it over stdin/stdout. It is a thin, transparent pipe:
# it exec()s the STDIO nexus-mcp container and passes the client's stdin and
# stdout straight through. NOTHING but JSON-RPC may be written to stdout — all
# diagnostics go to stderr only.
#
# The kit directory is resolved in this order:
#   1. $NEXUSIQ_SELFHOST_DIR if set (the MCP client config sets this)
#   2. the directory containing this script (robust to absolute-path launch)
#
set -euo pipefail

# ---- stderr-only logging (stdout is the JSON-RPC channel) -------------------
log() { printf '%s\n' "connect-mcp: $*" >&2; }

# ---- resolve this script's own directory, robustly --------------------------
# Follow symlinks so a symlinked launcher still finds the real kit dir.
_source="${BASH_SOURCE[0]}"
while [[ -h "$_source" ]]; do
  _dir="$(cd -P "$(dirname -- "$_source")" >/dev/null 2>&1 && pwd)"
  _source="$(readlink -- "$_source")"
  [[ "$_source" != /* ]] && _source="${_dir}/${_source}"
done
SCRIPT_DIR="$(cd -P "$(dirname -- "$_source")" >/dev/null 2>&1 && pwd)"

# Kit directory: env override wins, else the script's own directory.
NEXUSIQ_SELFHOST_DIR="${NEXUSIQ_SELFHOST_DIR:-$SCRIPT_DIR}"
COMPOSE_FILE="${NEXUSIQ_SELFHOST_DIR%/}/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  log "FATAL: docker-compose.yml not found at ${COMPOSE_FILE}"
  log "       Set NEXUSIQ_SELFHOST_DIR to the absolute path of the NexusIQ kit."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  log "FATAL: 'docker' not found on PATH. Install Docker and ensure it is running."
  exit 1
fi

log "launching nexus-mcp (compose file: ${COMPOSE_FILE})"

# exec() replaces this process so signals and the stdio pipe pass straight
# through to the container. -T disables pseudo-TTY allocation (required for a
# clean JSON-RPC byte stream). --rm removes the one-shot container on exit.
exec docker compose -f "$COMPOSE_FILE" --profile tools run --rm -T nexus-mcp
