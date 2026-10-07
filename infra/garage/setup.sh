#!/usr/bin/env bash
set -euo pipefail

export GARAGE_CONFIG_FILE=/etc/garage.toml

install -d -m 0750 -o root -g garage /etc/garage
for f in rpc_secret admin_token metrics_token; do
  if [ ! -s "/etc/garage/$f" ]; then
    umask 027
    openssl rand -hex 32 > "/etc/garage/$f"
    chgrp garage "/etc/garage/$f"
  fi
done
install -d -m 0750 -o garage -g garage /var/lib/garage/meta /var/lib/garage/data

systemctl daemon-reload
systemctl enable --now garage
sleep 3

NODE_ID="$(garage node id -q | cut -d@ -f1)"
if ! garage layout show | grep -q "$NODE_ID"; then
  garage layout assign -z dc1 -c 90G "$NODE_ID"
  garage layout apply --version 1
fi

for bucket in velero cnpg openbao app-dumps; do
  garage bucket info "$bucket" >/dev/null 2>&1 || garage bucket create "$bucket"
  garage key info "$bucket-key" >/dev/null 2>&1 || garage key create "$bucket-key"
  garage bucket allow --read --write --owner "$bucket" --key "$bucket-key"
done

garage status
echo "Store each key in OpenBao, never in Git:"
echo "  garage key info --show-secret <bucket>-key"
echo "  bao kv put secret/backup/<bucket> access_key=- secret_key=-"
