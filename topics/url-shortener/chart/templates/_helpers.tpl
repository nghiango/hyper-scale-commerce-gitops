{{- define "topic.validate" -}}
{{- $topic := toString .Values.topic -}}
{{- if not (regexMatch "^[a-z][a-z0-9-]{1,30}$" $topic) -}}
{{- fail (printf "invalid topic %q: use ^[a-z][a-z0-9-]{1,30}$" $topic) -}}
{{- end -}}
{{- range .Values.kafka.topics -}}
{{- if not (hasPrefix (printf "%s." $topic) (toString .name)) -}}
{{- fail (printf "kafka topic %q must start with '%s.'" (toString .name) $topic) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "topic.namespace" -}}topic-{{ .Values.topic }}{{- end -}}

{{- define "topic.dbName" -}}{{ replace "-" "_" .Values.topic }}{{- end -}}

{{- define "topic.labels" -}}
system-design/topic: {{ .Values.topic }}
app.kubernetes.io/part-of: system-design
app.kubernetes.io/managed-by: argocd
{{- end -}}

{{/* Sync wave annotation: include "topic.wave" "-2" */}}
{{- define "topic.wave" -}}
argocd.argoproj.io/sync-wave: {{ . | quote }}
{{- end -}}

{{/* Annotations for a Sync-phase hook Job at the given wave. */}}
{{- define "topic.hook" -}}
argocd.argoproj.io/hook: Sync
argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
argocd.argoproj.io/sync-wave: {{ . | quote }}
{{- end -}}
