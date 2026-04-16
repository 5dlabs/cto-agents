# Linear MCP Tools

## Overview
Project management and issue tracking via Linear's API. Manage issues, projects, cycles, teams, labels, and workflows programmatically.

## Capabilities
- Issue creation, update, search, and lifecycle management
- Project and cycle management
- Team and member operations
- Label and workflow state management
- Comment and attachment handling

## Tool Prefix
`linear_*` — 187 tools available

## Key Tools
| Tool | Description |
|------|-------------|
| `linear_create_issue` | Create a new issue with title, description, assignee, labels |
| `linear_update_issue` | Update issue fields (status, priority, assignee, etc.) |
| `linear_search_issues` | Search issues by query, filters, and labels |
| `linear_list_projects` | List all projects with status and progress |
| `linear_create_project` | Create a new project with milestones |
| `linear_list_cycles` | List cycles (sprints) for a team |
| `linear_list_teams` | List all teams in the organization |
| `linear_get_issue` | Get detailed info about a specific issue |
| `linear_add_comment` | Add a comment to an issue |
| `linear_list_labels` | List available labels |

## Configuration
Transport: Connected via in-cluster MCP server at `http://cto-tools.cto.svc.cluster.local:3000/mcp`
Auth: Linear API key configured as server-side secret.

## When to Use
- Tracking work items and tasks during development
- Creating issues from bug reports or feature requests
- Managing sprint cycles and project progress
- Automating issue triage and label assignment

## Tags
project-management, issue-tracking, sprint-planning, workflow-automation, team-collaboration
