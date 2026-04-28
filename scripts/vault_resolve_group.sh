#!/usr/bin/env bash
# Resolve the active group + vault for the current working directory.
#
# Output: a single line of TSV — group<TAB>vault<TAB>source — or empty if
# nothing matched. Stable, machine-readable, easy to consume from CLAUDE.md
# instructions or other scripts:
#
#   $ vault_resolve_group.sh
#   arc       company   company-map
#   $ vault_resolve_group.sh --json
#   {"group":"arc","vault":"company","source":"company-map"}
#
# Resolution order (first match wins):
#   1. Per-repo CLAUDE.md `group:` field in cwd
#   2. <company-vault>/.repo-map.json mapping for `git remote get-url origin`
#   3. <personal-vault>/.repo-map.json mapping (personal overrides for forks etc.)
#   4. Path heuristic: any segment of cwd matches a slug in any vault's .groups
#   5. Cached prompt result in <personal-vault>/.repo-map.json
#
# Mapping file format (JSON, parseable with jq):
#   {
#     "mappings": [
#       {"remote": "github.com/yourorg/arc-frontend", "group": "arc"},
#       {"remote": "github.com/yourorg/arc-*",        "group": "arc"},
#       {"remote": "github.com/yourorg/monorepo",     "group": "shared",
#        "path_overrides": [
#          {"path": "services/truenode/**", "group": "truenode"}
#        ]}
#     ],
#     "defaults": {"vault": "company", "prompt_on_miss": true}
#   }
#
# Globs use shell-style `*` and `?`. Path overrides match against the cwd
# relative to the repo root.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/vault_registry.sh"

JSON=0
CWD="$PWD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=1 ;;
    --cwd)  CWD="$2"; shift ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

emit() {
  local group="$1" vault="$2" source="$3"
  if (( JSON )); then
    if command -v jq >/dev/null 2>&1; then
      jq -nc --arg g "$group" --arg v "$vault" --arg s "$source" \
        '{group:$g, vault:$v, source:$s}'
    else
      printf '{"group":"%s","vault":"%s","source":"%s"}\n' "$group" "$vault" "$source"
    fi
  else
    printf '%s\t%s\t%s\n' "$group" "$vault" "$source"
  fi
}

