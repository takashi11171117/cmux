---
name: Git - 変更ファイル一覧を表示する
about: GIT 01 で作った Git タブに、git status の結果を一覧表示する
title: '[GIT 02] 変更ファイル一覧の表示（FR-G02, FR-G03, FR-G06）'
labels: agent-first-ide, git-review, git-02
assignees: ''
---

## 🎯 目的

Git タブに、作業ツリーの変更ファイルを変更種別つきで一覧表示する。
**クリックしたときの挙動は GIT 03 で作る**。ここでは表示のみ。

## 📊 背景

git status の取得も、その更新契機も**既に存在する**。新しく作らない。

| 事実 | 出所 |
|---|---|
| `FileExplorerStore` が `GitStatusProvider` を保持 | `[実コード: Sources/FileExplorerStore.swift:755-758]` |
| 根の切替時に `refreshGitStatus()` | `[同:818-821]` |
| ディレクトリ監視イベントごとに `reload()` + `refreshGitStatus()` | `[同:878-882]` |
| 戻り値は `[String: GitFileStatus]`（パス→状態） | `[実コード: Sources/GitStatusProvider.swift:24]` |
| 状態は modified/added/deleted/renamed/untracked の5種 | `[実コード: Sources/GitFileStatus.swift:1-3]` |
| 5種すべての色が `FileExplorerPalette` にある | `[実コード: Sources/FileExplorerPalette.swift:7-11, 15-17]` |

## ✅ タスク

- [ ] `FileExplorerStore` の git status を購読して一覧を作る
- [ ] 行に変更種別を表示する。色は `FileExplorerPalette` の既存定義を使う
- [ ] パス順に並べる
- [ ] 変更が無いとき・Git リポジトリでないときの空表示
- [ ] 差分ソース切替 UI（unstaged / staged / branch / last-turn）をヘッダーに置く
      `[実コード: CLI/cmux_open.swift:653-694]`

## ⚠️ 落とし穴

### SwiftUI の list 境界（最重要）

`ForEach` の下にある view は observable store への参照を持ってはならず、
`body` から state を書いてはならない。**違反すると 100% CPU のスピンループが再発する**
（upstream #2586）。

参照実装: `IndexSectionActions` / `SectionGapActions` / `SessionSearchFn`
（`Sources/SessionIndexView.swift`）`[出所: CLAUDE.md]`

### 新しい色を定義しない

ファイルツリーの変更マークと色が食い違うと、同じ情報が別物に見える。
`FileExplorerPalette` の既存色を使う。

### 独自のポーリングを作らない

更新契機は既にある（上表）。タイマーや独自の監視を足さない。

## 📦 成果物

- 一覧の View（新規ファイル。1ファイル1型の規約に従う）
- テスト: パス順に並ぶ／空リポジトリで空になる／5種の状態が区別される

## 🔗 トレーサビリティ

FR-G02, FR-G03, FR-G06（要件定義 §1）、NFR-G01, NFR-G02（同 §2）
