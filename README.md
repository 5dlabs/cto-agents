# CTO Skills

Modular skill definitions for [CTO platform](https://github.com/5dlabs/cto) agents.

Skills are directories containing `SKILL.md` (and optionally extra files like configs or templates) that provide domain-specific knowledge, patterns, and instructions to AI coding agents at runtime. Each skill is packaged as an individual `.tar.gz` tarball and published to a rolling `latest` GitHub Release.

## Structure

```
{agent}/
  {project}/
    {skill}/
      SKILL.md              # Skill content (required)
      config.yaml            # Optional extra files
      ...

skill-mappings.yaml          # Agent -> skill assignments by job type
```

### Example

```
rex/
  _default/
    rust-patterns/
      SKILL.md
    rust-error-handling/
      SKILL.md
  my-project/
    custom-skill/
      SKILL.md
      schema.json

blaze/
  _default/
    shadcn-stack/
      SKILL.md
    anime-js/
      SKILL.md
```

## How It Works

1. The CTO controller reads `spec.skillsUrl` from each `CodeRun` CR
2. On reconcile, it fetches `hashes.txt` from this repo's `latest` release
3. For each skill the agent needs, it compares the remote hash to its local cache
4. Changed or missing skills are downloaded as `{skill}.tar.gz` and extracted
5. Skill content (all files in the skill directory) is available to the agent

## Release Automation

Every push to `main` triggers the `release-skills` GitHub Action which:

1. Walks all `{agent}/{project}/{skill}/` directories
2. Creates per-skill `.tar.gz` tarballs (containing all files in the skill dir)
3. Deduplicates skills that appear under multiple agents
4. Computes `sha256` hashes
5. Publishes all tarballs + `hashes.txt` to a rolling `latest` release

## Adding a Skill

1. Create `{agent}/{project}/{skill}/SKILL.md` (and any extra files)
2. Add the skill to `skill-mappings.yaml` under the relevant agent(s)
3. Push to `main` — the release action handles the rest

## Adding a Project-Specific Skill

1. Create `{agent}/{project-name}/{skill}/SKILL.md`
2. Push to `main`

Project-specific skills override `_default` skills of the same name.
