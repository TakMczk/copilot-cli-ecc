#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO="${ECC_UPSTREAM_REPO:-https://github.com/affaan-m/everything-claude-code.git}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

language_glob() {
  case "$1" in
    cpp)
      printf '%s\n' '**/*.c,**/*.cc,**/*.cpp,**/*.cxx,**/*.h,**/*.hh,**/*.hpp,**/*.hxx'
      ;;
    csharp)
      printf '%s\n' '**/*.cs'
      ;;
    golang)
      printf '%s\n' '**/*.go'
      ;;
    java)
      printf '%s\n' '**/*.java'
      ;;
    kotlin)
      printf '%s\n' '**/*.kt,**/*.kts'
      ;;
    perl)
      printf '%s\n' '**/*.pl,**/*.pm,**/*.t'
      ;;
    php)
      printf '%s\n' '**/*.php,**/*.phtml,**/*.php3,**/*.php4,**/*.php5,**/*.phps'
      ;;
    python)
      printf '%s\n' '**/*.py'
      ;;
    rust)
      printf '%s\n' '**/*.rs'
      ;;
    swift)
      printf '%s\n' '**/*.swift'
      ;;
    typescript)
      printf '%s\n' '**/*.ts,**/*.tsx,**/*.js,**/*.jsx,**/*.mjs,**/*.cjs'
      ;;
    *)
      return 1
      ;;
  esac
}

append_rule_file() {
  local output_path="$1"
  local source_path="$2"

  [[ -f "$source_path" ]] || return 0

  printf '## Source: %s\n\n' "$(basename "$source_path")" >> "$output_path"
  perl -0pe 's/\A---\n.*?\n---\n+//s; s/^> This file extends .*\n//mg' "$source_path" >> "$output_path"
  printf '\n\n' >> "$output_path"
}

