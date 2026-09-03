---
name: Stage - Discard ボタン
about: 行に ↺ を追加、確認ダイアログ経由で未ステージ変更を捨てる
title: '[STAGE 04] Discard ボタン（FR-S04 SREQ-03, NFR-S03）'
labels: agent-first-ide, git-stage, stage-04
assignees: ''
---

## 🎯 目的

Changes セクションの行に `↺`（discard）を追加。押下で確認ダイアログ → 追跡済みは
`git checkout -- <path>`、未追跡は `FileManager.trashItem(at:)` で Trash 送り。

**依存: STAGE 03。**

## ✅ やること

- [x] `GitStageOperation` に `discardUnstaged(...)`
- [x] 行に `↺` ボタン（Changes セクションのみ）
- [x] `NSAlert` で確認ダイアログ、破棄が失敗した理由をユーザーに提示
- [x] 未追跡ファイルは `FileManager.trashItem` で Trash に入れる（既存の Move to Trash
      と同じ扱い）
- [x] ローカライズ: `git.discard.action`, `git.discard.confirmTitle`, `git.discard.confirmBody`

## ⚠️ 落とし穴

- **未追跡ファイルを `rm` しない**。復旧不能。既存の Move to Trash と同じ
  `FileManager.trashItem` を使う
- 追跡済みで staged 変更もあるファイルの `git checkout` は unstaged 側の変更だけ
  捨てて staged は残す。仕様どおり（要件 SREQ-03 は「未ステージの変更を捨てる」）
- ダイアログのボタンは既定を "Cancel" にし、Enter で誤爆しないようにする

## 🧪 完了条件

- `↺` 押下で確認ダイアログが必ず出る
- OK で未追跡は Trash に入り、追跡済みは HEAD の状態に戻る
- Cancel でファイルは残る
