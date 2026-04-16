# OpenMemory MCP Tools

## Overview
Persistent cross-session memory for agents. Store and retrieve knowledge, decisions, and context across sessions.

## Capabilities
- Store structured memories (facts, decisions, code patterns)
- Retrieve memories by semantic search
- Cross-session knowledge persistence
- Memory categorization and tagging

## Tool Prefix
`openmemory_*` — 6 tools available

## Key Tools
| Tool | Description |
|------|-------------|
| `openmemory_add_memory` | Store a new memory with tags |
| `openmemory_search_memories` | Search memories by query |
| `openmemory_list_memories` | List recent memories |
| `openmemory_delete_memory` | Remove a stored memory |
| `openmemory_get_memory` | Get a specific memory by ID |
| `openmemory_update_memory` | Update an existing memory |

## Configuration
Transport: In-cluster MCP server.

## When to Use
- Persisting architectural decisions across sessions
- Storing learned patterns and preferences
- Maintaining context about ongoing projects
- Cross-agent knowledge sharing

## Tags
memory, persistence, knowledge-management, cross-session, context
