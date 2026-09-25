#!/usr/bin/env bash
# Render .agents/mcp/servers.json into each agent's MCP config.
#
#   .agents/scripts/sync-mcp.sh                  write .mcp.json, .cursor/mcp.json, .codex/config.toml
#   .agents/scripts/sync-mcp.sh check            change nothing; exit 1 if a file is out of date
#   .agents/scripts/sync-mcp.sh install-codex    add the servers to $CODEX_HOME/config.toml
#   .agents/scripts/sync-mcp.sh uninstall-codex  remove them again
#
# Codex reads .codex/config.toml only in projects you have marked as trusted.
# install-codex is the fallback for other projects: it writes the servers into
# a marked block of $CODEX_HOME/config.toml (default ~/.codex/config.toml).
#
# Needs jq (built into macOS 15 and later, preinstalled on GitHub runners).

set -euo pipefail

agents_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
repo_root="$(dirname "$agents_dir")"
servers="$agents_dir/mcp/servers.json"
mode="${1:-sync}"

die() {
  echo "error: $*" >&2
  exit 1
}

case "$mode" in
  sync | check | install-codex | uninstall-codex) ;;
  -h | --help)
    sed -n '2,14s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "usage: $0 [sync|check|install-codex|uninstall-codex]" >&2
    exit 2
    ;;
esac

command -v jq >/dev/null 2>&1 || die "jq is required (brew install jq, or apt-get install jq)"
[ -f "$servers" ] || die "missing ${servers#"$repo_root/"}"

