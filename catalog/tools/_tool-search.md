# ToolSearch — Meta-Tool for Tool Discovery

## Overview
ToolSearch is a meta-tool that enables agents to discover and dynamically load tools from the 150+ tools available on the MCP server. Instead of loading all tools at startup (which would overwhelm the context), agents use ToolSearch to find relevant tools by keyword.

## How It Works
1. Agent receives a task requiring specific capabilities
2. Agent calls `ToolSearch` with relevant keywords
3. ToolSearch returns matching tools with their schemas
4. Agent can then call the discovered tools directly

## Usage Pattern
```
ToolSearch({ query: "create github pull request" })
→ Returns: github_create_pull_request tool with full schema

ToolSearch({ query: "kubernetes pods" })
→ Returns: kubernetes-related tools for pod management

ToolSearch({ query: "search logs for errors" })
→ Returns: loki_query_logs, loki_search_logs tools
```

## Best Practices
- Search with capability descriptions, not tool names
- Use multiple searches for different aspects of a task
- Cache discovered tools within a session
- Prefer specific queries over broad ones

## When to Use
- At the start of any task to discover relevant tools
- When you need a capability you haven't used before
- When switching between different types of work

## Tags
tool-discovery, meta-tool, dynamic-loading, capability-search
