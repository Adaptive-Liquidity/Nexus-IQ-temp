#!/usr/bin/env bash
#
# Compose service-set contract for default, tools, and memory profiles.
#
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  printf 'FAIL docker compose is required for profile contract tests\n' >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cp .env.example "${TMP_DIR}/env"

services_for() {
  docker compose --env-file "${TMP_DIR}/env" "$@" config --services 2>/dev/null | sort
}

assert_services() {
  local name="$1" expected="$2"
  shift 2
  local actual
  actual="$(services_for "$@")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL %s\nexpected:\n%s\nactual:\n%s\n' "$name" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'PASS %s\n' "$name"
}

assert_services "default profile contains only nexus-agentd" \
  'nexus-agentd'

assert_services "tools profile adds nexus-mcp without memory services" \
  $'nexus-agentd\nnexus-mcp' \
  --profile tools

assert_services "memory + tools profiles expose the full service set" \
  $'aeon\naeon-worker\nnexus-agentd\nnexus-mcp\npostgres' \
  --profile memory --profile tools

MODEL="$(docker compose --env-file "${TMP_DIR}/env" --profile memory --profile tools config 2>/dev/null)"
AGENTD_BLOCK="$(printf '%s\n' "$MODEL" | sed -n '/^  nexus-agentd:/,/^  [a-zA-Z0-9_-][a-zA-Z0-9_-]*:/p')"
MCP_BLOCK="$(printf '%s\n' "$MODEL" | sed -n '/^  nexus-mcp:/,/^  [a-zA-Z0-9_-][a-zA-Z0-9_-]*:/p')"

if grep -q '^    depends_on:' <<<"$AGENTD_BLOCK"; then
  printf 'FAIL nexus-agentd must not depend on memory services\n' >&2
  exit 1
fi
printf 'PASS nexus-agentd has no implicit memory dependency\n'

if grep -q '^    depends_on:' <<<"$MCP_BLOCK"; then
  printf 'FAIL nexus-mcp must use an already-running nexus-agentd\n' >&2
  exit 1
fi
printf 'PASS nexus-mcp has no implicit service startup dependency\n'
