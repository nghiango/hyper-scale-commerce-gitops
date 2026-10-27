# HyperScale Commerce GitOps

Desired-state configuration for the local ARM64 Kubernetes environment.

## Layout

- `charts/commerce/`: application, Kafka, Redis, PostgreSQL/Patroni, etcd and ingress chart.
- `charts/platform/`: Prometheus, Grafana, OpenTelemetry Collector and Tempo chart.
- `environments/local/values.yaml`: local registry images, resource/pool settings and image tags.
- `argocd/applications.yaml`: Argo CD Applications targeting the two charts.

## Bootstrap state

This initial commit contains configuration only. The `pending-ci` image tags
are deliberate placeholders, not published application releases. Commerce
auto-sync is disabled in the bootstrap Application. Do not manually sync it
until Jenkins has published verified images and replaced these values.

The local registry is `hyperscale-k8s-worker:30500` from Docker/kind, exposed
as `localhost:5001` on the host. The application repository contains bootstrap
scripts and the detailed runbook at `docs/operations/local-cicd.md`. Bootstrap
the named local kind cluster, registry and metrics-server before deploying.

Jenkins runs the application build and unit/integration tests, pushes ARM64
app/query/Patroni images, then updates both chart directories and local values
in one commit here. It uses a dedicated SSH write deploy key. Argo CD uses a
separate read-only key and the canonical repository URL:
`git@github.com:nghiango/hyper-scale-commerce-gitops.git`. The host's
`personal.github.com` alias is not available inside cluster containers.

After the first green CI release, configure Argo repository credentials, apply
the Applications and enable commerce auto-sync with pruning disabled:

```bash
kubectl --context kind-hyperscale-k8s apply -f argocd/applications.yaml
kubectl --context kind-hyperscale-k8s -n argocd patch application hyperscale-local \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":false,"selfHeal":true}}}}'
```

HPA owns deployment replicas; Argo ignores replica drift. Roll back by reverting
a verified release commit, after checking database migration compatibility.
No secrets or private keys belong in this repository. Grafana's admin password
is supplied by the bootstrap-created `local-platform-credentials` Secret.
The inherited commerce chart contains public local-development database/Redis
defaults; do not reuse them in shared or production environments. Monitoring
uses disposable storage; registry and application data use local PVCs.

## Validate without deploying

```bash
helm lint charts/commerce -f environments/local/values.yaml
helm lint charts/platform
helm template hyperscale charts/commerce -f environments/local/values.yaml > /tmp/hyperscale-commerce.yaml
helm template platform charts/platform > /tmp/hyperscale-platform.yaml
```

Configuration was seeded from the application working tree on 2026-10-27.
It is not a claim of successful CI qualification: the last full build failed
the existing catalog SLO check (163.5 ms p95 versus a 100 ms limit). Jenkins
onboarding, deploy keys and the GitHub webhook route still need to be connected.
