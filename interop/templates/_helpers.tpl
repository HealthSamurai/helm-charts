{{/*
Shared helpers for the Smartbox app charts (fhir-app-portal, interop, prior-auth).
fullname defaults to the chart name (NOT release-prefixed) so in-cluster service
names stay stable and predictable for cross-app wiring (e.g. http://interop:8088,
http://aidbox-admin-api). Override with fullnameOverride when needed.
*/}}

{{- define "smartbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "smartbox.fullname" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "smartbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "smartbox.labels" -}}
helm.sh/chart: {{ include "smartbox.chart" . }}
{{ include "smartbox.selectorLabels" . }}
app.kubernetes.io/name: {{ include "smartbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "smartbox.selectorLabels" -}}
app: {{ include "smartbox.fullname" . }}
{{- end -}}

{{/*
Name of the existing Secret consumed via envFrom. The Secret itself is NOT created
by this chart — provision it in your infra layer (e.g. External Secrets Operator).
Defaults to "<fullname>-secrets"; override with secrets.existingSecretName.
*/}}
{{- define "smartbox.secretName" -}}
{{- default (printf "%s-secrets" (include "smartbox.fullname" .)) .Values.secrets.existingSecretName -}}
{{- end -}}

{{- define "smartbox.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "smartbox.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
