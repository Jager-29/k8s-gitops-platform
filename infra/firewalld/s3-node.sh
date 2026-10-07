#!/usr/bin/env bash
set -euo pipefail

ZONE="$(firewall-cmd --get-default-zone)"

for source in 192.168.10.10/32 192.168.10.11/32; do
  firewall-cmd --permanent --zone="$ZONE" \
    --add-rich-rule="rule family=\"ipv4\" source address=\"$source\" port port=\"3900\" protocol=\"tcp\" accept"
done

firewall-cmd --reload
echo "OK: Garage S3 API (3900) reachable only from the Kubernetes nodes"
