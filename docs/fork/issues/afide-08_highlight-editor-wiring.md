---
name: Agent-first IDE - ハイライトのエディタ結線とテーマ連動
about: FilePreviewTextEditor / FilePreviewPanel / MarkdownPanelView にコントローラを結線し、applyTheme の textColor 一括代入と衝突しない形にする
title: '[AFIDE 08] ハイライトのエディタ結線と applyTheme 対処（FR-01 / FR-11）'
labels: enhancement, agent-first-ide, afide-08, syntax-highlight
assignees: ''
---

## 🎯 目的

afide-05〜07 で作った部品を実際のエディタに結線し、**画面に色が出る**状態にする。テーマ切替（明/暗）に再起動なしで追従させる。

## 📊 背景

### 実装上の最大の落とし穴（詳細設計 §7.4）

`FilePreviewTextEditor.applyTheme(to:backgroundColor:foregroundColor:drawsBackground:)` は `textView.textColor = foregroundColor` を実行する。`NSTextView.textColor` の setter は**テキスト全体**に `.foregroundColor` を適用する。そして `applyTheme` は `makeNSView` だけでなく **`updateNSView` の冒頭でも毎回呼ばれる**。何もしなければ、SwiftUI の更新が走るたびにハイライト色が本文色で塗り潰される。

### 再適用トリガ

`textView.string` への代入は `NSTextStorage` の属性を**全消去する**。したがって再適用のトリガは (1) `makeNSView` (2) `updateNSView` の本文差し替え (3) `textDidChange` (4) テーマ変更 (5) フォント変更 の5点。

### `makeNSView` の時点では本文がまだ無い

`FilePreviewPanel.textContent` の初期値は空文字で、本文は非同期の読み込み完了後に `updateNSView` で入る。**本文サイズに依存する判定を `attach` に置いてはならない**。

## ✅ タスクリスト

### `Sources/Panels/FilePreviewTextEditor.swift`

- [ ] `FilePreviewTextEditor` に `syntaxHighlight: Bool` プロパティを追加する
- [ ] `makeNSView`: `syntaxHighlight == true` のときだけ `coordinator.highlightController` を生成し `attach(textView:scrollView:)` する（NFR-03）。**この時点でサイズ判定をしない**
- [ ] `updateNSView`: `setEnabled(syntaxHighlight)`（FR-04 受け入れ条件1 のライブ反映）と `setPalette(FilePreviewHighlightPalette(background:foreground:))` を呼ぶ
- [ ] `updateNSView`: `textView.string` 差し替えの**直後**に `noteDocumentReplaced(text:)` を呼ぶ（ここでサイズ・言語を判定 → `invalidateAll()`）
- [ ] `Coordinator.textDidChange`: `noteTextDidChange()` を呼ぶ（デバウンス開始）
- [ ] `dismantleNSView`: `detach()` を呼ぶ（購読 Task とデバウンス Task の cancel）
- [ ] `applyTheme` に `preservesTextColor: Bool` を足し、**ハイライト有効時は `textView.textColor` の一括代入を行わない**。代わりに `textView.typingAttributes[.foregroundColor] = foregroundColor` を設定する。`insertionPointColor` は従来どおり設定する
- [ ] ハイライトが適用されない状態（FR-02 フォールバック / FR-03 閾値超過 / 設定オフ）では `preservesTextColor = false` に戻し、`applyTheme` の従来経路で `themeForegroundColor` が全体に効くようにする（FR-11 受け入れ条件3）
- [ ] `themeBackgroundColor` / `themeForegroundColor` が変わったときは `setPalette(_:)` → `invalidateAll()`（FR-11 受け入れ条件2）
- [ ] **`SavingTextView` にフィールドを追加しない。** `makeFilePreviewTextView()` の TextKit 1 構築を1行も変えない（NFR-07 / P-2）

### `Sources/Panels/FilePreviewPanel.swift` / `Sources/Panels/MarkdownPanelView.swift`

- [ ] `FilePreviewPanelView` に `@AppStorage(FilePreviewSyntaxHighlightSettings.key)` を追加し、`FilePreviewTextEditor(...)` 呼び出しに引数を渡す（`fileEditor.wordWrap` と同一経路。**新しい通知機構を足さない**）
- [ ] `MarkdownPanelView` にも同じ2箇所（`@AppStorage` と呼び出し引数）。`MarkdownPanel` の TextEdit モードでもハイライトを効かせる
- [ ] 上記以外の既存ロジック（保存・再読込・ワードラップ・ズーム）に手を入れない

### テスト

