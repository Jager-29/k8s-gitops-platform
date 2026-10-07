#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo "usage: $0 NAMESPACE SECRET BUCKET PREFIX OUTPUT_FILE" >&2
  echo "example: $0 gitea app-dumps-s3 app-dumps gitea/ /dev/shm/gitea-dump.tar.gz" >&2
  exit 2
fi

NS="$1"
SECRET="$2"
BUCKET="$3"
PREFIX="$4"
OUT="$5"
ENDPOINT="${S3_ENDPOINT:-http://192.168.10.13:3900}"
POD="s3-latest-$(date +%s)"

OVERRIDES="$(python3 - "$POD" "$SECRET" "$ENDPOINT" <<'PY'
import json, sys
pod, secret, endpoint = sys.argv[1:4]
print(json.dumps({"spec": {"containers": [{
    "name": pod,
    "image": "amazon/aws-cli:2.37.7",
    "command": ["sleep", "600"],
    "envFrom": [{"secretRef": {"name": secret}}],
    "env": [
        {"name": "AWS_DEFAULT_REGION", "value": "garage"},
        {"name": "AWS_REQUEST_CHECKSUM_CALCULATION", "value": "when_required"},
        {"name": "AWS_RESPONSE_CHECKSUM_VALIDATION", "value": "when_required"},
        {"name": "S3_ENDPOINT", "value": endpoint},
        {"name": "HOME", "value": "/tmp"}
    ]
}]}}))
PY
)"

kubectl -n "$NS" run "$POD" --image=amazon/aws-cli:2.37.7 --restart=Never --overrides="$OVERRIDES" >/dev/null
trap 'kubectl -n "$NS" delete pod "$POD" --wait=false >/dev/null 2>&1 || true' EXIT
kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=120s >/dev/null

KEY="$(kubectl -n "$NS" exec "$POD" -- sh -c "aws --endpoint-url \"\$S3_ENDPOINT\" s3 ls \"s3://$BUCKET/$PREFIX\" | grep -v ' PRE ' | sort | tail -n 1" | awk '{print $4}')"
if [ -z "$KEY" ]; then
  echo "STOP: no object found in s3://$BUCKET/$PREFIX" >&2
  exit 1
fi

REMOTE_SIZE="$(kubectl -n "$NS" exec "$POD" -- sh -c "aws --endpoint-url \"\$S3_ENDPOINT\" s3 ls \"s3://$BUCKET/$PREFIX$KEY\"" | awk '{print $3}')"
umask 077
kubectl -n "$NS" exec "$POD" -- aws --endpoint-url "$ENDPOINT" s3 cp "s3://$BUCKET/$PREFIX$KEY" - > "$OUT"
LOCAL_SIZE="$(stat -c %s "$OUT")"

if [ "$REMOTE_SIZE" = "$LOCAL_SIZE" ]; then
  echo "OK: s3://$BUCKET/$PREFIX$KEY -> $OUT ($LOCAL_SIZE bytes)"
else
  echo "FAILED: size mismatch (remote $REMOTE_SIZE, local $LOCAL_SIZE)" >&2
  exit 1
fi
