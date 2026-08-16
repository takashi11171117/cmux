---
name: Agent-first IDE - 行番号ルーラの実装と結線
about: NSRulerView サブクラスで行番号を描き、ワードラップ・フォントズーム・桁数変化に追従させる
title: '[AFIDE 10] 行番号表示（FR-05 / FR-06）'
labels: enhancement, agent-first-ide, afide-10, line-numbers
assignees: ''
---

## 🎯 目的

エディタの左端に論理行の行番号を表示する。折り返し・フォントズーム・スクロール・桁数増加のすべてに追従させ、設定でオフにできるようにする。

## 📊 背景

- `NSRulerView` サブクラスを `NSScrollView.verticalRulerView` に設置する方式を採る。スクロール同期・座標変換・`clientView` 追従を AppKit が持つため
- 不採用の代替案とその理由（詳細設計 §5 D-3）:
  - テキストビュー左に兄弟 `NSView` を置いて手動同期 → 慣性スクロール・ラバーバンド時にズレる
  - `textContainer` に左インセットを取り `drawBackground(in:)` で描く → 番号領域が横スクロールと一緒に流れ、FR-05 受け入れ条件5 を満たさない
  - `headIndent` + 行頭に番号文字を実挿入 → **テキスト内容を改変するため保存内容が壊れる**（NFR-06 違反）
  - `NSLayoutManager` の `temporaryAttributes` → 文字への装飾であり余白への描画には使えない
- `NSRulerView` はこのリポジトリに先例がない（`NSRulerView` / `lineNumberView` の grep が0件）。**AppKit 標準機能なので、失敗しても上記2番目の案に退避できる**

## ✅ タスクリスト

### ルーラ本体（`Sources/Panels/FilePreviewLineNumberRulerView.swift`）

- [ ] `final class FilePreviewLineNumberRulerView: NSRulerView` を追加する（1ファイル1型・DocC）
- [ ] `drawHashMarksAndLabels(in:)` で次の順に処理する: `layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)` → `characterRange(forGlyphRange:actualGlyphRange:)` → `enumerateLineFragments(forGlyphRange:)` で**表示行**を走査 → 各 fragment の先頭文字オフセットが `FilePreviewLineIndex.isLineStart(utf16Offset:)` を満たすときだけ番号を描く
- [ ] これにより `fileEditor.wordWrap == true` で折り返された2行目以降には番号が出ない（FR-05 受け入れ条件2）
- [ ] `ruleThickness = ceil(数字1文字幅 × max(3, 桁数(lineCount))) + 左右パディング`。`lineCount` が変わったときだけ再計算する（FR-05 受け入れ条件5）
- [ ] `FilePreviewTextEditorLayout.textContainerInset.width = 12` は**変更しない**（ルーラは `textContainerInset` の外側なので干渉しない）

### 設置と結線（`Sources/Panels/FilePreviewTextEditor.swift`）

- [ ] `FilePreviewTextEditor` に `lineNumbers: Bool` プロパティを追加する
- [ ] `makeNSView` の `scrollView.documentView = textView` の直後に `hasVerticalRuler = true` / `rulersVisible = lineNumbers` / ルーラ生成 / `ruler.clientView = textView` / `scrollView.verticalRulerView = ruler`
- [ ] `updateNSView` で `scrollView.rulersVisible = lineNumbers` を都度代入する（FR-06 受け入れ条件1 のライブ反映）。**設定オフのときルーラを描画しない**（NFR-14 受け入れ条件2 / NFR-03 受け入れ条件2）
- [ ] ワードラップ切替（`applyFilePreviewWordWrap(_:scrollView:)`）の後に `ruler.needsDisplay = true` を打つ。**既存関数の冪等性を壊さない**（`updateNSView` から毎回呼ばれてよい形にする）
- [ ] フォント変更の同期点を `applyCurrentPreviewFont()` **1箇所に集約する**（ピンチ / 修飾キー+スクロール / スマートズーム / ショートカット / アプリ全体の拡大率変更の5経路がここに集まる）。ルーラのフォント更新・`ruleThickness` 再計算・再描画をこの1箇所から行う（Shared behavior policy の適用）
- [ ] ルーラのフォントは本文と同じ `GlobalFontMagnification.monospacedSystemFont(ofSize:weight:)` を使う。番号の縦位置は line fragment の `rect` を `NSRulerView` の座標へ変換して合わせる
- [ ] `FilePreviewLineIndex` の構築はメインアクター外の `Task` で行い、`@MainActor` へ戻して差し替える瞬間に**世代を検査する**（不一致なら捨てて組み直す）
- [ ] **`SavingTextView` にフィールドを追加しない。** TextKit 1 構築を1行も変えない（NFR-07 / P-2）

