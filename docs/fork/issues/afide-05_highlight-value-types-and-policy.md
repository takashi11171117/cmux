---
name: Agent-first IDE - ハイライトの値型・言語表・ポリシー・パレット
about: エンジンに依存しない純粋な値型（言語判定 / サイズ閾値 / トークンロール / パレット / seam プロトコル）を先に確定させる
title: '[AFIDE 05] ハイライト基盤の値型と言語判定ポリシー（FR-02 / FR-03 / FR-11 の土台）'
labels: enhancement, agent-first-ide, afide-05, syntax-highlight
assignees: ''
---

## 🎯 目的

シンタックスハイライトの**エンジンに依存しない部分**を先に作り切る。ここが確定すれば、エンジン選定（afide-01）の結論を待たずにコントローラ（afide-07）の実装に進める。

## 📊 背景

詳細設計 P-3 は「ハイライトエンジンを具体ライブラリに直結させず、値型の seam を1枚挟む」を原則にしている。目的は**未確定-02 を実装開始のブロッカーにしない**こと。

seam の要は「エンジンは色を返さない」ことである。エンジンは `NSRange` + 意味論ロール（`FilePreviewHighlightRun`）だけを返し、色は `FilePreviewHighlightPalette` がテーマ（`themeBackgroundColor` / `themeForegroundColor`）から決める。iOS 側がエンジンにテーマ名（`xcode` / `xcode-dark`）を渡している構造とは**意図的に変える**。これで FR-11（テーマ連動）がエンジン非依存になる。

## ✅ タスクリスト

### 新規ファイル（すべて app target `Sources/Panels/`。1ファイル1型・自由関数禁止・DocC）

- [ ] `Sources/Panels/FilePreviewTokenRole.swift` — `enum FilePreviewTokenRole: Sendable { case keyword, string, comment, number, type, attribute, plain }`
- [ ] `Sources/Panels/FilePreviewHighlightRun.swift` — `struct FilePreviewHighlightRun: Sendable, Equatable { let range: NSRange; let role: FilePreviewTokenRole }`（**色を持たない**）
- [ ] `Sources/Panels/FilePreviewSyntaxHighlighting.swift` — `protocol FilePreviewSyntaxHighlighting: Sendable`。`func runs(for text: String, language: String, range: NSRange) async -> [FilePreviewHighlightRun]`
- [ ] 同ファイルに**座標系の契約を DocC コメントで明記する**: `text` は**ドキュメント全文**（スライス禁止）/ `range` は全文の UTF-16 座標 / 戻り値の `range` も全文の UTF-16 座標 / `range` 外を返してもよく呼び出し側がクリップする。**全文を渡す理由（ブロックコメント・複数行文字列の開始が `range` より手前にありうる）も書く**
- [ ] `runs(for:)` は `throws` にしない。エンジンが失敗したら空配列を返し、プレーン表示にフォールバックする
- [ ] `Sources/Panels/FilePreviewSyntaxLanguage.swift` — 拡張子 → 言語 ID の表。`Packages/iOS/CmuxAgentChatUI/.../ChatArtifactSyntaxHighlightPolicy.swift` の対応表を macOS 側へ**複製**する（共有パッケージ化はしない）
- [ ] `Sources/Panels/FilePreviewHighlightDecision.swift` — `enum { case highlight(language: String), skippedForSize, skippedNoLanguage }`
- [ ] `Sources/Panels/FilePreviewHighlightPolicy.swift` — `struct`。`maximumHighlightBytes` と言語表を `init` で受け取り（`UserDefaults` 非依存）、`func decision(path: String, byteCount: Int) -> FilePreviewHighlightDecision`。**namespace-enum にしない**（テストから注入できる形にする）
- [ ] `Sources/Panels/FilePreviewHighlightPalette.swift` — `struct`。`FilePreviewTokenRole` → `NSColor` を light / dark の2枚で持つ。色の出所は afide-01 の決定に従う（`Resources/markdown-viewer/highlight-github.css` / `highlight-github-dark.css` が出所候補）

### 仕様の固定

