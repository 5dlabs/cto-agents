# Context7 MCP Tools

## Overview
Up-to-date library documentation and code examples via Context7. Query current docs for any indexed library.

## Capabilities
- Library ID resolution (name → Context7 ID)
- Version-specific documentation retrieval
- Code example extraction
- Cross-library documentation search

## Tool Prefix
`context7_*` — 2 tools available

## Key Tools
| Tool | Description |
|------|-------------|
| `context7_resolve_library_id` | Find the Context7 ID for a library by name |
| `context7_get_library_docs` | Get documentation for a specific topic from a library |

## Configuration
Transport: In-cluster MCP server. Auth: Context7 API key (ctx7sk-*) configured server-side.

## When to Use
- Before implementing with any library — query current docs first
- When training data may be outdated for a library version
- Getting code examples for specific API patterns
- Verifying API signatures and configuration options

## Common Library IDs
| Library | Context7 ID |
|---------|-------------|
| Next.js | `/vercel/next.js` |
| React | `/facebook/react` |
| Effect | `/effect-ts/effect` |
| Drizzle ORM | `/drizzle-team/drizzle-orm` |
| Prisma | `/prisma/prisma` |
| Better Auth | `/better-auth/better-auth` |
| Elysia | `/elysiajs/elysia` |

## Tags
documentation, library-docs, api-reference, code-examples, context7
