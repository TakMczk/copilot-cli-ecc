#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_GITHUB_DIR="$ROOT_DIR/.github"
SOURCE_COPILOT_INSTRUCTIONS_FILE="$SOURCE_GITHUB_DIR/copilot-instructions.md"
SOURCE_AGENTS_DIR="$SOURCE_GITHUB_DIR/agents"
SOURCE_SKILLS_DIR="$SOURCE_GITHUB_DIR/skills"
SOURCE_EXTRA_INSTRUCTIONS_DIR="$SOURCE_GITHUB_DIR/instructions"

COPILOT_HOME_DIR="${COPILOT_HOME:-$HOME/.copilot}"
TARGET_COPILOT_INSTRUCTIONS_FILE="${COPILOT_CLI_INSTRUCTIONS_FILE:-$COPILOT_HOME_DIR/copilot-instructions.md}"
TARGET_AGENTS_DIR="${COPILOT_CLI_AGENTS_DIR:-$COPILOT_HOME_DIR/agents}"
TARGET_SKILLS_DIR="${COPILOT_CLI_SKILLS_DIR:-$COPILOT_HOME_DIR/skills}"
TARGET_EXTRA_INSTRUCTIONS_DIR="${COPILOT_CLI_EXTRA_INSTRUCTIONS_DIR:-$COPILOT_HOME_DIR/instructions/copilot-cli-ecc}"
STATE_DIR="${COPILOT_CLI_STATE_DIR:-$COPILOT_HOME_DIR/copilot-cli-ecc-state}"

MARKDOWN_BLOCK_START="<!-- copilot-cli-ecc:begin -->"
MARKDOWN_BLOCK_END="<!-- copilot-cli-ecc:end -->"
RC_BLOCK_START="# >>> copilot-cli-ecc >>>"
RC_BLOCK_END="# <<< copilot-cli-ecc <<<"

DRY_RUN=0
UPDATE_SHELL_RC=1
SHELL_RC_PATH="${COPILOT_CLI_SHELL_RC_PATH:-}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MANIFEST_DIR="$STATE_DIR/manifests"
BACKUP_ROOT="$STATE_DIR/backups/$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-copilot-cli.sh [options]

Installs copilot-cli-ecc assets into GitHub Copilot CLI's supported user-level paths.

Options:
  --dry-run       Show planned changes without writing files
  --no-shell-rc   Do not update shell startup files with COPILOT_CUSTOM_INSTRUCTIONS_DIRS
  --shell-rc PATH Write the shell snippet to PATH instead of auto-detecting
  --help          Show this help

Environment overrides:
  COPILOT_HOME                     Override Copilot CLI home (default: ~/.copilot)
  COPILOT_CLI_INSTRUCTIONS_FILE    Target path for copilot-instructions.md
  COPILOT_CLI_AGENTS_DIR           Target directory for custom agents
  COPILOT_CLI_SKILLS_DIR           Target directory for skills
  COPILOT_CLI_EXTRA_INSTRUCTIONS_DIR
                                   Target directory for *.instructions.md files
  COPILOT_CLI_STATE_DIR            Directory for manifests and backups
  COPILOT_CLI_SHELL_RC_PATH        Shell rc file to update
EOF
}

log() {
  printf '[install-copilot-cli] %s\n' "$*"
}

fail() {
  printf >&2 '[install-copilot-cli][error] %s\n' "$*"
  exit 1
}

ensure_exists() {
  local path="$1"
  [[ -e "$path" ]] || fail "required path not found: $path"
}

while (($# > 0)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --no-shell-rc)
      UPDATE_SHELL_RC=0
      ;;
    --shell-rc)
      shift
      (($# > 0)) || fail "--shell-rc requires a path"
      SHELL_RC_PATH="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
  shift
done

ensure_exists "$SOURCE_COPILOT_INSTRUCTIONS_FILE"
ensure_exists "$SOURCE_AGENTS_DIR"
ensure_exists "$SOURCE_SKILLS_DIR"
ensure_exists "$SOURCE_EXTRA_INSTRUCTIONS_DIR"

detect_shell_rc() {
  if [[ -n "$SHELL_RC_PATH" ]]; then
    printf '%s\n' "$SHELL_RC_PATH"
    return
  fi

  case "${SHELL##*/}" in
    bash)
      printf '%s\n' "$HOME/.bashrc"
      ;;
    zsh)
      printf '%s\n' "$HOME/.zshrc"
      ;;
    *)
      printf '%s\n' "$HOME/.profile"
      ;;
  esac
}

ensure_dir() {
  local dir="$1"
  if ((DRY_RUN)); then
    log "mkdir -p $dir"
  else
    mkdir -p "$dir"
  fi
}

