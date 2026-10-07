# CRD schemas

JSON schemas used by kubeconform for custom resources, generated from a running cluster:

```bash
python3 tools/gen-crd-schemas.py schemas
```

Layout: `schemas/<group>/<kind>_<version>.json`. The CI looks here first, then in the public CRD catalog (datreeio/CRDs-catalog). Every CRD used in this repository is currently covered by the catalog, so this folder can stay empty until a CRD is missing there or a local version differs.
