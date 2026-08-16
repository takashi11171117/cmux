---
name: Agent-first IDE - fileEditor 設定キー2本の追加
about: fileEditor.syntaxHighlight と fileEditor.lineNumbers を13箇所すべてに登録し、ローカライズと web スキーマまで通す
title: '[AFIDE 04] 設定キー fileEditor.syntaxHighlight / fileEditor.lineNumbers の追加'
labels: enhancement, agent-first-ide, afide-04, settings, localization
assignees: ''
---

## 🎯 目的

`fileEditor.syntaxHighlight` と `fileEditor.lineNumbers` の2キーを追加し、**Settings UI / コマンドパレット / `cmux.json` / web ドキュメントのすべてから一貫して切り替えられる**状態にする。ライブ反映（再起動なし）と `UserDefaults` 永続化まで含む。

## 📊 背景

- FR-04 / FR-06 が要求する設定。置き場所は既存の `fileEditor.*` セクションで、`fileEditor.wordWrap` が同じ性質（エディタ表示のトグル・ライブ反映）で実装済み
- 詳細設計 §12.2 は `fileEditor.wordWrap` を端から端まで辿り、**1キーあたりの登録先が13箇所ある**ことを確定させている。**1つでも漏らすと動かないか、既存テストが落ちる**
- FR-04 / FR-06 は「feature flag」ではない。PostHog は使わず、通常の Settings（`DefaultsKey<Bool>`）として実装する
- ライブ反映は `@AppStorage` → `FilePreviewTextEditor` の引数という `fileEditor.wordWrap` と同一経路で満たす。**新しい通知機構を足さない**

## ✅ タスクリスト

### 前提（着手前に確定させる）

- [x] ~~**既定値を確定させる**（未確定-05）~~ → **決定済み（2026-08-17）: 両方 `true`**。根拠は「FR-01 / FR-05 の目的はコードを読みやすくすることであり、既定 `false` では目的を果たさない」。`fileEditor.wordWrap` の既定 `false` は折り返しが好みの分かれる表示変更だからで、`fileEditor.*` を一律 `false` に揃える規則ではない。**FR-04 受け入れ条件3 の実装ブロックは解除された**
- [ ] Settings 行の置き場所を確認する。詳細設計は既存どおり **App セクション**（`AppSection.swift` の Markdown Viewer Font と iMessage Mode の間）へ追加する前提（新規-F）。独立セクションに分けると `CmuxSettingsUI` への差分が増え NFR-08 に不利

### 設定キーの登録（詳細設計 §12.2 の13箇所 × 2キー）

- [ ] 1. `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/FileEditorCatalogSection.swift` に `DefaultsKey<Bool>` を2本追加（`all` は `Mirror` 由来なので追加登録不要）
- [ ] 2. `Sources/Panels/FilePreviewSyntaxHighlightSettings.swift` / `Sources/Panels/FilePreviewLineNumberSettings.swift` を新規追加（`static let key` / `static let defaultEnabled` / `static func isEnabled(defaults:)`。既存 `FilePreviewWordWrapSettings` と同じ形に揃える — D-5）
- [ ] 3. `Sources/CmuxSettingsJSONPathSupport.swift` の `supportedSettingsJSONPaths` に2パス
- [ ] 4. `Sources/KeyboardShortcutSettingsFileStore+SectionParsers.swift` の `fileEditor` セクションパーサに2キー分の `if let value = jsonBool(...)` / `else if section.keys.contains(...)` ブロック（セクション dispatch 自体は既に配線済み）
- [ ] 5. `Sources/KeyboardShortcutSettingsFileStore+Template.swift` の生成テンプレート `"fileEditor"` dict に2エントリ
- [ ] 6. `Sources/SettingsNavigation.swift` の `settingEntries` に2件
- [ ] 7. `Sources/SettingsNavigation.swift` の `settingsPathAnchorIDs` に2件
- [ ] 8. `Sources/SettingsSearchAliases.swift` の `settingAliases` に2件
- [ ] 9. `Sources/CommandPalette/CommandPaletteSettingsToggle.swift` の `descriptors` に2件
- [ ] 10. `Packages/macOS/CmuxSettingsUI/.../Sections/AppSection.swift` の**4箇所ずつ**（`@State` / `init` バインド / `startSettingsObservation([...])` 配列 / `SettingsCardRow`）
- [ ] 11. `Packages/macOS/CmuxSettingsUI/.../Navigation/CuratedSettingEntry+Default.swift` に curated entry 2件
- [ ] 12. `Packages/macOS/CmuxSettingsUI/Tests/.../SettingsRowAnchorResolutionTests.swift` の `rowConfigPaths` に2パス（**手で維持する契約リスト**）
- [ ] 13. web 側（下記の別グループ）

### ローカライズ（`String(localized:)` + `Resources/Localizable.xcstrings`、en / ja 必須）

