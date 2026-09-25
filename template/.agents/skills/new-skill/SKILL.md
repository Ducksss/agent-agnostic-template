---
name: new-skill
description: Create or update an agent skill in this repository. Use when asked to add a skill, turn a repeated workflow into a skill, or change an existing skill. Keeps every skill in the shared .agents/skills folder so all coding agents can use it, never directly in .claude/skills or another agent's folder.
metadata:
  version: "1.0"
---

# New skill

Skills live in `.agents/skills/<name>/`. Most agents read that folder directly.
Claude Code doesn't, so `.claude/skills/` holds a symlink per skill, which
`.agents/scripts/link-skills.sh` manages. Each skill also keeps reference notes
in `references/NOTES.md`.

## Create a skill

1. Pick a name: 1-64 lowercase letters, digits and single hyphens, such as
   `deploy-preview`. Check that `.agents/skills/` and `.agents/skills-local/`
   don't already have it.
2. Decide who it is for. Shared with the team goes in `.agents/skills/`.
   Personal and never committed goes in `.agents/skills-local/` (add `--local`).
3. Scaffold it from the repository root:

   ```sh
   .agents/skills/new-skill/scripts/create.sh <name> "<what it does and when to use it>" [--local]
   ```

   This writes `SKILL.md` and `references/NOTES.md` and links the skill into
   `.claude/skills/`.
4. Write the instructions in `SKILL.md`: numbered steps, the exact commands to
   run, and what a finished result looks like.
5. Fill in all seven sections of `references/NOTES.md`. Write "None" or "N/A"
   rather than deleting a section.
6. Run `.agents/scripts/link-skills.sh check`.
7. Commit the skill folder together with its new link in `.claude/skills/`.
   Private skills are never committed.

## Update a skill

1. Edit the files in `.agents/skills/<name>/`.
2. Bump `metadata.version` in the frontmatter: the minor number for fixes and
   wording, the major number when the skill's behaviour changes.
3. Add a row to the top of the changelog in `references/NOTES.md` (version,
   date, author, changes) and update any other section the change affects.
4. Package it for upload:

   ```sh
   .agents/scripts/package-skill.sh <name>
   ```

   This writes `.agents/dist/<name>-v<version>.zip`, including the notes.

## Writing a good skill

- The description is all an agent sees when deciding whether to use the skill.
  Say what the skill does and when to use it, in words a user would type.
- Keep `SKILL.md` under 500 lines. Move long reference material into
  `references/` and link to it from the steps that need it.
- Put repeatable steps in `scripts/` and call them by their path from the
  repository root.
- Stick to the portable frontmatter fields: `name`, `description`, `license`,
  `compatibility`, `metadata` and `allowed-tools`. Fields that only one agent
  understands, such as Claude Code's `context` or `hooks`, stop the skill from
  uploading to claude.ai.
- Quote the description if it contains a colon followed by a space.
