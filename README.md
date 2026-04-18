# security-automation

個人アカウント配下の **全 GitHub リポジトリ** に、セキュリティ関連の GitHub Actions ワークフローを **中央から自動配布** するためのリポジトリです。

## リポジトリ構成

```
security-automation/
├── .github/
│   ├── scripts/
│   │   └── notify-security-findings.sh   # Issue 起票ロジック（このリポ専用）
│   └── workflows/
│       ├── distribute-workflows.yml      # 配布エンジン（他リポへ workflows/*.yml を追加）
│       └── notify-security-findings.yml  # Code Scanning 監視 → Issue 起票（このリポのみ・配布しない）
├── workflows/                            # 配布されるテンプレート置き場
│   ├── auto-merge-dependabot.yml
│   └── trivy.yml
└── README.md
```

## 目的

- `workflows/` に置いた `.yml` を、**まだ同じファイルが無いリポジトリ**へだけ追加する
- **毎週月曜 9:00（JST）** に巡回し、手動実行（`workflow_dispatch`）にも対応
- ファイル名をコードに埋め込まず、`workflows/*.yml` をすべて配布対象にする
- （このリポのみ）**Code Scanning のオープンアラート**を週次で確認し、Cursor 用プロンプト付き Issue を自動起票する

## 前提

- 配布の実行は `.github/workflows/distribute-workflows.yml` が行う
- 他リポジトリへのファイル作成には **Classic PAT**（または同等の権限を持つトークン）が必要
- PAT には少なくとも **`repo`** スコープに加え、ワークフロー YAML をコミットするための **`workflow`** スコープ** を付与すること（GitHub の案内に従う）

## セットアップ手順

1. **PAT を作成する**  
   GitHub → Settings → Developer settings → Personal access tokens で、上記スコープを含むトークンを発行する。

2. **このリポジトリに Secret を登録する**  
   - Repository → Settings → Secrets and variables → Actions  
   - **New repository secret**  
   - Name: `PAT_TOKEN`  
   - Value: 手順 1 のトークン

3. **初回配布を手動で実行する**  
   - Actions → **Distribute workflows** → **Run workflow**  
   - 成功ログで各リポジトリへの追加状況を確認する

4. **（任意）脆弱性通知 Issue を使う場合**  
   - Actions → **Notify security findings** を手動実行するか、毎週月曜のスケジュールに任せる  
   - 各リポジトリに `security-auto-fix` ラベル付き Issue が作成される（同一アラート集合の重複起票は抑制）

5. **（各リポジトリ側）自動マージを使う場合**  
   `auto-merge-dependabot.yml` が squash 自動マージ（`--auto`）を使うため、リポジトリで **Allow auto-merge** を有効にし、ブランチ保護ルールと整合させる。

## `workflows/` にファイルを追加する方法

1. このリポジトリの `workflows/` に **`.yml` ファイルを追加**（または既存を編集）して **既定ブランチ**（`master` / `main` など）へプッシュする  
2. 次回のスケジュール実行まで待つか、**Distribute workflows** を手動実行する  

配布ジョブは `workflows/*.yml` を列挙し、各リポジトリの `.github/workflows/` に **同名ファイルが無い場合だけ** GitHub API で追加する。

## 配布スケジュール

| 項目 | 値 |
|------|-----|
| Cron | `0 0 * * 1`（毎週月曜 **00:00 UTC**） |
| JST | 同じく月曜 **09:00** |
| 手動 | `workflow_dispatch` からいつでも実行可能 |

## 補足

- 配布先は `gh repo list <あなたのログイン名>` で得られる **同一オーナー配下**のリポジトリ（アーカイブは除く）です。
- 既に対象ファイルがあるリポジトリは **上書きしません**（スキップ）。更新を反映したい場合は各リポジトリ側で編集するか、別名のワークフローで運用してください。
- **Notify security findings** は GitHub の **Code Scanning アラート API**（`GET .../code-scanning/alerts`）を参照します。SARIF を Code Scanning にアップロードしている結果（CodeQL・Semgrep・Trivy の SARIF など）が対象です。配布される `trivy.yml` は既定で **table 出力**のため、GitHub の Security タブに載せるには別途 SARIF アップロード等が必要です。
- Issue の自動クローズは GitHub 標準どおり、修正コミットのメッセージに `Fixes #<番号>`（または `Closes #<番号>`）を含めてプッシュするとクローズできます。
