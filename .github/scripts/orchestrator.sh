#!/usr/bin/env bash
# 目的: 攻撃研究者/CISO/投資家の3層出力を統合し、重大リスクを自動エスカレーションします。
# トリガー: .github/workflows/orchestrate.yml から週次または手動で起動します。
# 依存: gh, jq, PAT_TOKEN, reports/ 配下の週次成果物です。
# 想定実行時間: 2〜8分です。
set -euo pipefail

: "${PAT_TOKEN:?PAT_TOKEN が未設定です。}"
export GH_TOKEN="${PAT_TOKEN}"

week_key="$(date -u +%G-%V)"
report_dir="reports/orchestrator"
report_file="${report_dir}/${week_key}.md"
mkdir -p "${report_dir}"

latest_cve="$(ls -1 reports/cve-intel/*.md 2>/dev/null | sort | tail -n 1 || true)"
latest_digest="$(ls -1 reports/[0-9][0-9][0-9][0-9]-[0-9][0-9].md 2>/dev/null | sort | tail -n 1 || true)"
latest_trend="$(ls -1 reports/trends/*.md 2>/dev/null | sort | tail -n 1 || true)"

attack_high="false"
ciso_high="false"
invest_high="false"

if [[ -n "${latest_cve}" ]] && grep -Eq 'CRITICAL|HIGH|CVE-' "${latest_cve}"; then
  attack_high="true"
fi
if [[ -n "${latest_digest}" ]] && grep -Eq 'P0: [1-9]|P1: [1-9]' "${latest_digest}"; then
  ciso_high="true"
fi
if [[ -n "${latest_trend}" ]] && grep -Eq '\| .* \| [0-9]+ \| \+[1-9][0-9]* \|' "${latest_trend}"; then
  invest_high="true"
fi

critical="false"
if [[ "${attack_high}" == "true" && "${ciso_high}" == "true" && "${invest_high}" == "true" ]]; then
  critical="true"
fi

{
  echo "# Orchestrator Report (${week_key})"
  echo ""
  echo "- Attack researcher high risk: ${attack_high}"
  echo "- CISO high risk: ${ciso_high}"
  echo "- Investor high risk: ${invest_high}"
  echo "- Final critical: ${critical}"
  echo ""
  echo "## Linked source reports"
  echo ""
  echo "- CVE intel: ${latest_cve:-N/A}"
  echo "- Weekly digest: ${latest_digest:-N/A}"
  echo "- Trend report: ${latest_trend:-N/A}"
} >"${report_file}"

if [[ "${critical}" == "true" ]]; then
  owner="$(gh api user --jq .login)"
  repo="security-automation"
  title="[CRITICAL] 3層一致で高リスクが検出されました (${week_key})"
  existing="$(gh issue list --repo "${owner}/${repo}" --state open --search "${title} in:title" --json number --jq 'length')"
  if [[ "${existing}" == "0" ]]; then
    gh issue create \
      --repo "${owner}/${repo}" \
      --title "${title}" \
      --label "security-auto-fix" \
      --body "orchestrator により 3 層すべてで高リスクを検出しました。詳細は ${report_file} を確認してください。"
  fi
fi

echo "出力: ${report_file}"
