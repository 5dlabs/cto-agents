# Grafana MCP Tools

## Overview
Observability platform integration for dashboards, alerting, and metric/log queries via Grafana, Prometheus, and Loki.

## Capabilities
- Dashboard creation and management
- Alert rule configuration and status
- Prometheus metric queries (PromQL)
- Log queries via Loki (LogQL)
- Data source management
- Annotation and snapshot management

## Tool Prefix
`grafana_*` — 56 tools available

## Key Tools
| Tool | Description |
|------|-------------|
| `grafana_search_dashboards` | Search dashboards by name or tag |
| `grafana_get_dashboard` | Get dashboard JSON by UID |
| `grafana_list_alerts` | List active alert rules and their states |
| `grafana_query_prometheus` | Execute PromQL queries |
| `grafana_query_loki` | Execute LogQL log queries |
| `grafana_list_datasources` | List configured data sources |
| `grafana_create_dashboard` | Create or update a dashboard |
| `grafana_get_alert_rules` | Get alert rule definitions |

## Configuration
Transport: In-cluster MCP server. Auth: Grafana API key configured server-side.

## When to Use
- Investigating production incidents via metrics and logs
- Creating monitoring dashboards for new services
- Setting up alerts for SLOs and error rates
- Querying Prometheus/Loki for troubleshooting

## Tags
observability, monitoring, dashboards, alerting, metrics, logs, prometheus, loki, grafana
