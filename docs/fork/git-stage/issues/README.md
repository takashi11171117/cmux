# Git ステージ操作 タスク一覧

仕様は `docs/fork/git-stage/` の 01〜03。

## 依存関係

```
STAGE 01（データ層）
    │
    ▼
STAGE 02（2 セクション表示 + 差分振り分け）
    │
    ▼
STAGE 03（Stage / Unstage ボタン）
    │
    ▼
STAGE 04（Discard ボタン）
```

## 一覧

| 番号 | 内容 |
|---|---|
| STAGE 01 | `GitEntryStatus` 型追加、パーサ更新、既存 API 互換維持 |
| STAGE 02 | Git タブを 2 セクション、差分の staged/unstaged 振り分け |
| STAGE 03 | 行に `+` `−` ボタン、git add / reset 実行 |
| STAGE 04 | 行に `↺` ボタン、Discard（確認ダイアログ経由） |

## 実装前に決まった罠

- `??` は「staged=nil, unstaged=untracked」に補正する（機械的に両方 untracked に
  すると壊れる）
- `−`（unstage）は初コミット前だと `git reset` が壊れる。HEAD 確認して
  `git rm --cached` に切り替える
- Discard の未追跡は絶対 `rm` しない、Trash 送りにする（NFR-S03）
- 既存 `gitStatusByPath` を消さない、派生で維持する（File Explorer 色分け互換）