- [ ] 言語判定は**パス拡張子のみ**。内容スニッフィングを行わない（FR-02 受け入れ条件3）。既存 `FilePreviewKindResolver.sniffLooksLikeText` は「テキストかどうか」の判定であって言語判定ではない — 混同しない
- [ ] 表にない拡張子・拡張子なしは `.skippedNoLanguage` を返す（FR-02 受け入れ条件2）。**iOS 側にある「自動言語検出」フォールバックは採らない**
- [ ] サイズ判定は `textContent` の **UTF-8 バイト長**で行う（ファイルサイズではない）。`FilePreviewPanel` はエンコーディング変換後の `String` しか持たないため
- [ ] `maximumHighlightBytes` は**まず定数**とする（iOS 側の `1_500_000` を初期候補とする）。設定キーにするかは未確定-05
- [ ] `FilePreviewTextLoader.maximumLoadedTextBytes = 16 * 1024 * 1024` と関連するサイズガードは**一切変更しない**（NFR-05 受け入れ条件1）

### テスト

- [ ] `cmuxTests/FilePreviewHighlightPolicyTests.swift`（`import Testing`）: 13言語（Swift / TS / JS / Dart / PHP / Python / JSON / YAML / Markdown / C / C++ / Rust / Go）の代表拡張子が `.highlight(language:)` を返す
- [ ] 同: `.foo` と拡張子なしが `.skippedNoLanguage` を返す
- [ ] 同: 閾値超過が `.skippedForSize` を返す
- [ ] 同: **内容スニッフィングをしていないこと**（同名・内容違いで結果が同じ）
- [ ] `cmuxTests/FilePreviewHighlightPaletteTests.swift`: 明背景・暗背景それぞれで全 `FilePreviewTokenRole` の色が背景とのコントラスト下限を満たす（**数値計算で検証。目視に頼らない**）（FR-11 受け入れ条件1）

### pbxproj 配線（**漏らすとテストは無言でスキップされ CI が緑になる**）

- [ ] 新規 `Sources/Panels/*.swift` 8本に `PBXBuildFile` / `PBXFileReference` / グループ child / `PBXSourcesBuildPhase` の4エントリ（雛形は既存 `Sources/Panels/FilePreviewWordWrapSettings.swift` のエントリ）
- [ ] 新規 `cmuxTests/*.swift` 2本に `PBXFileReference` + `PBXSourcesBuildPhase` の2エントリ
- [ ] `./scripts/lint-pbxproj-test-wiring.sh` を通す
- [ ] `./scripts/check-pbxproj.sh` を通す

### ビルド確認

- [ ] `./scripts/reload.sh --tag agent-first-ide`（**素の `xcodebuild` は使わない**）
- [ ] `scripts/test-unit.sh` で新規テストが**実際に実行されている**（実行件数が増えている）ことを確認

## 📦 成果物

- [ ] `Sources/Panels/` に8本の新規ファイル（トークンロール / ラン / seam プロトコル / 言語表 / 決定 / ポリシー / パレット / 決定用 enum）
- [ ] seam プロトコルに座標契約が DocC で書かれている
- [ ] `FilePreviewHighlightPolicyTests` / `FilePreviewHighlightPaletteTests` が緑で、実行件数が0でない
- [ ] pbxproj に新規ファイル10本ぶんの配線
- [ ] `Sources/Panels/FilePreviewTextEditor.swift` / `FilePreviewPanel.swift` / `MarkdownPanel*.swift` に**差分が無い**こと（この issue は結線しない）

## 📝 備考

- 破壊的変更なし。既存コードを1行も変えない純粋な追加
- 新規パッケージは作らない（詳細設計 §2.2）。app-target の新規ファイルとして追加する
- **エンジンの具体実装はこの issue に含めない**（afide-06）。seam プロトコルの宣言までとする

## 🔗 関連

- 依存: **afide-02 完了後に着手**。afide-01（エンジン選定）は**不要**（seam で切り離してあるため）。ただしパレットの色の出所は afide-01 の決定に合わせるので、afide-01 と並行する場合は色の出所だけ後で調整する
- 由来: FR-02（言語判定とフォールバック）、FR-03（サイズ上限）、FR-11（テーマ連動）、NFR-05（16 MB 上限維持）、NFR-11（seam による決定の遅延）
- 設計書: `docs/fork/03_詳細設計.md` §2.1 P-3、§5 D-2、§5 D-5、§6、§7.2、§7.5、§16.2
- 未確定事項: 未確定-05（閾値を設定キーにするか）は**実装中の判断でよい** — まず定数とし、`init` 注入の形にしておけば後からキーを足せる
