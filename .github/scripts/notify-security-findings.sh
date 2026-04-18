#!/usr/bin/env bash
# security-automation 専用: 全リポの Code Scanning アラートを監視し、重複しない Issue を起票する
set -euo pipefail

: "${PAT_TOKEN:?PAT_TOKEN が未設定です}"

export GH_TOKEN="${PAT_TOKEN}"

owner="$(gh api user -q .login)"
echo "監視オーナー: ${owner}"

mapfile -t repos < <(
  gh repo list "${owner}" \
    --limit 1000 \
    --json name,isArchived \
    -q '.[] | select(.isArchived | not) | .name'
)

for repo in "${repos[@]}"; do
  echo "=== ${owner}/${repo} ==="

  set +e
  alerts_json="$(
    gh api --paginate "/repos/${owner}/${repo}/code-scanning/alerts?state=open" 2>/dev/null
  )"
  alerts_rc=$?
  set -e

  if [[ "${alerts_rc}" -ne 0 ]] || [[ -z "${alerts_json}" ]]; then
    echo "::notice::${owner}/${repo}: Code Scanning アラートを取得できませんでした（未利用・権限・プラン等）。スキップします。"
    continue
  fi

  alert_count="$(echo "${alerts_json}" | jq 'length')"
  if [[ "${alert_count}" -eq 0 ]]; then
    echo "オープンなアラートはありません。スキップします。"
    continue
  fi

  fp="$(echo "${alerts_json}" | jq -r '[.[].number] | sort | join(",")')"

  set +e
  issues_json="$(
    gh api --paginate "/repos/${owner}/${repo}/issues?state=open&labels=security-auto-fix&per_page=100" 2>/dev/null
  )"
  issues_rc=$?
  set -e

  if [[ "${issues_rc}" -eq 0 ]] && [[ -n "${issues_json}" ]]; then
    dup="$(
      echo "${issues_json}" | jq -r --arg fp "${fp}" \
        '[.[] | select((.body // "") | contains("<!-- security-automation-fp:" + $fp + " -->"))] | length'
    )"
    if [[ "${dup}" -gt 0 ]]; then
      echo "同一 fingerprint のオープン Issue が既にあります。スキップします。"
      continue
    fi
  fi

  gh label create 'security-auto-fix' \
    --repo "${owner}/${repo}" \
    --color d73a4a \
    --description 'security-automation による脆弱性通知' 2>/dev/null || true

  table_md="$(
    echo "${alerts_json}" | jq -r '
      "| 重要度 | ルール | ファイル | 行 |",
      "|--------|--------|----------|-----|",
      (.[] |
        "| "
        + ((.rule.security_severity // .rule.severity // "—") | tostring | gsub("\\|"; "｜"))
        + " | "
        + ((.rule.id // "—") | tostring | gsub("\\|"; "｜"))
        + " | "
        + ((.most_recent_instance.location.path // "—") | tostring | gsub("\\|"; "｜"))
        + " | "
        + ((.most_recent_instance.location.start_line // "—") | tostring | gsub("\\|"; "｜"))
        + " |"
      )
    '
  )"

  prompt_md="$(
    echo "${alerts_json}" | jq -r '
      "■ 各アラート\n（アラートごとに）\n",
      (.[] |
        "\n- アラート名: " + (.rule.id // "—") + "\n" +
        "- 重要度: " + ((.rule.security_severity // .rule.severity // "—") | tostring) + "\n" +
        "- 該当ファイル: " + ((.most_recent_instance.location.path // "—") | tostring) + " 行" + ((.most_recent_instance.location.start_line // "—") | tostring) + "\n" +
        "- 説明: " + ((.rule.description // "—") | gsub("\n"; " ")) + "\n"
      )
    '
  )"

  marker="<!-- security-automation-fp:${fp} -->"

  body_file="$(mktemp)"
  {
    echo '---'
    echo "${marker}"
    echo '---'
    echo
    echo '## 検出された脆弱性'
    echo
    echo "${table_md}"
    echo
    echo '## Cursor用プロンプト'
    echo
    echo '以下をCursorのチャットにコピペしてください:'
    echo
    echo '```'
    echo '以下のセキュリティアラートをすべて修正してください。'
    echo
    echo '■ 対応の順番'
    echo 'CRITICAL → HIGH の優先度順'
    echo
    echo "${prompt_md}"
    echo '■ 制約'
    echo '- 既存の機能を壊さないこと'
    echo '- 修正は1ファイルずつ順番に行うこと'
    echo '- 各修正後にどのアラートが解消されるか明示すること'
    echo '```'
    echo
    echo '---'
    echo
    echo "*この Issue は \`security-automation\` のワークフローが起票しました。解消後はコミットメッセージに \`Fixes #番号\` を含めるとクローズできます。*"
  } >"${body_file}"

  title="[Security] ${alert_count}件の脆弱性が検出されました"

  set +e
  gh issue create \
    --repo "${owner}/${repo}" \
    --title "${title}" \
    --body-file "${body_file}" \
    --label 'security-auto-fix'
  create_rc=$?
  set -e

  rm -f "${body_file}"

  if [[ "${create_rc}" -ne 0 ]]; then
    echo "::warning::${owner}/${repo}: Issue の作成に失敗しました。次のリポジトリへ進みます。"
    continue
  fi

  echo "[OK] Issue を作成しました: ${title}"
done
