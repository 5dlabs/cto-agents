#!/usr/bin/env bash
# Validate SKILL.md frontmatter against the Agent Skills spec (agentskills.io).
#
# Common-denominator schema that loads cleanly on every major agent CLI
# (Claude Code, VS Code/Copilot Chat, OpenCode/OpenClaw, Cursor, Context7,
# Cline rules, ronaldtebrake/agent-skills-validator, etc.):
#
#   REQUIRED (errors — fail the build)
#     name         lowercase alnum + hyphens: ^[a-z0-9]+(-[a-z0-9]+)*$
#                  length 1..64; MUST match the parent directory name
#                  (VS Code / Copilot Chat silently drops skills where the
#                   `name` field doesn't match the directory name)
#     description  string, non-blank, 1..1024 chars
#
#   OPTIONAL (warnings — don't fail the build, but advise)
#     description <50 chars                — too vague for agent routing
#     allowed-tools present                — Claude-Code-only (non-portable)
#     model present                        — Claude-Code sub-agent only
#     unknown top-level fields             — spec is extensible, just advise
#
# Usage:
#   scripts/validate-skill-frontmatter.sh           # pretty, exit 1 on errors
#   scripts/validate-skill-frontmatter.sh --quiet   # one error path per line
#   scripts/validate-skill-frontmatter.sh --json    # machine-readable
#   scripts/validate-skill-frontmatter.sh --strict  # warnings become errors

set -euo pipefail

QUIET=0; JSON=0; STRICT=0
for arg in "$@"; do
  case "$arg" in
    --quiet)  QUIET=1 ;;
    --json)   JSON=1 ;;
    --strict) STRICT=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

NAME_RE='^[a-z0-9]+(-[a-z0-9]+)*$'
KNOWN_FIELDS='name description license allowed-tools metadata compatibility model agents triggers llm_docs_url llm-docs-url version tags'

errors_files=(); errors_reasons=(); errors_details=()
warnings_files=(); warnings_reasons=(); warnings_details=()

add_error()   { errors_files+=("$1");   errors_reasons+=("$2");   errors_details+=("$3"); }
add_warning() { warnings_files+=("$1"); warnings_reasons+=("$2"); warnings_details+=("$3"); }

# Extract the first `---`…`---` block as plain text.
extract_frontmatter() {
  awk '
    /^---[[:space:]]*$/ { c++; if (c==2) exit; next }
    c==1 { print }
  ' "$1"
}

# Very light YAML field reader: grabs the scalar value for a top-level key,
# stripping surrounding quotes. Sufficient for spec-compliant frontmatter.
yaml_scalar() {
  local key="$1" fm="$2"
  printf '%s\n' "$fm" | awk -v k="$key" '
    $0 ~ "^"k":" {
      sub("^"k":[[:space:]]*", "")
      # strip trailing comment
      sub("[[:space:]]+#.*$", "")
      # strip surrounding quotes
      gsub(/^"|"$/, "")
      gsub(/^\x27|\x27$/, "")
      print; exit
    }'
}

yaml_top_keys() {
  printf '%s\n' "$1" | awk '
    /^[A-Za-z_][A-Za-z0-9_-]*:/ { sub(":.*$", ""); print }'
}

