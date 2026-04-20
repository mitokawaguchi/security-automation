#!/usr/bin/env python3
# 目的: GitHub コード検索 API を用いて依存ライブラリ採用の現在値を計測し、トレンド化します。
# トリガー: .github/workflows/trend-forecast.yml から週次または手動で起動します。
# 依存: Python 標準ライブラリのみ（urllib, json, pathlib）です。
# 想定実行時間: 1〜5分です。

from __future__ import annotations

import json
import os
import pathlib
import urllib.parse
import urllib.request
from datetime import datetime, timezone


def gh_get(url: str, token: str) -> dict:
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "security-automation-dependency-trend",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def search_count(owner: str, token: str, dep: str) -> int:
    query = f'org:{owner} "{dep}" in:file language:yaml language:json language:toml'
    encoded = urllib.parse.quote(query, safe="")
    url = f"https://api.github.com/search/code?q={encoded}&per_page=1"
    data = gh_get(url, token)
    return int(data.get("total_count", 0))


def main() -> None:
    token = os.environ.get("PAT_TOKEN", "")
    owner = os.environ.get("GITHUB_OWNER", "")
    if not token:
        raise SystemExit("PAT_TOKEN が未設定です。")
    if not owner:
        raise SystemExit("GITHUB_OWNER が未設定です。")

    deps = [
        "next",
        "react",
        "@supabase/supabase-js",
        "zod",
        "axios",
        "express",
        "fastapi",
    ]

    week_key = datetime.now(timezone.utc).strftime("%G-%V")
    report_dir = pathlib.Path("reports/trends")
    report_dir.mkdir(parents=True, exist_ok=True)
    json_path = report_dir / "dependency-history.json"
    md_path = report_dir / f"{week_key}.md"

    history: dict[str, dict[str, int]]
    if json_path.exists():
        history = json.loads(json_path.read_text(encoding="utf-8"))
    else:
        history = {}

    current: dict[str, int] = {}
    for dep in deps:
        current[dep] = search_count(owner, token, dep)

    history[week_key] = current
    json_path.write_text(json.dumps(history, ensure_ascii=False, indent=2), encoding="utf-8")

    previous_key = sorted(history.keys())[-2] if len(history) >= 2 else None
    previous = history.get(previous_key, {}) if previous_key else {}

    lines = [
        f"# Dependency Trend ({week_key})",
        "",
        f"- 対象オーナー: {owner}",
        f"- 生成時刻(UTC): {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')}",
        "",
        "| Dependency | Current count | Diff from last week |",
        "|---|---:|---:|",
    ]
    for dep in deps:
        prev = int(previous.get(dep, 0))
        diff = current[dep] - prev
        sign = f"+{diff}" if diff > 0 else str(diff)
        lines.append(f"| {dep} | {current[dep]} | {sign} |")

    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
