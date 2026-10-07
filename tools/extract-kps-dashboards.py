import os
import re
import sys

import yaml

KEEP = re.compile(r"^Kubernetes / (Compute Resources / (?!Multi-Cluster).+|Networking / Cluster)$")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: helm template kps kube-prometheus-stack --repo https://prometheus-community.github.io/helm-charts "
                 "--version 91.9.0 --set fullnameOverride=kps --set grafana.enabled=false "
                 "--set grafana.forceDeployDashboards=true | python3 tools/extract-kps-dashboards.py monitoring")
    out = sys.argv[1]
    written = 0
    for doc in yaml.safe_load_all(sys.stdin):
        if not doc or doc.get("kind") != "ConfigMap":
            continue
        if doc.get("metadata", {}).get("labels", {}).get("grafana_dashboard") != "1":
            continue
        for key, body in doc.get("data", {}).items():
            title_match = re.search(r'"title":\s*"([^"]+)"\s*,\s*"uid"', body) or re.search(r'"title":\s*"(Kubernetes / [^"]+)"', body)
            if not title_match or not KEEP.match(title_match.group(1)):
                continue
            name = "dashboard-" + key.replace(".json", "")
            cm = {
                "apiVersion": "v1",
                "kind": "ConfigMap",
                "metadata": {
                    "name": name,
                    "namespace": "monitoring",
                    "labels": {"grafana_dashboard": "1"},
                    "annotations": {"grafana_folder": "Kubernetes"},
                },
                "data": {key: body},
            }
            path = os.path.join(out, name + ".yaml")
            with open(path, "w") as f:
                yaml.safe_dump(cm, f, sort_keys=False, width=1000000, allow_unicode=True)
            print("%s  %s" % (path, title_match.group(1)))
            written += 1
    if written == 0:
        sys.exit("no dashboard matched: check the chart output")


if __name__ == "__main__":
    main()
