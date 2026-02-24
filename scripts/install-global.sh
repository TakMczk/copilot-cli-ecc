#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PROMPTS_DIR="$HOME/Library/Application Support/Code/User/profiles/47c8a300/prompts"
PROMPTS_DIR="${VSCODE_PROMPTS_DIR:-$DEFAULT_PROMPTS_DIR}"
COPILOT_SKILLS_DIR="${COPILOT_SKILLS_DIR:-$HOME/.copilot/skills}"
ECC_GLOBAL_DIR="${ECC_GLOBAL_DIR:-$HOME/.copilot/ecc}"
CLAUDE_SETTINGS_PATH="${CLAUDE_SETTINGS_PATH:-$HOME/.claude/settings.json}"

mkdir -p "$PROMPTS_DIR"
mkdir -p "$COPILOT_SKILLS_DIR"
mkdir -p "$ECC_GLOBAL_DIR/scripts/hooks"
mkdir -p "$ECC_GLOBAL_DIR/scripts/lib"
mkdir -p "$(dirname "$CLAUDE_SETTINGS_PATH")"

echo "[install] copying global instructions"
cp "$ROOT_DIR/.github/copilot-instructions.md" "$PROMPTS_DIR/ecc-global.instructions.md"
cp "$ROOT_DIR/.github/instructions/"*.instructions.md "$PROMPTS_DIR/"

echo "[install] copying global custom agents"
for file in "$ROOT_DIR/.github/agents/"*.md; do
  name="$(basename "$file" .md)"
  cp "$file" "$PROMPTS_DIR/$name.agent.md"
done

echo "[install] copying global skills"
rsync -a --delete "$ROOT_DIR/.github/skills/" "$COPILOT_SKILLS_DIR/"

echo "[install] copying global hook scripts"
rsync -a --delete "$ROOT_DIR/.github/scripts/hooks/" "$ECC_GLOBAL_DIR/scripts/hooks/"
rsync -a --delete "$ROOT_DIR/.github/scripts/lib/" "$ECC_GLOBAL_DIR/scripts/lib/"

echo "[install] installing user hook configuration"
ECC_ROOT="$ROOT_DIR" ECC_GLOBAL_DIR="$ECC_GLOBAL_DIR" CLAUDE_SETTINGS_PATH="$CLAUDE_SETTINGS_PATH" node <<'NODE'
const fs = require('fs');
const path = require('path');

const eccRoot = process.env.ECC_ROOT;
const eccGlobalDir = process.env.ECC_GLOBAL_DIR;
const settingsPath = process.env.CLAUDE_SETTINGS_PATH;

const sourceHooksPath = path.join(eccRoot, '.github', 'hooks', 'ecc-hooks.json');
const raw = JSON.parse(fs.readFileSync(sourceHooksPath, 'utf8'));

const hooksDir = path.join(eccGlobalDir, 'scripts', 'hooks');
const transformed = { hooks: {} };

for (const [event, entries] of Object.entries(raw.hooks || {})) {
  transformed.hooks[event] = entries.map(entry => {
    const next = { ...entry };
    if (typeof next.command === 'string') {
      next.command = next.command.replace(
        /node \.github\/scripts\/hooks\/([\w.-]+\.js)/,
        (_, scriptName) => `node "${path.join(hooksDir, scriptName)}"`
      );
    }
    return next;
  });
}

let settings = {};
if (fs.existsSync(settingsPath)) {
  try {
    settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
  } catch {
    settings = {};
  }
}

if (fs.existsSync(settingsPath)) {
  const backupPath = `${settingsPath}.bak-${Date.now()}`;
  fs.copyFileSync(settingsPath, backupPath);
  console.log(`[install] backup created: ${backupPath}`);
}

settings = {
  ...settings,
  hooks: transformed.hooks,
};

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2), 'utf8');
console.log(`[install] hooks updated: ${settingsPath}`);
NODE

echo "[install] complete"
echo "[info] prompts dir: $PROMPTS_DIR"
echo "[info] skills dir:  $COPILOT_SKILLS_DIR"
echo "[info] hooks dir:   $ECC_GLOBAL_DIR/scripts/hooks"
