#!/usr/bin/env bash
#
# validate-env.sh — assert the .env is complete, consistent, and not a mock.
#
# Fails (non-zero) with a clear ✗ list if any invariant is violated. Reads
# .env in a subshell so its values never leak into the caller's environment
# and are never printed.
#
set -euo pipefail

# ---- colored helpers --------------------------------------------------------
if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_RED=''; C_YELLOW=''; C_RESET=''
fi
ok()   { printf '%s✓%s %s\n'  "$C_GREEN"  "$C_RESET" "$*"; }
err()  { printf '%s✗%s %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; }
warn() { printf '%s⚠%s %s\n'  "$C_YELLOW" "$C_RESET" "$*"; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  err "No .env at ${ENV_FILE} — run install.sh first."
  exit 1
fi

# ---- safe .env loader -------------------------------------------------------
# Read KEY=VALUE pairs without executing the file. Strips inline export,
# surrounding quotes, and ignores comments/blank lines. Populates an
# associative array ENVV[KEY]=VALUE.
declare -A ENVV
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="$raw"
  # strip leading whitespace
  line="${line#"${line%%[![:space:]]*}"}"
  # skip comments / blanks
  [[ -z "$line" || "$line" == \#* ]] && continue
  # strip optional leading 'export '
  line="${line#export }"
  # must contain '='
  [[ "$line" != *=* ]] && continue
  key="${line%%=*}"
  val="${line#*=}"
  # trim whitespace around key
  key="${key//[[:space:]]/}"
  # strip a trailing inline comment only when value is unquoted (best-effort):
  # we keep it simple and do NOT strip, to avoid corrupting secrets containing #.
  # strip surrounding matched quotes
  if [[ "$val" == \"*\" ]]; then val="${val%\"}"; val="${val#\"}";
  elif [[ "$val" == \'*\' ]]; then val="${val%\'}"; val="${val#\'}"; fi
  [[ -z "$key" ]] && continue
  ENVV["$key"]="$val"
done < "$ENV_FILE"

# Convenience getter (empty string if unset).
v() { printf '%s' "${ENVV[$1]:-}"; }

ERRORS=0
fail() { err "$*"; ERRORS=$((ERRORS + 1)); }

# ---- 1. required vars present & non-empty -----------------------------------
REQUIRED=(
  POSTGRES_PASSWORD
  MANAGEMENT_API_KEY
  NEXUS_AEON_MANAGEMENT_KEY
  NEXUS_AEON_HMAC_KEY
  NEXUS_AGENTD_AUTH_TOKEN
  UPSTREAM_PROVIDER
)
for key in "${REQUIRED[@]}"; do
  if [[ -z "$(v "$key")" ]]; then
    fail "required variable ${key} is missing or empty"
  fi
done

# ---- 2. HMAC key length (>=64 hex chars / >=32 bytes) -----------------------
hmac="$(v NEXUS_AEON_HMAC_KEY)"
if [[ -n "$hmac" ]]; then
  if [[ ${#hmac} -lt 64 ]]; then
    fail "NEXUS_AEON_HMAC_KEY must be >=64 hex chars (>=32 bytes); got ${#hmac} chars"
  elif [[ ! "$hmac" =~ ^[0-9a-fA-F]+$ ]]; then
    fail "NEXUS_AEON_HMAC_KEY must be hexadecimal"
  fi
fi

# ---- 3. cross-wired management key ------------------------------------------
mgmt="$(v MANAGEMENT_API_KEY)"
aeon_mgmt="$(v NEXUS_AEON_MANAGEMENT_KEY)"
if [[ -n "$mgmt" && "$aeon_mgmt" != "$mgmt" ]]; then
  fail "NEXUS_AEON_MANAGEMENT_KEY must equal MANAGEMENT_API_KEY (cross-wired secret mismatch)"
fi

# ---- 4. provider key present for selected UPSTREAM_PROVIDER ------------------
provider="$(v UPSTREAM_PROVIDER)"
# normalize to lowercase
provider_lc="$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')"
case "$provider_lc" in
  openai)
    [[ -z "$(v OPENAI_API_KEY)" ]] && fail "UPSTREAM_PROVIDER=openai requires OPENAI_API_KEY to be set"
    ;;
  anthropic)
    [[ -z "$(v ANTHROPIC_API_KEY)" ]] && fail "UPSTREAM_PROVIDER=anthropic requires ANTHROPIC_API_KEY to be set"
    ;;
  gemini)
    [[ -z "$(v GEMINI_API_KEY)" ]] && fail "UPSTREAM_PROVIDER=gemini requires GEMINI_API_KEY to be set"
    ;;
  ollama)
    [[ -z "$(v UPSTREAM_BASE_URL)" ]] && fail "UPSTREAM_PROVIDER=ollama requires UPSTREAM_BASE_URL to be set"
    ;;
  "")
    fail "UPSTREAM_PROVIDER is empty — set one of: openai, anthropic, gemini, ollama"
    ;;
  *)
    fail "UPSTREAM_PROVIDER='${provider}' is not recognized (expected: openai, anthropic, gemini, ollama)"
    ;;
esac

# ---- 5. ALLOW_UNAUTH_MANAGEMENT must not be true ----------------------------
allow_unauth="$(printf '%s' "$(v ALLOW_UNAUTH_MANAGEMENT)" | tr '[:upper:]' '[:lower:]')"
if [[ "$allow_unauth" == "true" || "$allow_unauth" == "1" || "$allow_unauth" == "yes" ]]; then
  fail "ALLOW_UNAUTH_MANAGEMENT must NOT be true (unauthenticated management plane is forbidden)"
fi

# ---- 6. no mock/test/synthetic vars set to a truthy value -------------------
# Scan every key for the dangerous patterns; flag any that are truthy.
is_truthy() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on|enabled) return 0 ;;
    *) return 1 ;;
  esac
}
for key in "${!ENVV[@]}"; do
  case "$key" in
    MOCK_*|*SYNTHETIC*|TEST_MODE|BENCH_MODE)
      if is_truthy "${ENVV[$key]}"; then
        fail "mock/test variable ${key} is set to a truthy value — not allowed in a real deployment"
      fi
      ;;
  esac
done

# ---- verdict ----------------------------------------------------------------
if [[ "$ERRORS" -ne 0 ]]; then
  echo
  err "validate-env: ${ERRORS} problem(s) found — fix the above and re-run."
  exit 1
fi

ok "validate-env: all required variables present, provider key OK, secrets cross-wired, no mocks."
