# CTO Tool & Skill Catalog

This directory is indexed by [Context7](https://context7.com) to provide semantic search
over all available MCP tools, agent skills, and library references.

## How Agents Use This

During intake provisioning, agents query Context7 to discover available capabilities:

```bash
# Find tools for a specific capability
ctx7 docs /5dlabs/cto-agents "what MCP tools handle GitHub operations?"

# Find skills for a domain
ctx7 docs /5dlabs/cto-agents "what skills help with code review?"

# Check if a tool exists
ctx7 docs /5dlabs/cto-agents "do we have a Kubernetes MCP tool?"
```

## Structure

```
catalog/
  ├── README.md          # This file
  ├── catalog.json       # Machine-readable index of all tools
  └── tools/             # One .md per MCP tool server
      ├── github-mcp.md
      ├── kubernetes-mcp.md
      └── ...
```

Skills live in `rex/_default/*/SKILL.md` (not duplicated here — Context7 indexes them directly).

## Adding a New Tool

1. Create `catalog/tools/{tool-name}.md` following the template below
2. Update `catalog/catalog.json` with the tool entry
3. Commit and push — Context7 re-indexes automatically

### Tool Document Template

```markdown
# {Tool Name}

## Overview
Brief description of what this tool does.

## Capabilities
- Capability 1
- Capability 2

## Tool Prefix
`{prefix}_*` — all tools are prefixed with this pattern

## Key Tools
| Tool | Description |
|------|-------------|
| `{prefix}_action1` | What it does |
| `{prefix}_action2` | What it does |

## Configuration
How to configure this tool server (env vars, secrets, etc.)

## When to Use
Describe scenarios where this tool is the right choice.
```

## Adding a New Skill

Skills are added to `rex/_default/{skill-name}/SKILL.md` (or agent-specific paths).
See the main [README.md](../README.md) for instructions.

## Machine-Readable Index

`catalog.json` provides a structured index for programmatic lookups:

```json
{
  "tools": {
    "github-mcp": {
      "prefix": "github",
      "capabilities": ["source-control", "code-review", "issue-tracking"],
      "tool_count": 26
    }
  }
}
```

## Context7 Integration

This repo is registered with Context7 as `/5dlabs/cto-agents`.
The `context7.json` at the repo root configures which directories are indexed.
