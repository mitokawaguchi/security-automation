<!--
目的: 3つの脳（攻撃研究者/CISO/投資家）の構成とデータフローを説明する設計書です。
トリガー: 運用時の参照ドキュメントです。
依存: 各 workflow と scripts の実装です。
想定実行時間: 読了目安は 5〜10分です。
-->

# 3つの脳アーキテクチャ

## 全体図（Mermaid）

```mermaid
flowchart TD
  A[配布エンジン<br/>distribute-workflows.yml] --> B[各リポに監査ワークフロー配布]

  B --> C1[攻撃研究者の脳]
  B --> C2[CISOの脳]
  B --> C3[投資家の脳]

  C1 --> D1[CodeQL / Gitleaks / Trivy / SBOM]
  C1 --> D2[cve-intel-collector.sh]

  C2 --> E1[risk-scorer.sh]
  C2 --> E2[weekly-digest.sh]
  C2 --> E3[compliance-checker.yml]

  C3 --> F1[threat-intel-scraper.sh]
  C3 --> F2[dependency-trend.py]

  D2 --> G[reports/]
  E2 --> G
  F1 --> G
  F2 --> G

  G --> H[orchestrator.sh]
  H --> I{3層すべて高リスク?}
  I -->|Yes| J[[CRITICAL Issue 起票]]
  I -->|No| K[レポートのみ更新]
  H --> L[DASHBOARD.md 更新]
```

## レイヤー別責務

- 攻撃研究者レイヤー  
  脆弱性・秘密情報漏えい・SBOM/CVEを収集し、技術的な危険シグナルを出します。

- CISOレイヤー  
  Issueの優先度化（P0〜P3）と週次サマリーにより、対応順序を組織視点で確定します。

- 投資家レイヤー  
  外部脅威トレンドと依存採用傾向から、将来リスクと技術負債の兆候を早期に検出します。

- 統合レイヤー  
  3層結果を合成し、3条件一致時のみ `[CRITICAL]` を発火してノイズを抑制します。

## データフロー

1. `workflows/*.yml` を全リポへ配布します。  
2. 各リポでセキュリティ系ワークフローが実行されます。  
3. このリポが API 経由で横断集計し、`reports/` に蓄積します。  
4. `orchestrator.sh` が統合判定を実行します。  
5. `update-dashboard.yml` が `DASHBOARD.md` を更新します。
