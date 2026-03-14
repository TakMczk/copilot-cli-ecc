# ECC for GitHub Copilot CLI / VS Code Port

このリポジトリは、`affaan-m/everything-claude-code` を GitHub Copilot CLI / VS Code 向けに移植したものです。

## 目的

- ECC の資産（agents / skills / hook scripts）を活用
- GitHub Copilot CLI と VS Code Copilot の両方で使える配置を用意
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
- GitHub Copilot CLI のユーザーグローバル配置は以下を使用
  - repo-wide instructions: `~/.copilot/copilot-instructions.md`
  - custom agents: `~/.copilot/agents/`
  - skills: `~/.copilot/skills/`
  - path-specific instructions: 任意ディレクトリ + `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`
- VS Code / Claude 互換レイヤーのグローバル配置は以下を使用
  - instructions/agents: VS Code profile の `prompts` フォルダ
  - hooks: `~/.claude/settings.json` の `hooks`

## Agents と Skills の住み分け

- `agents` は能動的にタスクを進める実行役です。レビュー、修正、計画、運用などのワークフローを持ちます。
- `skills` は必要時に読み込む参照パックです。詳細パターン、チェックリスト、サンプルを提供します。
- 役割が近い名前でも、意図的に `agent -> skill` の補完関係になっているものがあります。原則として重複ではなく、実行と参照の分離です。

代表的なペアは以下です。

| Agent | Skill | 役割分担 |
| --- | --- | --- |
| `security-reviewer` | `security-review` | agent がコード/変更をレビューし、skill が詳細パターンとチェックリストを補完 |
| `tdd-guide` | `tdd-workflow` | agent が TDD を実行・誘導し、skill がテスト設計や実例を補完 |
| `e2e-runner` | `e2e-testing` | agent が E2E を作成・実行し、skill が Playwright の詳細パターンを補完 |
| `python-reviewer` | `python-patterns` | agent が Python レビューを行い、skill が言語パターンを補完 |
| `go-reviewer` / `go-build-resolver` | `golang-patterns` | agent がレビュー/ビルド修正を行い、skill が Go の詳細例を補完 |
| `kotlin-reviewer` / `kotlin-build-resolver` | `kotlin-patterns` | agent が Kotlin/KMP レビューやビルド修正を行い、skill が Kotlin の詳細例を補完 |
| `database-reviewer` | `postgres-patterns` / `database-migrations` | agent が DB 観点でレビューし、skill が設計・移行パターンを補完 |

近い名前でもスコープが異なるものもあります。例えば `security-scan` はアプリコードレビューではなく、設定やハーネス側のセキュリティ監査向けです。

## インストール（グローバル適用）

### GitHub Copilot CLI 向け

```bash
./scripts/install-copilot-cli.sh
```

このスクリプトは以下を実施します。

- `.github/copilot-instructions.md` を `~/.copilot/copilot-instructions.md` の managed block として反映
- `.github/agents/*.md` を `~/.copilot/agents/` へ同期
- `.github/skills/` を `~/.copilot/skills/` へ同期
- `.github/instructions/*.instructions.md` を `~/.copilot/instructions/copilot-cli-ecc/` へ同期
- shell rc に `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` 用の managed block を追加
- 既存ファイルのバックアップを `~/.copilot/copilot-cli-ecc-state/backups/` に保存

必要に応じて環境変数で上書きできます。

```bash
COPILOT_HOME="$HOME/.copilot" \
COPILOT_CLI_EXTRA_INSTRUCTIONS_DIR="$HOME/.copilot/instructions/copilot-cli-ecc" \
COPILOT_CLI_SHELL_RC_PATH="$HOME/.bashrc" \
./scripts/install-copilot-cli.sh
```

### VS Code / Claude 互換レイヤー向け

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
./scripts/install-copilot-cli.sh
```

VS Code / Claude 互換レイヤーも併用している場合は、続けて以下も実行します。

```bash
./scripts/install-global.sh
```

`update-from-ecc.sh` は以下を自動で実施します。

- upstream の `agents`, `skills`, `scripts/hooks`, `scripts/lib` を同期
- Copilot 非互換の `model:` 行を自動削除
- `.github/hooks/ecc-hooks.json` を Copilot 用フォーマットに再生成
- `.instructions.md` 内の Claude 固有ブロック（`paths:` や壊れた extends 参照）を自動除去
- 更新後は利用しているクライアントに応じて `install-copilot-cli.sh` または `install-global.sh` を再実行する

## 検証チェックリスト

- Copilot CLI の `/instructions`, `/agent`, `/skills list` で instructions / agents / skills が見える
- `echo "$COPILOT_CUSTOM_INSTRUCTIONS_DIRS"` に `~/.copilot/instructions/copilot-cli-ecc` が含まれる
- VS Code Chat の `Configure Chat > Diagnostics` で instructions/agents/skills がロードされる
- hooks の diagnostics に JSON エラーが出ない
- `~/.claude/settings.json` の `hooks` が更新されている

## 運用メモ

- profile を切り替える場合は `VSCODE_PROMPTS_DIR` を指定して再実行
- hooks は Preview 機能のため、VS Code 側仕様変更時は `.github/hooks/ecc-hooks.json` を優先更新
- Copilot CLI だけを使う場合は `scripts/install-copilot-cli.sh` を利用し、`scripts/install-global.sh` は使わない
