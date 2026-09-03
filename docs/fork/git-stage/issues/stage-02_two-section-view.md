---
name: Stage - 2セクション表示（Staged Changes / Changes）
about: Git タブを 2 セクションに分けて表示する、差分の振り分けも実装
title: '[STAGE 02] 2 セクション + 差分振り分け（FR-S03, FR-S05）'
labels: agent-first-ide, git-stage, stage-02
assignees: ''
---

## 🎯 目的

STAGE 01 のデータを使って UI を 2 セクションに分ける。行にボタンはまだ無し。
差分の open は staged / unstaged で振り分ける。

**依存: STAGE 01。**

## ✅ やること

- [x] `GitChangesPanelView` を 2 セクションに分ける
- [x] 各セクションで独立に `collapsedFolders` を持つ
- [x] 該当ファイル 0 のセクションは非表示
- [x] `GitFilePatchCommand` に `Side` 追加、既存の init を書き換え or 追加
- [x] `AppDelegate.openFileDiffInCodeReviewColumn` の引数を `side: Side` に
- [x] 呼び出し側を全部更新
- [x] `GitFilePatchCommandTests` を Side 3 通り × hasHead 2 通り に拡張
- [x] ローカライズ: `git.staged.section`, `git.unstaged.section`

## ⚠️ 落とし穴

- MM ファイル（staged と unstaged 両方あり）は**両セクションに出す**
- 空セクションの見出しごと非表示にする（VS Code と同じ）
- 既存の行クリック→差分の経路 (`openFileDiffInCodeReviewColumn`) の署名変更が
  他の呼び出し元を壊さないよう grep で洗う

## 🧪 完了条件

- MM ファイルが両セクションに出て、クリックで両側の差分がそれぞれ出る
- 全ファイル staged なら "Changes" 見出しが消える
- 全ファイル unstaged なら "Staged Changes" 見出しが消える
