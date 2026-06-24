#!/usr/bin/env bash
#
# verify-live-stack.sh — orchestrator for live NexusIQ validation.
#
# Runs the health report (doctor.sh), then the real end-to-end flow
# (run-live-example.sh), and prints a final summary. Exits non-zero if either
# stage fails. This is the one command to prove a fresh self-host install
# actually works end to end — against the live stack, with no mocks.
#
set -euo pipefail

# ---- colored helpers --------------------------------------------------------
if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_RED=''; C_YELLOW=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_RESET=''
fi
ok()   { printf '%s✓%s %s\n'  "$C_GREEN"  "$C_RESET" "$*"; }
err()  { printf '%s✗%s %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; }
banner() {
  printf '\n%s%s═══════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%s%s %s%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"
  printf '%s%s═══════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
}

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

DOCTOR="${ROOT_DIR}/doctor.sh"
EXAMPLE="${ROOT_DIR}/run-live-example.sh"

for f in "$DOCTOR" "$EXAMPLE"; do
  if [[ ! -f "$f" ]]; then
    err "missing required script: $f"
    exit 1
  fi
done

DOCTOR_RC=0
EXAMPLE_RC=0

banner "Stage 1/2 — doctor (live health checks)"
if bash "$DOCTOR"; then
  ok "doctor passed"
else
  DOCTOR_RC=$?
  err "doctor reported failures (rc=${DOCTOR_RC})"
fi

banner "Stage 2/2 — run-live-example (real end-to-end flow)"
if [[ "$DOCTOR_RC" -ne 0 ]]; then
  err "skipping the live example because doctor failed — fix the FAILs above first."
  EXAMPLE_RC=1
else
  if bash "$EXAMPLE"; then
    ok "live example completed"
  else
    EXAMPLE_RC=$?
    err "live example reported failures (rc=${EXAMPLE_RC})"
  fi
fi

banner "Verdict"
if [[ "$DOCTOR_RC" -eq 0 && "$EXAMPLE_RC" -eq 0 ]]; then
  ok "NexusIQ live stack VERIFIED — health checks green and the real user flow completed end to end."
  exit 0
else
  err "NexusIQ live verification FAILED."
  printf '   %sdoctor:%s %s    %slive example:%s %s\n' \
    "$C_DIM" "$C_RESET" "$([[ $DOCTOR_RC -eq 0 ]] && echo PASS || echo FAIL)" \
    "$C_DIM" "$C_RESET" "$([[ $EXAMPLE_RC -eq 0 ]] && echo PASS || echo FAIL)"
  printf '   %sInspect logs with:%s ./logs.sh   |   bring the stack up with: ./start.sh\n' "$C_DIM" "$C_RESET"
  exit 1
fi
