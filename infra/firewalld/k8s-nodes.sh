#!/usr/bin/env bash
set -euo pipefail

ZONE="$(firewall-cmd --get-default-zone)"

for port in 80/tcp 443/tcp 6443/tcp 2379-2380/tcp 10250/tcp 10257/tcp 10259/tcp 4240/tcp 8472/udp 30080/tcp 30443/tcp; do
  firewall-cmd --permanent --zone="$ZONE" --add-port="$port"
done

for source in 10.244.0.0/16 192.168.10.10/32 192.168.10.11/32; do
  firewall-cmd --permanent --zone="$ZONE" \
    --add-rich-rule="rule family=\"ipv4\" source address=\"$source\" port port=\"9100\" protocol=\"tcp\" accept"
done

firewall-cmd --reload

if iptables -t nat -S PREROUTING | grep -q -- '-j REDIRECT'; then
  echo "FAILED: a NAT REDIRECT rule exists in PREROUTING, it hijacks pod traffic on 80/443:" >&2
  iptables -t nat -S PREROUTING | grep -- '-j REDIRECT' >&2
  exit 1
fi
echo "OK: firewalld rules applied on zone $ZONE, no NAT REDIRECT in PREROUTING"
