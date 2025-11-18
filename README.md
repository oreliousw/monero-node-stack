# monero-node-stack

Full Monero node + p2pool (mini) + XMRig + SNS healthcheck stack for Ubuntu.

Target environment:

- Host: personal workstation (VMware)
- Guest: Ubuntu 24.04 LTS (HWE kernel)
- VM: 10 vCPUs, 16 GB RAM, 1 TB LVM disk
- User: `ubu`
- Hostname: `lino169`

## Components

- **Monero (monerod)** – full node, stores blockchain under `/home/ubu/.bitmonero`
- **p2pool (mini)** – decentralized mining pool on top of your node
- **XMRig** – CPU miner pointing at local p2pool (`127.0.0.1:3333`)
- **SNS alerts** – healthcheck script sends alerts to an AWS SNS topic

## Wallet

The stack is pre-configured to mine to:

`48GugGo1NLXDV59yV2n7kfdTZJSWqPHBvCBsS6Z48ZnqWLGnD4nbiT9CeRJNQtgeyBew7JfSiTp5fRqhe9E6cPBuLPHwTte`

You can change this in:

- `configs/p2pool.conf`
- `configs/xmrig.json`

Search for `WALLET_REPLACE_ME`.

## SNS Topic

By default, the installer uses:

`arn:aws:sns:us-west-2:381328847089:monero-alerts`

You can override at install time:

```bash
cd ~/monero-node-stack
chmod +x install_full_stack.sh
MONERO_SNS_ARN="arn:aws:sns:YOUR-REGION:YOUR-ACCOUNT:YOUR-TOPIC" sudo ./install_full_stack.sh
