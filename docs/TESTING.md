<!--
目的: 3人合体型自動セキュリティシステムの統合テスト手順を定義する手順書です。
トリガー: 初回導入時・変更時・障害復旧時に参照します。
依存: GitHub Actions, PAT_TOKEN, SUPABASE_DB_URL（必要ワークフローのみ）です。
想定実行時間: フルテスト 30〜60分です。
-->

# 統合テスト手順

## 1. 事前確認

1. `PAT_TOKEN` が設定されていることを確認します。  
2. `SUPABASE_DB_URL` が設定されていることを確認します。  
3. Actions が有効であることを確認します。  
4. `security-auto-fix` ラベル作成権限があることを確認します。

## 2. Phase 1 テスト（攻撃研究者）

1. `Distribute workflows` を手動実行します。  
2. 任意の配布先リポで `CodeQL analysis` を実行します。  
3. 同リポで `Secret scan` を実行します。  
4. 同リポで `Trivy filesystem scan` を実行し、Security タブに SARIF が出ることを確認します。  
5. 同リポで `SBOM generate and scan` を実行し、artifact が出ることを確認します。  
6. このリポで `CVE intel` を実行し、`reports/cve-intel/YYYY-WW.md` を確認します。

## 3. Phase 2 テスト（CISO）

1. テスト用に `security-auto-fix` ラベルの Issue を1件作ります。  
2. `Risk score issues` を実行し、P0〜P3ラベルが付くことを確認します。  
3. `Weekly security digest` を実行し、`reports/YYYY-WW.md` が更新されることを確認します。  
4. 配布先で `Compliance checker` を実行し、必須ファイル不足時に失敗することを確認します。

## 4. Phase 3 テスト（投資家）

1. `Trend forecast` を実行します。  
2. `reports/threat-intel/YYYY-WW.md` が生成されることを確認します。  
3. `reports/trends/YYYY-WW.md` と `reports/trends/dependency-history.json` が更新されることを確認します。

## 5. Phase 4 テスト（統合）

1. `Orchestrate security brains` を実行します。  
2. `reports/orchestrator/YYYY-WW.md` が生成されることを確認します。  
3. 高リスク条件を満たした場合のみ `[CRITICAL]` Issue が作成されることを確認します。  
4. `Update dashboard` を実行し、`DASHBOARD.md` の数値が更新されることを確認します。

## 6. Phase 5 テスト（PRゲート / サプライチェーン）

1. 配布先リポでテスト PR を作成し、`Dependency review (PR gate)` が実行されることを確認します。  
   - 既知脆弱依存（例: 古い `lodash`）を追加した PR が **Moderate（中程度）以上で失敗**することを確認します。  
   - Dependency Graph 無効リポでは `::notice::` を出して**スキップ（成功）**することを確認します。
2. Next.js リポで `NEXT_PUBLIC_*_SECRET` への代入や、`'use client'` での機密 env 参照を含む PR が `Next.js client-secret guard` で**失敗**することを確認します。非 Next.js リポでは**スキップ**されることを確認します。  
   - ログに**秘密情報の値が出力されない**ことも確認します（キー名・ファイル:行のみ）。
3. TS/JS リポで型エラー／Lint エラーを含む PR が `TS type + lint gate` で**失敗**することを確認します。pnpm/yarn/npm/bun の各リポでパッケージマネージャが正しく判定されることを確認します。`package.json` の無いリポでは**スキップ**されることを確認します。
4. このリポで `Zizmor workflow audit` を手動実行し、SARIF が Security タブに表示されることを確認します。
5. すべてのワークフローで `uses:` が **commit SHA に固定**（`# vX.Y.Z` コメント付き）されていることを確認します（`grep -rEn 'uses:.*@v[0-9]'` が 0 件）。
6. `.github/dependabot.yml` 追加後、`github-actions` の更新 PR が作成されること、`Auto merge Dependabot patch PRs` がパッチ更新を自動マージすることを確認します。
7. （任意）`OpenSSF Scorecard` を手動実行し SARIF が出ること、`ZAP baseline scan` が URL 解決（inputs / `ZAP_TARGET_URL` / Homepage）で動作することを確認します。
8. （App移行時）`APP_ID` / `APP_PRIVATE_KEY` 設定後、`Distribute workflows` のログに「GitHub App 認証を使用します（短命トークン）。」が出ることを確認します。未設定時は `PAT_TOKEN` フォールバックで従来どおり動くことを確認します。

## 7. 回帰テスト

1. `Distribute workflows` が既存ロジックのまま動くことを確認します。  
2. `notify-security-findings.sh` の fingerprint 重複抑止が維持されていることを確認します。  
3. 月曜 00:00 UTC 周辺の cron が競合しないことを確認します。

## 8. 失敗時の切り分け

- API 403: `PAT_TOKEN` 権限不足です。  
- API 429: レート制限です。再実行前に数分待機します。  
- レポート未更新: `git diff --quiet` で変更なし判定になっている可能性があります。  
- CRITICAL未起票: `reports/orchestrator/*.md` の判定値を確認します。