append_rule_pack() {
  local source_dir="$1"
  local output_path="$2"
  local skip_name="$3"
  shift 3

  local preferred_names=("$@")
  local seen_names=""
  local file_name
  local source_path

  for file_name in "${preferred_names[@]}"; do
    source_path="$source_dir/$file_name"
    if [[ -f "$source_path" ]] && [[ "$file_name" != "$skip_name" ]]; then
      append_rule_file "$output_path" "$source_path"
      seen_names="${seen_names}${file_name}"$'\n'
    fi
  done

  for source_path in "$source_dir"/*.md; do
    [[ -f "$source_path" ]] || continue

    file_name="$(basename "$source_path")"

    if [[ "$file_name" == "README.md" ]] || [[ -n "$skip_name" && "$file_name" == "$skip_name" ]]; then
      continue
    fi

    if printf '%s' "$seen_names" | grep -Fqx "$file_name"; then
      continue
    fi

    append_rule_file "$output_path" "$source_path"
  done
}

generate_repo_instructions() {
  local rules_root="$1"
  local common_dir="$rules_root/common"
  local output_path="$ROOT_DIR/.github/copilot-instructions.md"

  [[ -d "$common_dir" ]] || return 0

  cat > "$output_path" <<'MARKDOWN'
# Global Copilot Instructions (Everything Claude Code port)

MARKDOWN

  append_rule_pack \
    "$common_dir" \
    "$output_path" \
    "" \
    coding-style.md \
    testing.md \
    git-workflow.md \
    performance.md \
    patterns.md \
    security.md \
    agents.md \
    hooks.md
}

generate_language_instructions() {
  local rules_root="$1"
  local target_dir="$ROOT_DIR/.github/instructions"
  local lang_dir
  local lang
  local apply_to
  local output_path

  mkdir -p "$target_dir"
  find "$target_dir" -maxdepth 1 -type f -name '*.instructions.md' -delete

  for lang_dir in "$rules_root"/*; do
    [[ -d "$lang_dir" ]] || continue

    lang="$(basename "$lang_dir")"
    apply_to="$(language_glob "$lang" || true)"

    [[ -n "$apply_to" ]] || continue

    output_path="$target_dir/$lang.instructions.md"
    printf -- '---\napplyTo: "%s"\n---\n\n' "$apply_to" > "$output_path"

    append_rule_pack \
      "$lang_dir" \
      "$output_path" \
      "hooks.md" \
      coding-style.md \
      patterns.md \
      security.md \
      testing.md
  done
}

generate_copilot_hooks() {
  cat > "$ROOT_DIR/.github/hooks/ecc-hooks.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"session:start\" \"scripts/hooks/session-start.js\" \"minimal,standard,strict\"",
        "timeout": 30
      }
    ],
    "PreToolUse": [
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"pre:bash:commit-quality\" \"scripts/hooks/pre-bash-commit-quality.js\" \"strict\"",
        "timeout": 15
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"pre:write:doc-file-warning\" \"scripts/hooks/doc-file-warning.js\" \"standard,strict\"",
        "timeout": 10
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"pre:edit-write:suggest-compact\" \"scripts/hooks/suggest-compact.js\" \"standard,strict\"",
        "timeout": 10
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"pre:config-protection\" \"scripts/hooks/config-protection.js\" \"standard,strict\"",
        "timeout": 5
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"pre:governance-capture\" \"scripts/hooks/governance-capture.js\" \"standard,strict\"",
        "timeout": 10
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"pre:mcp-health-check\" \"scripts/hooks/mcp-health-check.js\" \"standard,strict\"",
        "timeout": 10
      }
    ],
    "PostToolUse": [
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"post:quality-gate\" \"scripts/hooks/quality-gate.js\" \"standard,strict\"",
        "timeout": 30
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"post:edit:format\" \"scripts/hooks/post-edit-format.js\" \"strict\"",
        "timeout": 20
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"post:edit:typecheck\" \"scripts/hooks/post-edit-typecheck.js\" \"strict\"",
        "timeout": 20
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"post:edit:console-warn\" \"scripts/hooks/post-edit-console-warn.js\" \"standard,strict\"",
        "timeout": 15
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"post:governance-capture\" \"scripts/hooks/governance-capture.js\" \"standard,strict\"",
        "timeout": 15
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"stop:check-console-log\" \"scripts/hooks/check-console-log.js\" \"standard,strict\"",
        "timeout": 20
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"stop:session-end\" \"scripts/hooks/session-end.js\" \"minimal,standard,strict\"",
        "timeout": 20
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"stop:evaluate-session\" \"scripts/hooks/evaluate-session.js\" \"minimal,standard,strict\"",
        "timeout": 30
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"stop:cost-tracker\" \"scripts/hooks/cost-tracker.js\" \"minimal,standard,strict\"",
        "timeout": 30
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/run-with-flags.js \"stop:desktop-notify\" \"scripts/hooks/desktop-notify.js\" \"standard,strict\"",
        "timeout": 20
      }
    ]
  }
}
JSON
}

echo "[update] cloning upstream: $UPSTREAM_REPO"
git clone --depth 1 "$UPSTREAM_REPO" "$TMP_DIR/ecc" >/dev/null

echo "[update] syncing agents, skills, hooks scripts, libs"
rsync -a --delete "$TMP_DIR/ecc/agents/" "$ROOT_DIR/.github/agents/"
rsync -a --delete "$TMP_DIR/ecc/skills/" "$ROOT_DIR/.github/skills/"
rsync -a --delete "$TMP_DIR/ecc/scripts/hooks/" "$ROOT_DIR/.github/scripts/hooks/"

if [[ -d "$TMP_DIR/ecc/scripts/lib" ]]; then
  mkdir -p "$ROOT_DIR/.github/scripts/lib"
  rsync -a --delete "$TMP_DIR/ecc/scripts/lib/" "$ROOT_DIR/.github/scripts/lib/"
fi

if [[ -d "$TMP_DIR/ecc/rules" ]]; then
  echo "[update] regenerating Copilot instructions from upstream rules"
  generate_repo_instructions "$TMP_DIR/ecc/rules"
  generate_language_instructions "$TMP_DIR/ecc/rules"
fi

echo "[update] applying Copilot-specific normalization"
find "$ROOT_DIR/.github/agents" -maxdepth 1 -name '*.md' -type f -print0 | xargs -0 perl -i -pe 's/^model:\s.*\n//g'

echo "[update] regenerating Copilot hook configuration"
generate_copilot_hooks

echo "[update] done"
echo "[next] review diff, then reinstall for your target client:"
echo "       - GitHub Copilot CLI: ./scripts/install-copilot-cli.sh"
echo "       - VS Code / Claude compatibility layer: ./scripts/install-global.sh"
