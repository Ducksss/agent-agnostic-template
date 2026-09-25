# Reference

Background for the template: the model it follows, what each agent actually
reads, how to migrate an existing repository, and the traps found while
building it. Based on David Gibson's
[Agent-Agnostic Repository Guide](https://gist.github.com/davidgibsonp/337be9b80b3f03eccd188235c287bb05)
(fetch your own copy with `gh gist clone 337be9b80b3f03eccd188235c287bb05`).

Checked on 25 September 2026 against the agents' docs and, where possible, the
tools themselves (Codex CLI 0.152.1 and Claude Code 2.1.220).
Agents change quickly, so re-check the tables before relying on an old answer.

## The model

Every piece of agent configuration is one of three kinds.

| Kind | Means | Keep it | Examples |
| --- | --- | --- | --- |
| Portable | Every agent reads the same format | One copy, in the shared place | `AGENTS.md`, skills |
| Generated | The same information, but each agent wants its own format | One source, rendered by a script | MCP server lists |
| Agent-specific | Only one agent understands it | Where that agent expects it | `.claude/settings.json`, `.claude/agents/`, `.cursor/rules/*.mdc` |

To place a new file, ask in order:

1. Do several agents read this exact file and format? Then it's portable: one
   copy, plus links only for agents that can't find it.
2. Is it the same information in different formats? Then it's generated: keep
   the source in `.agents/` and render the rest.
3. Otherwise it's agent-specific: leave it alone. If other agents need the same
   knowledge, write it in `AGENTS.md` rather than converting between formats.

## What each agent reads

| | Instructions | Skills | MCP config |
| --- | --- | --- | --- |
| Claude Code | `CLAUDE.md` and its `@` imports. From 2.1.277 it reads `AGENTS.md` itself, but only when there is no `CLAUDE.md`. | `.claude/skills/` only; follows symlinks | `.mcp.json`; asks before first use |
| Codex | `AGENTS.md` from the repo root down to the working folder, one file per folder (`AGENTS.override.md` wins), 32 KiB in total | `.agents/skills/` from the working folder up to the repo root | `.codex/config.toml` in trusted projects, then `~/.codex/config.toml` |
| Cursor | Root and nested `AGENTS.md`, `CLAUDE.md`, and `.cursor/rules/*.mdc` | `.agents/skills/`, `.cursor/skills/`, `.claude/skills/`, `.codex/skills/` | `.cursor/mcp.json` merged with `~/.cursor/mcp.json` |

Skills in the other agents the template was checked against:

| Agent | Project skill folders |
| --- | --- |
| GitHub Copilot | `.github/skills/`, `.claude/skills/`, `.agents/skills/` |
| Gemini CLI | `.gemini/skills/`, `.agents/skills/` |
| OpenCode | `.opencode/skills/`, `.claude/skills/`, `.agents/skills/` (keeps one copy of duplicate names) |
| Amp | `.agents/skills/`, `.claude/skills/` |
| Devin (formerly Windsurf) | `.devin/skills/`, `.windsurf/skills/`, `.agents/skills/` |

So `.agents/skills/` covers everyone except Claude Code, which is why the
template links into `.claude/skills/` alone. Claude Code's support for
`.agents/skills/` is still an open request
([anthropics/claude-code#31005](https://github.com/anthropics/claude-code/issues/31005)).

### How the MCP formats differ

| | Claude Code `.mcp.json` | Cursor `.cursor/mcp.json` | Codex `.codex/config.toml` |
| --- | --- | --- | --- |
| Shape | `{"mcpServers": {...}}` | `{"mcpServers": {...}}` | `[mcp_servers.<name>]` tables |
| Transport | `"type": "stdio"` or `"http"` | `"type": "stdio"` for local servers; remote servers go without | worked out from `command` or `url` |
| Variables | `${VAR}` and `${VAR:-default}` | `${env:VAR}`, plus `${workspaceFolder}` and others | none: `env_vars`, `bearer_token_env_var` and `env_http_headers` name the variables instead |
| Mistakes | unset variables stay as text, with a warning | | unknown keys are ignored with a warning; a duplicate server name, or an HTTP-only key on a local server, stops Codex from loading its config at all |

Codex also starts local servers with only `PATH`, `HOME` and a few other
basics, plus whatever `env` and `env_vars` list. So name every variable a
server needs under `env`, even where another agent might pass it along anyway.

`sync-mcp.sh` handles all of this. The details are in
[`.agents/AGENTS.md`](AGENTS.md).

## Migrating an existing repository

1. **See what's there.** From the repo root:

   ```sh
   find . -maxdepth 3 -not -path './.git/*' -not -path '*/node_modules/*' \
     \( -name 'AGENTS*.md' -o -name 'CLAUDE*.md' -o -name '*mcp.json' -o -name '*.mdc' \
        -o -name SKILL.md -o -name config.toml -o -name 'settings*.json' \)
   ```

   Sort each file into portable, generated or agent-specific.
2. **Add the setup.** Clone the template anywhere and run
   `<template>/.agents/scripts/add-to-repo.sh <your repo>`. It adds `.agents/`
   and the other agent files without overwriting anything, then lists the steps
   below that apply.
3. **Instructions first**, as the least risky step. If `CLAUDE.md` holds the
   real instructions, move them into `AGENTS.md` and leave `CLAUDE.md` as
   `@AGENTS.md` plus any Claude-only notes. If both files have content, merge
   them into `AGENTS.md`.
4. **Skills.** Move each real folder with
   `git mv .claude/skills/<name> .agents/skills/<name>`, then run
   `.agents/scripts/link-skills.sh`. Remove any `.cursor/skills/` copies or
   links of shared skills. Add `references/NOTES.md` to each skill.
5. **MCP.** Copy the fullest config into the canonical file, for example
   `jq '.mcpServers' .mcp.json > .agents/mcp/servers.json`. Replace any literal
   secrets with `${VAR}`, run `.agents/scripts/sync-mcp.sh`, and compare the
   generated files with the old ones using `git diff`.
6. **Leave agent-specific files alone**: `.cursor/rules/`,
   `.claude/settings.json`, `.claude/agents/`.
7. **Commit it all together**, then confirm that
   `link-skills.sh check && sync-mcp.sh check` passes.

### Special cases

- **Monorepos:** give each package its own `AGENTS.md`. Codex and Cursor
  combine it with the ones above it. Claude Code reads nested `CLAUDE.md` files
  instead, so put a `CLAUDE.md` containing `@AGENTS.md` beside each one.
- **Git submodules:** treat each submodule as its own repository and run
  `add-to-repo.sh` on it. The parent keeps only what helps agents find their
  way between submodules.
- **Workspace repos that ignore everything** (`*` in `.gitignore`): add
  exceptions for the agent files, such as `!AGENTS.md`, `!CLAUDE.md`,
  `!.mcp.json`, `!.agents/` and `!.agents/**`, and the same pair for `.claude`,
  `.codex`, `.cursor` and `.github`. Add another pair whenever a new agent
  folder appears. In a repo like this, `AGENTS.md` works best as a router that
  says which sub-folder or guide to read for which task.

## Traps found while building this

- **macOS bash is 3.2.** No associative arrays, and `"${array[@]}"` on an empty
  array fails under `set -u`. The scripts avoid both.
- **Duplicate skills.** Cursor and Copilot read `.claude/skills/` as well as
  `.agents/skills/`, so they may list shared skills twice. Cursor can stop
  reading other tools' folders in its settings; check your skills still appear
  afterwards.
- **Codex trust.** Codex ignores `.codex/config.toml` until you trust the
  project, and since August 2026 it also skips `AGENTS.md` in projects marked
  untrusted.
- **Codex sandbox.** In its default sandbox `.codex/` and `.agents/` are
  read-only, so Codex asks before running the sync scripts.
- **Codex and relative paths.** Codex starts local servers in the session's
  working folder, not the repo root, so use commands on `PATH` or absolute
  paths rather than `./scripts/server.js`.
- **Claude Code and credentials.** In remote servers' headers it reads some
  credential variables, such as `ANTHROPIC_API_KEY`, `NPM_TOKEN` and
  `HTTPS_PROXY`, as empty. Copy the value into a variable name of your own.
- **Apps opened from the Dock** may not see variables exported in your shell
  profile. Start the agent from a terminal if a server can't find its key.
- **Cursor Cloud Agents** ignore `mcp.json` and use the server list at
  cursor.com/agents, and may not follow symlinks.
- **Windows** needs Developer Mode and `git config core.symlinks true` for the
  skill links.
- **Skills load at session start.** Restart the agent to see a new skill.
- **The skills CLI.** `npx skills add` writes to `.agents/skills/`, links Claude
  Code, and records the install in `skills-lock.json`; commit that file too.

## Sources

| Topic | Link |
| --- | --- |
| AGENTS.md | [agents.md](https://agents.md) |
| Skill format | [agentskills.io/specification](https://agentskills.io/specification) |
| Where clients look for skills | [agentskills.io client guide](https://agentskills.io/client-implementation/adding-skills-support) |
| Claude Code instructions | [code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory) |
| Claude Code skills | [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills) |
| Claude Code MCP | [code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp) |
| Codex MCP | [learn.chatgpt.com/docs/extend/mcp](https://learn.chatgpt.com/docs/extend/mcp) |
| Codex config | [learn.chatgpt.com/docs/config-file/config-reference](https://learn.chatgpt.com/docs/config-file/config-reference) |
| Codex skills | [learn.chatgpt.com/docs/build-skills](https://learn.chatgpt.com/docs/build-skills) |
| Codex AGENTS.md | [learn.chatgpt.com/docs/agent-configuration/agents-md](https://learn.chatgpt.com/docs/agent-configuration/agents-md) |
| Cursor MCP | [cursor.com/docs/mcp](https://cursor.com/docs/mcp) |
| Cursor skills | [cursor.com/docs/skills](https://cursor.com/docs/skills) |
| Cursor rules | [cursor.com/docs/rules](https://cursor.com/docs/rules) |
| GitHub Copilot skills | [docs.github.com: about agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills) |
| OpenCode skills | [opencode.ai/docs/skills](https://opencode.ai/docs/skills) |
| Amp skills | [ampcode.com/docs/customize/skills](https://ampcode.com/docs/customize/skills) |
| Skills CLI | [github.com/vercel-labs/skills](https://github.com/vercel-labs/skills) |
| Skill validator | [skills-ref](https://github.com/agentskills/agentskills/tree/main/skills-ref) |
