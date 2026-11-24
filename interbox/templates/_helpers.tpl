{{- define "interbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Not release-prefixed: keeps the in-cluster address http://interbox:3001 stable. */}}
{{- define "interbox.fullname" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The API port as a whole number; fails the render on a value outside 1..65535 or one the MLLP port takes. */}}
{{- define "interbox.apiPort" -}}
{{- $raw := toString .Values.apiPort -}}
{{- $port := 0 -}}
{{- if regexMatch "^[0-9]{1,5}$" $raw -}}
{{- $port = atoi $raw -}}
{{- end -}}
{{- if or (lt $port 1) (gt $port 65535) -}}
{{- fail (printf "apiPort must be a whole number from 1 to 65535, got %q" $raw) -}}
{{- end -}}
{{- if and .Values.mllp.enabled (eq $port (int .Values.mllp.port)) -}}
{{- fail (printf "apiPort %d is already taken by the MLLP port (mllp.port)" $port) -}}
{{- end -}}
{{- $port -}}
{{- end -}}

{{- define "interbox.workspaceServiceUrl" -}}
http://{{ include "interbox.fullname" . }}-workspace:{{ include "interbox.apiPort" . }}
{{- end -}}

{{- define "interbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "interbox.labels" -}}
{{ include "interbox.selectorLabels" . }}
{{ include "interbox.commonLabels" . }}
{{- end -}}

{{- define "interbox.workspaceServiceLabels" -}}
{{ include "interbox.workspaceServiceSelectorLabels" . }}
{{ include "interbox.commonLabels" . }}
{{- end -}}

{{- define "interbox.commonLabels" -}}
helm.sh/chart: {{ include "interbox.chart" . }}
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

{{/* A name of its own: the main Service selects `app: <fullname>` and must never match a workspace service pod. */}}
{{- define "interbox.workspaceServiceSelectorLabels" -}}
app: {{ include "interbox.fullname" . }}-workspace
app.kubernetes.io/component: workspace
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
{{- if eq $port (int (include "interbox.apiPort" .)) -}}
{{- fail (printf "webhook.port %d is already taken by the API port (apiPort)" $port) -}}
{{- end -}}
{{- if and .Values.mllp.enabled (eq $port (int .Values.mllp.port)) -}}
{{- fail (printf "webhook.port %d is already taken by the MLLP port (mllp.port)" $port) -}}
{{- end -}}
{{- $port -}}
{{- end -}}

{{/* Fails the render on a `config` key that does not belong in the ConfigMap. */}}
{{- define "interbox.checkConfig" -}}
{{- range $key, $value := .Values.config -}}
{{- if eq $key "DATABASE_URL" -}}
{{- fail "config.DATABASE_URL: a credential does not belong in a ConfigMap; put it in secrets" -}}
{{- end -}}
{{- if eq $key "INTERBOX_WEBHOOK_PORT" -}}
{{- fail "config.INTERBOX_WEBHOOK_PORT: set webhook.port instead; the chart sets this variable on the container from it, and a different value in a ConfigMap stops the engine at startup" -}}
{{- end -}}
{{- if eq $key "API_PORT" -}}
{{- fail "config.API_PORT: set apiPort instead; the chart sets this variable on both containers from it, and on their ports and Services" -}}
{{- end -}}
{{- if eq $key "INTERBOX_WORKSPACE_CACHE" -}}
{{- fail "config.INTERBOX_WORKSPACE_CACHE: remove it; the workspace service keeps its checkout on its volume at the engine's default path, and another path would leave the checkout off the volume" -}}
{{- end -}}
{{- end -}}
{{- end -}}
