# HyperScale Commerce GitOps

Desired state for the local ARM64 Kubernetes cluster (`kind-hyperscale-k8s`).

## Independent ownership

| Argo Application | Chart | Resources |
|---|---|---|
| hyperscale-local | charts/application | App, order-query, their Services, HPAs and PDBs |
| hyperscale-local-infrastructure | charts/infrastructure | Kafka, PostgreSQL/Patroni, etcd, Redis, ingress, backups and shared namespace/security |
| hyperscale-local-platform | charts/platform | Prometheus, Grafana, Collector, Tempo, Kafka UI, Loki and Alloy |

Local overrides are `environments/local/application-values.yaml` and
`environments/local/infrastructure-values.yaml`. Platform settings are in its
chart values. The legacy commerce chart and combined values were removed after
the scoped pipeline was merged and successfully published an application release.

## Releases

Jenkins polls the application repository. Its default `RELEASE_SCOPE=application`
builds app/query ARM64 images and updates only application chart/values.
`infrastructure` explicitly builds Patroni and updates its chart/values;
`platform` updates observability; `bootstrap` initializes all three scopes.
Templates originate in the application repository: change that source for durable
updates, since Jenkins replaces the selected chart on the next scoped release.
Images use full application commit SHA tags. Registry tag immutability is not
technically enforced. Infrastructure must be initialized before application
services can use its dependencies; independent Applications do not imply automatic
cross-Application health ordering.

Apply the registered Application definitions after publishing available charts
and images and configuring Argo's repository read credentials:

```bash
kubectl --context kind-hyperscale-k8s apply -f argocd/applications.yaml
```

Auto-sync/self-heal are enabled, pruning is disabled, and HPA owns app/query
replica counts. Argo renders Helm; do not also run Helm upgrades on these resources.
Roll back a normal release with a reviewed Git revert after checking database
migration compatibility. Ownership migration rollback needs an explicit paused
transfer; never cascade-delete Applications or PVCs to restore an old layout.

## Validation

```bash
helm lint charts/application -f environments/local/application-values.yaml
helm lint charts/infrastructure -f environments/local/infrastructure-values.yaml
helm lint charts/platform
helm template hyperscale charts/application -f environments/local/application-values.yaml > /tmp/hyperscale-application.yaml
helm template hyperscale charts/infrastructure -f environments/local/infrastructure-values.yaml > /tmp/hyperscale-infrastructure.yaml
helm template platform charts/platform > /tmp/hyperscale-platform.yaml
```

## Local inspection

Grafana: localhost:3000, Argo CD: https://localhost:8443, Kafka UI: localhost:8082
when the respective port-forward is running. Kafka UI is read-only.

```bash
kubectl --context kind-hyperscale-k8s -n hyperscale port-forward --address 127.0.0.1 svc/grafana 3000:3000
# In separate terminals when needed:
kubectl --context kind-hyperscale-k8s -n hyperscale port-forward --address 127.0.0.1 svc/kafka-ui 8082:8080
k9s --context kind-hyperscale-k8s --namespace hyperscale --readonly
```

For logs, use Grafana Explore → Loki and `{namespace="hyperscale"}`. Alloy reads
namespace pod logs through the Kubernetes API. Loki retains logs for 24 hours on
a 10Gi PVC; Grafana has a separate persistent database. Prometheus/Tempo use local
disposable storage. None of this establishes production durability or availability.

No private keys or other secrets belong here. Existing chart database/Redis
credentials are public development defaults, not production credentials. Jenkins
and Argo use separate GitOps deploy keys. Credentials and setup/runbooks live in
the application repository's local CI configuration and operations documentation.
