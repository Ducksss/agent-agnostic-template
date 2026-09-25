# .agents/

Shared configuration for every coding agent, in the open
[Agent Skills](https://agentskills.io) and [AGENTS.md](https://agents.md)
formats. Make changes here. Files in `.claude/`, `.cursor/`, `.codex/` and
`.mcp.json` are either generated from this folder or belong to one agent only.

## Layout

| Path | What it holds |
| --- | --- |
| `skills/<name>/` | Shared skills (committed): `SKILL.md` plus `references/NOTES.md` |
| `skills-local/<name>/` | Private skills (gitignored) |
| `mcp/servers.json` | The MCP servers every agent gets |
| `mcp/servers.example.json` | One example of each kind of server; nothing reads it |
| `scripts/link-skills.sh` | Links skills into `.claude/skills/` |
| `scripts/sync-mcp.sh` | Renders `servers.json` into each agent's MCP config |
| `scripts/package-skill.sh` | Zips a skill as `dist/<name>-v<version>.zip` |
| `scripts/add-to-repo.sh` | Copies this setup into another project without overwriting anything |
| `tests/run.sh` | Self-tests for the scripts; run them after changing one |
| `REFERENCE.md` | What each agent reads, how to migrate a repo, and known traps |

## Skills

Use the `new-skill` skill. In short:

1. Run `.agents/skills/new-skill/scripts/create.sh <name> "<description>"`,
   adding `--local` for a private skill.
2. Write the steps in `SKILL.md` and fill in `references/NOTES.md`.
3. Commit the skill folder and its link in `.claude/skills/`.

To install someone else's skills, run
`npx skills add <owner/repo> --skill <name> -y`. It puts the skill in
`.agents/skills/`, links it for Claude Code, and records it in
`skills-lock.json`; commit all three.

| Agent | Where it finds skills |
| --- | --- |
| Claude Code | `.claude/skills/`, through the links |
| Codex, Cursor, GitHub Copilot, Gemini CLI, OpenCode, Amp, Devin | `.agents/skills/` directly |

## MCP servers

Edit `mcp/servers.json`, run `.agents/scripts/sync-mcp.sh`, and commit
`.mcp.json`, `.cursor/mcp.json` and `.codex/config.toml` with it.

```json
{
  "docs": {
    "type": "http",
    "url": "https://example.com/mcp",
    "headers": { "Authorization": "Bearer ${DOCS_TOKEN}" }
  },
  "browser": {
    "type": "stdio",
    "command": "npx",
    "args": ["-y", "@playwright/mcp@latest"],
    "codex": { "startup_timeout_sec": 30 }
  }
}
```

- `type` is `stdio` (fields `command`, `args`, `env`) or `http` (fields `url`,
  `headers`). Leave it out and it's worked out from `command` or `url`.
- `claude`, `cursor` and `codex` hold extra fields for that agent only, copied
  as they are. Set one to `false` to leave the server out of that agent.

**Secrets never go in the file.** Write `${NAME}` and each agent reads the
environment variable `NAME`:

- Claude Code expands `${NAME}` itself, and Cursor gets `${env:NAME}`.
- Codex can't expand variables, so the script rewrites them. In `env`,
  `"NAME": "${NAME}"` becomes `env_vars = ["NAME"]` (the name can't change).
  In `headers`, `"Authorization": "Bearer ${NAME}"` becomes
  `bearer_token_env_var`, and `"Header": "${NAME}"` becomes `env_http_headers`.
  Any other use of a variable fails with a message saying why.
- List every variable a stdio server needs under `env`. Codex starts servers
  with only basics such as `PATH` and `HOME`, plus what is listed.
- In remote servers' headers, Claude Code blanks some credential variables,
  such as `ANTHROPIC_API_KEY` and `NPM_TOKEN`. Use a variable name of your own.
- Apps started from the macOS Dock may not see variables set in your shell
  profile. Start the agent from a terminal if a server can't find its key.

| Agent | Reads | Notes |
| --- | --- | --- |
| Claude Code | `.mcp.json` | Asks before using a project's servers the first time |
| Cursor | `.cursor/mcp.json` | Cloud Agents ignore it and use the settings at cursor.com/agents |
| Codex | `.codex/config.toml` | Trusted projects only |

Codex asks whether to trust a project the first time it opens there. Where you
can't trust the project, `sync-mcp.sh install-codex` copies the servers into a
marked block in `~/.codex/config.toml` (or `$CODEX_HOME`), and
`uninstall-codex` removes it. It refuses to add a server name that file already
defines, because a duplicate stops Codex from starting.

## Rules

- Create skills in `.agents/skills/`, never as real folders in `.claude/skills/`.
- Change MCP servers in `servers.json`, never in the generated files.
- Keep single-agent files where that agent expects them:
  `.claude/settings.json`, `.claude/agents/`, `.cursor/rules/*.mdc`, and so on.
- `link-skills.sh check` and `sync-mcp.sh check` run in pre-commit and CI, and
  both must pass.
- Add a folder to `TARGETS` in `link-skills.sh` only for an agent that can't
  read `.agents/skills/`.
