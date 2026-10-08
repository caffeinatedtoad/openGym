{{/*
Expand the name of the chart.
*/}}
{{- define "openGym.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" | lower }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "openGym.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "openGym.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "openGym.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