### 増分更新の受け口（新規-C の判断）

- [ ] `FilePreviewLineIndex.patched(...)` を呼ぶ位置を決める: (i) `NSTextStorage` の編集通知（`didProcessEditing` / `NSTextStorageDelegate`）— `editedRange` / `changeInLength` が取れて効率がよいが `SavingTextView` に delegate を1つ足すことになる / (ii) `Coordinator.textDidChange` で全再構築 — 大きなファイルで毎キーストローク O(N)
- [ ] **(ii) に倒れる場合、afide-09 の保留シフト方式は成立しない。** その場合は全再構築 + デバウンスへ切り替え、afide-09 の成果物の扱いを PR 説明に書く
- [ ] 決めた根拠を PR 説明に書く

### `Sources/Panels/FilePreviewPanel.swift` / `Sources/Panels/MarkdownPanelView.swift`

- [ ] `@AppStorage(FilePreviewLineNumberSettings.key)` を追加し、`FilePreviewTextEditor(...)` 呼び出しに引数を渡す

### テスト

- [ ] ルーラの `ruleThickness` が桁数に応じて変わることのテスト（可能なら単体）
- [ ] 折り返し時に論理行1つにつき番号1つであることを、`FilePreviewLineIndex.isLineStart` の呼び出し結果として検証できる形にする
- [ ] 既存 `FilePreviewTextEditorTextKitTests` の `textLayoutManager == nil` が維持されること（NFR-07）
- [ ] 新規テストファイルには **pbxproj の2エントリ**（`PBXFileReference` / `PBXSourcesBuildPhase`）を追加し `./scripts/lint-pbxproj-test-wiring.sh` を通す
- [ ] `Sources/Panels/FilePreviewLineNumberRulerView.swift` に pbxproj 4エントリ

### dogfood（FR-05 の受け入れ条件は実機でしか確認できない）

- [ ] `./scripts/reload.sh --tag agent-first-ide --launch`（**素の `xcodebuild` / untagged ビルド禁止**）
- [ ] 左端に 1 始まりの行番号が出て、本文の各行と縦位置が一致する（受け入れ条件1）
- [ ] `fileEditor.wordWrap = true` で折り返しても論理行に対して番号1つ（受け入れ条件2）
- [ ] ピンチ / ⌘+ / ⌘- でフォントサイズを変えても縦位置が一致し続ける（受け入れ条件3）
- [ ] スクロールしても行番号が本文に追従する（受け入れ条件4）
- [ ] 1 → 10000 と桁が増えても本文が水平に切れない（受け入れ条件5）
- [ ] 設定オフでルーラが消え、再起動なしで切り替わる（FR-06 受け入れ条件1）
- [ ] `scripts/test-unit.sh`

## 📦 成果物

- [ ] `FilePreviewLineNumberRulerView` と `FilePreviewTextEditor` への結線
- [ ] フォント同期点が `applyCurrentPreviewFont()` の1箇所に集約されている
- [ ] 増分更新の受け口（新規-C）の決定と、その根拠の記録
- [ ] pbxproj 配線
- [ ] dogfood 結果（FR-05 受け入れ条件1〜5 / FR-06 受け入れ条件1）が PR 説明に記録されている

## 📝 備考

- 破壊的変更なし（`applyTheme` のような既存シグネチャ変更は伴わない）
- `NSRulerView` は本リポジトリに先例がなく設計判断の比重が高い。**うまくいかない場合は §5 D-3 の2番目の案（兄弟 `NSView` + `NSClipView` の bounds 購読）に退避してよい**。退避した場合は理由を PR 説明に書く
- 常時表示 UI を増やさない（NFR-14）。行番号はエディタを開いている間かつ設定オンのときだけ描画する

## 🔗 関連

- 依存: **afide-04 完了後に着手**（`@AppStorage` するキーが必要）、**afide-09 完了後に着手**（`FilePreviewLineIndex` が必要）
- 由来: FR-05（行番号表示）、FR-06（行番号の有効・無効設定）、NFR-03、NFR-06、NFR-07、NFR-14
- 設計書: `docs/fork/03_詳細設計.md` §5 D-3、§8、§16.2、新規-C
- 未確定事項: **新規-C（増分更新の受け口）は本 issue で判断する**（実装中の判断でよい）。判断が (ii) に倒れた場合は afide-09 の成果物に手戻りが出るため、その旨を報告する