- [ ] `settings.app.fileEditorSyntaxHighlight` — `Syntax Highlighting`
- [ ] `settings.app.fileEditorSyntaxHighlight.subtitle` — `Color keywords, strings, and comments in the plain-text file editor.`
- [ ] `settings.search.alias.setting.app.file-editor-syntax-highlight` — 検索語列
- [ ] `settings.app.fileEditorLineNumbers` — `Line Numbers`
- [ ] `settings.app.fileEditorLineNumbers.subtitle` — `Show line numbers in the left margin of the plain-text file editor.`
- [ ] `settings.search.alias.setting.app.file-editor-line-numbers` — 検索語列
- [ ] `web/data/cmux.schema.json` の `fileEditor.properties` に `syntaxHighlight` / `lineNumbers`（`type` / `default` / `description` / `descriptionKey`）。**`"additionalProperties": false` なので登録しないと `cmux.json` がスキーマエラーになる**
- [ ] `web/messages/en.json` / `web/messages/ja.json` に `docs.configuration.schemaDescriptions.fileEditor.syntaxHighlight` / `.lineNumbers`
- [ ] `web/messages/en.json` / `web/messages/ja.json` に `exampleFileEditorSyntaxHighlight` / `exampleFileEditorLineNumbers`（docs のコード例用）
- [ ] `web/app/[locale]/(landing)/docs/configuration/page.tsx` のコメント例ブロックに2行
- [ ] ローカライズ監査: 変更した Swift / JSON / TSX に `rg` でベア英語文字列が残っていないこと、en / ja 両方にキーがあることを確認し、**監査内容をハンドオフに書く**

### テスト

- [ ] `cmuxTests/KeyboardShortcutSettingsFileStoreStartupTests.swift` の `testSettingsFileParsesFileEditorWordWrap()` を雛形に、`fileEditor.syntaxHighlight` / `.lineNumbers` の `cmux.json` パーステストを追加
- [ ] 新規テストファイルを足す場合は `import Testing`（`import XCTest` を書かない）+ **pbxproj の `PBXFileReference` と `PBXSourcesBuildPhase` の2エントリ**を追加し、`./scripts/lint-pbxproj-test-wiring.sh` を通す
- [ ] `SettingsRowAnchorResolutionTests` が緑であることを確認する。**`rowConfigPaths` を漏らすと `everyCuratedSettingEntryIsReachable` が落ち、解決できないパスを足すと `everyRowPathResolvesToAnIndexedEntry` が落ちる**
- [ ] Settings を切り替えると `UserDefaults` に永続化され、再起動後も保持されることを dogfood で確認（FR-04 受け入れ条件2 / FR-06 受け入れ条件2）

### ビルド確認

- [ ] `./scripts/reload.sh --tag agent-first-ide`（**素の `xcodebuild` は使わない**）
- [ ] `scripts/test-unit.sh`
- [ ] `./scripts/check-pbxproj.sh`

## 📦 成果物

- [ ] `fileEditor.syntaxHighlight` / `fileEditor.lineNumbers` が13箇所すべてに登録されている
- [ ] Settings UI・コマンドパレット・Settings 検索・`cmux.json` のいずれからも切り替えられる
- [ ] `Resources/Localizable.xcstrings` に6キー（en / ja）
- [ ] `web/data/cmux.schema.json` / `web/messages/{en,ja}.json` / configuration ページに登録済み
- [ ] `cmux.json` パーステストが追加され、既存 `SettingsRowAnchorResolutionTests` が緑
- [ ] 既定値の決定内容が PR 説明に書かれている

## 📝 備考

- **この時点ではキーは「存在するだけ」でよい。** 値を読んで挙動を変えるのは afide-08（ハイライト結線）と afide-10（行番号結線）。ただし `@AppStorage` を `FilePreviewPanelView` / `MarkdownPanelView` に置くところまでは本 issue に含めてよい
- 破壊的変更なし。既存キー（`fileEditor.wordWrap` / `fileExplorerDoubleClickAction` / `app.openMarkdownInCmuxViewer` / `app.openSupportedFilesInCmux`）は変更しない
- NFR-08 のはみ出し: 設定キー1本の登録先が app target 側6ファイルに散っている件は、詳細設計 §18.4 に理由が記録済み（02 NFR-08 受け入れ条件4 はこの記録で充足）
- セッションスナップショットには入れない（NFR-02 受け入れ条件3）

## 🔗 関連

- 依存: **afide-02 完了後に着手**。afide-03 完了後が望ましい（Session Restore の基準線を先に固定するため）
- 由来: FR-04（ハイライトの有効・無効設定）、FR-06（行番号の有効・無効設定）、D-02（設定データ）、NFR-02、NFR-03、NFR-08
- 設計書: `docs/fork/03_詳細設計.md` §5 D-5、§12、§13、§18.4、新規-F
- 未確定事項: **未確定-05（既定値・閾値）は着手前に解決が必要**。FR-04 受け入れ条件3 が「既定値が決まるまで実装しない」と定めているため、未解決のまま着手しない。閾値（`maximumHighlightBytes`）を設定キーにするかも未確定-05 だが、詳細設計 §12.1 は**まず定数**として実装する方針（afide-05 で扱う）
- 未確定事項: 新規-F（Settings 行を独立「File Editor」セクションに分けるか）は実装中に判断してよい。既存どおり App セクションへ追加する前提で書いてある
