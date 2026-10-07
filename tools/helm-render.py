import glob
import os
import shutil
import subprocess
import sys
import tempfile

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sources(app):
    spec = app["spec"]
    items = spec.get("sources") or [spec["source"]]
    return [s for s in items if s.get("chart")]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "render")
    only = set(sys.argv[2:])
    if shutil.which("helm") is None:
        sys.exit("helm not found in PATH")
    os.makedirs(out, exist_ok=True)
    failed = []
    for path in sorted(glob.glob(os.path.join(ROOT, "apps", "*.yaml"))):
        app = yaml.safe_load(open(path))
        name = app["metadata"]["name"]
        if only and name not in only:
            continue
        namespace = app["spec"]["destination"]["namespace"]
        for index, src in enumerate(sources(app)):
            helm = src.get("helm", {})
            release = helm.get("releaseName", name)
            target = os.path.join(out, "%s-%d-%s.yaml" % (name, index, src["chart"]))
            with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as values:
                yaml.safe_dump(helm.get("valuesObject", {}), values, allow_unicode=True)
            cmd = ["helm", "template", release, src["chart"], "--repo", src["repoURL"], "--version", str(src["targetRevision"]),
                   "--namespace", namespace, "--kube-version", "1.30.14", "--include-crds", "-f", values.name]
            result = subprocess.run(cmd, capture_output=True, text=True)
            os.unlink(values.name)
            if result.returncode != 0:
                print("FAILED %s source %d (%s): %s" % (name, index, src["chart"], result.stderr.strip()))
                failed.append(name)
                continue
            with open(target, "w") as f:
                f.write(result.stdout)
            warnings = [line for line in result.stderr.splitlines() if line.strip()]
            print("OK    %s source %d (%s %s) -> %s%s" % (name, index, src["chart"], src["targetRevision"], os.path.relpath(target, ROOT),
                                                       "  [%d helm warnings]" % len(warnings) if warnings else ""))
            for line in warnings:
                print("      " + line)
    if failed:
        sys.exit("render failed for: " + ", ".join(sorted(set(failed))))


if __name__ == "__main__":
    main()
