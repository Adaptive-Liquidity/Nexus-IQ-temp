#!/usr/bin/env bash
#
# start.sh — bring up the core NexusIQ stack and wait for it to be healthy.
#
# Starts postgres, aeon, aeon-worker, and nexus-agentd (the always-on
# services). nexus-mcp
# is on the `tools` profile and runs on demand, so it is intentionally not
# started here.
#
set -euo pipefail

# ---- colored helpers --------------------------------------------------------
if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_RED=''; C_YELLOW=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_RESET=''
fi
ok()    { printf '%s✓%s %s\n'  "$C_GREEN"  "$C_RESET" "$*"; }
err()   { printf '%s✗%s %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; }
warn()  { printf '%s⚠%s %s\n'  "$C_YELLOW" "$C_RESET" "$*"; }
step()  { printf '\n%s%s▸ %s%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

compose() { docker compose "$@"; }

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  err "No .env found. Run ./install.sh first."
  exit 1
fi

step "Starting core services (postgres, aeon, aeon-worker, nexus-agentd)"
if ! compose up -d postgres aeon aeon-worker nexus-agentd; then
  err "docker compose up failed."
  exit 1
fi
ok "containers started (detached)"

step "Waiting for health"
if ! bash "${ROOT_DIR}/scripts/wait-for-health.sh"; then
  err "Services did not become healthy. Check './logs.sh' for details."
  exit 1
fi

step "Endpoints"
bash "${ROOT_DIR}/scripts/print-urls.sh"

printf '%sMCP:%s generate a client config with %s./generate-mcp-config.sh%s\n' \
  "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
echo
ok "NexusIQ is up."
