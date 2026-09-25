#!/usr/bin/env bash
# Create a skill folder with SKILL.md and references/NOTES.md, then link it.
#
#   .agents/skills/new-skill/scripts/create.sh <name> "<description>" [--local]
#
# --local puts the skill in .agents/skills-local/ (private, never committed).

set -euo pipefail

usage() {
  echo "usage: $0 <name> \"<description>\" [--local]" >&2
  exit 2
}

die() {
  echo "error: $*" >&2
  exit 1
}

name=""
description=""
source=skills
while [ $# -gt 0 ]; do
  case "$1" in
    --local) source=skills-local ;;
    -h | --help)
      sed -n '2,6s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) usage ;;
    *)
      if [ -z "$name" ]; then
        name="$1"
      elif [ -z "$description" ]; then
        description="$1"
      else
        usage
      fi
      ;;
  esac
  shift
done
[ -n "$name" ] && [ -n "$description" ] || usage

# Resolve the real folder first: agents may run this through .claude/skills/.
scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
agents_dir="$(cd "$scripts_dir/../../.." && pwd -P)"

if ! printf '%s\n' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || [ "${#name}" -gt 64 ]; then
  die "'$name' must be 1-64 lowercase letters, digits and single hyphens"
fi
for existing in skills skills-local; do
  [ ! -e "$agents_dir/$existing/$name" ] || die ".agents/$existing/$name already exists"
done

description="$(printf '%s' "$description" | tr '\n\r\t' '   ')"
[ "${#description}" -le 1024 ] || die "the description must be 1024 characters or fewer"

today="$(date +%Y-%m-%d)"
author="$(git config user.name 2>/dev/null || true)"
author="${author:-${USER:-unknown}}"
title="$(printf '%s' "$name" | tr '-' ' ' | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')"
dir="$agents_dir/$source/$name"

mkdir -p "$dir/references"

{
  echo "---"
  echo "name: $name"
  printf 'description: "%s"\n' "$(printf '%s' "$description" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  echo "metadata:"
  echo '  version: "1.0"'
  echo "---"
  echo
  echo "# $title"
  cat <<'EOF'

TODO: numbered steps for the agent to follow, the exact commands to run, and
what a finished result looks like. Keep this file under 500 lines; move long
reference material into references/ and link to it.
EOF
} >"$dir/SKILL.md"

{
  echo "# $name: reference notes"
  cat <<'EOF'

Annex to `SKILL.md`. It records what the skill covers, why it works the way it
does, and how it has changed. Keep all seven sections; write "None" or "N/A"
when one doesn't apply.

## 1. Overview

TODO: one paragraph on the problem this skill solves and who uses it.

## 2. Scope

**In Scope**

- TODO

**Out of Scope & Deferred**

- TODO

**Status:** Draft.

## 3. Key Decisions

| Decision | Rationale |
| --- | --- |
| TODO | TODO |

## 4. Key Nuances & Limitations

- TODO: tool quirks, edge cases and lessons from live use.

## 5. Future Improvement Ideas

- **Phase 2:** TODO
- **Future:** TODO

## 6. Open Questions

| Question | Who resolves it |
| --- | --- |
| None | N/A |

## 7. Changelog

Newest first.

| Version | Date | Author | Changes |
| --- | --- | --- | --- |
EOF
  echo "| 1.0 | $today | $author | Created. |"
} >"$dir/references/NOTES.md"

echo "created .agents/$source/$name/SKILL.md"
echo "created .agents/$source/$name/references/NOTES.md"
"$agents_dir/scripts/link-skills.sh"
