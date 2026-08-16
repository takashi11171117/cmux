---
name: Agent-first IDE - FilePreviewLineIndex
about: 論理行の開始オフセット配列と保留シフト方式の増分更新を持つ純 Foundation の値型を作る
title: '[AFIDE 09] FilePreviewLineIndex の実装（FR-05 の土台）'
labels: enhancement, agent-first-ide, afide-09, line-numbers
assignees: ''
---

## 🎯 目的

「文字オフセット → 論理行番号」を O(log N) で引ける値型 `FilePreviewLineIndex` を作る。編集時の更新が**1打鍵ごとに O(N) の書き込みにならない**形にする。

AppKit に依存しない純 Foundation の値型なので、この issue は**単体テストで完結する**。

## 📊 背景

- 「文字オフセット → 論理行番号」を毎回テキスト先頭から数えると、16 MB / 数十万行のファイルで描画1回ごとに O(N) になる。`allowsNonContiguousLayout = true` で遅延レイアウトを成立させている既存設計の意図を打ち消す
- 素朴な増分更新（編集位置より後ろを `changeInLength` だけシフトした新しい配列を作る）は、シフト対象が末尾までである以上 **1打鍵ごとに O(N) の書き込み**になる（50万行なら約 4 MB の `[Int]` を毎回生成し、値型なので COW も効かない）
- したがって `(shiftBoundary, pendingShift)` の組を1つだけ持ち、二分探索時に「添字が `shiftBoundary` 以上なら `pendingShift` を足す」形でシフトを**遅延**させる

## ✅ タスクリスト

### 実装（`Sources/Panels/FilePreviewLineIndex.swift`）

- [ ] `struct FilePreviewLineIndex: Sendable, Equatable` を作る。保持するのは `lineStarts: [Int]`（保留シフト適用前）/ `shiftBoundary: Int` / `pendingShift: Int` / `generation: Int`
- [ ] `init(text: NSString, generation: Int)`
- [ ] `var lineCount: Int`
- [ ] `func lineNumber(atUTF16Offset offset: Int) -> Int`（**1 始まり**）。二分探索 + 保留シフトの加算
- [ ] `func isLineStart(utf16Offset: Int) -> Bool`
- [ ] `func patched(editedRange: NSRange, changeInLength: Int, text: NSString) -> FilePreviewLineIndex` — 編集範囲より前は不変、後ろは `pendingShift` に加算するだけ（**配列を再構築しない**）。編集範囲内の行頭のみ再スキャンして差し替える
- [ ] 連続編集で新しい境界が前回より後ろにあるときは、**その2点の間の要素だけ**を実値へ畳み込む（O(k)）。境界が前へ戻ったときだけ全体を畳み込む（O(N)、稀）
- [ ] `generation` を持たせる。**構築を非同期にする以上、ハイライトと同じ世代番号で「構築中に編集が入った古いインデックス」を弾く必要がある**。世代不一致なら捨てて組み直す
- [ ] 1ファイル1型・自由関数禁止・DocC を守る

### テスト（`cmuxTests/FilePreviewLineIndexTests.swift`、`import Testing`）

- [ ] `lineNumber(atUTF16Offset:)` の境界: 空文字列 / 末尾改行あり / 末尾改行なし / CRLF / 絵文字などサロゲートペア
- [ ] `patched(...)` の結果が**全再構築と一致する**こと（ランダム編集列で property test 風に）
- [ ] **保留シフトを畳み込む前後で同じ結果になる**こと
- [ ] 境界が前へ戻る編集（全体畳み込みが走るケース）でも一致すること
- [ ] **構築中に編集が入ったとき、世代不一致の古いインデックスが採用されない**こと。**ずれた行番号は見た目が正しそうに見えるため気づきにくく、テストで止めるしかない**
- [ ] `lineCount` が 0 行 / 1 行 / 末尾改行ありで期待どおりになること

### pbxproj 配線（**漏らすとテストは無言でスキップされ CI が緑になる**）

- [ ] `Sources/Panels/FilePreviewLineIndex.swift` に4エントリ（`PBXBuildFile` / `PBXFileReference` / グループ child / `PBXSourcesBuildPhase`）
- [ ] `cmuxTests/FilePreviewLineIndexTests.swift` に2エントリ（`PBXFileReference` / `PBXSourcesBuildPhase`）
- [ ] `./scripts/lint-pbxproj-test-wiring.sh` / `./scripts/check-pbxproj.sh` を通す

### ビルド確認

- [ ] `./scripts/reload.sh --tag agent-first-ide`（**素の `xcodebuild` は使わない**）
- [ ] `scripts/test-unit.sh` で新規テストが**実際に実行されている**ことを確認

## 📦 成果物

- [ ] `FilePreviewLineIndex`（二分探索 + 保留シフト方式の増分更新 + 世代）
- [ ] 全再構築との一致を保証するテスト（ランダム編集列 / 保留シフトの畳み込み前後 / 世代不一致の排除）
- [ ] 境界テスト（空 / 末尾改行 / CRLF / サロゲートペア）
- [ ] pbxproj 配線
- [ ] `FilePreviewTextEditor.swift` / `FilePreviewPanel.swift` に差分が**無い**こと（結線は afide-10）

## 📝 備考

- 破壊的変更なし（新規ファイルのみ）
- メモリ: 50万行で `[Int]` 約 4 MB。`FilePreviewTextLoader` の 16 MB 上限の内側なので許容と判断済み
- **FR-09（外部エディタへの行番号）はこのインデックスに依存させない**（行番号設定オフのときインデックスを構築しないため）。afide-14 側の設計制約

## 🔗 関連

- 依存: **afide-02 完了後に着手**（他の feature issue とは独立。並行可）
- 由来: FR-05（行番号表示）、NFR-04（メインスレッド外での構築）
- 設計書: `docs/fork/03_詳細設計.md` §6、§8.3、§16.2、§20.8、新規-C
- 未確定事項: **新規-C（増分更新をどこで受けるか: `NSTextStorage` の `didProcessEditing` か `Coordinator.textDidChange` か）は afide-10 で判断する**。本 issue の `patched(editedRange:changeInLength:text:)` は前者（`editedRange` / `changeInLength` が取れる）を前提にしている。**後者に倒れた場合、保留シフト方式そのものが成立せず全再構築の debounce に切り替える必要がある**ため、afide-10 で判断が覆ったらこの issue の成果物を見直す
