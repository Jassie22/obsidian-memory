#!/usr/bin/env bash
# Cross-vault wrapper around vault_search.py. Searches every registered vault
# in turn, prefixes each row with the vault name, and merges the results
# sorted by ascending distance (closer = more relevant).
#
# Usage:
#   vault_recall.sh search "<query>"        # default top-5 across all vaults
#   vault_recall.sh search "<query>" 10     # top-10
#   vault_recall.sh find-similar "<title>"
#   vault_recall.sh stats                   # stats per vault
#   vault_recall.sh index                   # rebuild every vault's index
#
# Filter to a single vault: VAULT_NAME=company vault_recall.sh search "..."
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/vault_registry.sh"

cmd="${1:-stats}"
shift || true

PY="$SCRIPT_DIR/vault_search.py"
[[ -x "$PY" ]] || PY="python3 $SCRIPT_DIR/vault_search.py"

filter_name="${VAULT_NAME:-}"

run_per_vault() {
  local action="$1"; shift
  local merged
  merged=$(mktemp)
  while IFS=$'\t' read -r vname vpath vrole; do
    [[ -n "$filter_name" && "$vname" != "$filter_name" ]] && continue
    [[ ! -d "$vpath" ]] && continue
    case "$action" in
      search|find-similar)
        VAULT_DIR="$vpath" $PY "$action" "$@" 2>/dev/null \
          | awk -v v="$vname" -F'\t' 'NF>=2{printf "%s\t%s\t%s\n", $1, v, substr($0, index($0,$2))}'
        ;;
      index|stats)
        printf '== %s (%s) ==\n' "$vname" "$vpath"
        VAULT_DIR="$vpath" $PY "$action" "$@" 2>&1
        ;;
    esac
  done < <(vault_list_rows) >> "$merged"
  case "$action" in
    search|find-similar)
      sort -k1,1n "$merged" | head -"${RECALL_TOP:-5}"
      ;;
    *)
      cat "$merged"
      ;;
  esac
  rm -f "$merged"
}

case "$cmd" in
  search|find-similar)
    if [[ $# -lt 1 ]]; then
      printf 'usage: %s %s "<query>"\n' "$(basename "$0")" "$cmd" >&2
      exit 2
    fi
    if [[ "$cmd" == "search" && $# -ge 2 ]]; then
      RECALL_TOP="$2"
    fi
    run_per_vault "$cmd" "$1"
    ;;
  index|stats)
    run_per_vault "$cmd"
    ;;
  *)
    printf 'unknown command: %s\n' "$cmd" >&2
    exit 2
    ;;
esac
