---
name: test-sandbox-guidelines
description: Project-specific guidelines for the test-sandbox repository.
---

# Test Sandbox Guidelines

This is a test skill for the `test-sandbox` project. It demonstrates project-specific skill overlays that get merged with the agent's `_default` skills into a single agent tarball.

## Convention

- All test code goes under `src/tests/`
- Use `cargo nextest` instead of `cargo test`
- Integration tests require the `TEST_DB_URL` env var
