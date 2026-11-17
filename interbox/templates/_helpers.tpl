{{- define "interbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Not release-prefixed: keeps the in-cluster address http://interbox:3001 stable. */}}
{{- define "interbox.fullname" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "interbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "interbox.labels" -}}
helm.sh/chart: {{ include "interbox.chart" . }}
{{ include "interbox.selectorLabels" . }}
app.kubernetes.io/name: {{ include "interbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "interbox.selectorLabels" -}}
app: {{ include "interbox.fullname" . }}
{{- end -}}

{{- define "interbox.secretName" -}}
{{- default (printf "%s-secrets" (include "interbox.fullname" .)) .Values.secrets.existingSecretName -}}
{{- end -}}

{{- define "interbox.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "interbox.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "interbox.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}
{{- end -}}

{{/* The webhook port as a whole number; fails the render on a value the engine or the pod's other ports reject. */}}
{{- define "interbox.webhookPort" -}}
{{- $raw := toString .Values.webhook.port -}}
{{- $port := 0 -}}
{{- if regexMatch "^[0-9]{1,5}$" $raw -}}
{{- $port = atoi $raw -}}
{{- end -}}
{{- if or (lt $port 1) (gt $port 65535) -}}
{{- fail (printf "webhook.port must be a whole number from 1 to 65535, got %q" $raw) -}}
{{- end -}}
{{- if eq $port (int .Values.service.port) -}}
{{- fail (printf "webhook.port %d is already taken by the dashboard/API port (service.port)" $port) -}}
{{- end -}}
{{- if and .Values.mllp.enabled (eq $port (int .Values.mllp.port)) -}}
{{- fail (printf "webhook.port %d is already taken by the MLLP port (mllp.port)" $port) -}}
{{- end -}}
{{- $port -}}
{{- end -}}

{{/* Fails the render on a `config` key the engine refuses in its runtime configuration directory: it would not start. */}}
{{- define "interbox.checkConfig" -}}
{{- $reserved := list "__proto__" "DATABASE_URL" "INTERBOX_RUNTIME_CONFIG_DIR" "INTERBOX_WORKSPACE_DIR" "INTERBOX_WORKSPACE_INSTANCE" "INTERBOX_INSTANCE_ID" -}}
{{- range $key, $_ := .Values.config -}}
{{- if not (regexMatch "^[A-Za-z_][A-Za-z0-9_]*$" $key) -}}
{{- fail (printf "config.%s: not a valid environment variable name; the engine refuses it in a ConfigMap and would not start" $key) -}}
{{- end -}}
{{- if has $key $reserved -}}
{{- fail (printf "config.%s: the engine refuses this key in a ConfigMap and would not start; put it in secrets" $key) -}}
{{- end -}}
{{- end -}}
{{- end -}}
