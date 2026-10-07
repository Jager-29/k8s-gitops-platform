# Operations

## Runbooks

### OpenBao sealed (alert OpenBaoSealed)

A restart of `openbao-0` always leaves the vault sealed. Two different key holders run:

```bash
kubectl -n openbao exec -it openbao-0 -- bao operator unseal
kubectl -n openbao exec -it openbao-0 -- bao operator status
```

Right after unsealing, `HA Mode` shows `standby` for a few seconds, then `active`. ExternalSecrets that failed meanwhile recover at their next refresh, or immediately with `kubectl annotate externalsecret <name> force-sync="$(date +%s)" --overwrite`.

### Lost root token

Set `disable_unauthed_generate_root_endpoints = false` inside the `listener "tcp"` block, restart and unseal, use `/v1/sys/generate-root` (attempt, then one update per key), decode `encoded_token` (base64 XOR the OTP), then remove the parameter, restart again and revoke the old root tokens.

### Wildcard certificate renewal

```bash
bao kv put secret/tls/wildcard-example-com tls.crt=@fullchain.pem tls.key=@privkey.pem
kubectl -n traefik annotate externalsecret wildcard-example-com force-sync="$(date +%s)" --overwrite
kubectl -n gravitee annotate externalsecret tls-gravitee force-sync="$(date +%s)" --overwrite
```

Traefik reloads the certificate without a restart. Check the "Certificate validity" panel of the Traefik dashboard. Servers outside Kubernetes are updated by an Ansible playbook reading the same OpenBao path.

### Manual backup

```bash
kubectl -n openbao create job --from=cronjob/openbao-snapshot openbao-snapshot-manual
kubectl -n gitea create job --from=cronjob/gitea-dump gitea-dump-manual
velero backup create manual-$(date +%Y%m%d) --wait
```

### Force a sync after a merge

Wait for the merge to be really done before checking, otherwise ArgoCD may read the previous `main`. For a file in `apps/`, refresh `root` first, check the Application definition, then refresh the Application.

## Lessons learned from real incidents

### CI runner: TLS timeouts caused by the MTU

Symptom: the "Install tools" step failed after exactly 5 min 1 s with `curl: (28) SSL connection timeout` to GitHub, while a normal pod reached GitHub in 0.3 s.

Cause: Cilium VXLAN gives pods an MTU of 1450, but Docker in Docker inside the runner pod created its bridges with 1500. Large packets (the TLS server response) were dropped; small ones went through, so the failure was intermittent.

Fix in `apps/gitea-ci.yaml`: `--mtu=1450` (for `docker0`) **and** `--default-network-opt=bridge=com.docker.network.driver.mtu=1450` (for the per job networks created by the runner, which `--mtu` does not cover). If the CNI mode changes, both values must follow. The CI also uses `--connect-timeout` and `--retry` on downloads to fail fast instead of waiting 5 minutes.

### Pods on the master could not reach anything on port 443

Symptom: Alertmanager could not post to Teams (`dial tcp ...:443: connect: connection timed out`) while the master itself and pods on the worker could.

Diagnosis: `tcpdump` showed the packet entering the pod interface and never leaving; an nftables trace found two leftover NAT rules from a removed ingress-nginx installation, on the master only:

```
-A PREROUTING -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 30276
-A PREROUTING -p tcp -m tcp --dport 443 -j REDIRECT --to-ports 31508
```

They redirected all port 80/443 traffic coming from local pods to dead NodePorts. Fix: save `iptables-save -t nat`, delete both rules, close the two ports in firewalld. `infra/firewalld/k8s-nodes.sh` now fails if any `REDIRECT` rule exists in `PREROUTING`.

### Gravitee accepted admin/admin and demo accounts

The chart ships a default bcrypt hash for `admin` and demo users (`user`, `api1`, `application1`) in the in-memory provider. Both were active in staging until checked. Fix: hash from OpenBao through an environment variable, decoy hash in the values, `extraInMemoryUsers: ""`. Lesson: always test the default credentials of a chart, even when SSO is in place.

### A shell alias swallowed the next pasted line

On the admin host, `cp` was an alias of `cp -i`: when a file already existed, the prompt consumed the next pasted line as its answer. For pasted procedures, use `cat source > destination` or `command cp`.

### Hooks replayed by ArgoCD

ArgoCD runs Helm hooks at every sync. The cert-manager `startupapicheck` Job failed once at install time and kept raising `KubeJobFailed`; it is disabled in the values. Same reasoning for the Prometheus operator admission webhook Jobs and the Velero CRD upgrade Job.

### Two CNPG operators

A manual installation and the Helm chart ran side by side, sharing the same leader lease, so only one was active. The manual one was removed by deleting only its Deployment and RBAC objects, never with `kubectl delete -f` on its manifest, which would have deleted the CRDs and every PostgreSQL cluster with them.
