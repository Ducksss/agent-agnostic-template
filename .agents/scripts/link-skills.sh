#!/usr/bin/env bash
# Link the canonical skills into each agent's skills folder.
#
#   .agents/scripts/link-skills.sh         create, repair and prune links
#   .agents/scripts/link-skills.sh check   change nothing; exit 1 if out of date
#
# Skills live in .agents/skills/<name>/ (committed) and .agents/skills-local/<name>/
# (private, gitignored). Each folder in TARGETS gets a relative symlink
# <target>/<name> -> ../../.agents/<source>/<name>. Links to private skills are
# listed in .git/info/exclude so they never get committed.
#
# Runs on the bash 3.2 that ships with macOS.

set -euo pipefail

# Agent folders that need one link per skill. Only Claude Code does today:
# Codex, Cursor, GitHub Copilot, Gemini CLI, OpenCode, Amp and Devin (Windsurf)
# read .agents/skills/ directly. Don't add .cursor/skills: Cursor already reads
# .agents/skills/ and .claude/skills/, and lists a skill once per folder.
TARGETS=(
  .claude/skills # Claude Code
)

agents_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
repo_root="$(dirname "$agents_dir")"
mode="${1:-sync}"

case "$mode" in
  sync | check) ;;
  -h | --help)
    sed -n '2,12s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "usage: $0 [sync|check]" >&2
    exit 2
    ;;
esac

if [ "${#TARGETS[@]}" -eq 0 ]; then
  echo "link-skills: no TARGETS configured, nothing to do"
  exit 0
fi

errors=0 # problems a person has to fix
drift=0  # problems a sync run fixes

error() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

stale() {
  echo "out of date: $*"
  drift=$((drift + 1))
}

