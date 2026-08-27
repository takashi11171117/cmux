---
name: History - 右サイドバーに History モードを追加
about: RightSidebarMode に .history を足し、タブとして出るところまで。中身は空でよい
title: '[HIST 01] 右サイドバーに History モードを追加（FR-H01）'
labels: agent-first-ide, git-history, hist-01
assignees: ''
---

## 🎯 目的

`RightSidebarMode` に `.history` を追加し、右サイドバーのタブとして表示される
ところまで。**一覧の中身は HIST 03 で作る**ので、ここでは空のプレースホルダでよい。

この issue が閉じるまで HIST 03 以降に着手できない（器が無いため）。

## 📊 背景

宣言順がタブ順になるため `[実コード: Sources/RightSidebarPanelView.swift:18-22]`、
`.git` の直後に置く。

```swift
case files
case git
case history      // ← ここ
case find
```

## ✅ やること

触る箇所は**6ファイル 13 箇所**。実測済みの一覧は
`docs/fork/git-history/03_詳細設計.md §2.2`。

**まず case を足してビルドし、コンパイラに残りを教えてもらう。**11 箇所は
`default` の無い `switch` なのでビルドが止まる。

- [ ] `case history` を `.git` の直後に追加
- [ ] ビルドを通す（11 箇所がエラーになる）
- [ ] `FileExplorerRootSyncPolicy.shouldSyncFileExplorerStore` を **true**
- [ ] `from(cliArgument:)` で `"history"` を受ける ★
- [ ] `paneModes` は触らない（`.git` も入っていない）★
- [ ] 空のプレースホルダビュー
- [ ] ローカライズ（en / ja）

## ⚠️ 落とし穴

★の2箇所は **`switch` の網羅性で検出されない** `[実測]`。

- `from(cliArgument:)` は `default: return nil` を持つ
  `[実コード: Sources/RightSidebarMode+Availability.swift:19-20]`
- `paneModes` は配列リテラル
  `[実コード: Sources/RightSidebarPanelView.swift:77]`

**足し忘れてもコンパイルは通り、実行時に機能しないだけになる。**

`shouldSyncFileExplorerStore` を false のままにすると、タブを開いてもルートが
同期されず履歴が常に空になる。

`Localizable.xcstrings` は **JSON を再直列化せずテキストとして挿入する**。
`json.dump` で書き戻すと並び順とエスケープが変わり、差分が万行になる。

## 🧪 完了条件

- 右サイドバーのタブに Git の隣で History が出る
- `cmux` の CLI 引数からも選択できる
- 既存の6モードが壊れていない