# 1. Per-repo CLAUDE.md `group:` field — explicit overrides win.
if [[ -f "$CWD/CLAUDE.md" ]]; then
  group=$(awk '/^group:/{sub(/^group: */,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$CWD/CLAUDE.md")
  vault_field=$(awk '/^vault:/{sub(/^vault: */,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$CWD/CLAUDE.md")
  if [[ -n "${group:-}" ]]; then
    if [[ -n "${vault_field:-}" ]]; then
      emit "$group" "$vault_field" "repo-claude-md"
    else
      # Default to company if the group is registered there, else personal.
      cv=$(vault_company_path); pv=$(vault_personal_path)
      vname=""
      [[ -n "$cv" && -f "$cv/.groups" ]] && grep -qxF "$group" "$cv/.groups" 2>/dev/null && vname=$(vault_name_for_role shared)
      if [[ -z "$vname" && -n "$pv" && -f "$pv/.groups" ]]; then
        grep -qxF "$group" "$pv/.groups" 2>/dev/null && vname=$(vault_name_for_role private)
      fi
      [[ -z "$vname" ]] && vname=$(vault_name_for_role shared)
      [[ -z "$vname" ]] && vname=$(vault_name_for_role private)
      [[ -z "$vname" ]] && vname="vault"
      emit "$group" "$vname" "repo-claude-md"
    fi
    exit 0
  fi
fi

# Normalize a git remote URL into <host>/<org>/<repo>, lowercased, no .git suffix.
# Handles ssh (git@host:org/repo), https (https://host/org/repo[.git]), and
# scheme-less forms. Empty stdout if the input is empty.
normalize_remote() {
  local u="$1"
  [[ -z "$u" ]] && return 0
  u="${u%.git}"
  u="${u#https://}"; u="${u#http://}"; u="${u#git://}"; u="${u#ssh://}"
  # ssh form: git@host:org/repo
  if [[ "$u" == *"@"*":"* ]]; then
    u="${u#*@}"
    u="${u/://}"
  fi
  # strip any user-info that survived (host already stripped above for https)
  u="${u#*@}"
  printf '%s' "$u" | tr '[:upper:]' '[:lower:]'
}

# Walk a JSON map file looking for a remote match. Echoes group on first hit.
# Optionally also matches path_overrides relative to repo root ($2).
match_in_map() {
  local map_file="$1" remote_norm="$2" rel_path="${3:-}"
  [[ -f "$map_file" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local count
  count=$(jq -r '.mappings | length // 0' "$map_file" 2>/dev/null)
  [[ -z "$count" || "$count" == "null" ]] && return 1
  local i=0 pat group ovr_count j ovr_pat ovr_group
  while (( i < count )); do
    pat=$(jq -r ".mappings[$i].remote // empty" "$map_file" 2>/dev/null)
    group=$(jq -r ".mappings[$i].group // empty" "$map_file" 2>/dev/null)
    if [[ -n "$pat" && -n "$group" ]]; then
      pat=$(printf '%s' "$pat" | tr '[:upper:]' '[:lower:]')
      pat="${pat%.git}"
      # shellcheck disable=SC2053  # intentional glob match
      if [[ "$remote_norm" == $pat ]]; then
        # check path overrides for monorepos
        if [[ -n "$rel_path" ]]; then
          ovr_count=$(jq -r ".mappings[$i].path_overrides | length // 0" "$map_file" 2>/dev/null)
          j=0
          while (( j < ovr_count )); do
            ovr_pat=$(jq -r ".mappings[$i].path_overrides[$j].path // empty" "$map_file" 2>/dev/null)
            ovr_group=$(jq -r ".mappings[$i].path_overrides[$j].group // empty" "$map_file" 2>/dev/null)
            # shellcheck disable=SC2053
            if [[ -n "$ovr_pat" && -n "$ovr_group" && "$rel_path" == $ovr_pat ]]; then
              printf '%s' "$ovr_group"
              return 0
            fi
            j=$((j + 1))
          done
        fi
        printf '%s' "$group"
        return 0
      fi
    fi
    i=$((i + 1))
  done
  return 1
}

# 2/3. Look up the git remote in each vault's .repo-map.json (company first).
remote_url=""
repo_root=""
if command -v git >/dev/null 2>&1; then
  remote_url=$(git -C "$CWD" remote get-url origin 2>/dev/null || true)
  # Prefer upstream if defined (works in fork-of-fork setups).
  upstream_url=$(git -C "$CWD" remote get-url upstream 2>/dev/null || true)
  [[ -n "$upstream_url" ]] && remote_url="$upstream_url"
  repo_root=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)
fi
remote_norm=$(normalize_remote "$remote_url")
rel_path=""
if [[ -n "$repo_root" && "$CWD" == "$repo_root"* ]]; then
  rel_path="${CWD#$repo_root}"
  rel_path="${rel_path#/}"
fi

if [[ -n "$remote_norm" ]]; then
  cv=$(vault_company_path)
  if [[ -n "$cv" ]]; then
    if g=$(match_in_map "$cv/.repo-map.json" "$remote_norm" "$rel_path"); then
      emit "$g" "$(vault_name_for_role shared)" "company-map"
      exit 0
    fi
  fi
  pv=$(vault_personal_path)
  if [[ -n "$pv" ]]; then
    if g=$(match_in_map "$pv/.repo-map.json" "$remote_norm" "$rel_path"); then
      emit "$g" "$(vault_name_for_role private)" "personal-map"
      exit 0
    fi
  fi
fi

# 4. Path heuristic: does any path segment match a slug in any .groups file?
while IFS=$'\t' read -r vname vpath vrole; do
  [[ -z "$vpath" || ! -f "$vpath/.groups" ]] && continue
  while IFS= read -r slug; do
    [[ -z "$slug" || "$slug" == \#* ]] && continue
    case "/$CWD/" in
      *"/$slug/"*)
        emit "$slug" "$vname" "path-heuristic"
        exit 0
        ;;
    esac
  done < "$vpath/.groups"
done < <(vault_list_rows)

# 5. Nothing matched — emit empty source so callers can decide whether to prompt.
emit "" "" "unresolved"
exit 0