in_git() {
  command -v git >/dev/null 2>&1 &&
    git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# A link this script owns points into .agents/skills or .agents/skills-local.
is_managed() {
  case "$1" in
    *.agents/skills/* | *.agents/skills-local/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Print the frontmatter of a SKILL.md: the lines between the first two "---".
frontmatter() {
  awk '{ sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    { print }' "$1"
}

# Print one line per problem with a skill folder (checks from agentskills.io).
skill_problems() {
  local dir="$1" name="$2" fm value
  if [ ! -f "$dir/SKILL.md" ]; then
    echo "$name: no SKILL.md"
    return
  fi
  if ! printf '%s\n' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || [ "${#name}" -gt 64 ]; then
    echo "$name: folder name must be 1-64 lowercase letters, digits and single hyphens"
  fi
  fm="$(frontmatter "$dir/SKILL.md")"
  if [ -z "$fm" ]; then
    echo "$name: SKILL.md must start with a --- frontmatter block"
    return
  fi
  value="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n 1 |
    sed -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")"
  if [ "$value" != "$name" ]; then
    echo "$name: frontmatter name is '$value', expected '$name'"
  fi
  case "$(printf '%s\n' "$fm" | awk '
    /^description:/ {
      v = $0; sub(/^description:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (v == "" || v ~ /^[>|][-+0-9]*$/) { block = 1; next }
      if (v == "\"\"" || v == "'"''"'") { print "missing"; exit }
      print (length(v) > 1024 ? "long" : "ok"); exit
    }
    block && /^[ \t]+[^ \t]/ { print "ok"; exit }
    block && /^[^ \t]/ { print "missing"; exit }
    END { if (!block) print "missing" }' | head -n 1)" in
    ok) ;;
    long) echo "$name: description is longer than 1024 characters" ;;
    *) echo "$name: frontmatter needs a description" ;;
  esac
}

names=()   # skill names
sources=() # "skills" or "skills-local", parallel to names

index_of() {
  local i=0
  while [ "$i" -lt "${#names[@]}" ]; do
    if [ "${names[$i]}" = "$1" ]; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# 1. Collect and validate the skills.
for source in skills skills-local; do
  for dir in "$agents_dir/$source"/*; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    if index_of "$name" >/dev/null; then
      error "'$name' exists in both .agents/skills and .agents/skills-local; rename one"
      continue
    fi
    problems="$(skill_problems "$dir" "$name")"
    if [ -n "$problems" ]; then
      while IFS= read -r line; do
        error ".agents/$source/$line"
      done <<<"$problems"
      continue
    fi
    names+=("$name")
    sources+=("$source")
  done
done
[ "$errors" -eq 0 ] || exit 1

# 2. Create or repair a link per skill in each target, then prune stale links.
for target in "${TARGETS[@]}"; do
  target_dir="$repo_root/$target"
  up="$(printf '%s' "$target" | sed -e 's#[^/][^/]*#..#g')" # .claude/skills -> ../..

  i=0
  while [ "$i" -lt "${#names[@]}" ]; do
    name="${names[$i]}"
    source="${sources[$i]}"
    i=$((i + 1))
    want="$up/.agents/$source/$name"
    link="$target_dir/$name"

    if [ -L "$link" ]; then
      have="$(readlink "$link")"
      [ "$have" = "$want" ] && continue
      if ! is_managed "$have"; then
        error "$target/$name links to $have, not .agents/$source/$name; remove it and re-run"
      elif [ "$mode" = check ]; then
        stale "$target/$name points to $have instead of $want"
      else
        rm "$link"
        ln -s "$want" "$link"
        echo "relinked $target/$name -> $want"
      fi
    elif [ -f "$link" ] && [ "$(cat "$link")" = "$want" ]; then
      # A link saved as a plain file, as some unzip tools and git with
      # core.symlinks off do: turn it back into a link.
      if [ "$mode" = check ]; then
        stale "$target/$name is a plain file instead of a link"
      else
        rm "$link"
        ln -s "$want" "$link"
        echo "relinked $target/$name -> $want"
      fi
    elif [ -e "$link" ]; then
      error "$target/$name is a real folder; move it into .agents/skills/ (git mv) and re-run"
    elif [ "$mode" = check ]; then
      stale "$target/$name is missing"
    else
      mkdir -p "$target_dir"
      ln -s "$want" "$link"
      echo "linked $target/$name -> $want"
    fi
  done

  [ -d "$target_dir" ] || continue
  for link in "$target_dir"/*; do
    [ -L "$link" ] || continue # the glob also matches dangling links
    is_managed "$(readlink "$link")" || continue
    name="$(basename "$link")"
    index_of "$name" >/dev/null && continue
    if [ "$mode" = check ]; then
      stale "$target/$name points to a skill that no longer exists"
    else
      rm "$link"
      echo "pruned $target/$name"
    fi
  done
done

# 3. Keep links to private skills out of git via .git/info/exclude.
if in_git; then
  exclude="$(git -C "$repo_root" rev-parse --git-path info/exclude)"
  case "$exclude" in /*) ;; *) exclude="$repo_root/$exclude" ;; esac
  prefix="$(git -C "$repo_root" rev-parse --show-prefix)" # repo root inside a larger checkout
  begin="# BEGIN link-skills.sh: private skill links"
  end="# END link-skills.sh"

  wanted=""
  i=0
  while [ "$i" -lt "${#names[@]}" ]; do
    if [ "${sources[$i]}" = skills-local ]; then
      for target in "${TARGETS[@]}"; do
        wanted="$wanted/$prefix$target/${names[$i]}"$'\n'
      done
    fi
    i=$((i + 1))
  done

  current=""
  if [ -f "$exclude" ]; then
    current="$(awk -v b="$begin" -v e="$end" '$0 == b { on = 1; next } $0 == e { on = 0; next } on' "$exclude")"
  fi
  if [ "$current" != "${wanted%$'\n'}" ]; then
    if [ "$mode" = check ]; then
      stale "private skill links are not listed in $exclude"
    else
      mkdir -p "$(dirname "$exclude")"
      kept=""
      if [ -f "$exclude" ]; then
        kept="$(awk -v b="$begin" -v e="$end" '$0 == b { on = 1; next } $0 == e { on = 0; next } !on' "$exclude")"
      fi
      {
        [ -z "$kept" ] || printf '%s\n' "$kept"
        [ -z "$wanted" ] || printf '%s\n%s%s\n' "$begin" "$wanted" "$end"
      } >"$exclude"
      echo "updated private skill links in $exclude"
    fi
  fi
fi

# 4. In check mode, flag shared skills that are in git without their links.
if [ "$mode" = check ] && in_git; then
  tracked="$(git -C "$repo_root" ls-files -- .agents/skills "${TARGETS[@]}")"
  missing=()
  i=0
  while [ "$i" -lt "${#names[@]}" ]; do
    name="${names[$i]}"
    source="${sources[$i]}"
    i=$((i + 1))
    [ "$source" = skills ] || continue
    printf '%s\n' "$tracked" | grep -Fxq -- ".agents/skills/$name/SKILL.md" || continue
    for target in "${TARGETS[@]}"; do
      printf '%s\n' "$tracked" | grep -Fxq -- "$target/$name" || missing+=("$target/$name")
    done
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    error "skill links not added to git: ${missing[*]} (git add them with the skill)"
  fi
fi

if [ "$errors" -gt 0 ]; then
  exit 1
fi
if [ "$drift" -gt 0 ]; then
  echo "Run .agents/scripts/link-skills.sh to fix." >&2
  exit 1
fi
echo "link-skills: ${#names[@]} skill(s) linked into ${TARGETS[*]}"
