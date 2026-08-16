---
name: Agent-first IDE - 保存衝突 UI（Reload / Keep Mine）
about: 外部変更 × 未保存バッファのときに選択肢を提示する。暗黙 Keep Mine を明示的な選択に変える
title: '[AFIDE 12] 外部変更 × 未保存バッファの選択 UI（FR-07）'
labels: enhancement, agent-first-ide, afide-12, save-conflict, localization
assignees: ''
---

## 🎯 目的

未保存の編集がある状態でファイルが外部から変更されたとき、ユーザーに選択肢を提示する。**現状は何も提示せず暗黙的に Keep Mine になっている**。

## 📊 背景

### 現状の挙動（変更してはいけない部分）

外部変更を検知すると `handleObservedFileChange()` → `reloadFromDisk()` → `loadTextContent(replacingDirtyContent: false)` → `applyTextLoadResult` と流れ、dirty 枝では `originalTextContent`（ディスク側）だけを差し替え、ユーザーの `textContent` を温存して `return` する。**UI 提示は一切ない。**

**この「バッファを温存する」挙動そのものは既存テストが固定している**（`cmuxTests/FilePreviewReloadTests.swift` の `manualRefreshPreservesDirtyText`）。したがって既存の条件・代入・`return` を一切変えず、**dirty 枝に2行だけ足す**。

### `handleObservedFileChange()` に分岐を足す設計を採らない理由（実コードで確認済み・3点）

1. その時点ではまだディスクを読んでおらず、`diskContent` の生成元が無い
2. `isDirty` で `reloadFromDisk()` を止めると、dirty 枝の `originalTextContent = content` / `setTabMetadataDirtyState(...)` / `isFileUnavailable = false` が走らなくなり、タブの dirty 表示がディスク実体とずれ、ファイル消失時のフォールバックも壊れる
3. **`handleObservedFileChange()` は保存失敗経路からも呼ばれる**。ここに衝突分岐を置くと「外部変更が無いのに保存失敗で衝突バナーが出る」経路が生まれる

## ✅ タスクリスト

### 回帰テスト2コミット規約（**この issue は既存挙動を変える唯一の項目**）

- [ ] **コミット1**: 「外部変更 × dirty で選択が提示される」テストファイル **+ その pbxproj 2エントリ（`PBXFileReference` と `PBXSourcesBuildPhase`）** のみ（CI red）
- [ ] **コミット1 に pbxproj 配線を必ず含める。** 配線が無いとテストはビルドに含まれず無言でスキップされ、CI は「Executed 0 tests」で**緑**になる。それでは「CI red を確認してから直す」という規約の目的が果たせない
- [ ] コミット1 の時点で `./scripts/lint-pbxproj-test-wiring.sh` を通し、`scripts/test-unit.sh` が**実際に失敗する**ことを確認する
- [ ] **コミット2**: 実装（CI green）

### 新規型（`Sources/Panels/`、1ファイル1型・DocC）

- [ ] `FilePreviewSaveConflict.swift` — `struct { filePath: String; diskContent: String; detectedAt: Date }`
- [ ] `FilePreviewSaveConflictResolution.swift` — `enum { case reload, compare, keepMine }`
- [ ] `FilePreviewSaveConflictResolving.swift` — `@MainActor protocol: AnyObject { var isDirty: Bool { get }; func reloadDiscardingLocalEdits() }`
- [ ] **既存 `FilePreviewTextEditingPanel` にメソッドを追加しない。** 同プロトコルの要件は `textContent` / `attachTextView` / `retryPendingFocus` / `updateTextContent` / `saveTextContent` の5つで、`isDirty` も `loadTextContent(replacingDirtyContent:)` も含まない。`any FilePreviewTextEditingPanel` からそれらを呼ぶコードは**コンパイルできない**
- [ ] `reloadDiscardingLocalEdits()` という戻り値なしの別名にする理由: `loadTextContent(replacingDirtyContent:)` の戻り値型が2実装で食い違う（`FilePreviewPanel` は `Task<Void, Never>`、`MarkdownPanel` は `Task<Void, Never>?`）
- [ ] `FilePreviewSaveConflictCoordinator.swift` — `@MainActor final class`。`pending: FilePreviewSaveConflict?` を**キューではなく最新1件で上書き**する
- [ ] `FilePreviewSaveConflictBanner.swift` — `struct: View`。3択のバナー（Compare は未実装のまま置く）

