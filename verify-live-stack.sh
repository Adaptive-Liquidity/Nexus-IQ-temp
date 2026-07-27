#!/usr/bin/env bash
#
# verify-live-stack.sh — prove the live service set selected by configuration.
#
set -euo pipefail

if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
  C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_RED=''; C_CYAN=''; C_BOLD=''; C_RESET=''
fi
ok()  { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
err() { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
banner() { printf '\n%s%s%s%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
ENV_FILE="${ROOT_DIR}/.env"

# shellcheck source=scripts/runtime-mode.sh
source "${ROOT_DIR}/scripts/runtime-mode.sh"
nexusiq_resolve_runtime_mode "$ENV_FILE"

banner "Doctor — required live health gate"
if ! bash "${ROOT_DIR}/doctor.sh"; then
  err "doctor failed; live verification stopped"
  exit 1
fi
ok "doctor passed"

if [[ "$NEXUSIQ_MEMORY_MODE" == "disabled" ]]; then
  banner "Nexus MCP handshake and tool listing"
  bash "${ROOT_DIR}/scripts/smoke-nexus-execute.sh"

  banner "Nexus WASM execution and Proof Capsule"
  bash "${ROOT_DIR}/scripts/smoke-proof-capsule.sh"

  banner "Verdict"
  ok "Nexus execution/proof plane verified; memory intentionally disabled."
else
  banner "Full NexusIQ memory-enabled live example"
  if ! bash "${ROOT_DIR}/run-live-example.sh"; then
    err "memory-enabled live example failed"
    exit 1
  fi
  banner "Verdict"
  ok "NexusIQ memory-enabled live stack verified end to end."
fi