- [ ] `cmuxTests/FilePreviewTextEditorTextKitTests.swift`: 既存の `#expect(textView.textLayoutManager == nil)` を**維持したまま**、ハイライト有効時にも同じ不変条件が成り立つケースを追加（NFR-07 受け入れ条件2）
- [ ] 同ファイル: **「ハイライト適用後に Undo が編集操作1回ぶん戻る」テストを追加する**（FR-01 受け入れ条件2）。これは新規-B の検証であり、**設計の前提「属性のみの変更は Undo スタックに乗らない」が成り立たなければ設計を見直す**（`shouldChangeText` を通さない別経路、または `undoManager.disableUndoRegistration()` で囲う）
- [ ] テーマ切替でパレットが差し替わり再適用されることのテスト（可能なら単体、無理なら dogfood 手順を PR 説明に書く）
- [ ] 既存テスト `FilePreviewReloadTests` / `FilePreviewReloadCompletionTests` / `MarkdownPanelTests` を**無改変で**通す（NFR-06）
- [ ] 新規テストファイルを足す場合は **pbxproj の2エントリ**（`PBXFileReference` / `PBXSourcesBuildPhase`）を追加し `./scripts/lint-pbxproj-test-wiring.sh` を通す

### dogfood（FR-01 の受け入れ条件は実機でしか確認できない）

- [ ] `./scripts/reload.sh --tag agent-first-ide --launch`（**素の `xcodebuild` / untagged ビルド禁止**）
- [ ] `.swift` を File Preview で開き、キーワード・文字列・コメントが本文色と異なる色で描画される（FR-01 受け入れ条件1）
- [ ] 編集・Undo・Redo・保存が従来と同じ結果になる（FR-01 受け入れ条件2）
- [ ] ライトテーマ / ダークテーマの両方で判読できる（FR-01 受け入れ条件4 / FR-11 受け入れ条件1）
- [ ] テーマを切り替えると再起動なしで配色が変わる（FR-11 受け入れ条件2）
- [ ] 閾値超過ファイル・非対応拡張子でプレーン表示になり、本文色が正しい（FR-02 / FR-03 / FR-11 受け入れ条件3）
- [ ] 数十万行規模のファイルを開いて、初回描画が体感で悪化しないこと（NFR-04 受け入れ条件2）
- [ ] 文字入力中に入力の取りこぼしが無いこと（NFR-04 受け入れ条件3）
- [ ] `scripts/test-unit.sh`

## 📦 成果物

- [ ] `FilePreviewTextEditor` にハイライトが結線され、`applyTheme` の一括代入と衝突しない
- [ ] `FilePreviewPanelView` / `MarkdownPanelView` から設定がライブ反映される
- [ ] TextKit 1 の不変条件テストがハイライト有効時にも通る
- [ ] Undo 挙動のテスト（新規-B の検証）
- [ ] 既存テスト群が無改変で緑
- [ ] dogfood 結果（テーマ両方・閾値超過・大容量ファイル）が PR 説明に記録されている

## 📝 備考

- **破壊的変更あり**: `applyTheme` は既存 static メソッドで、`preservesTextColor` を足すのは**本設計で唯一の既存 API シグネチャ変更**（新規-A）。呼び出しは同ファイル内2箇所だけなので影響は閉じるが、upstream が同メソッドを触っていた場合コンフリクトする
- 新規-A の代替案は (b) ハイライト適用後に毎回 `applyTheme` の副作用を打ち消す（無駄な再描画）、(c) `applyTheme` を呼ぶ前にハイライト有効かを判定して呼び分ける。**(a) 引数追加を仮採用しているが、実装中に (c) の方が差分が小さいと分かれば切り替えてよい**
- `Sources/Workspace.swift` / `Sources/TerminalPanel*.swift` / `Sources/ContentView.swift` / `Sources/GhosttyTerminalView.swift` / `Sources/TerminalWindowPortal.swift` は**触らない**（NFR-08 受け入れ条件3 / タイピング遅延に敏感な経路）

## 🔗 関連

- 依存: **afide-04 完了後に着手**（`@AppStorage` するキーが必要）、**afide-06 完了後に着手**（実際に色を出すためにエンジンが必要）、**afide-07 完了後に着手**（コントローラが必要）
- 由来: FR-01（ハイライト表示）、FR-02（フォールバック）、FR-03（閾値）、FR-04（ライブ反映）、FR-11（テーマ連動）、NFR-03、NFR-04、NFR-06、NFR-07、NFR-14
- 設計書: `docs/fork/03_詳細設計.md` §7.1、§7.4、§7.5、§16.3、新規-A、新規-B
- 未確定事項: **新規-A（`applyTheme` のシグネチャ変更をどう扱うか）は実装中に判断してよい**。3案のどれを採ったかを PR 説明に書く。**新規-B（属性変更が Undo に乗らないか）は実装の最初のステップで検証する** — 成り立たなければ設計を見直し、その旨を報告する