### コーディネータのガード（テストで固定する）

- [ ] `noteDiskContentWhileDirty(filePath:diskContent:previousDiskContent:bufferContent:)` を実装する。**呼び出し側（パネル）は条件判定を持たない**
- [ ] `guard diskContent != previousDiskContent else { return }` — ディスクが変わっていないなら通知しない。**これが保存失敗経路の誤検知を止める**
- [ ] `guard bufferContent != diskContent else { return }` — 自分の保存のエコーを潰す。**`isSaving` に依存しない条件にする**（`FilePreviewPanel.handleObservedFileChange()` には `guard !isSaving` があるが `MarkdownPanel` の監視ループには `isClosed` チェックしかない。この非対称は実在する）
- [ ] **`MarkdownPanel` の監視ループに `isSaving` ガードを足さない**（既存挙動の変更を避けるため）

### 既存ファイルへの最小変更

- [ ] `Sources/Panels/FilePreviewPanel.swift` の `applyTextLoadResult` の dirty 枝に**2行**（枝の先頭で `let previousDiskContent = originalTextContent`、`return` の直前でコーディネータへ通知）。**既存の条件・代入・`return` を変えない**
- [ ] `Sources/Panels/MarkdownPanel.swift` の `applyLoadedContent` の dirty 枝に同じ2行
- [ ] 両パネルに `FilePreviewSaveConflictResolving` への準拠を **extension で**足す
- [ ] `Sources/Panels/FilePreviewPanel+Reload.swift` は**変更しない**
- [ ] `reloadFromDisk()` / `loadTextContent(replacingDirtyContent:)` / 監視ループの既存シグネチャと分岐を変えない
- [ ] `FileWatcher` の生成箇所・生成数を変えない（NFR-12）

### バナーの設置

- [ ] `FilePreviewPanelView.body` の `header` + `Divider()` の直後、`MarkdownPanelView.body` の同位置に条件付きで差し込む
- [ ] **表示条件に `!panel.isFileUnavailable` を含める（必須）。** バナーは `content(previewRevision:)` の**兄弟**として `VStack` 直下に置くが、`isFileUnavailable` の分岐は `content` の**内側**にある。条件を書かないと、バナーが出たままファイルが消えたときに「消えたファイルの Reload / Keep Mine」を提示し続ける
- [ ] バナーを `LazyVStack` / `List` / `ForEach` の下に置かない。`body` から呼ばれる関数で state を書かない（SwiftUI リスト境界規約）
- [ ] **Compare ボタンは実装しない**（未確定-03 が決まるまで。afide-13）

### ローカライズ（`String(localized:)` + `Resources/Localizable.xcstrings`、en / ja 必須）

- [ ] `filePreview.saveConflict.title` — `This file changed on disk`
- [ ] `filePreview.saveConflict.message` — `You have unsaved edits. Choose how to continue.`
- [ ] `filePreview.saveConflict.reload` — `Reload`
- [ ] `filePreview.saveConflict.keepMine` — `Keep Mine`
- [ ] `filePreview.saveConflict.compare` — `Compare`（**afide-13 の決定後に使う。キーだけ先に入れるか、afide-13 まで入れないかを PR で明示する**）
- [ ] ローカライズ監査: `rg` でベア英語文字列が残っていないこと、en / ja 両方にキーがあることを確認し、**監査内容をハンドオフに書く**

### テスト（`cmuxTests/FilePreviewSaveConflictCoordinatorTests.swift`）

