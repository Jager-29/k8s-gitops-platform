import json
import os
import subprocess
import sys


def strict(node):
    if isinstance(node, dict):
        if node.get("type") == "object" and "properties" in node and not node.get("x-kubernetes-preserve-unknown-fields"):
            node.setdefault("additionalProperties", False)
        for value in node.values():
            strict(value)
    elif isinstance(node, list):
        for value in node:
            strict(value)
    return node


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: gen-crd-schemas.py OUTPUT_DIR [crds.json]  (without a file, reads kubectl get crd -o json)")
    out = sys.argv[1]
    if len(sys.argv) == 3:
        data = json.load(open(sys.argv[2]))
    else:
        data = json.loads(subprocess.run(["kubectl", "get", "crd", "-o", "json"], check=True, capture_output=True, text=True).stdout)
    count = 0
    for crd in data["items"]:
        group = crd["spec"]["group"]
        kind = crd["spec"]["names"]["kind"].lower()
        for version in crd["spec"]["versions"]:
            schema = version.get("schema", {}).get("openAPIV3Schema")
            if not schema:
                continue
            os.makedirs(os.path.join(out, group), exist_ok=True)
            path = os.path.join(out, group, "%s_%s.json" % (kind, version["name"]))
            with open(path, "w") as f:
                json.dump(strict(schema), f, indent=2, sort_keys=True)
                f.write("\n")
            count += 1
    print("%d schemas written to %s" % (count, out))


if __name__ == "__main__":
    main()
