---
name: Git - 一覧から差分をコードレビューカラムに開く
about: 一覧の項目をクリックしたら差分が開く。ターミナルを分割しない
title: '[GIT 03] 一覧から差分をカラムに開く（FR-G04, FR-G05）'
labels: agent-first-ide, git-review, git-03
assignees: ''
---

## 🎯 目的

Git 一覧の項目をクリックしたら、そのファイルの差分がコードレビューカラムに開く。

**何度クリックしてもターミナル側のペイン構成が変わらないこと**が要点。
`cmux diff` の既定は `split_right` `[実測: cmux diff --unstaged --json]` で、
そのままだと一覧から開くたびにターミナルが分割されていく。

## 📊 背景

差分の描画は既存を使う。**改変しない**（NFR-G03）。

| 事実 | 出所 |
|---|---|
| 差分は `cmux-diff-viewer://` スキームの WebView | `[実コード: Sources/TerminalController+DiffViewerTrust.swift:19]` |
| 差分ソースは4種 | `[実コード: CLI/cmux_open.swift:653-694]` |
| レビューコメント機能が乗っている | `[実コード: Sources/Panels/DiffCommentsBridge.swift]` |
| カラムは自前の `Workspace` を持つ | `[実コード: Sources/CodeReviewPanelState.swift]` |
| ブラウザサーフェスを開く API がある | `[実コード: Sources/Workspace.swift:8664-8671]` |

```swift
func newBrowserSurface(
    inPane paneId: PaneID,
    url: URL? = nil,
    ...
) -> BrowserPanel?
```

ファイルを開く既存実装（`newFilePreviewSurface` / `newMarkdownSurface` の
使い分け）と同じ並びに置ける。

## ✅ タスク

- [ ] 一覧の行クリックで、そのファイルの差分 URL を得る
- [ ] カラムの workspace に `newBrowserSurface` で開く
- [ ] 同じ差分を再度開いたときタブを増やさない（既存を focus する）
- [ ] **FR-G07 の判断を実装前に確認する**（下記）

## ❓ 実装前に決めること（FR-G07）

差分を開こうとしたときカラムが非表示なら、どうするか。

- 案A: 自動的に開く
- 案B: 開かず、タイトルバーのトグルを促す

**案A を推奨**。ファイルを開く経路は `show(filePath:)` の先頭で
`isVisible = true` としており、揃う `[実コード: Sources/CodeReviewPanelState.swift]`。
ただし利用者の意図に反して画面が動く可能性があるため、**着手前に確認すること**。

## ⚠️ 落とし穴

### `cmux diff` の既定を変えない

CLI から直接叩く既存の使い方（`split_right`）は壊さない。
**Git 一覧からの導線だけ**がカラムを使う。

### 同じファイルを二重に開かない

カラムのファイル表示では、`FilePreviewPanel` と `MarkdownPanel` の両方を見て
既存判定している `[実コード: Sources/CodeReviewPanelState.swift の existingSurface]`。
差分（`BrowserPanel`）も同じ扱いが要る。片方しか見ないと二重に開く。

## 📦 成果物

- 一覧 → カラムの配線
- テスト: 同じ差分を2回開いてもサーフェスが増えない

## 🔗 トレーサビリティ

FR-G04, FR-G05, FR-G07（要件定義 §1）、NFR-G03（同 §2）
