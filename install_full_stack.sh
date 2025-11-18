
#!/bin/bash
set -e

echo ""
echo "────────────────────────────────────"
echo "   Monero Node Installer (Patched)"
echo "────────────────────────────────────"
echo ""

STACK_DIR="$HOME/monero-node-stack"
CONFIG_DIR="$STACK_DIR/configs"
SYSTEMD_DIR="$STACK_DIR/systemd"
SCRIPTS_DIR="$STACK_DIR/scripts"
SNS_ARN="arn:aws:sns:us-west-2:381328847089:monero-alerts"

echo "[1/10] Updating apt..."
sudo apt update -y

echo "[2/10] Installing base packages..."
sudo apt install -y curl jq python3 python3-pip git lsb-release

echo "[3/10] Ensuring SNS Python libs installed..."
pip3 install boto3 requests --quiet

echo "[4/10] Skipping Monero CLI install (manual install detected)..."
if [ ! -f /opt/monero/monerod ]; then
   echo "ERROR: monerod not found in /opt/monero"
   exit 1
fi

echo "[5/10] Copying configs..."
mkdir -p ~/.monero
cp "$CONFIG_DIR/monerod.conf" ~/.monero/monerod.conf
cp "$CONFIG_DIR/p2pool.conf" ~/.monero/p2pool.conf

echo "[6/10] Installing systemd services..."
sudo cp "$SYSTEMD_DIR"/monerod-p2pool.service /etc/systemd/system/
sudo cp "$SYSTEMD_DIR"/xmrig.service /etc/systemd/system/
sudo systemctl daemon-reload

echo "[7/10] Enabling services..."
sudo systemctl enable monerod-p2pool.service
sudo systemctl enable xmrig.service

echo "[8/10] Installing health checks..."
sudo mkdir -p /opt/monero-health
sudo cp "$SCRIPTS_DIR/healthcheck.sh" /opt/monero-health/
sudo cp "$SCRIPTS_DIR/send_sms.py" /opt/monero-health/
sudo chmod +x /opt/monero-health/*.sh

echo "[9/10] Creating cron job..."
(crontab -l 2>/dev/null; echo "*/10 * * * * /opt/monero-health/healthcheck.sh") | crontab -

echo "[10/10] Starting services..."
sudo systemctl start monerod-p2pool.service
sudo systemctl start xmrig.service

echo ""
echo "────────────────────────────────────"
echo " Monero Node Installed Successfully"
echo "────────────────────────────────────"
echo ""
