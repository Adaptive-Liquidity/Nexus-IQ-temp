#!/usr/bin/env bash
#
# generate-secrets.sh — fill blank secrets in .env, in place.
#
# For each managed secret that is blank in .env, generate a strong random
# value and rewrite the line. Cross-wire NEXUS_AEON_MANAGEMENT_KEY to the
# generated MANAGEMENT_API_KEY. NEXUS_AEON_HMAC_KEY is forced to 64 hex chars
# (32 bytes). Secret VALUES are never printed — only the names of generated
# secrets are reported.
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

# ---- locate .env ------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  err "No .env at ${ENV_FILE} — run install.sh first (it creates .env from .env.example)."
  exit 1
fi

# ---- random hex generator (openssl preferred, /dev/urandom fallback) --------
# Args: $1 = number of bytes. Emits 2*N lowercase hex chars, no newline issues.
rand_hex() {
  local bytes="$1"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes"
  elif command -v xxd >/dev/null 2>&1; then
    head -c "$bytes" /dev/urandom | xxd -p | tr -d '\n'
  elif command -v od >/dev/null 2>&1; then
    head -c "$bytes" /dev/urandom | od -An -tx1 | tr -d ' \n'
  else
    err "No openssl, xxd, or od available to generate randomness."
    exit 1
  fi
}

# ---- read current value of a key from .env (raw, may be empty) --------------
# Matches: KEY=value  (ignores surrounding quotes for emptiness test).
get_val() {
  local key="$1" line val
  line="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 || true)"
  val="${line#*=}"
  # strip surrounding single/double quotes for the emptiness check
  val="${val%\"}"; val="${val#\"}"
  val="${val%\'}"; val="${val#\'}"
  printf '%s' "$val"
}

# ---- check whether key exists at all ----------------------------------------
has_key() {
  grep -qE "^$1=" "$ENV_FILE"
}

# ---- set KEY=value in .env, in place (create if missing) --------------------
# Uses a temp file + awk so the value is never exposed on a command line and
# special characters in the value are written literally (no shell/sed escaping
# pitfalls). The value is passed via environment, not argv.
set_val() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp "${ENV_FILE}.XXXXXX")"
  if has_key "$key"; then
    KEY="$key" VALUE="$value" awk '
      BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VALUE"]; done = 0 }
      {
        if ($0 ~ "^" k "=") { print k "=" v; done = 1 }
        else { print }
      }
      END { if (!done) print k "=" v }
    ' "$ENV_FILE" > "$tmp"
  else
    cat "$ENV_FILE" > "$tmp"
    KEY="$key" VALUE="$value" awk 'BEGIN { print ENVIRON["KEY"] "=" ENVIRON["VALUE"] }' >> "$tmp"
  fi
  # Preserve restrictive perms across the swap.
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$ENV_FILE"
}

# ---- generate one secret if blank -------------------------------------------
# Args: $1 = key, $2 = byte length (default 32).
ensure_secret() {
  local key="$1" bytes="${2:-32}" cur
  cur="$(get_val "$key")"
  if [[ -z "$cur" ]]; then
    set_val "$key" "$(rand_hex "$bytes")"
    ok "generated ${key}"
  else
    warn "${key} already set — left unchanged"
  fi
}

echo "Generating missing secrets in .env (values are never printed)…"

# POSTGRES_PASSWORD: 32 random bytes -> 64 hex chars (URL-safe, no specials).
ensure_secret POSTGRES_PASSWORD 32

# MANAGEMENT_API_KEY: 32 random bytes -> 64 hex chars.
ensure_secret MANAGEMENT_API_KEY 32

# NEXUS_AGENTD_AUTH_TOKEN: 32 random bytes -> 64 hex chars.
ensure_secret NEXUS_AGENTD_AUTH_TOKEN 32

# NEXUS_AEON_HMAC_KEY: MUST be >=32 bytes / >=64 hex chars. Force exactly 64
# hex chars whenever blank OR too short.
hmac_cur="$(get_val NEXUS_AEON_HMAC_KEY)"
if [[ -z "$hmac_cur" ]]; then
  set_val NEXUS_AEON_HMAC_KEY "$(rand_hex 32)"
  ok "generated NEXUS_AEON_HMAC_KEY"
elif [[ ${#hmac_cur} -lt 64 ]]; then
  set_val NEXUS_AEON_HMAC_KEY "$(rand_hex 32)"
  warn "NEXUS_AEON_HMAC_KEY was shorter than 64 hex chars — regenerated"
else
  warn "NEXUS_AEON_HMAC_KEY already set — left unchanged"
fi

# Cross-wire: NEXUS_AEON_MANAGEMENT_KEY MUST equal MANAGEMENT_API_KEY.
mgmt_val="$(get_val MANAGEMENT_API_KEY)"
if [[ -z "$mgmt_val" ]]; then
  err "MANAGEMENT_API_KEY is empty after generation — cannot cross-wire NEXUS_AEON_MANAGEMENT_KEY."
  exit 1
fi
aeon_mgmt_cur="$(get_val NEXUS_AEON_MANAGEMENT_KEY)"
if [[ "$aeon_mgmt_cur" != "$mgmt_val" ]]; then
  set_val NEXUS_AEON_MANAGEMENT_KEY "$mgmt_val"
  ok "cross-wired NEXUS_AEON_MANAGEMENT_KEY = MANAGEMENT_API_KEY"
else
  ok "NEXUS_AEON_MANAGEMENT_KEY already matches MANAGEMENT_API_KEY"
fi

# DATABASE_URL: prefer compose interpolation. Do NOT embed the password here.
# If a stale DATABASE_URL exists with an inline password, warn (we intentionally
# leave compose to interpolate ${POSTGRES_PASSWORD}). We do not write the
# password into DATABASE_URL.
db_url="$(get_val DATABASE_URL)"
if [[ -n "$db_url" && "$db_url" != *'${POSTGRES_PASSWORD}'* && "$db_url" == *':'*'@'* ]]; then
  warn "DATABASE_URL appears to embed a literal password — prefer \${POSTGRES_PASSWORD} interpolation in compose."
fi

# Lock down the file: secrets at rest must be 0600.
chmod 600 "$ENV_FILE"
ok "secured ${ENV_FILE} (chmod 600)"

echo "Secret generation complete."