check_file() {
  local f="$1"
  local dir_name; dir_name="$(basename "$(dirname "$f")")"

  if ! head -1 "$f" | grep -q '^---[[:space:]]*$'; then
    add_error "$f" "no-frontmatter" "file does not start with \`---\`"
    return
  fi

  local fm; fm="$(extract_frontmatter "$f")"
  if [ -z "${fm// }" ]; then
    add_error "$f" "empty-frontmatter" "frontmatter block is empty"
    return
  fi

  # name
  local name; name="$(yaml_scalar name "$fm")"
  if [ -z "$name" ]; then
    add_error "$f" "missing-name" "required field \`name\` is missing"
  else
    local nlen=${#name}
    if ! [[ "$name" =~ $NAME_RE ]]; then
      add_error "$f" "invalid-name" "name \"$name\" must match $NAME_RE"
    elif [ "$nlen" -lt 1 ] || [ "$nlen" -gt 64 ]; then
      add_error "$f" "name-length" "name length $nlen not in 1..64"
    elif [ "$name" != "$dir_name" ]; then
      add_error "$f" "name-dirname-mismatch" \
        "name \"$name\" must match parent directory \"$dir_name\" (VS Code/Copilot silently drops mismatches)"
    fi
  fi

  # description
  local desc; desc="$(yaml_scalar description "$fm")"
  if [ -z "$desc" ]; then
    add_error "$f" "missing-description" "required field \`description\` is missing"
  else
    local dlen=${#desc}
    if [ "$dlen" -gt 1024 ]; then
      add_error "$f" "description-too-long" "description length $dlen exceeds 1024 chars"
    elif [ "$dlen" -lt 50 ]; then
      add_warning "$f" "description-too-short" \
        "description length $dlen <50 chars — unlikely to route agents well"
    fi
  fi

  # Advisory: Claude-Code-only fields
  if grep -qE '^allowed-tools:' <<< "$fm"; then
    add_warning "$f" "claude-code-only-field" \
      "\`allowed-tools\` is Claude-Code-only; non-portable to VS Code/Copilot/Cursor"
  fi
  if grep -qE '^model:' <<< "$fm"; then
    add_warning "$f" "claude-code-only-field" \
      "\`model\` is Claude-Code sub-agent-only; non-portable"
  fi

  # Advisory: unknown top-level keys
  local key
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    case " $KNOWN_FIELDS " in
      *" $key "*) : ;;
      *) add_warning "$f" "unknown-field" \
           "unknown top-level frontmatter key \`$key\` (spec is extensible, but most CLIs ignore it)"
         ;;
    esac
  done < <(yaml_top_keys "$fm")
}

while IFS= read -r f; do
  check_file "$f"
done < <(find . -type f -name 'SKILL.md' \
         -not -path './.git/*' \
         -not -path './node_modules/*' \
         -not -path './.github/*' | sort)

n_err=${#errors_files[@]}
n_warn=${#warnings_files[@]}

if [ "$JSON" -eq 1 ]; then
  printf '{"errors":['
  for i in "${!errors_files[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '{"file":%s,"reason":%s,"detail":%s}' \
      "$(jq -Rn --arg s "${errors_files[$i]}"   '$s')" \
      "$(jq -Rn --arg s "${errors_reasons[$i]}" '$s')" \
      "$(jq -Rn --arg s "${errors_details[$i]}" '$s')"
  done
  printf '],"warnings":['
  for i in "${!warnings_files[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '{"file":%s,"reason":%s,"detail":%s}' \
      "$(jq -Rn --arg s "${warnings_files[$i]}"   '$s')" \
      "$(jq -Rn --arg s "${warnings_reasons[$i]}" '$s')" \
      "$(jq -Rn --arg s "${warnings_details[$i]}" '$s')"
  done
  printf ']}\n'
elif [ "$QUIET" -eq 1 ]; then
  # Files-only output, suitable for piping to xargs
  printf '%s\n' "${errors_files[@]}" 2>/dev/null || true
  [ "$STRICT" -eq 1 ] && printf '%s\n' "${warnings_files[@]}" 2>/dev/null || true
else
  if [ "$n_err" -eq 0 ] && [ "$n_warn" -eq 0 ]; then
    echo "✅ All SKILL.md files pass validation."
  else
    if [ "$n_err" -gt 0 ]; then
      echo "❌ Errors ($n_err):"
      for i in "${!errors_files[@]}"; do
        printf '  [%s]\n    %s\n    → %s\n' \
          "${errors_reasons[$i]}" "${errors_files[$i]}" "${errors_details[$i]}"
      done
      echo ""
    fi
    if [ "$n_warn" -gt 0 ]; then
      echo "⚠️  Warnings ($n_warn):"
      for i in "${!warnings_files[@]}"; do
        printf '  [%s]\n    %s\n    → %s\n' \
          "${warnings_reasons[$i]}" "${warnings_files[$i]}" "${warnings_details[$i]}"
      done
      echo ""
    fi
    echo "Summary: $n_err error(s), $n_warn warning(s)"
  fi
fi

# Exit status: errors always fail; warnings fail only with --strict.
if [ "$n_err" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$n_warn" -gt 0 ]; then exit 2; fi
exit 0
