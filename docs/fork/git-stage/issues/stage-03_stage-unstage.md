---
name: Stage - Stage / Unstage ボタン
about: 行 hover で + / - を出し、押下で git add / reset を実行
title: '[STAGE 03] Stage / Unstage ボタン（FR-S04 SREQ-01/02）'
labels: agent-first-ide, git-stage, stage-03
assignees: ''
---

## 🎯 目的

各行に `+`（stage） `−`（unstage）ボタンを追加。押下で対応する git コマンドを走らせ、
一覧を再取得。

**依存: STAGE 02。**

## ✅ やること

- [x] `Sources/GitStageOperation.swift` を新設（actor）
- [x] Changes セクションの行に `+`、Staged セクションの行に `−`
- [x] hover / 常時 は実装中に判定して仕様書 §5 に書き戻す
- [x] 押下後に `store.refreshGitStatus()` を明示的に呼ぶ
- [x] ローカライズ: `git.stage.action`, `git.unstage.action`

## ⚠️ 落とし穴

- **初コミット前**は `git reset -- <path>` が「ambiguous argument HEAD」を返す。
  `git rev-parse HEAD` で HEAD の存在確認 → 無いなら `git rm --cached -- <path>` に
  切り替え
- ボタン押下と watcher による refresh がぶつからないよう、明示的 refresh は debounce
  無しでも良い（`gitEntryStatusByPath` は Published なので UI は最新値を描く）
- 行 hover で observable な state を書かないこと（既存の #2586 制約）

## 🧪 完了条件

- `+` で `git add`、`−` で `git reset` が走り、一覧が数秒以内に反映される
- 初コミット前でも `−` が壊れない
- File Explorer の色分けも更新される（`gitStatusByPath` 派生経由）
