# GitHub MCP Tools

## Overview
Source control, code review, and repository management via GitHub's API.

## Capabilities
- Pull request creation, review, and merge
- Issue management and search
- Code and repository browsing
- Branch and tag operations
- GitHub Actions workflow management

## Tool Prefix
`github_*` — 26 tools available

## Key Tools
| Tool | Description |
|------|-------------|
| `github_create_pull_request` | Create a PR with title, body, base/head branches |
| `github_list_pull_requests` | List PRs with filters (state, author, label) |
| `github_get_pull_request_diff` | Get the diff for a PR |
| `github_create_issue` | Create a new issue |
| `github_search_code` | Search code across repositories |
| `github_get_file_contents` | Read file contents from a repo |
| `github_list_commits` | List commits on a branch |
| `github_create_or_update_file` | Create or update a file via commit |
| `github_list_branches` | List branches in a repository |
| `github_merge_pull_request` | Merge a pull request |

## Configuration
Transport: In-cluster MCP server. Auth: GitHub App or PAT configured server-side.

## When to Use
- Creating and managing pull requests
- Browsing code and repository structure
- Automating issue workflows
- Code search across the organization

## Tags
source-control, code-review, pull-requests, issue-tracking, git, repository-management
