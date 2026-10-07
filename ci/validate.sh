#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PY="${PYTHON:-${VENV:-$HOME/.venv-ci}/bin/python3}"
[ -x "$PY" ] || PY=python3

echo "== yamllint"
yamllint -s .

echo "== kubeconform"
mapfile -t FILES < <(find bootstrap apps argocd secret-stores traefik oauth2-proxy keycloak gitea gravitee monitoring backups velero roadmap \
  -type f -name '*.yaml' ! -name 'values-*.yaml' | sort)
kubeconform -strict -summary -kubernetes-version 1.30.14 \
  -schema-location default \
  -schema-location 'schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "${FILES[@]}"

echo "== monitoring rules and Alertmanager"
"$PY" tools/check-monitoring.py
