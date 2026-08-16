---
name: Agent-first IDE - textExtensions 追加と入口別検証
about: dart / php / mjs / cjs / cxx / hh を textExtensions に足し、3入口すべてで .text モードに落ちることを検証する
title: '[AFIDE 11] コード拡張子のルーティング確定と入口別検証（FR-10 / FR-02 AC1）'
labels: enhancement, agent-first-ide, afide-11, file-routing
assignees: ''
---

## 🎯 目的

コード拡張子のファイルが**どの入口から開いても** File Preview の `.text` モードに落ちることを、環境非依存に確定させる。

## 📊 背景

- FR-10 の残作業は「新しいルーターを作ること」ではない。既存の3入口はいずれも `Workspace.openOrFocusFilePreviewSplit(from:filePath:)` / `openOrFocusMarkdownSplit(from:filePath:)` に集まり、`FilePreviewKindResolver` が `.text` を返す拡張子はテキストモードへ落ちる。**したがって分岐は1つも追加しない**（Shared behavior policy の要求そのもの）
- **唯一の例外**: `FilePreviewKindResolver.textExtensions` に `dart` / `php` / `mjs` / `cjs` / `cxx` / `hh` の6拡張子が無い。これらは `UTType(filenameExtension:)` が text / sourceCode に conform するか、または `sniffLooksLikeText` 頼みになり、**`.text` に落ちるかが環境依存になる**（`.dart` は UTI を宣言するアプリが無ければ `initialMode` が `.quickLook` になり、非同期 sniff 後に `.text` へ切り替わる）
- これは分岐の追加ではなく**データ表への追加**であり、判定関数は1本のままである
- 要件定義 FR-10 に対する 01 の記述「現状は外部アプリ起動に倒れている」は誤り。File Explorer のダブルクリックの既定は `.preview`（内蔵プレビュー）である

## ✅ タスクリスト

### 実装

- [ ] `Sources/Panels/FilePreviewPanel.swift` の `FilePreviewKindResolver.textExtensions` に `dart` / `php` / `mjs` / `cjs` / `cxx` / `hh` の6拡張子を追加する
- [ ] **これ以外の変更をしない。** 新しいルーター・新しい `FilePreviewMode` ケース・入口ごとの分岐を作らない
- [ ] `Sources/CommandClickFileOpenRouter.swift` / `Sources/FileExplorerKeyboardShortcuts.swift` / `Sources/Workspace.swift` は**触らない**（NFR-08 の「触らないと明言するファイル」）

### テスト（入口別検証 = Shared behavior policy の要求）

- [ ] `cmuxTests/FilePreviewKindResolverTests.swift`: コード拡張子が `.text` を返すこと（FR-10 受け入れ条件1）
- [ ] 同: **新たに足した `dart` / `php` / `mjs` / `cjs` / `cxx` / `hh` が `initialMode` の時点で `.text` を返すこと**（UTI 登録の有無に依存しないこと）
- [ ] 同: `.png` / PDF / メディアの解決が変わらないこと（FR-10 受け入れ条件4）
- [ ] `cmuxTests/TerminalLinkOpenCoordinatorTests.swift`: `CommandClickFileOpenRouter.openInCmux(...)` を叩く既存テストに、`.swift` などコード拡張子が File Preview の `.text` モードに落ちるケースを追加（**ターミナル Cmd-click 入口**）
- [ ] `.md` が従来どおり Markdown 側で開くこと（FR-10 受け入れ条件2 の回帰確認）
- [ ] 同一パスを2回開いても新規パネルが増えず既存パネルにフォーカスが移ること（FR-10 受け入れ条件3 の回帰確認）
- [ ] 新規テストファイルを足す場合は **pbxproj の2エントリ**（`PBXFileReference` / `PBXSourcesBuildPhase`）を追加し `./scripts/lint-pbxproj-test-wiring.sh` を通す

### dogfood（3入口すべて）

- [ ] `./scripts/reload.sh --tag agent-first-ide --launch`（**素の `xcodebuild` / untagged ビルド禁止**）
- [ ] 入口1: ターミナルの Cmd-click でコード拡張子のファイルが `.text` モードで開く
- [ ] 入口2: File Explorer のダブルクリック / Return でコード拡張子のファイルが `.text` モードで開く
- [ ] 入口3: `CMUX_TAG=agent-first-ide scripts/cmux-debug-cli.sh` 経由の `cmux open <code-file>` で `.text` モードで開く（**`/tmp/cmux-cli` を使わない**。ユーザーの本番アプリのソケットを叩く危険がある）
- [ ] `.dart` / `.php` が3入口すべてで `.quickLook` を経由せず `.text` で開くこと
- [ ] `scripts/test-unit.sh`

## 📦 成果物

- [ ] `textExtensions` に6拡張子追加
- [ ] `FilePreviewKindResolverTests` に `.text` 判定と非テキスト回帰のケース
- [ ] `TerminalLinkOpenCoordinatorTests` にコード拡張子のケース
- [ ] 3入口すべてでの dogfood 結果が PR 説明に記録されている
- [ ] CLI / socket 契約に**差分が無い**こと（NFR-13）

## 📝 備考

- 破壊的変更なし。既存の振り分けロジックを1行も変えない（データ表への追加のみ）
- CLI の**契約**は変わらないが、`cmux open <code-file>` の**見た目**は afide-08 / afide-10 のマージ後に変わる。契約テストが見た目に依存していないことを確認する
- Agent の成果物を自動で開く挙動は追加しない（NFR-13 受け入れ条件3）

## 🔗 関連

- 依存: **afide-02 完了後に着手**（他の feature issue とは独立。並行可）
- 由来: FR-10（拡張子から表示先へのルーティング拡張）、FR-02 受け入れ条件1（13言語）、NFR-13（CLI / socket 契約）、NFR-08
- 設計書: `docs/fork/03_詳細設計.md` §5 D-1 根拠3、§10.1、§14、§16.3、§20.1
- 未確定事項: なし（未確定-01 は詳細設計 D-1 で「Panel 層に足す」に解決済み。この issue はその帰結）
