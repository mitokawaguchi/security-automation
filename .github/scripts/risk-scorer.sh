#!/usr/bin/env bash
# 目的: 全リポジトリの security-auto-fix Issue を評価し、P0〜P3 ラベルを統一付与します。
# トリガー: .github/workflows/risk-score.yml から週次または手動で起動します。
# 依存: gh, jq, PAT_TOKEN です。
# 想定実行時間: 2〜10分です。
set -euo pipefail

: "${PAT_TOKEN:?PAT_TOKEN が未設定です。}"
export GH_TOKEN="${PAT_TOKEN}"

owner="$(gh api user --jq .login)"

score_from_text() {
  local text="$1"
  if [[ "${text}" =~ CRITICAL|P0|RCE|remote\ code\ execution ]]; then
    echo "P0"
  elif [[ "${text}" =~ HIGH|P1|SQLi|XSS|credential|secret ]]; then
    echo "P1"
  elif [[ "${text}" =~ MEDIUM|P2|timeout|dos|rate\ limit ]]; then
    echo "P2"
  else
    echo "P3"
  fi
}

mapfile -t repos < <(
  gh repo list "${owner}" --limit 300 --json name,isArchived \
    --jq -r '.[] | select(.isArchived | not) | .name'
)

for repo in "${repos[@]}"; do
  set +e
  issues_json="$(
    gh api --paginate "/repos/${owner}/${repo}/issues?state=open&labels=security-auto-fix&per_page=100" 2>/dev/null
  )"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] && continue

  mapfile -t issue_rows < <(
    echo "${issues_json}" | jq -r '.[] | [.number, .title, (.body // "")] | @tsv'
  )

  for row in "${issue_rows[@]}"; do
    number="$(echo "${row}" | cut -f1)"
    title="$(echo "${row}" | cut -f2)"
    body="$(echo "${row}" | cut -f3)"
    score="$(score_from_text "${title} ${body}")"

    gh label create "${score}" --repo "${owner}/${repo}" --color "b60205" \
      --description "security risk priority ${score}" >/dev/null 2>&1 || true

    existing_score="$(
      gh api "/repos/${owner}/${repo}/issues/${number}" --jq '.labels[].name' 2>/dev/null \
        | grep -E '^P[0-3]$' || true
    )"
    if [[ -n "${existing_score}" ]] && [[ "${existing_score}" != "${score}" ]]; then
      while IFS= read -r old; do
        [[ -z "${old}" ]] && continue
        gh issue edit "${number}" --repo "${owner}/${repo}" --remove-label "${old}" >/dev/null 2>&1 || true
      done <<<"${existing_score}"
    fi

    gh issue edit "${number}" --repo "${owner}/${repo}" --add-label "${score}" >/dev/null 2>&1 || true

    gh issue comment "${number}" --repo "${owner}/${repo}" \
      --body "リスクスコア自動評価: **${score}**（security-automation/risk-scorer）" >/dev/null 2>&1 || true
  done
done

echo "リスクスコア付与が完了しました。"
