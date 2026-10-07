#!/usr/bin/env bash
set -euo pipefail

DEST="${1:-$HOME/.local/bin}"
mkdir -p "$DEST"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() {
  local url="$1" sum="$2" file="$WORK/$(basename "$1")"
  curl -fsSL --connect-timeout 10 --retry 3 --retry-delay 5 -o "$file" "$url"
  echo "$sum  $file" | sha256sum -c - >/dev/null
  echo "$file"
}

f="$(fetch https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz 551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb)"
tar -xzf "$f" -C "$DEST" gitleaks

f="$(fetch https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz 9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883)"
tar -xzf "$f" -C "$DEST" kubeconform

f="$(fetch https://github.com/prometheus/prometheus/releases/download/v3.7.3/prometheus-3.7.3.linux-amd64.tar.gz fc9e5da126817438cf2820d9a7206c75e3122802ba8d20add3a6219a59ca6913)"
tar -xzf "$f" -C "$DEST" --strip-components=1 prometheus-3.7.3.linux-amd64/promtool

f="$(fetch https://github.com/prometheus/alertmanager/releases/download/v0.34.1/alertmanager-0.34.1.linux-amd64.tar.gz 265b9d1e55ef0d5306a436018af6d2b686c2ce051f03d968f7464ecb1372a7e8)"
tar -xzf "$f" -C "$DEST" --strip-components=1 alertmanager-0.34.1.linux-amd64/amtool

python3 -m venv "${VENV:-$HOME/.venv-ci}"
"${VENV:-$HOME/.venv-ci}/bin/pip" install --quiet yamllint==1.38.0 PyYAML==6.0.3
ln -sf "${VENV:-$HOME/.venv-ci}/bin/yamllint" "$DEST/yamllint"

echo "tools installed in $DEST"
