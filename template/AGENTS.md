# {{PROJECT_NAME}}

<!--
  Instructions for every coding agent (Codex, Cursor, Copilot, Gemini CLI,
  Claude Code via CLAUDE.md, ...). Agents load this file into every session,
  so keep it short and specific. Replace each TODO and delete what you don't
  need. A sub-package can have its own AGENTS.md (plus a CLAUDE.md containing
  "@AGENTS.md" for Claude Code); agents combine it with this one.
-->

TODO: one or two sentences on what this project does and who it is for.

## Layout

TODO: the top-level folders and what lives in each.

- `.agents/`: shared agent skills, MCP servers and the scripts that sync them

## Commands

TODO: the exact commands agents should run.

```sh
# install:
# dev:
# test:
# lint:
# build:
```

## Conventions

TODO: language and style rules, naming, error handling, and what "done" means
(for example: tests pass, types check, docs updated).

## Git

TODO: branch naming, commit message style, and pull request expectations.

## Agent configuration

Skills, MCP servers and each agent's adapter files are managed from `.agents/`.
Read `.agents/AGENTS.md` before adding or changing a skill or an MCP server,
or anything under `.claude/`, `.cursor/`, `.codex/` or `.mcp.json`.

- Never edit generated files by hand: `.mcp.json`, `.cursor/mcp.json`,
  `.codex/config.toml`, or the skill symlinks in `.claude/skills/`.
- Check everything is in sync with
  `.agents/scripts/link-skills.sh check && .agents/scripts/sync-mcp.sh check`.
