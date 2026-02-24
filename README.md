# ECC for GitHub Copilot (VS Code) Port

このリポジトリは、`affaan-m/everything-claude-code` を VS Code / GitHub Copilot 向けに移植したものです。

## 目的

- ECC の資産（agents / skills / hook scripts）を活用
- VS Code Copilot の最新仕様に合わせて互換層を維持
- グローバル適用とアップデートを 1 コマンド化

## 対応関係（ECC → Copilot）

| ECC 側 | このポートでの配置 | 備考 |
| --- | --- | --- |
| `agents/*.md` | `.github/agents/*.md` | `model:` は Copilot 向けに削除 |
| `skills/*/SKILL.md` | `.github/skills/*/SKILL.md` | Agent Skills 仕様に準拠 |
| `scripts/hooks/*.js` | `.github/scripts/hooks/*.js` | Copilot Hooks から実行 |
| `scripts/lib/*.js` | `.github/scripts/lib/*.js` | Hooks 依存を補完 |
| `hooks/hooks.json` (Claude) | `.github/hooks/ecc-hooks.json` | Copilot 用のイベント・キーへ変換済み |
| `rules/common + language` | `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md` | Copilot instructions 形式へ移植 |

## 仕様差分ポリシー

- Copilot 専用最適化（Claude 固有の `model:` や CLI 固有記述は除去）
- Hooks は VS Code Copilot Preview 仕様（`SessionStart`, `PreToolUse`, `PostToolUse`, `Stop` など）を採用
- ユーザーグローバル配置は以下を使用
  - instructions/agents: VS Code profile の `prompts` フォルダ
  - skills: `~/.copilot/skills`
  - hooks: `~/.claude/settings.json` の `hooks`

## インストール（グローバル適用）

```bash
./scripts/install-global.sh
```

必要に応じて環境変数で上書きできます。

```bash
VSCODE_PROMPTS_DIR="~/Library/Application Support/Code/User/profiles/<profile-id>/prompts" \
COPILOT_SKILLS_DIR="~/.copilot/skills" \
ECC_GLOBAL_DIR="~/.copilot/ecc" \
CLAUDE_SETTINGS_PATH="~/.claude/settings.json" \
./scripts/install-global.sh
```

## アップデート手順（ECC 本家追従）

1. upstream から同期

```bash
./scripts/update-from-ecc.sh
```

1. 差分確認

```bash
git status
git diff
```

1. グローバル再インストール

```bash
./scripts/install-global.sh
```

`update-from-ecc.sh` は以下を自動で実施します。

- upstream の `agents`, `skills`, `scripts/hooks`, `scripts/lib` を同期
- Copilot 非互換の `model:` 行を自動削除
- `.github/hooks/ecc-hooks.json` を Copilot 用フォーマットに再生成
- `.instructions.md` 内の Claude 固有ブロック（`paths:` や壊れた extends 参照）を自動除去

## 検証チェックリスト

- VS Code Chat の `Configure Chat > Diagnostics` で instructions/agents/skills がロードされる
- hooks の diagnostics に JSON エラーが出ない
- `~/.claude/settings.json` の `hooks` が更新されている

## 運用メモ

- profile を切り替える場合は `VSCODE_PROMPTS_DIR` を指定して再実行
- hooks は Preview 機能のため、VS Code 側仕様変更時は `.github/hooks/ecc-hooks.json` を優先更新
