#!/usr/bin/env bash
# Register an author's callout class in the company vault's CSS snippet,
# using a deterministic color derived from the author's name. Idempotent —
# safe to re-run on every setup.sh invocation.
#
# Usage:
#   vault_register_callout.sh <author> <company-vault-dir>
#
# Why deterministic: same name → same color on every teammate's machine
# without any coordination. Two teammates with different names will see
# different colors for the same person, but everyone agrees on each name's
# color.
set -euo pipefail

AUTHOR="${1:?author name required}"
VAULT="${2:?company vault dir required}"

[[ -d "$VAULT" ]] || { echo "vault dir not found: $VAULT" >&2; exit 1; }

# Deterministic color from name: md5 → hue (0-359), fixed sat 65% / lightness
# 55%, then HSL → RGB. 360 hues ≈ negligible collision risk for ≤20 teammates.
slug="$(printf '%s' "$AUTHOR" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-_')"
color="$(python3 - "$slug" <<'PY'
import sys, hashlib, colorsys
name = sys.argv[1]
h = int(hashlib.md5(name.encode()).hexdigest()[:4], 16) % 360 / 360.0
r, g, b = colorsys.hls_to_rgb(h, 0.55, 0.65)
print(f"{int(r*255)},{int(g*255)},{int(b*255)}")
PY
)"

snippet_dir="$VAULT/.obsidian/snippets"
snippet="$snippet_dir/authors.css"
mkdir -p "$snippet_dir"

# If our author already has an entry, leave it alone.
if [[ -f "$snippet" ]] && grep -qE "^\.callout\[data-callout=\"$slug\"\]" "$snippet"; then
  echo "callout already registered: [!$slug] (color $color)"
  exit 0
fi

# Append a new rule. Header on first creation only.
if [[ ! -f "$snippet" ]]; then
  cat > "$snippet" <<'HEADER'
/* Author callouts — auto-maintained by setup.sh. Each teammate's name
   gets a unique callout class with a deterministic color derived from
   the name (md5 mod 12 over a 12-color palette). Use these in notes:

       > [!jasmeen] 2026-04-28
       > My addition to this paragraph.

   Don't hand-edit color values — they'll diverge from other teammates'
   files. Add new entries by re-running setup.sh --author "Name".
   Removing entries: just delete the matching block. */
HEADER
fi

cat >> "$snippet" <<EOF

.callout[data-callout="$slug"] {
  --callout-color: $color;
  --callout-icon: lucide-user;
}
.callout[data-callout="$slug"] .callout-title-inner::before {
  content: "$AUTHOR — ";
  font-weight: 600;
  opacity: 0.85;
}
EOF

# Ensure Obsidian auto-enables the snippet for everyone (commits to git).
appearance="$VAULT/.obsidian/appearance.json"
if command -v jq >/dev/null 2>&1; then
  if [[ ! -f "$appearance" ]]; then
    echo '{}' > "$appearance"
  fi
  tmp="$(mktemp)"
  jq '.enabledCssSnippets = ((.enabledCssSnippets // []) + ["authors"] | unique)' \
     "$appearance" > "$tmp" && mv "$tmp" "$appearance"
fi

echo "registered callout: [!$slug] → rgb($color)"
