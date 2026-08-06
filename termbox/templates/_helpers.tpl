{{/*
Helpers for the termbox chart. fullname defaults to the chart name (NOT
release-prefixed) so the in-cluster service name stays stable/predictable
(http://termbox:3000). Override with fullnameOverride when needed.
*/}}

{{- define "termbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "termbox.fullname" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "termbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "termbox.labels" -}}
helm.sh/chart: {{ include "termbox.chart" . }}
{{ include "termbox.selectorLabels" . }}
app.kubernetes.io/name: {{ include "termbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "termbox.selectorLabels" -}}
app: {{ include "termbox.fullname" . }}
{{- end -}}

{{/* Secret holding env-var-named keys — generated unless secrets.existingSecretName is set. */}}
{{- define "termbox.secretName" -}}
{{- default (printf "%s-secrets" (include "termbox.fullname" .)) .Values.secrets.existingSecretName -}}
{{- end -}}

{{- define "termbox.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "termbox.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* termbox image ref (digest wins over tag; tag defaults to appVersion). */}}
{{- define "termbox.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}
{{- end -}}
