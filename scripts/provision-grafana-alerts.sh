#!/usr/bin/env bash
# Provisiona 5 alert rules no Grafana Cloud via Alerting Provisioning API.
# Idempotente: roda quantas vezes quiser, cria ou atualiza.

set -euo pipefail

: "${GRAFANA_URL:?GRAFANA_URL nao definido}"
: "${GRAFANA_TOKEN:?GRAFANA_TOKEN nao definido}"

DS_UID="grafanacloud-prom"
FOLDER_UID="desafio-ods"
FOLDER_TITLE="Desafio ODS"
GROUP_NAME="platform"

auth=(-H "Authorization: Bearer $GRAFANA_TOKEN" -H "Content-Type: application/json")

echo "==> Garantindo folder $FOLDER_UID"
folder_check=$(curl -sS "${auth[@]}" "$GRAFANA_URL/api/folders/$FOLDER_UID" 2>&1 | jq -r '.uid // "MISSING"')
if [ "$folder_check" = "MISSING" ]; then
  curl -sS "${auth[@]}" -X POST "$GRAFANA_URL/api/folders" \
    -d "{\"uid\":\"$FOLDER_UID\",\"title\":\"$FOLDER_TITLE\"}" | jq '.uid, .title'
else
  echo "  ja existe."
fi

echo ""
echo "==> Criando/atualizando alert rules (PUT idempotente)"

put_rule() {
  local uid="$1" title="$2" pending="$3" query="$4" threshold_op="$5" threshold="$6" severity="$7" description="$8"

  local payload
  payload=$(cat <<JSON
{
  "uid": "$uid",
  "title": "$title",
  "folderUID": "$FOLDER_UID",
  "ruleGroup": "$GROUP_NAME",
  "condition": "C",
  "for": "$pending",
  "noDataState": "OK",
  "execErrState": "Error",
  "labels": { "severity": "$severity", "service": "desafio-ods-api" },
  "annotations": { "summary": "$title", "description": "$description" },
  "data": [
    {
      "refId": "A",
      "queryType": "",
      "relativeTimeRange": { "from": 300, "to": 0 },
      "datasourceUid": "$DS_UID",
      "model": {
        "expr": $(jq -Rn --arg e "$query" '$e'),
        "instant": false,
        "range": true,
        "refId": "A",
        "intervalMs": 60000,
        "maxDataPoints": 43200
      }
    },
    {
      "refId": "B",
      "queryType": "",
      "relativeTimeRange": { "from": 0, "to": 0 },
      "datasourceUid": "__expr__",
      "model": {
        "type": "reduce",
        "refId": "B",
        "datasource": { "type": "__expr__", "uid": "__expr__" },
        "expression": "A",
        "reducer": "last",
        "settings": { "mode": "dropNN" }
      }
    },
    {
      "refId": "C",
      "queryType": "",
      "relativeTimeRange": { "from": 0, "to": 0 },
      "datasourceUid": "__expr__",
      "model": {
        "type": "threshold",
        "refId": "C",
        "datasource": { "type": "__expr__", "uid": "__expr__" },
        "expression": "B",
        "conditions": [{
          "type": "query",
          "operator": { "type": "and" },
          "query": { "params": ["B"] },
          "reducer": { "type": "last", "params": [] },
          "evaluator": { "type": "$threshold_op", "params": [$threshold] }
        }]
      }
    }
  ]
}
JSON
)

  echo "  - $title ($uid)"
  # Ve se ja existe: se sim, PUT (update); se nao, POST (create).
  local existing http_code
  http_code=$(curl -sS -o /dev/null -w "%{http_code}" "${auth[@]}" \
    "$GRAFANA_URL/api/v1/provisioning/alert-rules/$uid")
  if [ "$http_code" = "200" ]; then
    curl -sS "${auth[@]}" -X PUT "$GRAFANA_URL/api/v1/provisioning/alert-rules/$uid" \
      -H "X-Disable-Provenance: true" -d "$payload" \
      | jq -r 'if .uid then "    updated" else "    FAIL: " + (tostring) end'
  else
    curl -sS "${auth[@]}" -X POST "$GRAFANA_URL/api/v1/provisioning/alert-rules" \
      -H "X-Disable-Provenance: true" -d "$payload" \
      | jq -r 'if .uid then "    created" else "    FAIL: " + (tostring) end'
  fi
}

put_rule "ods-a01-api-down" "API fora do ar" "2m" \
  'up{instance="desafio-ods-api"}' "lt" 1 "critical" \
  "Backend caiu ou Alloy perdeu contato com /metrics."

put_rule "ods-a02-5xx-rate" "Taxa de erro 5xx alta" "5m" \
  'sum(rate(http_requests_total{status_code=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))' "gt" 0.05 "warning" \
  "Mais de 5% das requisicoes retornando 5xx nos ultimos 5 min."

put_rule "ods-a03-p95-latency" "Latencia p95 alta" "10m" \
  'histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))' "gt" 1 "warning" \
  "p95 do tempo de resposta acima de 1s por 10 min contínuos."

put_rule "ods-a04-memory-high" "Memoria alta" "15m" \
  'process_resident_memory_bytes' "gt" 419430400 "warning" \
  "Processo consumindo mais de 400 MB (aprox 40% da t3.micro) por 15 min."

put_rule "ods-a05-eventloop-lag" "Event loop lag alto" "5m" \
  'nodejs_eventloop_lag_seconds' "gt" 0.1 "warning" \
  "Event loop do Node.js com lag acima de 100 ms por 5 min."

echo ""
echo "==> Feito. Ver em: $GRAFANA_URL/alerting/list"