- [ ] (a) `isDirty == false` の外部変更で pending が立たない（FR-07 受け入れ条件4）
- [ ] (b) `isDirty == true` で立つ（受け入れ条件1）
- [ ] (c) pending 中に再度衝突が起きても `textContent` が変わらない（受け入れ条件5）
- [ ] (d) `.reload` で内容がディスク側になり `isDirty == false`（受け入れ条件2）
- [ ] (e) `.keepMine` で内容も `isDirty` も不変（受け入れ条件3）
- [ ] (f) **ディスク内容が前回と同じなら pending が立たない**（保存失敗経由の誤検知）
- [ ] (g) **バッファとディスクが一致するときは pending が立たない**（自分の保存のエコー）
- [ ] (h) 通知を受けても `isFileUnavailable` / `originalTextContent` 由来の dirty 表示が既存どおり更新される
- [ ] `cmuxTests/FilePreviewReloadTests.swift` の `manualRefreshPreservesDirtyText` を**変更せずに通す**（**これが FR-07 実装の合否判定**）
- [ ] 同ファイルに、衝突コーディネータ経由でも同じ結果になるケースを追加
- [ ] 解決の適用は View 抜きで単体テストできる形にする（`BrowserHTTPBasicAuthPrompt` の注入パターンが先例）

### ビルド確認

- [ ] `./scripts/reload.sh --tag agent-first-ide --launch`（**素の `xcodebuild` / untagged ビルド禁止**）
- [ ] dogfood: 未保存編集中に外部からファイルを書き換えてバナーが出ること、Reload / Keep Mine が受け入れ条件どおりに動くこと、ファイルを消したらバナーが消えること
- [ ] `scripts/test-unit.sh`
- [ ] `./scripts/check-pbxproj.sh`

## 📦 成果物

- [ ] 衝突の値型・解決 enum・新規プロトコル・コーディネータ・バナーの6ファイル
- [ ] `FilePreviewPanel` / `MarkdownPanel` の dirty 枝に2行ずつ + extension 準拠
- [ ] バナーが `!panel.isFileUnavailable` 条件付きで両パネルに出る
- [ ] ローカライズ4〜5キー（en / ja）
- [ ] コーディネータのテスト (a)〜(h)
- [ ] `manualRefreshPreservesDirtyText` が**無改変で**緑
- [ ] コミットが2本（テスト先行 red → 実装 green）に分かれている

## 📝 備考

- **破壊的変更あり（ユーザーから見た挙動の変更）**: これまで無言で Keep Mine されていたケースでバナーが出るようになる
- **モーダルシートにしない。** cmux は複数のエージェントセッションが同時に走る前提のアプリであり、1ファイルの衝突で他ペインの操作を止めるのは思想に反する。また受け入れ条件5（選択中にさらに外部変更が起きてもバッファが失われない）は非モーダルのほうが素直に書ける
- 保存経路（`FilePreviewTextSaver.save`）を変えないため、書き込み権限まわりの挙動は不変
- 解決の適用を `FilePreviewSaveConflictCoordinator.resolve(_:on:)` の1メソッドに閉じることで、将来コマンドパレットや socket から叩く必要が出ても分岐が増えない（Shared behavior policy）

## 🔗 関連

- 依存: **afide-02 完了後に着手**（他の feature issue とは独立。並行可）
- 由来: FR-07（外部変更 × 未保存バッファの選択 UI）、NFR-06（既存編集機能の回帰禁止）、NFR-12（File Watch の粒度）、NFR-14（常時表示 UI を増やさない）
- 設計書: `docs/fork/03_詳細設計.md` §5 D-4、§9.1、§9.2、§9.3、§13、§16.2、§16.3、§16.5、§20.8
- 未確定事項: **未確定-03 に依存する部分がある。** FR-07 受け入れ条件1 は Reload / **Compare** / Keep Mine の**3択**を求めており、本 issue は2択で実装する。**「2択で先行リリースしてよいか」は決まっていない**（未確定-03 に含まれる）。**着手前にこの点の判断が要る** — 「2択で先にマージしてよい」なら本 issue 単独で完了、「3択揃うまで待つ」なら afide-13 → Compare 実装まで本 issue をマージしない
