#!/usr/bin/env bash
# 目的: 全リポジトリ横断の週次セキュリティサマリーを Markdown で生成します。
# トリガー: .github/workflows/weekly-security-digest.yml から週次または手動で起動します。
# 依存: gh, jq, PAT_TOKEN です。
# 想定実行時間: 2〜8分です。
set -euo pipefail

: "${PAT_TOKEN:?PAT_TOKEN が未設定です。}"
export GH_TOKEN="${PAT_TOKEN}"

owner="$(gh api user --jq .login)"
week_key="$(date -u +%G-%V)"
report_dir="reports"
report_file="${report_dir}/${week_key}.md"

mkdir -p "${report_dir}"

echo "# Weekly Security Digest (${week_key})" >"${report_file}"
echo "" >>"${report_file}"
echo "- 対象オーナー: ${owner}" >>"${report_file}"
echo "- 生成時刻(UTC): $(date -u '+%Y-%m-%d %H:%M:%S')" >>"${report_file}"
echo "" >>"${report_file}"
echo "| Repository | Open Security Issues | P0 | P1 | Dependabot Alerts |" >>"${report_file}"
echo "|---|---:|---:|---:|---:|" >>"${report_file}"

mapfile -t repos < <(
  gh repo list "${owner}" --limit 300 --json name,isArchived \
    --jq -r '.[] | select(.isArchived | not) | .name'
)

total_open=0
total_p0=0
total_p1=0
total_dep=0

for repo in "${repos[@]}"; do
  issues_json="$(gh api --paginate "/repos/${owner}/${repo}/issues?state=open&labels=security-auto-fix&per_page=100" 2>/dev/null || echo '[]')"
  dep_json="$(gh api --paginate "/repos/${owner}/${repo}/dependabot/alerts?state=open&per_page=100" 2>/dev/null || echo '[]')"

  open_count="$(echo "${issues_json}" | jq 'length')"
  p0_count="$(echo "${issues_json}" | jq '[.[] | select(any(.labels[]?; .name == "P0"))] | length')"
  p1_count="$(echo "${issues_json}" | jq '[.[] | select(any(.labels[]?; .name == "P1"))] | length')"
  dep_count="$(echo "${dep_json}" | jq 'length')"

  total_open=$((total_open + open_count))
  total_p0=$((total_p0 + p0_count))
  total_p1=$((total_p1 + p1_count))
  total_dep=$((total_dep + dep_count))

  echo "| ${repo} | ${open_count} | ${p0_count} | ${p1_count} | ${dep_count} |" >>"${report_file}"
done

echo "" >>"${report_file}"
echo "## 全体サマリー" >>"${report_file}"
echo "" >>"${report_file}"
echo "- Open Security Issues: ${total_open}" >>"${report_file}"
echo "- P0: ${total_p0}" >>"${report_file}"
echo "- P1: ${total_p1}" >>"${report_file}"
echo "- Open Dependabot Alerts: ${total_dep}" >>"${report_file}"

echo "出力: ${report_file}"
