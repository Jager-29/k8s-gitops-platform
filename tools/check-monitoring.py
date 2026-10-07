import json
import os
import subprocess
import sys
import tempfile

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(cmd, cwd=None):
    print("+ " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True)


def main():
    rules_doc = yaml.safe_load(open(os.path.join(ROOT, "monitoring", "alerts-infra.yaml")))
    kps = yaml.safe_load(open(os.path.join(ROOT, "apps", "kube-prometheus-stack.yaml")))
    am = kps["spec"]["source"]["helm"]["valuesObject"]["alertmanager"]

    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "rules.yaml"), "w") as f:
            yaml.safe_dump({"groups": rules_doc["spec"]["groups"]}, f, allow_unicode=True)
        for name in os.listdir(os.path.join(ROOT, "tests")):
            if name.endswith(".test.yaml"):
                with open(os.path.join(ROOT, "tests", name)) as src, open(os.path.join(tmp, name), "w") as dst:
                    dst.write(src.read())
        run(["promtool", "check", "rules", "rules.yaml"], cwd=tmp)
        tests = sorted(n for n in os.listdir(tmp) if n.endswith(".test.yaml"))
        if tests:
            run(["promtool", "test", "rules"] + tests, cwd=tmp)

        config = am["config"]
        config["templates"] = [os.path.join(tmp, "*.tmpl")]
        url_file = os.path.join(tmp, "webhook_url")
        with open(url_file, "w") as f:
            f.write("https://example.invalid/webhook")
        for receiver in config.get("receivers", []):
            for target in receiver.get("msteamsv2_configs", []):
                target["webhook_url_file"] = url_file
        with open(os.path.join(tmp, "alertmanager.yaml"), "w") as f:
            yaml.safe_dump(config, f, allow_unicode=True)
        for name, body in am.get("templateFiles", {}).items():
            with open(os.path.join(tmp, name), "w") as f:
                f.write(body)
        run(["amtool", "check-config", "alertmanager.yaml"], cwd=tmp)

        sample = os.path.join(ROOT, "tests", "alert-sample.json")
        for tpl in ("platform.title", "platform.text"):
            run(["amtool", "template", "render",
                 "--template.glob=" + os.path.join(tmp, "*.tmpl"),
                 "--template.text={{ template \"%s\" . }}" % tpl,
                 "--template.data=" + sample], cwd=tmp)

        expected = {
            "alertname=Watchdog severity=none": "null",
            "alertname=CNPGClusterHACritical severity=critical": "null",
            "alertname=CertificateExpiresSoon team=infra severity=warning": "teams",
            "alertname=KubePodCrashLooping severity=warning": "null",
            "alertname=KubeNodeNotReady severity=critical": "teams",
            "alertname=OpenBaoSealed team=infra severity=critical": "teams",
        }
        for labels, receiver in expected.items():
            out = subprocess.run(["amtool", "config", "routes", "test", "--config.file=alertmanager.yaml"] + labels.split(),
                                 cwd=tmp, check=True, capture_output=True, text=True).stdout.strip()
            status = "OK" if out == receiver else "FAILED"
            print("%s route %s -> %s (expected %s)" % (status, labels, out, receiver))
            if out != receiver:
                sys.exit(1)


if __name__ == "__main__":
    main()