# The jq program validates servers.json and renders one target:
# claude (.mcp.json), cursor (.cursor/mcp.json), codex (.codex/config.toml) or
# codex-block (the tables alone, for install-codex).
jq_program() {
  cat <<'JQ'
def fail($msg): error("servers.json: " + $msg);
def refs: [scan("\\$\\{[^}]*\\}?")];
def has_ref: test("\\$\\{");
def is_ref: test("^\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}$");
def ref_name: capture("\\$\\{(?<n>[A-Za-z_][A-Za-z0-9_]*)\\}").n;
def cursor_refs: gsub("\\$\\{(?<n>[A-Za-z_][A-Za-z0-9_]*)\\}"; "${env:\(.n)}");

def toml_key: if test("^[A-Za-z0-9_-]+$") then . else tojson end;
def toml_value:
  if type == "string" then tojson | gsub("\u007f"; "\\u007f")
  elif type == "array" then "[" + (map(toml_value) | join(", ")) + "]"
  elif type == "object" then
    if length == 0 then "{}"
    else "{ " + (to_entries | map("\(.key | toml_key) = \(.value | toml_value)") | join(", ")) + " }"
    end
  elif type == "null" then fail("null can't be written to TOML")
  else tostring
  end;

def strings_only($where):
  if type == "string" then .
  else fail("\($where) must be a string")
  end
  | if (refs | map(is_ref) | all) then .
    else fail("\($where): write variables as ${NAME}; other forms don't work in every agent")
    end;

# Check one server and fill in its type.
def server($name):
  if ($name | test("^[A-Za-z0-9_-]+$") | not) then fail("server name \"\($name)\" may only use letters, digits, - and _") else . end
  | if type != "object" then fail("\($name) must be an object") else . end
  | (keys - ["type", "command", "args", "env", "url", "headers", "claude", "cursor", "codex"]) as $extra
  | if ($extra | length) > 0 then
      fail("\($name) has unknown fields: \($extra | join(", ")). Put fields for one agent under \"claude\", \"cursor\" or \"codex\"")
    else . end
  | .type //= (if has("url") then "http" else "stdio" end)
  | if .type == "stdio" then
      if has("url") or has("headers") then fail("\($name): url and headers are for http servers") else . end
      | .command |= strings_only("\($name).command")
      | if .command == "" then fail("\($name) needs a command") else . end
    elif .type == "http" then
      if has("command") or has("args") or has("env") then fail("\($name): command, args and env are for stdio servers") else . end
      | .url |= strings_only("\($name).url")
      | if .url == "" then fail("\($name) needs a url") else . end
    else fail("\($name): type must be \"stdio\" or \"http\"")
    end
  | if has("args") then
      if (.args | type) != "array" then fail("\($name).args must be a list") else . end
      | .args |= map(strings_only("\($name).args"))
    else . end
  | reduce ("env", "headers") as $field (.;
      if has($field) then
        if (.[$field] | type) != "object" then fail("\($name).\($field) must be an object") else . end
        | .[$field] |= with_entries(.key as $key | .value |= strings_only("\($name).\($field).\($key)"))
      else . end)
  | reduce ("claude", "cursor", "codex") as $agent (.;
      if has($agent) and .[$agent] != false and (.[$agent] | type) != "object" then
        fail("\($name).\($agent) must be an object of extra fields, or false to leave the server out")
      else . end);

def shared: {command, args, env, url, headers} | with_entries(select(.value != null));

def claude_entry: {type} + shared + (.claude // {});

# Cursor's docs list "type": "stdio" for local servers; remote ones go without.
def cursor_entry:
  (.cursor // {}) as $extra
  | (if .type == "stdio" then {type} else {} end) + shared
  | if has("command") then .command |= cursor_refs else . end
  | if has("args") then .args |= map(cursor_refs) else . end
  | if has("env") then .env |= map_values(cursor_refs) else . end
  | if has("url") then .url |= cursor_refs else . end
  | if has("headers") then .headers |= map_values(cursor_refs) else . end
  | . + $extra;

def codex_tables($name):
  ["", "[mcp_servers.\($name | toml_key)]"]
  + if .type == "stdio" then
      (if (.command | has_ref) then fail("\($name): Codex can't expand variables in command") else . end)
      | ["command = \(.command | toml_value)"]
      + (if has("args") then
           if (.args | map(has_ref) | any) then
             fail("\($name): Codex can't expand variables in args; pass the value through env instead")
           else ["args = \(.args | toml_value)"]
           end
         else [] end)
      + (if has("env") then
           (.env | to_entries) as $env
           | ($env | map(select(.value | has_ref | not)) | from_entries) as $plain
           | ($env | map(select(.value | has_ref))
              | map(if (.value | is_ref) and (.value | ref_name) == .key then .key
                    else fail("\($name).env.\(.key): Codex can only pass a variable through under its own name, as ${\(.key)}")
                    end)) as $passed
           | (if ($plain | length) > 0 then ["env = \($plain | toml_value)"] else [] end)
             + (if ($passed | length) > 0 then ["env_vars = \($passed | toml_value)"] else [] end)
         else [] end)
    else
      (if (.url | has_ref) then fail("\($name): Codex can't expand variables in url") else . end)
      | ["url = \(.url | toml_value)"]
      + (if has("headers") then
           (.headers | to_entries) as $headers
           | ($headers | map(select((.key | ascii_downcase) == "authorization"
                                    and (.value | test("^Bearer \\$\\{[A-Za-z_][A-Za-z0-9_]*\\}$"))))) as $bearer
           | ($headers | map(select(.value | has_ref | not)) | from_entries) as $plain
           | ($headers - $bearer | map(select(.value | has_ref))
              | map(if (.value | is_ref) then {key, value: (.value | ref_name)}
                    else fail("\($name).headers.\(.key): Codex needs the whole header to be \"${VAR}\", or \"Bearer ${VAR}\" for Authorization")
                    end)
              | from_entries) as $from_env
           | (if ($bearer | length) > 0 then ["bearer_token_env_var = \($bearer[0].value | ref_name | toml_value)"] else [] end)
             + (if ($plain | length) > 0 then ["http_headers = \($plain | toml_value)"] else [] end)
             + (if ($from_env | length) > 0 then ["env_http_headers = \($from_env | toml_value)"] else [] end)
         else [] end)
    end
  + ((.codex // {}) | to_entries | map("\(.key | toml_key) = \(.value | toml_value)"));

if type != "object" then fail("the top level must be an object of servers by name") else . end
| to_entries
| map(.key as $name | .value |= server($name))
| (if $target == "codex-block" then "codex" else $target end) as $agent
| map(select(.value[$agent] != false))
| if $agent == "claude" then {mcpServers: (map(.value |= claude_entry) | from_entries)}
  elif $agent == "cursor" then {mcpServers: (map(.value |= cursor_entry) | from_entries)}
  else
    (map(.key as $name | .value | codex_tables($name)) | add // []) as $tables
    | if $target == "codex" then
        ["# Generated from .agents/mcp/servers.json by .agents/scripts/sync-mcp.sh. Do not edit.",
         "# Codex reads this file only in trusted projects; see .agents/AGENTS.md."] + $tables
      else $tables[1:]
      end
    | join("\n")
  end
JQ
}

render() {
  local out status=0
  out="$(jq -r --indent 2 --arg target "$1" "$(jq_program)" "$servers" 2>&1)" || status=$?
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$out" | sed -e 's/^jq: error (at [^)]*): //' >&2
    exit 1
  fi
  printf '%s\n' "$out"
}

# Each generated file and the target that renders it.
outputs=(".mcp.json:claude" ".cursor/mcp.json:cursor" ".codex/config.toml:codex")

codex_config="${CODEX_HOME:-$HOME/.codex}/config.toml"
begin="# BEGIN MCP servers from $repo_root"
end="# END MCP servers from $repo_root"
# awk reads these from the environment: macOS awk rejects multi-line -v values.
export SYNC_MCP_BEGIN="$begin" SYNC_MCP_END="$end" SYNC_MCP_BLOCK=""

# Print the config with this repo's block removed, or with it replaced by
# $SYNC_MCP_BLOCK when that is set.
without_block() {
  [ -f "$codex_config" ] || return 0
  awk '$0 == ENVIRON["SYNC_MCP_BEGIN"] {
      if (ENVIRON["SYNC_MCP_BLOCK"] != "") print ENVIRON["SYNC_MCP_BLOCK"]
      skip = 1; next
    }
    $0 == ENVIRON["SYNC_MCP_END"] { skip = 0; next }
    !skip' "$codex_config"
}

current_block() {
  [ -f "$codex_config" ] || return 0
  awk '$0 == ENVIRON["SYNC_MCP_BEGIN"] { on = 1 } on { print } $0 == ENVIRON["SYNC_MCP_END"] { on = 0 }' "$codex_config"
}

wanted_block() {
  local tables
  tables="$(render codex-block)"
  [ -n "$tables" ] || return 0
  printf '%s\n%s\n%s\n%s\n' "$begin" \
    "# Managed by .agents/scripts/sync-mcp.sh install-codex; remove with uninstall-codex." \
    "$tables" "$end"
}

# Writes in place, so the file keeps its permissions and a symlinked config
# stays a symlink.
write_codex_config() { # <new content>
  mkdir -p "$(dirname "$codex_config")"
  [ ! -f "$codex_config" ] || cp "$codex_config" "$codex_config.bak"
  printf '%s' "$1" >"$codex_config"
}

case "$mode" in
  sync | check)
    # Render everything before writing anything, so an error leaves no file half-updated.
    rendered=()
    for entry in "${outputs[@]}"; do
      content="$(render "${entry##*:}")"
      rendered+=("$content")
    done
    stale=0
    i=0
    for entry in "${outputs[@]}"; do
      file="${entry%%:*}"
      content="${rendered[$i]}"
      i=$((i + 1))
      if [ -f "$repo_root/$file" ] && [ "$(cat "$repo_root/$file")" = "$content" ]; then
        continue
      fi
      if [ "$mode" = check ]; then
        echo "out of date: $file"
        stale=$((stale + 1))
      else
        mkdir -p "$(dirname "$repo_root/$file")"
        printf '%s\n' "$content" >"$repo_root/$file"
        echo "wrote $file"
      fi
    done
    if [ "$stale" -gt 0 ]; then
      echo "Edit .agents/mcp/servers.json, not the generated files, then run .agents/scripts/sync-mcp.sh." >&2
      exit 1
    fi
    count="$(jq 'length' "$servers")"
    echo "sync-mcp: $count server(s) in .mcp.json, .cursor/mcp.json and .codex/config.toml"
    block="$(current_block)"
    if [ "$mode" = sync ] && [ -n "$block" ] && [ "$block" != "$(wanted_block)" ]; then
      echo "note: the copy in $codex_config is out of date; run $0 install-codex"
    fi
    ;;

  install-codex)
    block="$(wanted_block)"
    [ -n "$block" ] || die "servers.json has no servers for Codex"
    # A server defined twice stops Codex from starting, so refuse duplicates.
    taken="$(without_block | awk '
      /^[ \t]*\[/ {
        table = $0
        sub(/^[ \t]*\[+[ \t]*/, "", table); sub(/[ \t]*\]+.*$/, "", table)
        if (table ~ /^mcp_servers\./) {
          name = substr(table, 13); sub(/\..*$/, "", name); gsub(/"/, "", name); print name
        }
        next
      }
      table == "mcp_servers" && /^[ \t]*[A-Za-z0-9_"-]+[ \t]*=/ {
        name = $0; sub(/[ \t]*=.*$/, "", name); gsub(/[ \t"]/, "", name); print name
      }' | sort -u)"
    ours="$(render codex-block | sed -n 's/^\[mcp_servers\.\([^]]*\)\]$/\1/p' | tr -d '"')"
    clash="$(printf '%s\n' "$ours" | grep -Fx -f <(printf '%s\n' "$taken") || true)"
    [ -z "$clash" ] ||
      die "$codex_config already defines $(echo "$clash" | tr '\n' ' ')outside this repo's block; remove or rename it first"
    [ "$(current_block)" != "$block" ] || {
      echo "install-codex: $codex_config is already up to date"
      exit 0
    }
    if [ -n "$(current_block)" ]; then
      new="$(SYNC_MCP_BLOCK="$block" without_block)" # replace the old block where it is
    else
      rest="$(without_block)"
      new="${rest:+$rest$'\n\n'}$block"
    fi
    write_codex_config "$new"$'\n'
    echo "install-codex: wrote $(printf '%s\n' "$ours" | wc -l | tr -d ' ') server(s) to $codex_config (backup: config.toml.bak)"
    ;;

  uninstall-codex)
    [ -n "$(current_block)" ] || {
      echo "uninstall-codex: nothing from this repo in $codex_config"
      exit 0
    }
    rest="$(without_block)"
    write_codex_config "${rest:+$rest$'\n'}"
    echo "uninstall-codex: removed this repo's servers from $codex_config (backup: config.toml.bak)"
    ;;
esac