backup_path() {
  local path="$1"
  [[ -e "$path" ]] || return 0

  local backup_path="$BACKUP_ROOT/${path#/}"
  ensure_dir "$(dirname "$backup_path")"

  if ((DRY_RUN)); then
    log "backup $path -> $backup_path"
  else
    cp -a "$path" "$backup_path"
  fi
}

copy_file_if_changed() {
  local source_path="$1"
  local target_path="$2"

  if [[ -e "$target_path" ]] && cmp -s "$source_path" "$target_path"; then
    return 0
  fi

  if [[ -e "$target_path" ]]; then
    backup_path "$target_path"
  fi

  ensure_dir "$(dirname "$target_path")"

  if ((DRY_RUN)); then
    log "install -m 0644 $source_path -> $target_path"
  else
    install -m 0644 "$source_path" "$target_path"
  fi
}

merge_managed_block_from_file() {
  local source_file="$1"
  local target_file="$2"
  local block_start="$3"
  local block_end="$4"
  local rendered_file="$TMP_DIR/rendered-$(basename "$target_file").tmp"

  python - "$source_file" "$target_file" "$block_start" "$block_end" >"$rendered_file" <<'PY'
import pathlib
import re
import sys

source_path = pathlib.Path(sys.argv[1])
target_path = pathlib.Path(sys.argv[2])
block_start = sys.argv[3]
block_end = sys.argv[4]

source_text = source_path.read_text(encoding="utf-8").rstrip() + "\n"
managed_block = f"{block_start}\n{source_text}{block_end}\n"

if target_path.exists():
    target_text = target_path.read_text(encoding="utf-8")
else:
    target_text = ""

has_start = block_start in target_text
has_end = block_end in target_text

if has_start != has_end:
    raise SystemExit(
        f"inconsistent managed block markers in {target_path}: expected both or neither"
    )

if has_start:
    pattern = re.compile(re.escape(block_start) + r".*?" + re.escape(block_end) + r"\n?", re.S)
    merged = pattern.sub(managed_block, target_text, count=1)
else:
    stripped = target_text.rstrip()
    if stripped:
      merged = stripped + "\n\n" + managed_block
    else:
      merged = managed_block

sys.stdout.write(merged)
PY

  if [[ -e "$target_file" ]] && cmp -s "$rendered_file" "$target_file"; then
    return 0
  fi

  if [[ -e "$target_file" ]]; then
    backup_path "$target_file"
  fi

  ensure_dir "$(dirname "$target_file")"

  if ((DRY_RUN)); then
    log "update managed block in $target_file"
  else
    install -m 0644 "$rendered_file" "$target_file"
  fi
}

remove_stale_entries() {
  local manifest_path="$1"
  local current_entries_path="$2"
  local target_root="$3"
  local entry_label="$4"

  [[ -f "$manifest_path" ]] || return 0

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue

    if grep -Fqx "$entry" "$current_entries_path"; then
      continue
    fi

    local target_path="$target_root/$entry"
    if [[ -e "$target_path" ]]; then
      backup_path "$target_path"
      if ((DRY_RUN)); then
        log "remove stale $entry_label $target_path"
      else
        rm -rf "$target_path"
      fi
    fi
  done <"$manifest_path"
}

write_manifest() {
  local current_entries_path="$1"
  local manifest_path="$2"

  if ((DRY_RUN)); then
    log "write manifest $manifest_path"
    return 0
  fi

  ensure_dir "$(dirname "$manifest_path")"
  cp "$current_entries_path" "$manifest_path"
}

sync_agents() {
  local current_entries_path="$TMP_DIR/agents.txt"
  local manifest_path="$MANIFEST_DIR/agents.txt"

  find "$SOURCE_AGENTS_DIR" -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort >"$current_entries_path"

  ensure_dir "$TARGET_AGENTS_DIR"
  remove_stale_entries "$manifest_path" "$current_entries_path" "$TARGET_AGENTS_DIR" "agent"

  while IFS= read -r filename; do
    [[ -n "$filename" ]] || continue
    copy_file_if_changed "$SOURCE_AGENTS_DIR/$filename" "$TARGET_AGENTS_DIR/$filename"
  done <"$current_entries_path"

  write_manifest "$current_entries_path" "$manifest_path"
}

