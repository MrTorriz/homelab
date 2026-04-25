#!/usr/bin/env bash
# cert-expiry.sh — Check SSL certificate expiry via Nginx Proxy Manager API.
# Requires: ${NPM_URL} (e.g. http://npm:81), ${NPM_USER}, ${NPM_SECRET} from .env.
# Alerts via ntfy when any cert expires within 30 days (high priority below 14).
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

LOG_DIR="${LOG_DIR:-$HOME/logs}"
LOG_FILE="${LOG_DIR}/cert_expiry.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

mkdir -p "$LOG_DIR"

# Read credentials from .env if present
ENV_FILE="${ENV_FILE:-$(dirname "$0")/../.env}"
[[ -f "$ENV_FILE" ]] && . "$ENV_FILE"
NPM_URL="${NPM_URL:-http://${LAN_IP:-192.168.1.10}:81}"
NPM_USER="${NPM_USER:-admin@example.com}"
NPM_SECRET="${NPM_SECRET:-}"

if [[ -z "$NPM_SECRET" ]]; then
  echo "[$TIMESTAMP] ERR NPM_SECRET missing — set in scripts/.env" >> "$LOG_FILE"
  exit 1
fi

# Authenticate against NPM
TOKEN=$(curl -sf --max-time 10 -X POST "${NPM_URL}/api/tokens" \
  -H "Content-Type: application/json" \
  -d "{\"identity\":\"$NPM_USER\",\"secret\":\"$NPM_SECRET\"}" \
  | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [[ -z "$TOKEN" ]]; then
  echo "[$TIMESTAMP] ERR Could not authenticate against NPM" >> "$LOG_FILE"
  exit 1
fi

# Fetch certificates
CERTS=$(curl -sf --max-time 10 "${NPM_URL}/api/nginx/certificates" \
  -H "Authorization: Bearer $TOKEN")

WARNINGS=()

while IFS= read -r line; do
  DOMAIN=$(echo "$line" | cut -d'|' -f1)
  EXPIRES=$(echo "$line" | cut -d'|' -f2)

  EXPIRE_EPOCH=$(date -d "$EXPIRES" +%s 2>/dev/null)
  NOW_EPOCH=$(date +%s)
  DAYS=$(( (EXPIRE_EPOCH - NOW_EPOCH) / 86400 ))

  if [[ $DAYS -lt 30 ]]; then
    WARNINGS+=("$DOMAIN — $DAYS days left (${EXPIRES})")
    echo "[$TIMESTAMP] WARN $DOMAIN expires in $DAYS days ($EXPIRES)" >> "$LOG_FILE"
  else
    echo "[$TIMESTAMP] OK   $DOMAIN — $DAYS days left" >> "$LOG_FILE"
  fi
done < <(echo "$CERTS" | python3 -c "
import sys, json
certs = json.load(sys.stdin)
for c in certs:
    domains = ','.join(c.get('domain_names', []))
    expires = c.get('expires_on', '')
    print(f'{domains}|{expires}')
" 2>/dev/null)

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  MSG=$(printf '%s\n' "${WARNINGS[@]}")
  DAYS_MIN=$(printf '%s\n' "${WARNINGS[@]}" | grep -oP '\d+ days' | sort -n | head -1)
  PRIORITY="default"
  [[ "${DAYS_MIN%% *}" -lt 14 ]] && PRIORITY="high"
  ntfy_send "SSL cert expiring soon" "$MSG" "$PRIORITY" "lock,warning"
fi

log_rotate "$LOG_FILE" 200
