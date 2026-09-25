#!/usr/bin/env bash
# Copy the agent-agnostic template into a new or existing project.
#
#   ./scaffold.sh <dir> [--name <project name>] [--no-git]
#
# Nothing in <dir> is overwritten: files that already exist are kept and
# listed, .gitignore and .gitattributes get the template's lines appended, and
# MCP configs are only generated when the project has none of its own. Then
# skills are linked, MCP configs are rendered, and (unless --no-git) the
# folder is made a git repository if it isn't one yet.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
template="$here/template"
marker="# --- agent config (agent-agnostic-template) ---"

usage() {
  echo "usage: $0 <dir> [--name <project name>] [--no-git]" >&2
  exit 2
}

die() {
  echo "error: $*" >&2
  exit 1
}

target=""
name=""
init_git=1
while [ $# -gt 0 ]; do
  case "$1" in
    --name)
      [ $# -ge 2 ] || usage
      name="$2"
      shift
      ;;
    --no-git) init_git=0 ;;
    -h | --help)
      sed -n '2,11s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) usage ;;
    *)
      [ -z "$target" ] || usage
      target="$1"
      ;;
  esac
  shift
done
[ -n "$target" ] || usage

# Print an absolute path for $1, which may not exist yet.
abs_path() {
  local path="$1" rest=""
  while [ ! -d "$path" ]; do
    rest="/$(basename "$path")$rest"
    path="$(dirname "$path")"
  done
  printf '%s%s\n' "$(cd "$path" && pwd -P)" "$rest"
}

target="$(abs_path "$target")"
case "$target/" in
  "$here/"*) die "pick a folder outside $here" ;;
esac
mkdir -p "$target"
name="${name:-$(basename "$target")}"

generated=(.mcp.json .cursor/mcp.json .codex/config.toml)
had_servers=0
[ ! -e "$target/.agents/mcp/servers.json" ] || had_servers=1
existing_mcp=()
for file in "${generated[@]}"; do
  [ ! -e "$target/$file" ] || existing_mcp+=("$file")
done

is_generated() {
  local file
  for file in "${generated[@]}"; do
    [ "$1" != "$file" ] || return 0
  done
  return 1
}

copied=()
kept=()
merged=()
while IFS= read -r rel; do
  rel="${rel#./}"
  src="$template/$rel"
  dest="$target/$rel"
  # Skill links and MCP configs are recreated by the sync scripts below.
  [ ! -L "$src" ] || continue
  ! is_generated "$rel" || continue
  # Never copy packaged zips or private skills that live in the template.
  case "$rel" in
    .agents/dist/* | */.DS_Store | .DS_Store) continue ;;
    .agents/skills-local/.gitkeep) ;;
    .agents/skills-local/*) continue ;;
  esac

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    case "$rel" in
      .gitignore | .gitattributes)
        if grep -Fqx -- "$marker" "$dest"; then
          kept+=("$rel")
        else
          { echo; cat "$src"; } >>"$dest"
          merged+=("$rel")
        fi
        ;;
      *) kept+=("$rel") ;;
    esac
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  cp -p "$src" "$dest"
  if [ "$rel" = AGENTS.md ]; then
    safe="${name//\\/\\\\}"
    safe="${safe//&/\\&}"
    PROJECT_NAME="$safe" awk '{ gsub(/\{\{PROJECT_NAME\}\}/, ENVIRON["PROJECT_NAME"]); print }' \
      "$dest" >"$dest.tmp" && mv "$dest.tmp" "$dest"
  fi
  copied+=("$rel")
done < <(cd "$template" && find . -mindepth 1 \( -type f -o -type l \) | LC_ALL=C sort)

in_git() { git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; }
if [ "$init_git" -eq 1 ] && command -v git >/dev/null 2>&1 && ! in_git; then
  git -C "$target" init -q
  echo "Initialised a git repository in $target"
fi

echo
echo "Copied ${#copied[@]} file(s) into $target."
[ "${#merged[@]}" -eq 0 ] || echo "Appended the template's lines to: ${merged[*]}"
if [ "${#kept[@]}" -gt 0 ]; then
  echo "Kept your existing:"
  printf '  %s\n' "${kept[@]}"
fi

echo
"$target/.agents/scripts/link-skills.sh" || echo "Fix the problem above, then run .agents/scripts/link-skills.sh."

if [ "$had_servers" -eq 0 ] && [ "${#existing_mcp[@]}" -gt 0 ]; then
  echo
  echo "Kept your MCP config (${existing_mcp[*]}) and skipped generating new ones."
  echo "To manage it from .agents/, copy its servers into .agents/mcp/servers.json, for example"
  echo "  jq '.mcpServers' .mcp.json > .agents/mcp/servers.json"
  echo "then check the file and run .agents/scripts/sync-mcp.sh (it rewrites all three configs)."
else
  "$target/.agents/scripts/sync-mcp.sh"
fi

# Point out steps from the migration guide that need a person.
notes=()
kept_file() {
  local file
  for file in ${kept[@]+"${kept[@]}"}; do
    [ "$file" != "$1" ] || return 0
  done
  return 1
}
if kept_file AGENTS.md && ! grep -Fq '.agents/AGENTS.md' "$target/AGENTS.md"; then
  notes+=("Your AGENTS.md doesn't mention .agents/; copy the \"Agent configuration\" section from $template/AGENTS.md.")
fi
if kept_file CLAUDE.md && ! grep -Fq '@AGENTS.md' "$target/CLAUDE.md"; then
  notes+=("CLAUDE.md doesn't import AGENTS.md. Move its shared instructions into AGENTS.md and leave @AGENTS.md plus any Claude-only notes.")
fi
if kept_file .pre-commit-config.yaml && ! grep -Fq 'link-skills.sh' "$target/.pre-commit-config.yaml"; then
  notes+=("Add the two local hooks from $template/.pre-commit-config.yaml to your .pre-commit-config.yaml.")
fi
for dir in "$target"/.claude/skills/*; do
  [ -d "$dir" ] && [ ! -L "$dir" ] && [ -f "$dir/SKILL.md" ] || continue
  skill="$(basename "$dir")"
  notes+=("Claude-only skill .claude/skills/$skill: share it with every agent with  git mv .claude/skills/$skill .agents/skills/$skill && .agents/scripts/link-skills.sh")
done
if [ -d "$target/.cursor/skills" ]; then
  notes+=("Cursor reads .agents/skills/ itself; remove .cursor/skills/ entries that duplicate shared skills, or Cursor lists them twice.")
fi

echo
if [ "${#notes[@]}" -gt 0 ]; then
  echo "Needs your attention:"
  printf -- '- %s\n' "${notes[@]}"
  echo
fi
cat <<EOF
Next steps in $target:
1. Fill in the TODOs in AGENTS.md.
2. Add MCP servers to .agents/mcp/servers.json (servers.example.json shows every
   field), then run .agents/scripts/sync-mcp.sh.
3. Add skills with .agents/skills/new-skill/scripts/create.sh <name> "<description>".
4. Optional: run  pre-commit install  so commits check links and MCP configs.
5. Codex only reads .codex/config.toml in trusted projects: accept its trust
   prompt, or run .agents/scripts/sync-mcp.sh install-codex.
EOF
