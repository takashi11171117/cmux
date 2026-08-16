---
name: Agent-first IDE - シンタックスハイライトエンジン選定
about: 未確定-02 を解決する。3候補を NFR-11 の6軸で評価し、比較表を docs/fork/ に残して1つに決める
title: '[AFIDE 01] シンタックスハイライトエンジン選定（未確定-02 の解決）'
labels: research, agent-first-ide, afide-01, syntax-highlight
assignees: ''
---

## 🎯 目的

シンタックスハイライトのエンジンを **1つに決める**。決定と根拠を比較表として `docs/fork/` に残す。

NFR-11 は「比較表がない状態でライブラリを本体に追加しない」を受け入れ条件にしているため、この issue が完了するまで afide-06（エンジン実装）に着手できない。

## 📊 背景

詳細設計 §5 D-2 で、選択肢は次の **3つ** であることが確定している（「Highlightr か自前か」の2択ではない）。

| 選択肢 | 依存 | 実行場所 | 備考 |
|---|---|---|---|
| A. Highlightr（SPM remote package） | remote package 1本 + JavaScriptCore | JSC | §15.2 の pbxproj 配線（`cmux` と `cmuxTests` の両ターゲット）+ `Package.resolved` 差分が発生 |
| B. 自前スキャナ | なし | Swift | `[FilePreviewHighlightRun]` を直接返せる |
| C. 同梱済み `Resources/markdown-viewer/highlight.min.js` を JavaScriptCore で直接評価 | SPM 依存ゼロ・バンドル増分ゼロ | JSC | Highlightr の薄いラッパ相当を自前で書く |

C は「highlight.js は新規の第三者コードではない」という事実（macOS 本体の Markdown Viewer が既に同梱・実行している）に基づく選択肢である。

**`Packages/iOS/CmuxAgentChatUI` 経由の流用は既に「不可」と結論が出ている**（詳細設計 §5 D-2）。macOS 本体は同パッケージをリンクしておらず、macOS 側 `Package.resolved` に Highlightr は無く、`Packages/iOS/` からの利用はパッケージ配置規約に抵触する。この issue で再検討しない。

設計側で既に判定済みの軸（TextKit 1 互換 / 13言語カバー / dependency 固定 / 実行環境）は再調査せず、**未判定の軸（maintenance / license / 部分入力時の performance）に絞って調べる**。

## ✅ タスクリスト

### 評価（NFR-11 の6軸）

- [ ] 軸1 maintenance: Highlightr / highlight.js それぞれの最終リリース・issue 対応状況を調べる（`[要調査]` 扱いの軸）
- [ ] 軸2 dependency 固定: A は `exact: "2.3.0"` で pin 可能（iOS 側の運用実績あり）。B / C は依存ゼロであることを確認して記録
- [ ] 軸3 performance: **「全文を渡しつつ `range` に交差するトークンだけ安く返せるか」** を測る。Highlightr / highlight.js は `range` を無視して全文を色付けするため可視範囲優先が効かない可能性がある（詳細設計 §20.2 の最大リスク）
- [ ] 軸3 の測定条件を決めて記録する（対象ファイルの行数・言語・回数）。数値目標そのものは未確定-08 なので、この issue では**候補間の相対比較**までとする
- [ ] 軸4 license: Highlightr / highlight.js（同梱物を含む）のライセンスと表記義務を確認する
- [ ] 軸5 TextKit 1 互換: 設計 §5 D-2 の判定（`NSAttributedString` を返すため問題なし、`CodeAttributedString` は使わない）を追認して記録
- [ ] 軸6 13言語カバー: Swift / TS / JS / Dart / PHP / Python / JSON / YAML / Markdown / C / C++ / Rust / Go を候補ごとに確認
- [ ] 追加軸: 「エンジンにどの範囲のファイル内容を渡すことになるか」（詳細設計 §20.5）。B は入力面が広がらない

### 検証（コードを書いて確かめる部分）

- [ ] 選定のためのスパイクは `docs/fork/` 外へコミットしない。ローカル検証にとどめ、**本体（`Sources/` / `cmux.xcodeproj`）へ依存を追加しない**（NFR-11 受け入れ条件2）
- [ ] C を評価する場合、`Resources/markdown-viewer/highlight.min.js` を `JavaScriptCore` で評価してトークン列を得られるかを実際に試す
- [ ] A を評価する場合、`cmux` と `cmuxTests` の両ターゲットへの product 追加と `Package.resolved` 差分が必要になる点をコストとして記録する

### 決定と記録

- [ ] `docs/fork/04_ハイライトエンジン比較.md`（ファイル名は任意、`docs/fork/` 配下であること）に6軸 + 追加軸の比較表を書く
- [ ] 採用する1案を明記し、不採用理由も書く
- [ ] 採用案が `FilePreviewSyntaxHighlighting`（`func runs(for text: String, language: String, range: NSRange) async -> [FilePreviewHighlightRun]`）にどう適合するかを1節書く。Highlightr / highlight.js 系なら `NSAttributedString` の `.foregroundColor` ラン → `FilePreviewTokenRole` への逆写像アダプタが必要になる点を含める
- [ ] `FilePreviewHighlightPalette` の色の出所を決める（`Resources/markdown-viewer/highlight-github.css` / `highlight-github-dark.css` を出所候補にできる）

## 📦 成果物

- [ ] `docs/fork/` にエンジン比較表（6軸 + 追加軸、候補3件、採用/不採用の理由付き）
- [ ] 採用エンジン1件の決定文
- [ ] 採用案を seam（`FilePreviewSyntaxHighlighting`）に載せる方法の記述（アダプタの要否）
- [ ] パレット色の出所の決定
- [ ] 本体コード（`Sources/` / `cmux.xcodeproj` / `Package.resolved`）に差分が**無い**こと

## 📝 備考

- この issue は調査 issue であり、`docs/fork/` 以外を変更しない。実装は afide-06 で行う
- 工数見積もりは比較表の完成後に出す（NFR-11 受け入れ条件3）
- ビルド確認は不要（本体を変更しないため）。ローカルスパイクを消したことを PR 説明に書く

## 🔗 関連

- 依存: なし（**着手前に解決が必要な最上位の未確定事項**。afide-06 のブロッカー）
- 由来: NFR-11（ライブラリ選定基準）、FR-01 / FR-02 / FR-03 / FR-11、NFR-04 / NFR-15
- 設計書: `docs/fork/03_詳細設計.md` §5 D-2、§15.2、§20.2、§20.5、§20.6
- 未確定事項: **未確定-02（本 issue で解決する）**。未確定-08（性能の数値目標）は本 issue では解決しない — 候補間の相対比較までとし、絶対値の目標は別途決める
