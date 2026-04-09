# CTO Skills

Modular skill definitions for [CTO platform](https://github.com/5dlabs/cto) agents.

Skills are `SKILL.md` files that provide domain-specific knowledge, patterns, and instructions to AI coding agents at runtime. Each skill is packaged as an individual `.tar.gz` tarball and published to a rolling `latest` GitHub Release, enabling the CTO controller to download only the skills an agent needs.

## Structure

```
skills/
  {skill-name}/
    SKILL.md              # Skill content (markdown)

skill-mappings.yaml       # Agent -> skill assignments by job type
llm-docs-registry.yaml    # LLM documentation skill registry
```

## Agent Skill Mappings

Skills are assigned to agents via `skill-mappings.yaml` with job-type specificity:

- **default** — always loaded for the agent
- **coder** / **healer** / **intake** / **quality** / **test** / **security** / **review** / **deploy** / **integration** — merged with defaults based on the CodeRun's `runType`
- **optional** — loaded based on triggers or explicit request

See `skill-mappings.yaml` for the full mapping.

## How It Works

1. The CTO controller reads `spec.skillsUrl` from each `CodeRun` CR
2. On reconcile, it fetches `hashes.txt` from this repo's `latest` release
3. For each skill the agent needs, it compares the remote hash to its local cache
4. Changed or missing skills are downloaded as `{skill}.tar.gz` and extracted
5. Skill content is inlined into the agent's container ConfigMap

## Release Automation

Every push to `main` triggers the `release-skills` GitHub Action which:

1. Walks `skills/*/SKILL.md`
2. Creates a per-skill `.tar.gz` (containing `{skill_name}/SKILL.md`)
3. Computes `sha256` hashes
4. Publishes all tarballs + `hashes.txt` to a rolling `latest` release

## Adding a New Skill

1. Create `skills/{skill-name}/SKILL.md`
2. Add the skill to `skill-mappings.yaml` under the relevant agent(s)
3. Push to `main` — the release action handles the rest

## Skill Categories

| Category | Count | Examples |
|----------|-------|---------|
| Context | 8 | context-fundamentals, memory-systems, tool-design |
| Languages | 6 | rust-patterns, go-patterns, effect-patterns |
| Platforms | 22 | kubernetes-operators, expo-patterns, cloudflare-workers |
| LLM Docs | 15 | drizzle-queries, expo, hono, prisma, stripe |
| Quality | 14 | code-review, testing-strategies, playwright-testing |
| Security | 12 | semgrep, codeql, cargo-fuzz, variant-analysis |
| Tools | 16 | github-mcp, kubernetes-mcp, firecrawl, openmemory |
| Workflow | 19 | intake-pipeline, parallel-agents, deep-research |
| Design | 3 | frontend-design, react-best-practices |
| Stacks | 2 | shadcn-stack, tanstack-stack |
| Auth | 3 | better-auth, better-auth-expo, better-auth-electron |
| Documents | 4 | pdf, docx, xlsx, pptx |
| Animations | 1 | anime-js |
