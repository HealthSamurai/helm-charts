{{- define "coverage-kb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Not release-prefixed: keeps the in-cluster address http://coverage-kb:53917 stable. */}}
{{- define "coverage-kb.fullname" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "coverage-kb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "coverage-kb.labels" -}}
helm.sh/chart: {{ include "coverage-kb.chart" . }}
{{ include "coverage-kb.selectorLabels" . }}
app.kubernetes.io/name: {{ include "coverage-kb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "coverage-kb.selectorLabels" -}}
app: {{ include "coverage-kb.fullname" . }}
{{- end -}}

{{- define "coverage-kb.secretName" -}}
{{- default (printf "%s-secrets" (include "coverage-kb.fullname" .)) .Values.secrets.existingSecretName -}}
{{- end -}}

{{- define "coverage-kb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "coverage-kb.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "coverage-kb.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}
{{- end -}}
