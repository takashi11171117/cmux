---
name: Agent-first IDE - ハイライトコントローラ
about: 可視範囲算出・デバウンス・世代管理・NSTextStorage への属性適用・購読ライフサイクルを持つコントローラを作る
title: '[AFIDE 07] FilePreviewSyntaxHighlightController の実装（NFR-03 / NFR-04）'
labels: enhancement, agent-first-ide, afide-07, syntax-highlight
assignees: ''
---

## 🎯 目的

`@MainActor final class FilePreviewSyntaxHighlightController` を作る。可視範囲の算出・デバウンス・世代管理・`NSTextStorage` への属性適用・テーマ変更時の再適用・購読 Task の後始末を1箇所に閉じる。

**View 側への結線はこの issue に含めない**（afide-08）。偽エンジン（記録用スタブ）を注入して単体テストで完結させる。

## 📊 背景

- NFR-04 は「ハイライト処理がメインスレッドで同期実行されない」「入力を取りこぼさない」を要求する。既存エディタは `allowsNonContiguousLayout = true` で巨大ファイルの遅延レイアウトを成立させており、全文一括同期処理はその意図を打ち消す
- NFR-03 は「エディタ未使用時にエンジンが初期化されない」「設定オフのとき処理が実行されない」を要求する
- 詳細設計 §7.3 / §7.5 は、この issue で**踏んではいけない地雷**を4つ挙げている。いずれもテストで固定する

## ✅ タスクリスト

### コントローラ本体（`Sources/Panels/FilePreviewSyntaxHighlightController.swift`）

- [ ] `attach(textView:scrollView:)` / `detach()` / `setEnabled(_:)` / `setPalette(_:)` / `noteDocumentReplaced(text:)` / `noteTextDidChange()` / `invalidateAll()` の公開契約を作る
- [ ] 可視範囲の算出: `layoutManager.glyphRange(forBoundingRect: clipView.documentVisibleRect, in: textContainer)` → `characterRange(forGlyphRange:actualGlyphRange:)` → 前後にオーバースキャン行を足した `NSRange`
- [ ] エンジンには**全文の `String` と全文座標の `NSRange`** を渡す（**スライスを渡さない**。`String` は COW なのでコピーは発生しない）
- [ ] デバウンス: `Task` + `Clock.sleep` で再計算を1回にまとめる。**`DispatchQueue.asyncAfter` は使わない**。前の `Task` は `cancel()` する
- [ ] スクロール追従: `NotificationCenter.default.notifications(named: NSView.boundsDidChangeNotification, object: clipView)` を購読する（`clipView.postsBoundsChangedNotifications = true`）。**`object:` に自分の `NSClipView` を必ず渡す** — 省くとアプリ内の全 `NSView`（ターミナルを含む）の bounds 変更で発火する
- [ ] 購読 Task のライフサイクル: `attach` で作った Task を保持し、`detach()` で必ず `cancel()`。ループ内は `[weak self]` で受け nil なら `break`（既存 `FilePreviewPanel+Reload.swift` の監視 Task と同じ形）。**怠ると `NSTextView` / `NSScrollView` ごとリークする**
- [ ] 属性適用: `beginEditing()` → `removeAttribute(.foregroundColor, range:)` → ラン単位 `addAttribute(.foregroundColor, value:range:)` → `endEditing()`
- [ ] **適用直前に `NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))` でクランプする。** クリップ先は「計算時点の可視範囲」ではなく「**適用時点の `textStorage.length`**」。世代チェックが漏れる経路が1つでもあると `NSRangeException` でクラッシュするため、世代管理とは独立の防御として置く
- [ ] 世代管理: `highlightGeneration` を持ち、戻ってきた結果の世代が現行と違えば破棄する。**`invalidateAll()` / `noteDocumentReplaced(text:)` / `noteTextDidChange()` は必ず世代を加算する。世代を加算しない無効化経路を作らない**
- [ ] 全文への既定色: `invalidateAll()` の直後に、文書全体へパレットの `.plain` 色を **1回だけ** `addAttribute(.foregroundColor:range: 全文)` する。その上に可視範囲のハイライトを重ねる。**この手順を省くと、スクロールして初めて可視になった領域が `NSTextView` 既定色（黒）で描画され、暗背景テーマで読めなくなる**（FR-11 受け入れ条件3）
- [ ] サイズ・言語の判定は **`noteDocumentReplaced(text:)` で行う**（`attach` で行わない）。`attach` 時点の `panel.textContent` は初期値の空文字でありうるため、**attach で判定すると常に「閾値以下」と判定されて FR-03 が実機で効かない**
- [ ] `decision` が `.skippedForSize` / `.skippedNoLanguage` を返したら、**エンジンを一度も呼ばずに**コントローラを破棄できる形にする（呼び出し側が `nil` を代入できる）
- [ ] 状態（可視範囲・世代・パレット）は**すべて AppKit 側に置く**。SwiftUI の `@State` / `@Published` に持たない（SwiftUI リスト境界規約）
- [ ] 新しいアプリ全体向け通知・グローバルタイマー・ディスプレイリンクを追加しない

