# System design topics

Topics come from [system-design-practise](https://github.com/nghiango/system-design-practise).
**At most one topic is online at a time.**

## Switching

`topics/active.yaml` holds one topic name or `none`:

```yaml
active: url-shortener
```

- Jenkins `system-design/topic-switch`: `ACTION=activate TOPIC=<topic>` (the topic that was
  online goes offline in the same commit), `ACTION=deactivate` (nothing online), or
  `ACTION=status`.
- Or edit `active.yaml` by hand. It has the same effect.

The ApplicationSet `argocd/topics-applicationset.yaml` turns the value into the single Argo
Application `topic-<topic>` (namespace `topic-<topic>`). Each topic chart starts with a
`wait-for-exclusive` job, so a new topic's services only start after the previous topic's
namespace is fully gone.

## Who owns what

```
topics/
├── active.yaml              switch-owned (topic-switch job or a manual edit)
└── <topic>/
    ├── topic.yaml           Jenkins-owned: title, focus, level (copied from the source repo)
    ├── values-local.yaml    Jenkins-owned: image tags and revision
    └── chart/               Jenkins-owned: deploy/topic-chart + the topic's values-topic.yaml
```

Topic jobs (`system-design/<topic>`) write only `topics/<topic>/`. They never write
`active.yaml`, `charts/` or `environments/`.

## Going offline

Removed: the topic's namespace (pods, services, jobs, secrets), its `topic-<topic>-*`
NetworkPolicies in `hyperscale`, and its ClusterRole.

Kept on the shared infrastructure: its Postgres database, Kafka topics (`<topic>.*`) and Redis
keys (`<topic>:*`), so the data is still there when the topic comes back online. Wipe it with
`scripts/topic.sh reset <topic>` in the source repo.

Warning: deleting the ApplicationSet itself takes the active topic offline.
