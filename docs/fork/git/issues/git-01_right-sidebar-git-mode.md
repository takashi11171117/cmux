---
name: Git - 右サイドバーに Git モードを追加
about: RightSidebarMode に .git を足し、タブとして出るところまで。中身は空でよい
title: '[GIT 01] 右サイドバーに Git モードを追加（FR-G01）'
labels: agent-first-ide, git-review, git-01
assignees: ''
---

## 🎯 目的

`RightSidebarMode` に `.git` を追加し、右サイドバーのタブとして表示されるところまで。
**一覧の中身は次の issue（GIT 02）で作る**ので、ここでは空のプレースホルダでよい。

この issue が閉じるまで GIT 02 以降に着手できない（器が無いため）。

## 📊 背景

右サイドバーはモード切替式で、現在 6 モードある。

```swift
enum RightSidebarMode: String, CaseIterable, Codable, Sendable {
    case files, find, sessions, feed, dock
    case customSidebar = "custom-sidebar"
}
```
`[実コード: Sources/RightSidebarPanelView.swift:16-22]`

タブは `availableModes.map { ... }` `[実コード: 同:152]` で作られ、
`availableModes` は `allCases.filter`
`[実コード: Sources/RightSidebarMode+Availability.swift:30]`。並べ替えが無いため
**enum の宣言順がそのままタブ順**になる。

## ✅ タスク

- [ ] `RightSidebarMode` に `case git` を追加する。**`files` の直後**に置く（タブ順のため）
- [ ] `label` に「Git」を追加（`String(localized:)` + xcstrings に en/ja）
- [ ] `symbolName` を決める
- [ ] `isAvailable(feedEnabled:dockEnabled:)` で常に利用可能とする
- [ ] `FileExplorerRootSyncPolicy.shouldSyncFileExplorerStore` を `.files, .find, .git` に
- [ ] `from(cliArgument:)` に `"git"` を追加する
- [ ] `paneModes` に含めるかを判断する（含めないなら理由をコメントに書く）
- [ ] `shortcutAction` を追加するか判断する。追加するなら `KeyboardShortcutSettings` 側も
- [ ] 中身は「変更なし」等のプレースホルダでよい

## ⚠️ 落とし穴

**コンパイラが検出しない箇所が 2 つある。**

| 箇所 | 理由 |
|---|---|
| `from(cliArgument:)` | `default: return nil` があるため、case を足しても通る。CLI から切り替えられないだけ |
| `paneModes` | 配列リテラルのため、足さなくても通る |

`customSidebar` を参照する箇所は 20 ある `[実測: grep -rn "case .customSidebar"]`。
すべて確認すること。

## 📦 成果物

- `Sources/RightSidebarPanelView.swift`（enum + label + symbolName + 同期ポリシー）
- `Sources/RightSidebarMode+Availability.swift`（`from(cliArgument:)` + `isAvailable`）
- `Resources/Localizable.xcstrings`（en/ja）
- テスト: `from(cliArgument: "git")` が `.git` を返す／`availableModes()` に含まれる／
  `shouldSyncFileExplorerStore(mode: .git)` が true

## 🔗 トレーサビリティ

FR-G01（要件定義 §1）
