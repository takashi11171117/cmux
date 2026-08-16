---
name: Agent-first IDE - upstream 追従と基準線の確立
about: 実装コミットを積む前に upstream manaflow-ai/cmux を取り込み、ビルドとユニットテストが通る状態を基準線にする
title: '[AFIDE 02] upstream 追従とビルド・テスト基準線の確立'
labels: chore, agent-first-ide, afide-02, upstream-sync
assignees: ''
---

## 🎯 目的

`fork/agent-first-ide` に upstream `manaflow-ai/cmux` の最新を取り込み、**取り込み後にビルドとユニットテストが通る状態**を作る。以降の全 issue はこの基準線の上に積む。

## 📊 背景

- NFR-10 は「FR-01 以降の実装コミットを積む前に upstream の最新を取り込む」「取り込み後にビルドが通り、NFR-06 のテストが通る」を受け入れ条件にしている
- 要件定義の確認時点で、`origin` は `takashi11171117/cmux` のみで **upstream リモートが未設定**、fork は独自コミット0 / upstream から12コミット遅れだった
- 本ブランチの独自変更は現時点で `docs/fork/` のみ。**取り込みのコンフリクトが最小で済む今が唯一の低コストな機会**である

## ✅ タスクリスト

### upstream の取り込み

- [ ] `git remote add upstream https://github.com/manaflow-ai/cmux.git`（リモート名は `upstream`）
- [ ] `git fetch upstream` して差分件数を記録する
- [ ] `fork/agent-first-ide` に upstream の既定ブランチを取り込む（merge / rebase のどちらを採るかを PR 説明に書く。`main` は直接触らない — NFR-08 受け入れ条件2）
- [ ] コンフリクトが出た場合、解決内容を PR 説明に列挙する（`docs/fork/` 以外に独自変更が無いため、原則コンフリクトは出ない想定）
- [ ] サブモジュール（`ghostty`）のポインタ更新が入った場合は `./scripts/setup.sh` を回して整合を取る

### ビルドとテストの基準線

- [ ] `./scripts/setup.sh` を実行（submodule 初期化・GhosttyKit ビルド・pbxproj 正規化 pre-commit フックの導入）
- [ ] `./scripts/reload.sh --tag agent-first-ide` でビルドが通ることを確認（**素の `xcodebuild` / untagged ビルドは禁止**）
- [ ] `scripts/test-unit.sh`（`cmux-unit` scheme）が通ることを確認
- [ ] NFR-06 が挙げる既存テストが通ることを個別に確認する: `cmuxTests/FilePreviewTextEditorTextKitTests.swift` / `FilePreviewReloadTests.swift` / `FilePreviewReloadCompletionTests.swift` / `FilePreviewKindResolverTests.swift` / `MarkdownPanelTests.swift`
- [ ] `./scripts/lint-pbxproj-test-wiring.sh` と `./scripts/check-pbxproj.sh` が通ることを確認（以降の issue で使うため、この時点で緑であることを確かめておく）

### 基準線の記録

- [ ] 取り込んだ upstream のコミットハッシュ、テスト結果（実行件数を含む）、ビルドタグを PR 説明に残す
- [ ] 詳細設計 §4.1 が参照している行番号（`FilePreviewTextEditor.swift:143-186` など）が取り込み後もずれていないかを抜き取りで確認し、**ずれていた箇所を PR 説明に列挙する**（後続 issue が設計書の行番号を頼りにするため）

## 📦 成果物

- [ ] `upstream` リモートが設定され、`fork/agent-first-ide` が upstream 最新を含んでいる
- [ ] `./scripts/reload.sh --tag agent-first-ide` が成功する
- [ ] `scripts/test-unit.sh` が成功し、「Executed 0 tests」ではない実行件数が出ている
- [ ] 取り込みハッシュ・テスト結果・設計書の行番号ずれの一覧が PR 説明に記録されている

## 📝 備考

- `main` を直接触らない。作業は `fork/agent-first-ide`（および派生ブランチ）に限定する（NFR-08 受け入れ条件2）
- upstream への PR は出さない。この issue は追従コスト低減のためであり、還元のためではない（NFR-09）
- 取り込み後に設計書の行番号がずれていた場合、**設計書を書き換えるのはこの issue のスコープ外**。ずれの一覧を残すところまでとし、後続 issue は実ファイルを読んで作業する

## 🔗 関連

- 依存: なし（**afide-03 以降すべての前提**。実装コミットはこの issue の完了後に積む）
- 由来: NFR-10（着手前に upstream 追従）、NFR-08（差分の局所化）、NFR-09（upstream PR を前提にしない）、NFR-06（既存テスト）
- 設計書: `docs/fork/03_詳細設計.md` §15.3、§18
- 未確定事項: **未確定-11（upstream 追従の実施時期）を本 issue で解決する**。「upstream リモートを追加して追従するか」は着手前に本人確認が必要
