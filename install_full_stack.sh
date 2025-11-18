#!/usr/bin/env bash
#
# monero-node-stack – Full installer
# - Monero CLI (monerod)
# - p2pool (mini chain)
# - XMRig CPU miner
# - SNS healthcheck wiring
#
# Target:
#   Host:   lino169
#   User:   ubu
#   OS:     Ubuntu 24.04 LTS (HWE)
#   Disk:   1 TB LVM
#

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run this script with sudo:"
  echo "  sudo ./install_full_stack.sh"
  exit 1
fi

TARGET_USER="${SUDO_USER:-ubu}"
TARGET_HOME="/home/${TARGET_USER}"
STACK_DIR="/opt/monero-node-stack"
MONERO_DIR="/opt/monero"
P2POOL_DIR="/opt/p2pool"
XMRIG_DIR="/opt/xmrig"

MONERO_DATA_DIR="${TARGET_HOME}/.bitmonero"
MONERO_SNS_ARN_DEFAULT="arn:aws:sns:us-west-2:381328847089:monero-alerts"
MONERO_SNS_ARN="${MONERO_SNS_ARN:-$MONERO_SNS_ARN_DEFAULT}"

WALLET_ADDR="48GugGo1NLXDV59yV2n7kfdTZJSWqPHBvCBsS6Z48ZnqWLGnD4nbiT9CeRJNQtgeyBew7JfSiTp5fRqhe9E6cPBuLPHwTte"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "────────────────────────────────────────"
echo " monero-node-stack installer"
echo " User:        ${TARGET_USER}"
echo " Home:        ${TARGET_HOME}"
echo " Hostname:    $(hostname)"
echo " STACK_DIR:   ${STACK_DIR}"
echo " MONERO_SNS_ARN: ${MONERO_SNS_ARN}"
echo "────────────────────────────────────────"
sleep 2

echo "[1/10] Installing base dependencies..."
apt-get update -y
apt-get install -y \
  curl wget git jq \
  ca-certificates \
  python3 python3-pip \
  systemd \
  build-essential \
  libuv1-dev libssl-dev libhwloc-dev pkg-config

pip3 install --upgrade boto3 >/dev/null 2>&1 || true

echo "[2/10] Syncing repo into ${STACK_DIR}..."
mkdir -p "${STACK_DIR}"
rsync -a --delete "${SCRIPT_DIR}/" "${STACK_DIR}/"
chown -R "${TARGET_USER}:${TARGET_USER}" "${STACK_DIR}"

echo "[3/10] Creating core directories..."
mkdir -p "${MONERO_DIR}" "${P2POOL_DIR}" "${XMRIG_DIR}" "${MONERO_DATA_DIR}"
chown -R "${TARGET_USER}:${TARGET_USER}" "${MONERO_DIR}" "${P2POOL_DIR}" "${XMRIG_DIR}" "${MONERO_DATA_DIR}"

echo "[4/10] Installing Monero CLI..."
cd /tmp
MONERO_TARBALL="monero-linux-x64-latest.tar.bz2"
wget -q "https://downloads.getmonero.org/cli/${MONERO_TARBALL}"
tar -xf "${MONERO_TARBALL}"
MONERO_EXTRACT_DIR="$(find . -maxdepth 1 -type d -name 'monero-*' | head -n1)"
if [[ -z "${MONERO_EXTRACT_DIR}" ]]; then
  echo "Failed to locate extracted Monero directory"
  exit 1
fi
cp -f "${MONERO_EXTRACT_DIR}/monerod" "${MONERO_DIR}/"
cp -f "${MONERO_EXTRACT_DIR}/monero-wallet-cli" "${MONERO_DIR}/" || true
cp -f "${MONERO_EXTRACT_DIR}/monero-wallet-rpc" "${MONERO_DIR}/" || true
chmod +x "${MONERO_DIR}/monerod" "${MONERO_DIR}/"monero-wallet* || true

echo "[5/10] Installing p2pool (mini)..."
cd /tmp
P2POOL_URL="$(curl -s https://api.github.com/repos/SChernykh/p2pool/releases/latest \
  | jq -r '.assets[] | select(.name | test("linux-x86_64")) | .browser_download_url' | head -n1)"
if [[ -z "${P2POOL_URL}" ]]; then
  echo "Could not determine latest p2pool linux-x86_64 asset URL"
  exit 1
fi
P2POOL_TARBALL="$(basename "${P2POOL_URL}")"
wget -q "${P2POOL_URL}"
tar -xf "${P2POOL_TARBALL}" -C "${P2POOL_DIR}" --strip-components=1 || {
  # some releases ship a single binary
  mv "${P2POOL_TARBALL}" "${P2POOL_DIR}/p2pool" || true
}
if [[ ! -x "${P2POOL_DIR}/p2pool" ]]; then
  chmod +x "${P2POOL_DIR}/p2pool" || true