sync_extra_instructions() {
  local current_entries_path="$TMP_DIR/extra-instructions.txt"
  local manifest_path="$MANIFEST_DIR/extra-instructions.txt"

  find "$SOURCE_EXTRA_INSTRUCTIONS_DIR" -maxdepth 1 -type f -name '*.instructions.md' -printf '%f\n' | sort >"$current_entries_path"

  ensure_dir "$TARGET_EXTRA_INSTRUCTIONS_DIR"
  remove_stale_entries "$manifest_path" "$current_entries_path" "$TARGET_EXTRA_INSTRUCTIONS_DIR" "instruction"

  while IFS= read -r filename; do
    [[ -n "$filename" ]] || continue
    copy_file_if_changed "$SOURCE_EXTRA_INSTRUCTIONS_DIR/$filename" "$TARGET_EXTRA_INSTRUCTIONS_DIR/$filename"
  done <"$current_entries_path"

  write_manifest "$current_entries_path" "$manifest_path"
}

sync_skills() {
  local current_entries_path="$TMP_DIR/skills.txt"
  local manifest_path="$MANIFEST_DIR/skills.txt"

  find "$SOURCE_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort >"$current_entries_path"

  ensure_dir "$TARGET_SKILLS_DIR"
  remove_stale_entries "$manifest_path" "$current_entries_path" "$TARGET_SKILLS_DIR" "skill"

  while IFS= read -r skill_name; do
    [[ -n "$skill_name" ]] || continue

    local source_dir="$SOURCE_SKILLS_DIR/$skill_name/"
    local target_dir="$TARGET_SKILLS_DIR/$skill_name/"
    local preview_file="$TMP_DIR/rsync-$skill_name.preview"

    if [[ -d "$target_dir" ]]; then
      rsync -ani --delete "$source_dir" "$target_dir" | grep -Ev '^(sending incremental file list|$)' >"$preview_file" || true
      if [[ -s "$preview_file" ]]; then
        backup_path "$target_dir"
      fi
    fi

    ensure_dir "$target_dir"
    if ((DRY_RUN)); then
      log "rsync -a --delete $source_dir $target_dir"
    else
      rsync -a --delete "$source_dir" "$target_dir"
    fi
  done <"$current_entries_path"

  write_manifest "$current_entries_path" "$manifest_path"
}

update_shell_rc() {
  local rc_file
  local quoted_instructions_dir
  local snippet_file="$TMP_DIR/shell-rc-snippet.sh"

  rc_file="$(detect_shell_rc)"
  quoted_instructions_dir="$(
    python - "$TARGET_EXTRA_INSTRUCTIONS_DIR" <<'PY'
import shlex
import sys

print(shlex.quote(sys.argv[1]))
PY
  )"

  cat >"$snippet_file" <<EOF
_copilot_cli_ecc_instructions_dir=$quoted_instructions_dir
case ",\${COPILOT_CUSTOM_INSTRUCTIONS_DIRS-}," in
  *,"\${_copilot_cli_ecc_instructions_dir}",*) ;;
  "") export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="\${_copilot_cli_ecc_instructions_dir}" ;;
  *) export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="\${_copilot_cli_ecc_instructions_dir},\${COPILOT_CUSTOM_INSTRUCTIONS_DIRS}" ;;
esac
unset _copilot_cli_ecc_instructions_dir
EOF

  if [[ ! -e "$rc_file" ]] && ! ((DRY_RUN)); then
    ensure_dir "$(dirname "$rc_file")"
    : >"$rc_file"
  fi

  merge_managed_block_from_file "$snippet_file" "$rc_file" "$RC_BLOCK_START" "$RC_BLOCK_END"
}

log "source repo: $ROOT_DIR"
log "copilot home: $COPILOT_HOME_DIR"

merge_managed_block_from_file \
  "$SOURCE_COPILOT_INSTRUCTIONS_FILE" \
  "$TARGET_COPILOT_INSTRUCTIONS_FILE" \
  "$MARKDOWN_BLOCK_START" \
  "$MARKDOWN_BLOCK_END"
sync_agents
sync_extra_instructions
sync_skills

if ((UPDATE_SHELL_RC)); then
  update_shell_rc
else
  log "skipped shell rc update (--no-shell-rc)"
fi

log "done"
log "copilot instructions: $TARGET_COPILOT_INSTRUCTIONS_FILE"
log "agents dir:            $TARGET_AGENTS_DIR"
log "skills dir:            $TARGET_SKILLS_DIR"
log "extra instructions:    $TARGET_EXTRA_INSTRUCTIONS_DIR"

if ((UPDATE_SHELL_RC)); then
  log "reload your shell or run: source $(detect_shell_rc)"
  log "current session can use: export COPILOT_CUSTOM_INSTRUCTIONS_DIRS=\"$TARGET_EXTRA_INSTRUCTIONS_DIR\${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:+,\$COPILOT_CUSTOM_INSTRUCTIONS_DIRS}\""
fi
