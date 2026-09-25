#!/usr/bin/env bash
# shellcheck disable=SC2016 # many strings here are meant to hold a literal ${VAR}
# End-to-end tests for the template and its scripts.
#
#   tests/run.sh            run every test
#   tests/run.sh <name>...  run only the named tests
#
# Each test scaffolds a fresh project in a temporary folder. HOME and
# CODEX_HOME point into that folder too, so nothing touches your real config.
# Uses the codex CLI and shellcheck when they are installed.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/agent-template-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# --- helpers -----------------------------------------------------------------

fail_now() {
  echo "assertion failed: $*"
  exit 1
}

# Run a command that must succeed; its output goes to $out.
ok() {
  "$@" >"$out" 2>&1 || {
    cat "$out"
    fail_now "command failed: $*"
  }
}

# Run a command that must fail; its output goes to $out.
fails() {
  if "$@" >"$out" 2>&1; then
    cat "$out"
    fail_now "expected a failure: $*"
  fi
}

output_has() { grep -Fq -- "$1" "$out" || { cat "$out"; fail_now "output lacks: $1"; }; }
file_has() { grep -Fq -- "$2" "$1" || fail_now "$1 lacks: $2"; }
file_lacks() { ! grep -Fq -- "$2" "$1" || fail_now "$1 should not contain: $2"; }
same() { [ "$1" = "$2" ] || fail_now "expected [$2], got [$1]"; }
working_link() { [ -L "$1" ] && [ -e "$1" ] || fail_now "not a working symlink: $1"; }

# Scaffold a fresh project and cd into it.
new_project() {
  proj="$tdir/proj"
  ok "$root/scaffold.sh" "$proj" "$@"
  cd "$proj" || exit 1
}

write_servers() { printf '%s\n' "$1" >.agents/mcp/servers.json; }

skill() { # <dir> <frontmatter lines...>
  local dir="$1"
  shift
  mkdir -p "$dir"
  { echo "---"; printf '%s\n' "$@"; echo "---"; echo "Body."; } >"$dir/SKILL.md"
}

# --- scaffold -------------------------------------------------------------------

