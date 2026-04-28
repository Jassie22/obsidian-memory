#!/usr/bin/env bash
# Helpers for reading the vault registry. Source this from other scripts:
#   . "$(dirname "${BASH_SOURCE[0]}")/vault_registry.sh"
#
# Registry file: ~/.claude/vaults.json
#   {
#     "vaults": [
#       {"name": "company",  "path": "~/company-vault", "role": "shared"},
#       {"name": "personal", "path": "~/vault",         "role": "private"}
#     ]
#   }
#
# Backwards-compat: if the file is missing, behaves as if the single legacy
# vault at $VAULT_DIR (default ~/vault) were registered with role=private.
# That way every existing single-vault install keeps working unchanged.
#
# All functions echo absolute paths with ~ expanded.

VAULT_REGISTRY="${VAULT_REGISTRY:-$HOME/.claude/vaults.json}"
LEGACY_VAULT="${VAULT_DIR:-$HOME/vault}"

_vr_have_jq() { command -v jq >/dev/null 2>&1; }

_vr_expand() {
  # Expand a leading ~ to $HOME. Leaves absolute / relative paths alone.
  # Note: ${p#~/} unsafely tilde-expands inside the brace — use a substring.
  local p="$1"
  case "$p" in
    "~/"*) printf '%s\n' "$HOME/${p:2}" ;;
    "~")   printf '%s\n' "$HOME" ;;
    *)     printf '%s\n' "$p" ;;
  esac
}

# List every registered vault path, one per line. Falls back to the legacy
# single-vault path if no registry exists. Prunes entries whose path doesn't
# exist on disk so callers don't have to.
vault_list_paths() {
  if [[ -f "$VAULT_REGISTRY" ]] && _vr_have_jq; then
    jq -r '.vaults[]?.path // empty' "$VAULT_REGISTRY" 2>/dev/null \
      | while read -r p; do
          [[ -z "$p" ]] && continue
          _vr_expand "$p"
        done
  else
    printf '%s\n' "$LEGACY_VAULT"
  fi
}

# Same as vault_list_paths but emits one TSV row per vault: name<TAB>path<TAB>role
vault_list_rows() {
  if [[ -f "$VAULT_REGISTRY" ]] && _vr_have_jq; then
    jq -r '.vaults[]? | [(.name // "vault"), .path, (.role // "private")] | @tsv' \
      "$VAULT_REGISTRY" 2>/dev/null \
      | while IFS=$'\t' read -r n p r; do
          [[ -z "$p" ]] && continue
          printf '%s\t%s\t%s\n' "$n" "$(_vr_expand "$p")" "$r"
        done
  else
    printf 'vault\t%s\tprivate\n' "$LEGACY_VAULT"
  fi
}

# Echo the path of the single vault with role=private. Empty if none.
# Personal vault is where rules, logs, captures, and inbox live.
vault_personal_path() {
  vault_list_rows | awk -F'\t' '$3=="private"{print $2; exit}'
}

# Echo the path of the single vault with role=shared. Empty if none.
# Company vault is where durable team-wide notes (decisions, runbooks,
# architecture, gotchas) live.
vault_company_path() {
  vault_list_rows | awk -F'\t' '$3=="shared"{print $2; exit}'
}

# Echo the name of the vault with role=X (private/shared). Empty if none.
vault_name_for_role() {
  vault_list_rows | awk -F'\t' -v r="$1" '$3==r{print $1; exit}'
}

# Given a filesystem path, echo the name of the registered vault that contains
# it (longest-prefix match wins, so nested vault paths still resolve correctly).
# Empty stdout + non-zero exit if the path is outside every registered vault.
vault_for_path() {
  local target="$1"
  [[ -z "$target" ]] && return 1
  local best_name="" best_path="" best_len=0
  while IFS=$'\t' read -r n p r; do
    [[ -z "$p" ]] && continue
    case "$target" in
      "$p"/*|"$p")
        if (( ${#p} > best_len )); then
          best_name="$n"; best_path="$p"; best_len=${#p}
        fi
        ;;
    esac
  done < <(vault_list_rows)
  [[ -z "$best_name" ]] && return 1
  printf '%s\t%s\n' "$best_name" "$best_path"
}

# Echo the path of a vault by name. Empty if not registered.
vault_path_by_name() {
  vault_list_rows | awk -F'\t' -v n="$1" '$1==n{print $2; exit}'
}