### テスト（`cmuxTests/FilePreviewSyntaxHighlightControllerTests.swift`）

- [ ] 記録用スタブ（`FilePreviewSyntaxHighlighting` 準拠、呼び出しを記録する）を用意する
- [ ] (a) **本文を `noteDocumentReplaced(text:)` で投入したうえで**、閾値超過なら `runs(for:)` が**一度も呼ばれない**（FR-03 受け入れ条件2）。**「スタブに本文を先に持たせてコントローラが nil であること」という形にしない** — attach 時点で判定している不具合を検出できないため
- [ ] (b) 設定オフで `runs(for:)` が呼ばれない（NFR-03 受け入れ条件2）
- [ ] (c) エンジンには**全文**が渡り、`range` だけが可視範囲に絞られている（座標契約）
- [ ] (d) 世代が古い結果が破棄される
- [ ] (e) **可視範囲外の文字にも `.foregroundColor`（`.plain` 色）が付いている**（FR-11 受け入れ条件3）
- [ ] (f) `detach()` 後に購読 Task が終了し、コントローラが解放される
- [ ] 追加: `textStorage.length` より長い `range` を返すスタブでも `NSRangeException` にならない（クランプの検証）

### pbxproj 配線（**漏らすとテストは無言でスキップされ CI が緑になる**）

- [ ] 新規 `Sources/Panels/FilePreviewSyntaxHighlightController.swift` に4エントリ（`PBXBuildFile` / `PBXFileReference` / グループ child / `PBXSourcesBuildPhase`）
- [ ] 新規 `cmuxTests/FilePreviewSyntaxHighlightControllerTests.swift` に2エントリ（`PBXFileReference` / `PBXSourcesBuildPhase`）
- [ ] `./scripts/lint-pbxproj-test-wiring.sh` / `./scripts/check-pbxproj.sh` を通す

### ビルド確認

- [ ] `./scripts/reload.sh --tag agent-first-ide`（**素の `xcodebuild` は使わない**）
- [ ] `scripts/test-unit.sh` で新規テストが**実際に実行されている**ことを確認

## 📦 成果物

- [ ] `FilePreviewSyntaxHighlightController`（可視範囲算出 / デバウンス / 世代管理 / クランプ / 全文既定色 / 購読ライフサイクル）
- [ ] スタブエンジンによる単体テスト (a)〜(f) + クランプ検証
- [ ] pbxproj 配線
- [ ] `FilePreviewTextEditor.swift` / `FilePreviewPanel.swift` / `MarkdownPanel*.swift` に差分が**無い**こと（結線は afide-08）

## 📝 備考

- 破壊的変更なし（新規ファイルのみ）
- デバウンス幅とオーバースキャン行数の**具体値**は未確定-08。実装は定数として持ち、値は暫定でよい。暫定値と選んだ理由を PR 説明に書く
- `CodeAttributedString` を使わない（NFR-07）。`NSTextStorage` サブクラスを差し替えない

## 🔗 関連

- 依存: **afide-05 完了後に着手**（seam プロトコル・ポリシー・パレットが必要）。afide-06（エンジン実装）は**不要** — スタブでテストが完結する
- 由来: FR-01、FR-03、FR-11、NFR-03、NFR-04、NFR-07
- 設計書: `docs/fork/03_詳細設計.md` §7.1、§7.3、§7.5、§7.6、§7.7、§16.2、§20.8
- 未確定事項: 未確定-08（性能の数値目標・デバウンス幅・オーバースキャン行数）は**実装中の判断でよい**。定数として実装し、数値目標が決まったら調整する
