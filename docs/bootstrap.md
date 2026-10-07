# Bootstrap from empty machines

The repository is hosted by Gitea, which is itself deployed by ArgoCD. To break this loop, the first steps apply manifests by hand; then `root` adopts everything and Git becomes the only way in.

Applications that only use Helm charts (`repoURL` pointing to a chart repository) can be applied before Gitea exists. Applications deploying a folder of this repository (`apps/*-config.yaml`, `apps/backups.yaml`) need Gitea.

## 1. Outside the cluster

1. **Nodes**: kubeadm 1.30.14, Cilium in VXLAN mode, local-path-provisioner as the default StorageClass. On both nodes: `infra/firewalld/k8s-nodes.sh`.
2. **S3**: Garage binary in `/usr/local/bin/garage`, `infra/garage/garage.toml` in `/etc/garage.toml`, `infra/garage/garage.service` in `/etc/systemd/system/`, a `garage` system user, then `infra/garage/setup.sh` and `infra/firewalld/s3-node.sh`.
3. **Load balancer**: `infra/haproxy/haproxy.cfg` on lb-01, `haproxy -c -f /etc/haproxy/haproxy.cfg`, then reload.
4. **DNS**: A records for argocd, git, grafana, openbao, keycloak, traefik, apim, apim-gw to 192.168.10.12.

## 2. ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.5/manifests/install.yaml
```

## 3. Foundations (charts only)

```bash
kubectl apply -f apps/external-secrets.yaml -f apps/cert-manager.yaml -f apps/cnpg-operator.yaml \
  -f apps/plugin-barman-cloud.yaml -f apps/openbao.yaml -f apps/traefik.yaml
```

Wait until they are Synced. Traefik stays without a certificate until step 5.

## 4. OpenBao

Initialize, unseal and configure it as described in [secrets.md](secrets.md), then write every secret of the layout table (Garage keys, wildcard certificate, database passwords, Gitea runner token later).

## 5. Secret store, certificate, Gitea

```bash
kubectl apply -f secret-stores/openbao.yaml
kubectl create namespace gitea
kubectl apply -f traefik/wildcard-secret.yaml -f gitea/ -f backups/cnpg-gitea.yaml
kubectl apply -f apps/gitea-pg.yaml -f apps/gitea.yaml
```

The `gitea-runner` ExternalSecret stays in error until the runner token exists, which is expected at this stage.

Once Gitea answers on https://git.example.com: create the organization `infra`, the teams `infra-admins` and `infra-readers`, the private repository `infra/k8s-manifests`, push this repository to it, create the `argocd-reader` account and its token (`argocd/gitea-reader` in OpenBao), then the runner registration token (`gitea/runner`).

## 6. Hand over to Git

```bash
kubectl apply -f argocd/gitea-repo-creds.yaml
kubectl apply -f bootstrap/root.yaml
```

`root` creates every Application from `apps/`, including the ones already applied by hand, which it adopts without recreating anything. From now on, every change is a pull request.

## 7. After the first sync

* Keycloak realm and clients ([sso.md](sso.md)), then client secrets into OpenBao.
* Gravitee identity provider in the console.
* Branch protection on `main` ([gitops-ci.md](gitops-ci.md)).
* Kubernetes dashboards: `helm template kps kube-prometheus-stack --repo https://prometheus-community.github.io/helm-charts --version 91.9.0 --set fullnameOverride=kps --set grafana.enabled=false --set grafana.forceDeployDashboards=true | python3 tools/extract-kps-dashboards.py monitoring`, on a branch, then a pull request.
* CRD schemas for the CI: `python3 tools/gen-crd-schemas.py schemas`, on a branch.

## Changing the repository address

Every path based Application points to `http://gitea-http.gitea.svc.cluster.local:3000/infra/k8s-manifests.git`. To use another Git server:

```bash
grep -rl 'gitea-http.gitea.svc.cluster.local:3000/infra/k8s-manifests.git' apps bootstrap \
  | xargs sed -i 's#http://gitea-http.gitea.svc.cluster.local:3000/infra/k8s-manifests.git#https://git.example.org/me/k8s-manifests.git#'
```
