# Loki MCP Tools

## Overview
Log aggregation and search via Grafana Loki. Query, search, and correlate log data.

## Capabilities
- LogQL query execution
- Log stream searching and filtering
- Log pattern detection
- Cross-service log correlation
- Label-based log discovery

## Tool Prefix
`loki_*` — 7 tools available

## Key Tools
| Tool | Description |
|------|-------------|
| `loki_query_logs` | Execute LogQL queries |
| `loki_search_logs` | Full-text search across log streams |
| `loki_list_labels` | List available log labels |
| `loki_get_label_values` | Get values for a specific label |
| `loki_query_patterns` | Detect log patterns |
| `loki_tail_logs` | Tail live log streams |
| `loki_correlate` | Correlate logs across services |

## Configuration
Transport: In-cluster MCP server. Connected to Grafana Loki instance.

## When to Use
- Investigating production errors and incidents
- Searching for specific log messages across services
- Detecting log patterns and anomalies
- Correlating logs during distributed trace analysis

## Tags
logging, log-search, logql, observability, incident-response, correlation
