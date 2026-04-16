# Argo CD MCP Tools

## Overview
GitOps continuous delivery for Kubernetes. Manage application deployments, sync status, and rollbacks.

## Capabilities
- Application sync and status monitoring
- Rollback to previous revisions
- Resource tree inspection
- Application creation and configuration
- Health and sync status checks

## Tool Prefix
`argocd_*` — 14 tools available

## Key Tools
| Tool | Description |
|------|-------------|
| `argocd_list_applications` | List all Argo CD applications |
| `argocd_get_application` | Get detailed app status and health |
| `argocd_sync_application` | Trigger a sync for an application |
| `argocd_rollback_application` | Rollback to a previous revision |
| `argocd_get_resource_tree` | Get the resource tree of an app |
| `argocd_get_application_history` | Get deployment history |

## Configuration
Transport: In-cluster MCP server. Auth: Argo CD API token configured server-side.

## When to Use
- Deploying applications to Kubernetes
- Checking deployment status and health
- Rolling back failed deployments
- Inspecting Kubernetes resources managed by GitOps

## Tags
gitops, kubernetes, deployment, continuous-delivery, rollback, argocd
