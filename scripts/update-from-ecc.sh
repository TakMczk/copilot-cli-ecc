#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO="${ECC_UPSTREAM_REPO:-https://github.com/affaan-m/everything-claude-code.git}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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

echo "[update] applying Copilot-specific normalization"
find "$ROOT_DIR/.github/agents" -maxdepth 1 -name '*.md' -type f -print0 | xargs -0 perl -i -pe 's/^model:\s.*\n//g'

# Normalize instruction files for Copilot (.instructions.md supports applyTo frontmatter,
# but upstream Claude rules may include additional YAML blocks and broken local links)
for file in "$ROOT_DIR/.github/instructions/"*.instructions.md; do
  perl -0i -pe 's/\n## Source: testing\.md\n\n---\npaths:[\s\S]*?---\n/\n/g' "$file" || true
  perl -0i -pe 's/\n## Source: hooks\.md\n\n---\npaths:[\s\S]*?---\n/\n/g' "$file" || true
  perl -0i -pe 's/^> This file extends .*\n//mg' "$file" || true
done

# Ensure hooks config stays in Copilot format and includes Stop lifecycle actions
cat > "$ROOT_DIR/.github/hooks/ecc-hooks.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "node .github/scripts/hooks/session-start.js",
        "timeout": 20
      }
    ],
    "PreToolUse": [
      {
        "type": "command",
        "command": "node .github/scripts/hooks/suggest-compact.js",
        "timeout": 10
      }
    ],
    "PostToolUse": [
      {
        "type": "command",
        "command": "node .github/scripts/hooks/post-edit-format.js",
        "timeout": 20
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/post-edit-typecheck.js",
        "timeout": 20
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/post-edit-console-warn.js",
        "timeout": 15
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "node .github/scripts/hooks/check-console-log.js",
        "timeout": 20
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/session-end.js",
        "timeout": 20
      },
      {
        "type": "command",
        "command": "node .github/scripts/hooks/evaluate-session.js",
        "timeout": 30
      }
    ]
  }
}
JSON

echo "[update] done"
echo "[next] review diff, then run: ./scripts/install-global.sh"