test_scaffold_new_project() {
  new_project --name "Demo & Co"
  output_has "Initialised a git repository"
  file_has AGENTS.md "# Demo & Co"
  file_lacks AGENTS.md "{{PROJECT_NAME}}"
  file_has CLAUDE.md "@AGENTS.md"
  working_link .claude/skills/new-skill
  same "$(readlink .claude/skills/new-skill)" "../../.agents/skills/new-skill"
  [ ! -e .cursor/skills ] || fail_now ".cursor/skills should not exist"
  for f in .mcp.json .cursor/mcp.json .codex/config.toml .gitignore .gitattributes \
    .pre-commit-config.yaml .github/workflows/agent-config.yml .claude/settings.json \
    .agents/AGENTS.md .agents/skills-local/.gitkeep; do
    [ -f "$f" ] || fail_now "missing $f"
  done
  jq -e '.mcpServers == {}' .mcp.json >/dev/null || fail_now ".mcp.json should have no servers"
  ok .agents/scripts/link-skills.sh check
  ok .agents/scripts/sync-mcp.sh check
  for f in .agents/scripts/*.sh .agents/skills/new-skill/scripts/*.sh; do
    [ -x "$f" ] || fail_now "$f is not executable"
  done
}

test_scaffold_twice_changes_nothing() {
  new_project
  before="$(find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs shasum)"
  ok "$root/scaffold.sh" "$proj"
  output_has "Copied 0 file(s)"
  after="$(find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs shasum)"
  same "$after" "$before"
  same "$(grep -c 'agent-agnostic-template' .gitignore)" 1
}

test_scaffold_keeps_existing_files() {
  proj="$tdir/proj"
  mkdir -p "$proj/.claude/skills/legacy" && cd "$proj" || exit 1
  git init -q
  echo "# Mine" >AGENTS.md
  echo "Use tabs." >CLAUDE.md
  echo "node_modules/" >.gitignore
  echo '{"mcpServers":{"mine":{"command":"echo"}}}' >.mcp.json
  skill .claude/skills/legacy "name: legacy" "description: Old skill"
  ok "$root/scaffold.sh" "$proj"
  same "$(cat AGENTS.md)" "# Mine"
  same "$(cat CLAUDE.md)" "Use tabs."
  same "$(cat .mcp.json)" '{"mcpServers":{"mine":{"command":"echo"}}}'
  [ ! -e .cursor/mcp.json ] || fail_now "should not generate MCP configs over an existing one"
  same "$(head -n 1 .gitignore)" "node_modules/"
  file_has .gitignore ".agents/skills-local/*"
  output_has "Kept your MCP config (.mcp.json)"
  output_has "CLAUDE.md doesn't import AGENTS.md"
  output_has "git mv .claude/skills/legacy .agents/skills/legacy"
  output_has "Your AGENTS.md doesn't mention .agents/"
}

test_scaffold_refuses_template_folder() {
  fails "$root/scaffold.sh" "$root/template/sub"
  output_has "pick a folder outside"
  [ ! -e "$root/template/sub" ] || fail_now "created a folder inside the template"
}

# --- link-skills.sh ----------------------------------------------------------

test_links_prune_deleted_skill() {
  new_project
  ok .agents/skills/new-skill/scripts/create.sh demo "Demo skill"
  working_link .claude/skills/demo
  rm -rf .agents/skills/demo
  fails .agents/scripts/link-skills.sh check
  output_has "points to a skill that no longer exists"
  ok .agents/scripts/link-skills.sh
  output_has "pruned .claude/skills/demo"
  [ ! -L .claude/skills/demo ] || fail_now "dangling link was not pruned"
  ok .agents/scripts/link-skills.sh check
}

test_links_repair_wrong_target() {
  new_project
  rm .claude/skills/new-skill
  ln -s ../../.agents/skills-local/new-skill .claude/skills/new-skill
  fails .agents/scripts/link-skills.sh check
  ok .agents/scripts/link-skills.sh
  same "$(readlink .claude/skills/new-skill)" "../../.agents/skills/new-skill"
}

test_links_must_be_committed_with_skill() {
  new_project
  ok .agents/skills/new-skill/scripts/create.sh demo "Demo skill"
  ok .agents/scripts/link-skills.sh check # nothing staged yet: not our business
  git add .agents/skills/demo
  fails .agents/scripts/link-skills.sh check
  output_has "skill links not added to git: .claude/skills/demo"
  git add .claude/skills/demo
  ok .agents/scripts/link-skills.sh check
}

test_links_private_skills_stay_out_of_git() {
  new_project
  ok .agents/skills/new-skill/scripts/create.sh mine "Private helper" --local
  working_link .claude/skills/mine
  file_has .git/info/exclude "/.claude/skills/mine"
  [ -z "$(git status --porcelain --untracked-files=all -- .claude/skills/mine .agents/skills-local/mine)" ] ||
    fail_now "private skill files show up in git status"
  ok .agents/scripts/link-skills.sh check
  rm -rf .agents/skills-local/mine
  ok .agents/scripts/link-skills.sh
  file_lacks .git/info/exclude "/.claude/skills/mine"
}

test_links_refuse_to_replace_real_folders() {
  new_project
  rm .claude/skills/new-skill
  mkdir .claude/skills/new-skill
  fails .agents/scripts/link-skills.sh
  output_has ".claude/skills/new-skill is a real folder"
  rmdir .claude/skills/new-skill
  ln -s /somewhere/else .claude/skills/new-skill
  fails .agents/scripts/link-skills.sh
  output_has "links to /somewhere/else"
}

test_links_validate_skills() {
  new_project
  skill .agents/skills/Bad_Name "name: Bad_Name" "description: x"
  skill .agents/skills/mismatch "name: other" "description: x"
  skill .agents/skills/no-desc "name: no-desc"
  skill .agents/skills/empty-desc "name: empty-desc" 'description: ""'
  fails .agents/scripts/link-skills.sh
  output_has "Bad_Name: folder name must be"
  output_has "frontmatter name is 'other', expected 'mismatch'"
  output_has "no-desc: frontmatter needs a description"
  output_has "empty-desc: frontmatter needs a description"
  rm -rf .agents/skills/Bad_Name .agents/skills/mismatch .agents/skills/no-desc .agents/skills/empty-desc
  skill .agents/skills/folded "name: \"folded\"" "description: >-" "  A folded" "  description."
  mkdir -p .agents/skills-local/folded
  cp .agents/skills/folded/SKILL.md .agents/skills-local/folded/
  fails .agents/scripts/link-skills.sh
  output_has "exists in both .agents/skills and .agents/skills-local"
  rm -rf .agents/skills-local/folded
  ok .agents/scripts/link-skills.sh
  working_link .claude/skills/folded
}

# --- new-skill and package-skill.sh ------------------------------------------

test_create_skill_writes_notes_and_quotes_description() {
  new_project
  ok .agents/skills/new-skill/scripts/create.sh deploy-preview 'Deploy it. Use when: they say "ship" \o/'
  f=.agents/skills/deploy-preview/SKILL.md
  file_has "$f" 'description: "Deploy it. Use when: they say \"ship\" \\o/"'
  file_has "$f" 'version: "1.0"'
  for section in "## 1. Overview" "## 2. Scope" "## 3. Key Decisions" "## 4. Key Nuances & Limitations" \
    "## 5. Future Improvement Ideas" "## 6. Open Questions" "## 7. Changelog"; do
    file_has .agents/skills/deploy-preview/references/NOTES.md "$section"
  done
  fails .agents/skills/new-skill/scripts/create.sh deploy-preview "Again"
  output_has "already exists"
  fails .agents/skills/new-skill/scripts/create.sh "two--hyphens" "x"
  # Claude Code sees the skill through its link; the result must be the same.
  ok .claude/skills/new-skill/scripts/create.sh via-link "Made through the link"
  [ -f .agents/skills/via-link/SKILL.md ] || fail_now "skill not created in .agents/skills"
  working_link .claude/skills/via-link
}

test_package_skill() {
  new_project
  ok .agents/scripts/package-skill.sh new-skill
  zip=.agents/dist/new-skill-v1.0.zip
  [ -f "$zip" ] || fail_now "missing $zip"
  listing="$(unzip -Z1 "$zip")"
  printf '%s\n' "$listing" | grep -Fxq new-skill/SKILL.md || fail_now "zip lacks new-skill/SKILL.md"
  printf '%s\n' "$listing" | grep -Fxq new-skill/references/NOTES.md || fail_now "zip lacks the notes"
  git check-ignore -q "$zip" || fail_now ".agents/dist should be gitignored"

  ok .agents/skills/new-skill/scripts/create.sh demo "Demo"
  rm .agents/skills/demo/references/NOTES.md
  fails .agents/scripts/package-skill.sh demo
  output_has "has no references/NOTES.md"
  skill .agents/skills/demo "name: demo" "description: Demo" "context: fork" "metadata:" '  version: "2.3"'
  mkdir -p .agents/skills/demo/references && touch .agents/skills/demo/references/NOTES.md
  ok .agents/scripts/package-skill.sh demo
  output_has "claude.ai rejects these frontmatter fields: context"
  [ -f .agents/dist/demo-v2.3.zip ] || fail_now "missing demo-v2.3.zip"
  skill .agents/skills/demo "name: demo" "description: Demo"
  fails .agents/scripts/package-skill.sh demo
  output_has "set metadata.version"
}

# --- sync-mcp.sh -------------------------------------------------------------

test_mcp_example_matches_golden_files() {
  new_project
  cp .agents/mcp/servers.example.json .agents/mcp/servers.json
  ok .agents/scripts/sync-mcp.sh
  diff -u "$root/tests/golden/mcp.json" .mcp.json || fail_now ".mcp.json differs from tests/golden"
  diff -u "$root/tests/golden/cursor-mcp.json" .cursor/mcp.json || fail_now ".cursor/mcp.json differs"
  diff -u "$root/tests/golden/codex-config.toml" .codex/config.toml || fail_now ".codex/config.toml differs"
  ok .agents/scripts/sync-mcp.sh check
}

test_mcp_check_catches_hand_edits() {
  new_project
  echo '{"mcpServers":{"x":{"command":"y"}}}' >.cursor/mcp.json
  rm .codex/config.toml
  fails .agents/scripts/sync-mcp.sh check
  output_has "out of date: .cursor/mcp.json"
  output_has "out of date: .codex/config.toml"
  ok .agents/scripts/sync-mcp.sh
  ok .agents/scripts/sync-mcp.sh check
}

test_mcp_agent_overrides() {
  new_project
  write_servers '{
    "only-claude": {"url": "https://a.example/mcp", "cursor": false, "codex": false},
    "tuned": {"command": "tool", "env": {}, "claude": {"timeout": 5000},
              "cursor": {"envFile": "${workspaceFolder}/.env"},
              "codex": {"enabled_tools": ["a", "b"], "tools": {"a": {"approval_mode": "approve"}}}}
  }'
  ok .agents/scripts/sync-mcp.sh
  same "$(jq -c '.mcpServers["only-claude"]' .mcp.json)" '{"type":"http","url":"https://a.example/mcp"}'
  same "$(jq -c '.mcpServers | keys' .cursor/mcp.json)" '["tuned"]'
  same "$(jq -c '.mcpServers.tuned' .mcp.json)" '{"type":"stdio","command":"tool","env":{},"timeout":5000}'
  same "$(jq -r '.mcpServers.tuned.envFile' .cursor/mcp.json)" '${workspaceFolder}/.env'
  file_lacks .codex/config.toml "only-claude"
  file_has .codex/config.toml 'enabled_tools = ["a", "b"]'
  file_has .codex/config.toml 'tools = { a = { approval_mode = "approve" } }'
  file_lacks .codex/config.toml "env ="
}

test_mcp_rejects_what_an_agent_cannot_express() {
  new_project
  check_error() { # <servers.json> <expected message>
    write_servers "$1"
    fails .agents/scripts/sync-mcp.sh
    output_has "$2"
    [ "$(cat .mcp.json)" = '{
  "mcpServers": {}
}' ] || fail_now "a failed run must not write files"
  }
  check_error '[]' "the top level must be an object"
  check_error '{"a.b": {"command": "x"}}' 'server name "a.b" may only use'
  check_error '{"x": {"command": "y", "cwd": "/tmp"}}' "unknown fields: cwd"
  check_error '{"x": {"url": "https://a", "command": "y"}}' "command, args and env are for stdio servers"
  check_error '{"x": {"command": "y", "headers": {}}}' "url and headers are for http servers"
  check_error '{"x": {"type": "sse", "url": "https://a"}}' 'type must be "stdio" or "http"'
  check_error '{"x": {"command": "y", "args": "a b"}}' "x.args must be a list"
  check_error '{"x": {"command": "y", "env": {"A": 1}}}' "x.env.A must be a string"
  check_error '{"x": {"command": "y", "env": {"A": "${A:-1}"}}}' 'write variables as ${NAME}'
  check_error '{"x": {"command": "y", "args": ["--key=${KEY}"]}}' "Codex can't expand variables in args"
  check_error '{"x": {"command": "y", "env": {"A": "${B}"}}}' 'as ${A}'
  check_error '{"x": {"url": "https://a/${HOST}"}}' "Codex can't expand variables in url"
  check_error '{"x": {"url": "https://a", "headers": {"X-Key": "key-${K}"}}}' 'Codex needs the whole header'
  check_error '{"x": {"command": "y", "codex": "yes"}}' "x.codex must be an object"
  # The same things work once Codex is left out.
  write_servers '{"x": {"command": "y", "args": ["--key=${KEY}"], "codex": false}}'
  ok .agents/scripts/sync-mcp.sh
  same "$(jq -r '.mcpServers.x.args[0]' .cursor/mcp.json)" '--key=${env:KEY}'
}

test_mcp_toml_quoting() {
  new_project
  write_servers '{"x": {"command": "say \"hi\"\\now", "env": {"MY.KEY": "tab\there"}}}'
  ok .agents/scripts/sync-mcp.sh
  file_has .codex/config.toml 'command = "say \"hi\"\\now"'
  file_has .codex/config.toml 'env = { "MY.KEY" = "tab\there" }'
}

test_codex_reads_generated_config() {
  command -v codex >/dev/null 2>&1 || {
    echo "skipped: codex is not installed"
    return 0
  }
  new_project
  cp .agents/mcp/servers.example.json .agents/mcp/servers.json
  ok .agents/scripts/sync-mcp.sh
  mkdir -p "$CODEX_HOME"
  printf '[projects."%s"]\ntrust_level = "trusted"\n' "$(pwd -P)" >"$CODEX_HOME/config.toml"
  ok codex mcp list --json
  same "$(jq -r 'map(.name) | sort | join(" ")' "$out")" "context7 figma github github-docker playwright"
  same "$(jq -r '.[] | select(.name == "github") | .transport.bearer_token_env_var' "$out")" "GITHUB_PAT"
  same "$(jq -c '.[] | select(.name == "github-docker") | .transport.env_vars' "$out")" '["GITHUB_PERSONAL_ACCESS_TOKEN"]'
  jq -e '.[] | select(.name == "playwright") | .startup_timeout_sec == 30' "$out" >/dev/null ||
    fail_now "playwright should have startup_timeout_sec = 30"
}

test_install_codex() {
  new_project
  config="$CODEX_HOME/config.toml"
  write_servers '{"alpha": {"command": "a"}, "beta": {"url": "https://b.example/mcp"}}'
  ok .agents/scripts/sync-mcp.sh
  mkdir -p "$CODEX_HOME"
  printf 'model = "gpt-5"\n\n[mcp_servers.mine]\ncommand = "echo"\n\n[profiles.fast]\nmodel = "x"\n' >"$config"
  original="$(cat "$config")"

  ok .agents/scripts/sync-mcp.sh install-codex
  output_has "wrote 2 server(s)"
  same "$(cat "$config.bak")" "$original"
  file_has "$config" "# BEGIN MCP servers from $(pwd -P)"
  ok .agents/scripts/sync-mcp.sh install-codex
  output_has "already up to date"

  # A change is flagged by sync and replaces the block where it is.
  write_servers '{"alpha": {"command": "a2"}}'
  ok .agents/scripts/sync-mcp.sh
  output_has "is out of date; run"
  ok .agents/scripts/sync-mcp.sh install-codex
  same "$(grep -c '^# BEGIN MCP servers' "$config")" 1
  file_has "$config" 'command = "a2"'
  file_lacks "$config" "beta"
  same "$(tail -n 1 "$config")" "# END MCP servers from $(pwd -P)"
  if command -v codex >/dev/null 2>&1; then
    (cd "$tdir" && codex mcp list --json) >"$out" 2>&1 || fail_now "codex can't read $config"
    same "$(jq -r 'map(.name) | sort | join(" ")' "$out")" "alpha mine"
  fi

  # Names defined elsewhere in the file are refused.
  write_servers '{"mine": {"command": "a"}}'
  fails .agents/scripts/sync-mcp.sh install-codex
  output_has "already defines mine"
  printf '[mcp_servers]\nother = { command = "o" }\n' >"$config"
  write_servers '{"other": {"command": "a"}}'
  fails .agents/scripts/sync-mcp.sh install-codex
  output_has "already defines other"

  printf '%s\n' "$original" >"$config"
  write_servers '{"alpha": {"command": "a"}}'
  ok .agents/scripts/sync-mcp.sh install-codex
  ok .agents/scripts/sync-mcp.sh uninstall-codex
  same "$(cat "$config")" "$original"
  ok .agents/scripts/sync-mcp.sh uninstall-codex
  output_has "nothing from this repo"

  # A private or symlinked config keeps its permissions and its link.
  mkdir -p "$tdir/dotfiles"
  mv "$config" "$tdir/dotfiles/config.toml"
  chmod 600 "$tdir/dotfiles/config.toml"
  ln -s "$tdir/dotfiles/config.toml" "$config"
  ok .agents/scripts/sync-mcp.sh install-codex
  [ -L "$config" ] || fail_now "install-codex replaced the symlinked config with a file"
  file_has "$tdir/dotfiles/config.toml" "# BEGIN MCP servers from"
  [ -n "$(find "$tdir/dotfiles/config.toml" -perm 600)" ] || fail_now "install-codex changed the config's permissions"
}

# --- the template itself -----------------------------------------------------

test_template_is_in_sync() {
  cd "$root/template" || exit 1
  working_link .claude/skills/new-skill
  ok .agents/scripts/link-skills.sh check
  ok .agents/scripts/sync-mcp.sh check
  jq -e . .agents/mcp/servers.example.json .claude/settings.json >/dev/null || fail_now "invalid JSON"
}

test_shellcheck() {
  command -v shellcheck >/dev/null 2>&1 || {
    echo "skipped: shellcheck is not installed"
    return 0
  }
  ok shellcheck "$root/scaffold.sh" "$root/tests/run.sh" "$root"/template/.agents/scripts/*.sh \
    "$root"/template/.agents/skills/new-skill/scripts/*.sh
}

# --- runner ------------------------------------------------------------------

if [ $# -gt 0 ]; then
  tests=("$@")
else
  tests=()
  while IFS= read -r name; do tests+=("$name"); done < <(declare -F | awk '{ print $3 }' | grep '^test_')
fi

passed=0
failed=0
for name in "${tests[@]}"; do
  name="test_${name#test_}"
  tdir="$work/$name"
  mkdir -p "$tdir/home"
  (
    export HOME="$tdir/home" CODEX_HOME="$tdir/codex-home"
    out="$tdir/out"
    cd "$tdir" || exit 1
    "$name"
  ) >"$tdir/log" 2>&1
  status=$?
  if [ "$status" -eq 0 ]; then
    passed=$((passed + 1))
    if grep -q '^skipped:' "$tdir/log"; then
      echo "skip ${name#test_} ($(grep '^skipped:' "$tdir/log" | head -n 1 | cut -c 10-))"
    else
      echo "ok   ${name#test_}"
    fi
  else
    failed=$((failed + 1))
    echo "FAIL ${name#test_}"
    sed 's/^/     /' "$tdir/log"
  fi
done

echo
echo "$passed passed, $failed failed (bash $BASH_VERSION)"
[ "$failed" -eq 0 ]