fi

echo "[6/10] Installing XMRig..."
cd /tmp
XMRIG_URL="$(curl -s https://api.github.com/repos/xmrig/xmrig/releases/latest \
  | jq -r '.assets[] | select(.name | test("linux-x64.tar.gz$")) | .browser_download_url' | head -n1)"
if [[ -z "${XMRIG_URL}" ]]; then
  echo "Could not determine latest XMRig linux-x64 asset URL"
  exit 1
fi
XMRIG_TARBALL="$(basename "${XMRIG_URL}")"
wget -q "${XMRIG_URL}"
tar -xf "${XMRIG_TARBALL}"
XMRIG_EXTRACT_DIR="$(find . -maxdepth 1 -type d -name 'xmrig*' | head -n1)"
if [[ -z "${XMRIG_EXTRACT_DIR}" ]]; then
  echo "Failed to locate extracted XMRig directory"
  exit 1
fi
cp -f "${XMRIG_EXTRACT_DIR}/xmrig" "${XMRIG_DIR}/"
chmod +x "${XMRIG_DIR}/xmrig"

echo "[7/10] Installing configs..."
mkdir -p /etc/monero-node-stack
cp -f "${STACK_DIR}/configs/monerod.conf" /etc/monerod.conf
cp -f "${STACK_DIR}/configs/p2pool.conf" /etc/monero-node-stack/p2pool.conf
cp -f "${STACK_DIR}/configs/xmrig.json" /etc/monero-node-stack/xmrig.json

# Inject correct username & wallet into configs if needed
sed -i "s|/home/REPLACE_USER/.bitmonero|${MONERO_DATA_DIR}|g" /etc/monerod.conf
sed -i "s|WALLET_REPLACE_ME|${WALLET_ADDR}|g" /etc/monero-node-stack/p2pool.conf
sed -i "s|WALLET_REPLACE_ME|${WALLET_ADDR}|g" /etc/monero-node-stack/xmrig.json

echo "[8/10] Installing helper scripts..."
mkdir -p /opt/monero-node-stack/scripts
cp -f "${STACK_DIR}/scripts/send_sns.py" /opt/monero-node-stack/scripts/send_sns.py
cp -f "${STACK_DIR}/scripts/healthcheck.sh" /opt/monero-node-stack/scripts/healthcheck.sh
chmod +x /opt/monero-node-stack/scripts/healthcheck.sh
chown -R "${TARGET_USER}:${TARGET_USER}" /opt/monero-node-stack

# Env file for SNS + paths
ENV_FILE="/etc/monero-node-stack.env"
cat > "${ENV_FILE}" <<EOF
MONERO_SNS_ARN="${MONERO_SNS_ARN}"
MONERO_DATA_DIR="${MONERO_DATA_DIR}"
MONERO_DIR="${MONERO_DIR}"
P2POOL_DIR="${P2POOL_DIR}"
XMRIG_DIR="${XMRIG_DIR}"
WALLET_ADDR="${WALLET_ADDR}"
EOF

echo "[9/10] Installing systemd units..."
cp -f "${STACK_DIR}/systemd/monerod.service" /etc/systemd/system/monerod.service
cp -f "${STACK_DIR}/systemd/p2pool.service"  /etc/systemd/system/p2pool.service
cp -f "${STACK_DIR}/systemd/xmrig.service"   /etc/systemd/system/xmrig.service

systemctl daemon-reload
systemctl enable monerod.service
systemctl enable p2pool.service
systemctl enable xmrig.service

echo "[10/10] Starting services..."
systemctl start monerod.service
sleep 5
systemctl start p2pool.service
sleep 5
systemctl start xmrig.service

echo "Setting up cron-based healthcheck (every 5 minutes)..."
CRON_LINE="*/5 * * * * /opt/monero-node-stack/scripts/healthcheck.sh >/var/log/monero-node-stack-health.log 2>&1"
( crontab -u "${TARGET_USER}" -l 2>/dev/null | grep -v 'monero-node-stack/scripts/healthcheck.sh' ; echo "${CRON_LINE}" ) | crontab -u "${TARGET_USER}" -

echo "────────────────────────────────────────"
echo " Installation complete."
echo " Services:"
echo "   systemctl status monerod"
echo "   systemctl status p2pool"
echo "   systemctl status xmrig"
echo
echo " Logs:"
echo "   journalctl -u monerod -f"
echo "   journalctl -u p2pool -f"
echo "   journalctl -u xmrig -f"
echo
echo " Healthcheck runs every 5 minutes via cron for user: ${TARGET_USER}"
echo "────────────────────────────────────────"
