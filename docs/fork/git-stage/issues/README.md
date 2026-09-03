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

## STAGE 02 の Codex レビューで決めたこと（2026-09-03）

- `hasHead` は廃止。`git diff --cached` / `git diff` は HEAD 無しでも動く
  `[実測: unborn ブランチで確認]`。初コミット前に `--no-index` へ倒すと staged と
  unstaged が同じ全文パッチになる
- `git status` に `--untracked-files=all` を付ける。無いと未追跡ディレクトリが
  `?? dir/` 1 件で出て、開けない・件数も合わない `[実測]`
- unmerged（`UU` `AU` `UD` `DU` `AA` `DD`）は **Changes に 1 回だけ** 出す
  `[設計判断]`。両セクションに出すと staged 側の `--cached` パッチが意味を持たない。
  Merge Changes セクションは別 issue
- セクション件数は行数でなく**ファイル数**（フォルダを畳んでも減らない）
- SSH ルートでは行は出るが**差分は開かない**（ローカル git を remote パスで叩かない
  ためのガード）。SSH で差分を開く対応は **要確認**（別 issue）
- `ForEach` 配下に渡すクロージャは `self` を捕まえない（`Binding` と値だけ）。
  `store` が list 境界の下に流れると upstream #2586 のスピンループを再発させる

