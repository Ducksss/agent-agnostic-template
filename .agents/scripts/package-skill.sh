#!/usr/bin/env bash
# Zip a skill for upload, for example to claude.ai.
#
#   .agents/scripts/package-skill.sh <name> [--out <dir>]
#
# Writes <dir>/<name>-v<version>.zip (default dir: .agents/dist/) with the skill
# folder at its root. The version comes from metadata.version in SKILL.md, and
# the skill must have references/NOTES.md.

set -euo pipefail

usage() {
  echo "usage: $0 <name> [--out <dir>]" >&2
  exit 2
}

die() {
  echo "error: $*" >&2
  exit 1
}

agents_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
out_dir="$agents_dir/dist"
name=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      [ $# -ge 2 ] || usage
      out_dir="$2"
      shift
      ;;
    -h | --help)
      sed -n '2,8s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) usage ;;
    *)
      [ -z "$name" ] || usage
      name="$1"
      ;;
  esac
  shift
done
[ -n "$name" ] || usage
command -v zip >/dev/null 2>&1 || die "zip is not installed"

skill_dir=""
for source in skills skills-local; do
  if [ -f "$agents_dir/$source/$name/SKILL.md" ]; then
    skill_dir="$agents_dir/$source/$name"
    break
  fi
done
[ -n "$skill_dir" ] || die "no skill named '$name' in .agents/skills or .agents/skills-local"
[ -f "$skill_dir/references/NOTES.md" ] ||
  die "$name has no references/NOTES.md; every skill keeps reference notes (see the new-skill skill)"

frontmatter="$(awk '{ sub(/\r$/, "") }
  NR == 1 { if ($0 != "---") exit; next }
  $0 == "---" { exit }
  { print }' "$skill_dir/SKILL.md")"

version="$(printf '%s\n' "$frontmatter" | awk '
  /^metadata:[ \t]*$/ { meta = 1; next }
  meta && /^[ \t]+version:/ {
    v = $0
    sub(/^[ \t]+version:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
    gsub(/^["'\'']|["'\'']$/, "", v)
    print v; exit
  }
  meta && /^[^ \t]/ { meta = 0 }')"
printf '%s\n' "$version" | grep -Eq '^[0-9]+(\.[0-9]+)*$' ||
  die "set metadata.version in $name/SKILL.md, for example:  metadata: / version: \"1.0\""

# claude.ai only accepts the portable frontmatter fields.
extra="$(printf '%s\n' "$frontmatter" | sed -n 's/^\([A-Za-z0-9_-][A-Za-z0-9_-]*\):.*/\1/p' |
  grep -Ev '^(name|description|license|compatibility|metadata|allowed-tools)$' | tr '\n' ' ' || true)"
[ -z "$extra" ] || echo "warning: claude.ai rejects these frontmatter fields: $extra" >&2

mkdir -p "$out_dir"
out_dir="$(cd "$out_dir" && pwd -P)"
zip_path="$out_dir/$name-v$version.zip"
rm -f "$zip_path"
(cd "$(dirname "$skill_dir")" && zip -r -X -q "$zip_path" "$name" -x '*.DS_Store' '*/__pycache__/*')
echo "packaged $zip_path"
