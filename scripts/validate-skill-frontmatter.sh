#!/usr/bin/env bash
# Validate Agent Skills frontmatter across all SKILL.md files.
#
# Agent Skills spec (Context7 / Anthropic) requires YAML frontmatter at the
# very top of SKILL.md with at least:
#   - name:        lowercase-hyphenated identifier (should match directory name)
#   - description: concise sentence describing what the skill does / when to use
#
# Usage:
#   scripts/validate-skill-frontmatter.sh           # prints broken files, exit 1 on any
#   scripts/validate-skill-frontmatter.sh --quiet   # list only, no headers
#   scripts/validate-skill-frontmatter.sh --json    # machine-readable output

set -euo pipefail

QUIET=0
JSON=0
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    --json)  JSON=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

broken_files=()
broken_reasons=()

check_file() {
  local f="$1"
  # Must start with ---
  if ! head -1 "$f" | grep -q '^---[[:space:]]*$'; then
    broken_files+=("$f")
    broken_reasons+=("no-frontmatter")
    return
  fi
  # Extract frontmatter block between first pair of --- markers
  local fm
  fm="$(awk '
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 { print }
  ' "$f")"
  if [ -z "$fm" ]; then
    broken_files+=("$f")
    broken_reasons+=("empty-frontmatter")
    return
  fi
  # Required: name
  if ! printf '%s\n' "$fm" | grep -qE '^name:[[:space:]]+'; then
    broken_files+=("$f")
    broken_reasons+=("missing-name")
    return
  fi
  # Required: description
  if ! printf '%s\n' "$fm" | grep -qE '^description:[[:space:]]+'; then
    broken_files+=("$f")
    broken_reasons+=("missing-description")
    return
  fi
}

while IFS= read -r f; do
  check_file "$f"
done < <(find . -type f -name 'SKILL.md' \
         -not -path './.git/*' \
         -not -path './node_modules/*' \
         -not -path './.github/*' | sort)

if [ "$JSON" -eq 1 ]; then
  printf '{"broken":['
  for i in "${!broken_files[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '{"file":%s,"reason":%s}' \
      "$(printf '%s' "${broken_files[$i]}" | jq -R .)" \
      "$(printf '%s' "${broken_reasons[$i]}" | jq -R .)"
  done
  printf ']}\n'
elif [ "${#broken_files[@]}" -eq 0 ]; then
  [ "$QUIET" -eq 0 ] && echo "✅ All SKILL.md files have valid frontmatter."
  exit 0
else
  if [ "$QUIET" -eq 0 ]; then
    echo "❌ Found ${#broken_files[@]} SKILL.md file(s) with invalid frontmatter:"
    echo
  fi
  for i in "${!broken_files[@]}"; do
    if [ "$QUIET" -eq 1 ]; then
      printf '%s\n' "${broken_files[$i]}"
    else
      printf '  %-30s  %s\n' "${broken_reasons[$i]}" "${broken_files[$i]}"
    fi
  done
fi

[ "${#broken_files[@]}" -eq 0 ]
