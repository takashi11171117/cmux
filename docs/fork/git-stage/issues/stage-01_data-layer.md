---
name: Stage - データ層（GitEntryStatus + パーサ更新）
about: 型を追加してパーサを差し替え、既存 gitStatusByPath を派生で維持
title: '[STAGE 01] データ層（FR-S01, FR-S02）'
labels: agent-first-ide, git-stage, stage-01
assignees: ''
---

## 🎯 目的

ステージ／未ステージを別々に扱えるようデータ層を分ける。UI は変更しない。

## ✅ やること

- [ ] `Sources/GitEntryStatus.swift` を新設
- [ ] `Sources/GitStatusProvider.swift` の `parseStatusChars` → `parseXY` に置換、
      `parseGitStatus` の戻り型を `[String: GitEntryStatus]` に
- [ ] `FileExplorerStore` に `@Published gitEntryStatusByPath` 追加、既存
      `gitStatusByPath` は `compactMapValues(\.displayStatus)` で派生
- [ ] `GitStatusProviderTests` に XY 全パターン追加

## ⚠️ 落とし穴

- `??`（両方 `?`）は untracked。`staged=untracked, unstaged=untracked` にしない。
  慣習どおり `staged=nil, unstaged=untracked` に補正する
- 既存の File Explorer 色分けが壊れないこと（`gitStatusByPath` 派生が同じ値を返すか）
- `R ` は 2 パス（renamed source と dest）を消費するので `statusUsesSecondPath` は
  据え置き

## 🧪 完了条件

- 全 XY パターンのテストが緑
- 既存の File Explorer 色分け表示が変わらない（手動確認）
