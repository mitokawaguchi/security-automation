#!/usr/bin/env bash
# 目的: GitHub Advisory / CISA KEV / OSV.dev から週次脅威情報を収集して保存します。
# トリガー: .github/workflows/trend-forecast.yml から週次または手動で起動します。
# 依存: curl, jq, gh, PAT_TOKEN です。
# 想定実行時間: 2〜10分です。
set -euo pipefail

: "${PAT_TOKEN:?PAT_TOKEN が未設定です。}"
export GH_TOKEN="${PAT_TOKEN}"

week_key="$(date -u +%G-%V)"
report_dir="reports/threat-intel"
report_file="${report_dir}/${week_key}.md"
tmp_ghsa="$(mktemp)"
tmp_kev="$(mktemp)"
tmp_osv="$(mktemp)"
trap 'rm -f "${tmp_ghsa}" "${tmp_kev}" "${tmp_osv}"' EXIT

mkdir -p "${report_dir}"

echo "# Threat Intel (${week_key})" >"${report_file}"
echo "" >>"${report_file}"
echo "- 生成時刻(UTC): $(date -u '+%Y-%m-%d %H:%M:%S')" >>"${report_file}"
echo "" >>"${report_file}"

gh api "/advisories?per_page=20&sort=published&direction=desc" >"${tmp_ghsa}"
curl -fsSL "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json" -o "${tmp_kev}"

cat >"${tmp_osv}" <<'JSON'
{
  "queries": [
    {"package": {"name": "lodash", "ecosystem": "npm"}},
    {"package": {"name": "requests", "ecosystem": "PyPI"}},
    {"package": {"name": "gin", "ecosystem": "Go"}}
  ]
}
JSON

osv_resp="$(curl -fsSL -X POST "https://api.osv.dev/v1/querybatch" -H "Content-Type: application/json" --data @"${tmp_osv}")"

echo "## GitHub Security Advisories（最新20件）" >>"${report_file}"
echo "" >>"${report_file}"
echo "| GHSA | Severity | Summary | Published |" >>"${report_file}"
echo "|---|---|---|---|" >>"${report_file}"
jq -r '.[] | "| \(.ghsa_id) | \(.severity) | \(.summary | gsub("\\|"; "｜")) | \(.published_at[0:10]) |"' "${tmp_ghsa}" >>"${report_file}"
echo "" >>"${report_file}"

echo "## CISA KEV（最新20件）" >>"${report_file}"
echo "" >>"${report_file}"
echo "| cveID | Vendor | Product | Due date |" >>"${report_file}"
echo "|---|---|---|---|" >>"${report_file}"
jq -r '.vulnerabilities[:20] | .[] | "| \(.cveID) | \(.vendorProject) | \(.product) | \(.dueDate) |"' "${tmp_kev}" >>"${report_file}"
echo "" >>"${report_file}"

echo "## OSV.dev snapshot（主要3パッケージ）" >>"${report_file}"
echo "" >>"${report_file}"
echo "| Package | Vulnerability count |" >>"${report_file}"
echo "|---|---:|" >>"${report_file}"
echo "${osv_resp}" | jq -r '
  .results as $r |
  [
    ["lodash", ($r[0].vulns // [] | length)],
    ["requests", ($r[1].vulns // [] | length)],
    ["gin", ($r[2].vulns // [] | length)]
  ][] | "| \(.[0]) | \(.[1]) |"
' >>"${report_file}"

echo "出力: ${report_file}"
