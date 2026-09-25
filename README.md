# Agent-ready repo template

Makes any repository agent-ready: one set of instructions, skills and MCP
servers that every AI coding agent uses (Claude Code, Codex, Cursor, Copilot,
Gemini CLI and others), instead of a separate copy for each tool. Run one
script on a new or existing project and it's set up.

It implements the "new repo template" from David Gibson's
[Agent-Agnostic Repository Guide](https://gist.github.com/davidgibsonp/337be9b80b3f03eccd188235c287bb05),
updated to match how the agents actually behave as of 25 September 2026.
The gist's scripts have been fixed and tested. [REFERENCE.md](REFERENCE.md)
explains the model, what each agent reads, and how to migrate an existing repo.

## Quick start

```sh
gh repo clone Ducksss/agent-agnostic-template ~/Dev/agent-agnostic-template  # once per machine
~/Dev/agent-agnostic-template/scaffold.sh ~/Dev/my-project
```

This works for a new folder or an existing project. It never overwrites a file:
anything that exists is kept and listed, and `.gitignore` and `.gitattributes`
get the template's lines appended. It then links skills, generates the MCP
configs, runs `git init` if needed, and prints the steps left for you (for an
existing repo, that includes the migration steps it spotted). Use
`--name "My Project"` to set the title in `AGENTS.md`, and `--no-git` to skip
`git init`.

## What a project gets

```text
AGENTS.md                  instructions for every agent (fill in the TODOs)
CLAUDE.md                  "@AGENTS.md" plus Claude-only notes
.agents/
  AGENTS.md                how to maintain this folder (for people and agents)
  skills/new-skill/        a skill that creates and versions other skills
  skills-local/            private skills, gitignored
  mcp/servers.json         MCP servers, defined once
  mcp/servers.example.json one example of every kind of server
  scripts/link-skills.sh   links skills into .claude/skills/
  scripts/sync-mcp.sh      renders servers.json for each agent
  scripts/package-skill.sh zips a skill as <name>-v<version>.zip
.claude/skills/new-skill   symlink into .agents/skills (generated)
.claude/settings.json      Claude-only settings (lets Claude run the checks)
.mcp.json                  Claude Code MCP config (generated)
.cursor/mcp.json           Cursor MCP config (generated)
.codex/config.toml         Codex MCP config (generated)
.pre-commit-config.yaml    blocks commits when anything is out of sync
.github/workflows/agent-config.yml   the same check on pull requests
```

## Everyday use

| To | Run |
| --- | --- |
| Add a skill | `.agents/skills/new-skill/scripts/create.sh <name> "<what it does and when to use it>"` |
| Add a private skill | the same with `--local` |
| Install someone else's skill | `npx skills add <owner/repo> --skill <name> -y` |
| Add an MCP server | edit `.agents/mcp/servers.json`, then `.agents/scripts/sync-mcp.sh` |
| Check everything | `.agents/scripts/link-skills.sh check && .agents/scripts/sync-mcp.sh check` |
| Zip a skill for claude.ai | `.agents/scripts/package-skill.sh <name>` |
| Give Codex the MCP servers | trust the project when Codex asks; otherwise `.agents/scripts/sync-mcp.sh install-codex` |

Agents learn all of this from `AGENTS.md` and `.agents/AGENTS.md`, so you can
also just ask them ("add a skill that...", "add the Figma MCP server").

## Where this differs from the gist

| Gist | This template | Why |
| --- | --- | --- |
| Links skills into `.claude/skills/` and `.cursor/skills/` | Links into `.claude/skills/` only | Cursor, Codex, Copilot, Gemini CLI, OpenCode, Amp and Devin read `.agents/skills/` directly. A `.cursor/skills/` link makes Cursor list every skill twice. |
| `link-skills.sh` uses `declare -A` | Plain arrays | macOS still ships bash 3.2, which has no associative arrays, so the gist's script fails there. |
| Prunes links with a `*/` glob | Checks every entry | `*/` never matches a dangling link, so links to deleted skills were never removed. |
| Private skill links "should not be committed" | Listed in `.git/info/exclude` automatically | Otherwise `git add -A` commits links that are broken for everyone else. |
| `sync-mcp.sh` not included | Written and tested | Renders all three formats, translates `${VAR}` secrets for each agent, and refuses what an agent can't express. |
| Codex never reads `.codex/config.toml` | Codex reads it in trusted projects | Supported since Codex 0.78 (January 2026). `install-codex` stays as the fallback, and refuses duplicate names, which would stop Codex from starting. |
| Pre-commit hook fixes links during the commit | Hooks only check, and CI runs the same checks | New symlinks made during a commit aren't staged, so the commit went through without them. |
| No skill notes | Every skill has `references/NOTES.md`, a version and a zip script | Follows the skill-notes and packaging conventions. |

## Requirements

- bash (3.2 or later), git and jq (built into macOS 15 and later).
- Optional: `zip` for packaging, `pre-commit` for the commit hooks, and
  `shellcheck` and the `codex` CLI to run the full test suite.
- Windows: symlinks need Developer Mode and `git config core.symlinks true`.

## Changing the template

Edit files under `template/`, then run the tests:

```sh
tests/run.sh
```

They scaffold throwaway projects, with `HOME` and `CODEX_HOME` pointed at
temporary folders, so your real settings are never touched. They cover every
script, compare the rendered example against `tests/golden/`, and check that
Codex itself accepts the generated TOML. GitHub runs them on Linux for every
push and pull request (`.github/workflows/test.yml`). If you change how configs are
rendered, check the new output by hand, then copy it into `tests/golden/`.
After changing `template/.agents`, run `link-skills.sh` and `sync-mcp.sh`
inside `template/` so its own generated files stay current (a test checks this).
