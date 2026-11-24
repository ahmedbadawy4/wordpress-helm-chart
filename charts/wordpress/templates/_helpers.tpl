{{/* Name of the release objects. */}}
{{- define "wordpress.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Name of the MySQL objects. */}}
{{- define "wordpress.mysqlName" -}}
{{- printf "%s-mysql" (include "wordpress.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Name of the WordPress volume claim. */}}
{{- define "wordpress.claimName" -}}
{{- .Values.wordpress.persistence.existingClaim | default (printf "%s-data" (include "wordpress.fullname" .)) -}}
{{- end -}}

{{/*
Labels that select the pods of one component. They never change after the
first install. Call with: dict "root" . "component" "wordpress" (or "mysql").
*/}}
{{- define "wordpress.selectorLabels" -}}
app.kubernetes.io/name: {{ .root.Chart.Name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/* Labels on every object. Same arguments as selectorLabels. */}}
{{- define "wordpress.labels" -}}
{{ include "wordpress.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" }}
{{- end -}}
