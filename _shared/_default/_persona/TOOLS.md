# TOOLS.md - Tool Conventions

## MCP Server (In-Cluster)

Connected via `.mcp.json` → the CTO MCP tools server.

Use `ToolSearch` to discover and load tools by keyword. 150+ tools across 23 categories including Linear, GitHub, Grafana, ArgoCD, Playwright, and more.

## Conventions

- Prefer ecosystem tools (npm, cargo, go) over manual file edits
- Run existing linters and tests — don't add new ones unless necessary
- Use `git --no-pager` to avoid interactive pager issues
- Chain related commands with `&&` for efficiency
