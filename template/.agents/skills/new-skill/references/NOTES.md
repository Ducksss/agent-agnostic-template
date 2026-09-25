# new-skill: reference notes

Annex to `SKILL.md`. It records what the skill covers, why it works the way it
does, and how it has changed. Keep all seven sections; write "None" or "N/A"
when one doesn't apply.

## 1. Overview

Agents' built-in skill creators write into their own folders, such as
`.claude/skills/` or `~/.codex/skills/`, which leaves each skill usable by one
tool only. This skill makes any agent create and update skills in the shared
`.agents/skills/` folder instead, with a version and reference notes, and link
them for Claude Code, the one agent that can't read that folder yet. It is for
anyone, human or agent, adding or changing a skill in a repository made from
the agent-agnostic template.

## 2. Scope

**In Scope**

- Creating a shared or private skill with valid `SKILL.md` frontmatter.
- Creating `references/NOTES.md` with the seven required sections.
- Linking the skill into `.claude/skills/` via `link-skills.sh`.
- Versioning, changelog updates and zip packaging for existing skills.

**Out of Scope & Deferred**

- Installing third-party skills: use `npx skills add <owner/repo> --skill <name> -y`.
- Writing the skill's actual instructions; the agent does that with the user.
- Publishing skills anywhere; packaging stops at a local zip.

**Status:** Ready (v1.2).

## 3. Key Decisions

| Decision | Rationale |
| --- | --- |
| Skills live only in `.agents/skills/`; `.claude/skills/` holds symlinks | One copy to edit. Codex, Cursor, Copilot, Gemini CLI and most other agents read `.agents/skills/` directly; only Claude Code needs the links. |
| No links in `.cursor/skills/` | Cursor already reads `.agents/skills/` and `.claude/skills/`, and lists a skill once per folder it finds it in. |
| Every skill has `references/NOTES.md` with seven fixed sections | The skill-notes convention: record why, not only what, so the next editor understands the skill. |
| Version lives in `metadata.version` in the frontmatter | `metadata` is a portable field, so the version travels with the skill and claude.ai still accepts it. |
| Descriptions are written as double-quoted YAML | A plain YAML value breaks on a colon followed by a space, which descriptions often contain. |
| `create.sh` runs `link-skills.sh` itself | A skill without its link is invisible to Claude Code, and the step is easy to forget. |

## 4. Key Nuances & Limitations

- Cursor and GitHub Copilot also read `.claude/skills/`, so they may list each
  shared skill twice. Cursor can stop reading other tools' folders (Settings,
  Rules, Skills and Subagents, "Include Third-Party Plugins, Skills, and Other
  Configs"); check the shared skills still appear after changing it.
- Claude Code finds skills through the symlinks, so a new skill only reaches
  teammates once its link is committed. `link-skills.sh check` flags a shared
  skill whose link isn't in git.
- Private skills in `.agents/skills-local/` get links too. Those links are
  listed in `.git/info/exclude` so they stay out of commits.
- Codex follows symlinked skill folders but ignores a symlinked `SKILL.md`
  file, so always link whole folders.
- On Windows, symlinks need Developer Mode and `git config core.symlinks true`.
- Agents load their skill list at session start; restart the agent to see a
  new skill.

## 5. Future Improvement Ideas

- **Phase 2:** Validate with the official `skills-ref validate` (needs Python
  3.11+, for example through `uvx`) when it is available, and keep the built-in
  checks as the fallback.
- **Future:** Offer to convert an existing real folder in `.claude/skills/`
  into a shared skill automatically.
- **Future:** Drop the `.claude/skills/` links once Claude Code reads
  `.agents/skills/` (anthropics/claude-code issue 31005).

## 6. Open Questions

| Question | Who resolves it |
| --- | --- |
| None | N/A |

## 7. Changelog

Newest first.

| Version | Date | Author | Changes |
| --- | --- | --- | --- |
| 1.2 | 2026-09-26 | Claude | Open Questions set to None: the duplicate-listing choice is made on each machine and is covered under Key Nuances, and this file is copied into every project made from the template. |
| 1.1 | 2026-09-25 | Claude | Rewrote one argument check in `create.sh` so older ShellCheck versions pass (no change in behaviour); corrected the `npx skills add` command in Scope. |
| 1.0 | 2026-09-25 | Claude | Created the skill, its `create.sh` scaffolder and these notes. |
