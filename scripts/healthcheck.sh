#!/usr/bin/env bash
#
# healthcheck.sh - Monero / p2pool / XMRig healthcheck
# Runs via cron every 5 minutes (see installer)
#

set -euo pipefail

ENV_FILE="/etc/monero-node-stack.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

SNS_HELPER="/opt/monero-node-stack/scripts/send_sns.py"

send_alert() {
  local subject="$1"
  local body="$2"
  if command -v python3 >/dev/null 2>&1 && [[ -f "${SNS_HELPER}" ]]; then
    MONERO_SNS_ARN="${MONERO_SNS_ARN:-}" python3 "${SNS_HELPER}" "${subject}" "${body}" || true
  fi
}

MONEROD_OK=1
P2POOL_OK=1
XMRIG_OK=1

# 1) Monero RPC health
INFO_JSON="$(curl -s --max-time 5 http://127.0.0.1:18081/get_info || true)"

if [[ -z "${INFO_JSON}" ]]; then
  MONEROD_OK=0
else
  OFFLINE="$(echo "${INFO_JSON}" | jq -r '.offline // false')"
  HEIGHT="$(echo "${INFO_JSON}" | jq -r '.height // 0')"
  TGT_HEIGHT="$(echo "${INFO_JSON}" | jq -r '.target_height // 0')"

  if [[ "${OFFLINE}" == "true" ]]; then
    MONEROD_OK=0
  else
    if (( TGT_HEIGHT > 0 && TGT_HEIGHT - HEIGHT > 20 )); then
      MONEROD_OK=0
    fi
  fi
fi

# 2) p2pool status
if ! systemctl is-active --quiet p2pool.service; then
  P2POOL_OK=0
fi

# 3) XMRig status
if ! systemctl is-active --quiet xmrig.service; then
  XMRIG_OK=0
fi

# Decide whether to alert
if (( MONEROD_OK == 1 && P2POOL_OK == 1 && XMRIG_OK == 1 )); then
  # All good – silent success
  exit 0
fi

SUBJECT="Monero stack health issue on $(hostname)"
BODY="Monero stack healthcheck:

monerod:   $([[ ${MONEROD_OK} -eq 1 ]] && echo OK || echo FAIL)
p2pool:    $([[ ${P2POOL_OK} -eq 1 ]] && echo OK || echo FAIL)
xmrig:     $([[ ${XMRIG_OK} -eq 1 ]] && echo OK || echo FAIL)
"

if [[ -n "${INFO_JSON}" ]]; then
  BODY+="
get_info:
$(echo "${INFO_JSON}" | jq '.height, .target_height, .offline' 2>/dev/null || true)
"
fi

send_alert "${SUBJECT}" "${BODY}"
