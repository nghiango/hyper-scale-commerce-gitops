{{- define "topic.validate" -}}
{{- $topic := toString .Values.topic -}}
{{- if not (regexMatch "^[a-z][a-z0-9-]{1,30}$" $topic) -}}
{{- fail (printf "invalid topic %q: use ^[a-z][a-z0-9-]{1,30}$" $topic) -}}
{{- end -}}
{{- range .Values.kafka.topics -}}
{{- $name := toString .name -}}
{{- if not (hasPrefix (printf "%s." $topic) $name) -}}
{{- fail (printf "kafka topic %q must start with '%s.'" $name $topic) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9-]+\\.[a-zA-Z0-9._-]+$" $name) -}}
{{- fail (printf "kafka topic %q: only letters, digits and ._- are allowed" $name) -}}
{{- end -}}
{{- end -}}
{{- range .Values.services -}}
{{- $name := toString .name -}}
{{- if not (regexMatch "^[a-z][a-z0-9-]{0,30}$" $name) -}}
{{- fail (printf "service name %q: use ^[a-z][a-z0-9-]{0,30}$" $name) -}}
{{- end -}}
{{- range $k, $v := .env -}}
{{- if not (regexMatch "^[A-Z_][A-Z0-9_]*$" $k) -}}
{{- fail (printf "service %q env key %q: use ^[A-Z_][A-Z0-9_]*$" $name $k) -}}
{{- end -}}
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
