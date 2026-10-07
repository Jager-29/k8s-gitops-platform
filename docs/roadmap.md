# Roadmap

## Planned (files ready in `roadmap/`, not deployed)

### External gateway with sharding tags

Production needs two gateways: an internal one for internal consumers and an external one exposed to partners, each serving only the APIs tagged for it.

* `roadmap/external-gateway/values-external-gateway.yaml`: a second Gravitee release with only the gateway enabled, sharing the same PostgreSQL, Redis and license, with `gravitee_tags=external` and host `apim-gw-ext.example.com`. The current gateway already runs with `gravitee_tags=internal`.
* APIs are then published with the `internal` or `external` sharding tag in the console, and each gateway ignores the others.

### WAF in front of the external gateway

* `roadmap/external-gateway/waf-coraza.yaml`: a Traefik middleware using the Coraza WASM plugin with the OWASP Core Rule Set, started in `DetectionOnly` to tune false positives before switching to `On`.
* `roadmap/external-gateway/values-traefik-plugins.yaml`: the static configuration Traefik needs to load the plugin, to merge into `apps/traefik.yaml`.
* Alternatives considered: WAF on the perimeter firewall or in HAProxy. Traefik keeps the rule set in Git with the rest of the platform.

## Improvements

1. Required approvals set to 1 as soon as a second administrator works on the repository.
2. Full OpenBao restore test on a temporary instance with the real unseal keys.
3. Gravitee gateway memory: it was OOMKilled with a 256 MB heap and a 512 Mi limit; now 512 MB and 1 Gi, to be confirmed under load.
4. Redis and Elasticsearch images come from `bitnamilegacy` (frozen, no more security fixes): choose another source before production.
5. The Elastic Logstash chart is deprecated: plan a replacement.
6. Dedicated PostgreSQL cluster for Keycloak, and more than one instance per cluster in production (today a single instance is a single point of failure for SSO and APIM).
7. Elasticsearch index retention (ILM) and replicas: the single node cluster is yellow because replicas cannot be allocated.
8. metrics-server for `kubectl top`, volume usage metrics.
9. Ansible: firewalld rules of the nodes, wildcard certificate deployment to servers outside Kubernetes from the same OpenBao path.
10. Kubernetes upgrade to 1.31 or later, then remove the `selectableFields` ignore rule of External Secrets.
