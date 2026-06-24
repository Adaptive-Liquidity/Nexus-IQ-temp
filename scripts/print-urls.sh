#!/usr/bin/env bash
#
# print-urls.sh — print the live endpoints for the running NexusIQ stack.
#
# No secrets are printed. The management base requires the X-Management-Key
# header (value lives in .env as MANAGEMENT_API_KEY) — we name the header, not
# the value.
#
set -euo pipefail

# ---- colored helpers --------------------------------------------------------
if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_RESET=''
fi
ok() { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }

AEON_HOST="127.0.0.1"
AEON_PORT="8080"
AEON_BASE="http://${AEON_HOST}:${AEON_PORT}"

printf '\n%s%sNexusIQ — live endpoints%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
printf '%s─────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"

printf '  %sAEON-IQ API%s        %s\n'        "$C_BOLD" "$C_RESET" "$AEON_BASE"
printf '  %sHealth check%s       %s/health\n' "$C_BOLD" "$C_RESET" "$AEON_BASE"
printf '  %sManagement base%s    %s/api/v1   %s(requires header: X-Management-Key)%s\n' \
  "$C_BOLD" "$C_RESET" "$AEON_BASE" "$C_DIM" "$C_RESET"

printf '\n%s%sQuick checks%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
printf '%s─────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
printf '  Health:      %scurl -fsS %s/health%s\n' "$C_DIM" "$AEON_BASE" "$C_RESET"
printf '  Management:  %scurl -fsS -H "X-Management-Key: $MANAGEMENT_API_KEY" %s/api/v1/...%s\n' \
  "$C_DIM" "$AEON_BASE" "$C_RESET"

printf '\n%s%sMCP (nexus-mcp, stdio)%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
printf '%s─────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
printf '  Run on demand: %sdocker compose --profile tools run --rm nexus-mcp%s\n' "$C_DIM" "$C_RESET"
printf '  MCP config:    %s./generate-mcp-config.sh%s\n' "$C_DIM" "$C_RESET"

printf '\n%sNote:%s Postgres is not published to the host; AEON-IQ is bound to %s only.\n' \
  "$C_BOLD" "$C_RESET" "$AEON_HOST"
echo
