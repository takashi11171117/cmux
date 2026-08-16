---
name: Agent-first IDE - Session Restore 回帰フィクスチャとテスト
about: 実装前のセッション JSON をフィクスチャ化し、後方互換のデコードとレイアウト round-trip を検証するテストを追加する
title: '[AFIDE 03] Session Restore 回帰フィクスチャとテスト（NFR-01 / NFR-02）'
labels: test, agent-first-ide, afide-03, session-restore
assignees: ''
---

## 🎯 目的

**FR-01〜FR-11 の実装コミットを積む前に**、実装前のセッションファイルをフィクスチャとしてリポジトリに固定し、以降どの issue でも Session Restore が壊れていないことを機械的に検出できるようにする。

## 📊 背景

- NFR-01（Session Restore を壊さない）は要件定義で**最優先**と明記されている
- 詳細設計 D-1 は「新しい `PanelType` を作らない」と決めた。理由は `PanelType.init(from:)` が未知の raw value に対して `DecodingError.dataCorruptedError` を throw し、`SessionWorkspaceSnapshot.panels` が非 Optional 配列の合成 `Codable` であるため、**1パネルの type が読めないだけで workspace snapshot 全体のデコードが失敗する**から
- したがって NFR-01 / NFR-02 は「何もしない」ことで満たされる設計になっている。**満たされていることを証明するテストが要る**
- フィクスチャは**実装前のビルドで保存されたもの**でなければ意味がない。この issue を feature issue より先に片付ける理由がここにある

## ✅ タスクリスト

### フィクスチャの取得

- [ ] `./scripts/reload.sh --tag agent-first-ide --launch` で afide-02 時点のビルドを起動する
- [ ] Terminal / Browser / Markdown / File Preview / Project を含む workspace を作り、分割レイアウトと選択パネルを持たせる
- [ ] アプリを終了してセッションファイルを取得し、テスト用フィクスチャとしてリポジトリに追加する（個人情報・実パスが載る場合は匿名化し、匿名化したことをテスト内コメントに書く）
- [ ] フィクスチャがどのビルド（コミットハッシュ）で保存されたものかをテストのコメントに記録する

### テスト

- [ ] 新規テストファイル（`import Testing` / `@Test` / `@Suite`。**`import XCTest` を書かない**）を追加し、フィクスチャのデコードが成功することを検証する（NFR-02 受け入れ条件2）
- [ ] Terminal / Browser / Markdown / File Preview / Project を含む `SessionWorkspaceSnapshot` の round-trip テストを追加し、パネル構成・分割レイアウト・選択パネルが一致することを検証する（NFR-01 受け入れ条件1）
- [ ] `SessionFilePreviewPanelSnapshot` / `SessionMarkdownPanelSnapshot` のキー集合が変わっていないことを、**実行時のデコード挙動として**検証する（ソーステキストの grep で検証しない — テスト品質規約）

### pbxproj 配線（**漏らすと CI が緑のまま無言でスキップされる**）

- [ ] 新規テストファイルに `PBXFileReference` を追加する
- [ ] 同ファイルを `cmuxTests` ターゲットの `PBXSourcesBuildPhase` に追加する
- [ ] フィクスチャをリソースとして読む場合、その配線（`PBXFileReference` + 必要なら resources build phase）も追加する
- [ ] `./scripts/lint-pbxproj-test-wiring.sh` が通ることを確認する
- [ ] `./scripts/check-pbxproj.sh` が通ることを確認する

### ビルド確認

- [ ] `./scripts/reload.sh --tag agent-first-ide`（**素の `xcodebuild` は使わない**）
- [ ] `scripts/test-unit.sh` で新規テストが**実際に実行されている**こと（実行件数が増えていること）を確認する

## 📦 成果物

- [ ] 実装前ビルドで保存されたセッションフィクスチャがリポジトリに存在する
- [ ] フィクスチャのデコード成功テスト
- [ ] 5種のパネルを含む workspace snapshot の round-trip テスト
- [ ] pbxproj に `PBXFileReference` + `PBXSourcesBuildPhase` の2エントリ（+ フィクスチャ配線）
- [ ] `./scripts/lint-pbxproj-test-wiring.sh` / `scripts/test-unit.sh` が緑で、実行件数が0でないこと

## 📝 備考

- 破壊的変更なし。`Sources/SessionPersistence.swift` は**変更しない**（NFR-08 の「触らないと明言するファイル」に含まれる）
- 以降の全 issue の完了条件に「このテストが通ること」が乗る。落ちた場合は設計が D-1 から逸脱している合図

## 🔗 関連

- 依存: **afide-02 完了後に着手**（基準線のビルドでフィクスチャを取る必要がある）。かつ **afide-04 以降の実装 issue より先に完了させる**
- 由来: NFR-01（Session Restore を壊さない）、NFR-02（セッションスキーマの後方互換）、D-01（セッション永続化データ）
- 設計書: `docs/fork/03_詳細設計.md` §5 D-1、§11、§16.1、§16.4、§15.1
- 未確定事項: なし
