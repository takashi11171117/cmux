---
name: History - 履歴データ層（コマンド・パース・サービス）
about: git log / git show を値型で決め、actor 越しに実行する。UI は無し
title: '[HIST 02] 履歴データ層（IF-H01, IF-H02, NFR-H01）'
labels: agent-first-ide, git-history, hist-02
assignees: ''
---

## 🎯 目的

履歴を読む部分だけを作る。**UI は作らない**。リポジトリ無しでテストできる形に
切り出すのがこの issue の主目的。

HIST 01 と並行して進められる。

## ✅ やること

- [ ] `GitHistoryCommand`（`--max-count` / `--skip` の組み立て）
- [ ] `GitCommitPatchCommand`（**常に `--first-parent`**）
- [ ] `GitCommitLine` と `parse` / `parseAll`（NUL 区切り）
- [ ] `GitHistoryService`（actor。`GIT_OPTIONAL_LOCKS=0`）
- [ ] 上記すべてのテスト

## ⚠️ 落とし穴（実測済み）

**`git show` はマージコミットの差分を既定で抑制する。**

| オプション | ルート | 通常 | マージ |
|---|---|---|---|
| なし | 8行 | 7行 | **0行** |
| `--first-parent` | 8行 | 7行 | **7行** |

オプション無しだと出力が空になり、呼び出し側が空パッチを捨てて**行が無反応になる**。
先行機能で `git add` 済みファイルにまったく同じ失敗をしている
`[docs/fork/技術メモ.md「git diff はステージした瞬間に空になる」]`。

`--root` は不要。`--first-parent` は通常コミットに付けても出力が変わらないので、
**分岐せず常に付ける**。`-c` / `--cc` は 0 行のままで使えない。

**`git log` をメインスレッドで待たない。** `git rev-parse` は stat 1回で終わるので
同期実行が許されるが、`git log` は所要時間がリポジトリ規模に比例する。

**区切りは NUL。** 件名に改行以外の任意文字が入りうるので、タブや `|` では壊れる。

## 🧪 完了条件

- マージコミットで `--first-parent` が付くテストがある
- 件名に区切り文字が入るケースのパーステストがある
- 親0個（ルート）・1個・複数（マージ）のパーステストがある
