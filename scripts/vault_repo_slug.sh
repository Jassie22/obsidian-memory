#!/usr/bin/env bash
# Derive a repo slug from the current directory's git remote, for use as a
# vault note tag (`repo/<slug>`). Empty output if not in a git repo or no
# remote — caller skips the tag in that case.
#
# Usage:
#   vault_repo_slug.sh [path]   # default: current dir
#   echo "tags: [<group>, repo/$(vault_repo_slug.sh)]"
#
# Examples:
#   git@github.com:arc-simulations/arc-frontend.git  → arc-frontend
#   https://github.com/arc-simulations/truenode-api  → truenode-api
#   /tmp/some-non-git-dir                            → (empty, exit 0)
set -u

dir="${1:-$PWD}"
[[ -d "$dir" ]] || exit 0

# `git -C` will return non-zero from any non-git dir; the `|| true`
# swallows that and we just emit nothing.
url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
[[ -z "$url" ]] && exit 0

# Strip any of: `git@host:`, `https://host/`, `ssh://git@host/`, then `.git`
slug="${url##*[:/]}"     # last segment after `:` or `/`
slug="${slug%.git}"
slug="${slug%/}"

# Sanity-check: kebab-case-ish, no path separators left
[[ -z "$slug" || "$slug" == *"/"* ]] && exit 0

printf '%s' "$slug"
