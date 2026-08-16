---
name: Agent-first IDE - ハイライトエンジン実装
about: afide-01 で選定したエンジンを FilePreviewSyntaxHighlighting に適合させ、actor でメインアクター外に閉じる
title: '[AFIDE 06] シンタックスハイライトエンジンの実装（afide-01 の決定を実装する）'
labels: enhancement, agent-first-ide, afide-06, syntax-highlight
assignees: ''
---

## 🎯 目的

afide-01 で選定した1案を、`FilePreviewSyntaxHighlighting`（afide-05 で宣言済み）の具体実装として作る。エンジンは `actor` に閉じてメインアクター外で直列化する。

## 📊 背景

- 選択肢は A. Highlightr（SPM）/ B. 自前スキャナ / C. 同梱済み `Resources/markdown-viewer/highlight.min.js` を JavaScriptCore で直接評価、の3つ（詳細設計 §5 D-2）。**どれを採るかは afide-01 の成果物で決まっている前提**
- iOS 側の `ChatArtifactSyntaxHighlighter` が `actor` + 遅延生成 engine の形で先例になっている。同じ形を採る
- **`Highlightr` 同梱の `CodeAttributedString`（`NSTextStorage` サブクラス）は使わない。** `makeFilePreviewTextView()` は `NSTextStorage()` を明示構築して TextKit 1 スタックを組んでおり、差し替えると NFR-07 の不変条件を検証しているテストの意図が壊れる。加えて `processEditing` に同期ハイライトを載せる形になり NFR-04 受け入れ条件1（メインスレッド同期実行の禁止）に直接違反する

## ✅ タスクリスト

### エンジン本体

- [ ] `FilePreviewSyntaxHighlighting` に準拠する `actor` を `Sources/Panels/` に追加する（1ファイル1型）
- [ ] エンジン実体は**初回 `runs(for:)` まで生成しない**（NFR-03 受け入れ条件1: エディタ未使用時にエンジンが初期化されない）
- [ ] `DispatchQueue` を使わない。`async` / `actor` のみで直列化する（Swift 6 並行性規約）
- [ ] `runs(for:)` は `throws` にしない。エンジンが例外・タイムアウトで結果を返せない場合は**空配列**を返し、プレーン表示へフォールバックする
- [ ] 受け取った `text` は**全文**として扱い、返す `range` は**全文の UTF-16 座標**に統一する（afide-05 の座標契約）。スライスを切って渡し直す実装にしない

### 選定案がエンジン出力を色で返す場合（A / C）のアダプタ

- [ ] `NSAttributedString` の `.foregroundColor` 属性ランを走査し、`FilePreviewTokenRole` へ逆写像するアダプタを1つ書く（**色をそのまま持ち回らない**）
- [ ] 逆写像の対応表（エンジン側クラス名/色 → ロール）をテストで固定する
- [ ] エンジンが `range` を無視して全文を色付けする場合の実測コストを PR 説明に書く（詳細設計 §20.2 の最大リスク。許容できなければ afide-01 の決定に差し戻す）

### A（Highlightr）を採った場合のみ

- [ ] `Highlightr` を `XCRemoteSwiftPackageReference` として `cmux.xcodeproj` に追加する。バージョンは `exact: "2.3.0"`（iOS 側の pin と揃える）
- [ ] product を **`cmux` ターゲットと `cmuxTests` ターゲットの両方**に足す（`cmux-unit` は scheme 名であり、pbxproj 上のテストターゲット名は `cmuxTests`）
- [ ] `cmux.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` の差分を **PR に含める**（gitignore しない）。`python3 scripts/check-package-resolved-policy.py` が gate
- [ ] `Packages/iOS/CmuxAgentChatUI` への依存追加は**行わない**（詳細設計 §5 D-2）

### C（同梱 highlight.js を JSC 評価）を採った場合のみ

- [ ] `Resources/markdown-viewer/highlight.min.js` をバンドルから読み `JavaScriptCore` で評価する薄いラッパを書く
- [ ] SPM 依存を増やさない（`Package.resolved` に差分が出ないこと）
- [ ] 既存の Markdown Viewer 側の利用（WKWebView）に影響しないこと（同一ファイルを読むだけで変更しない）

### テスト

- [ ] エンジン単体テスト（`import Testing`）: 代表言語で `keyword` / `string` / `comment` のランが返ること
- [ ] 同: `range` に交差しないトークンしか無い入力でも**クラッシュせず**空配列相当を返すこと
- [ ] 同: 返る `NSRange` が全文座標であること（オフセットのある `range` を渡しても位置がずれない）
- [ ] 同: ブロックコメント・複数行文字列の開始が `range` より手前にある入力で、`range` 内が正しくコメント/文字列として返ること（**全文を渡す契約の意味そのもの**）
- [ ] 新規テストファイルに **pbxproj の `PBXFileReference` + `PBXSourcesBuildPhase` の2エントリ**を追加し、`./scripts/lint-pbxproj-test-wiring.sh` を通す

### ビルド確認

- [ ] `./scripts/reload.sh --tag agent-first-ide`（**素の `xcodebuild` は使わない**）
- [ ] `scripts/test-unit.sh` で新規テストが**実際に実行されている**ことを確認
- [ ] `./scripts/check-pbxproj.sh`
- [ ] A を採った場合のみ `python3 scripts/check-package-resolved-policy.py`

## 📦 成果物

- [ ] `FilePreviewSyntaxHighlighting` に準拠する `actor` 実装1本
- [ ] （A / C の場合）色 → `FilePreviewTokenRole` の逆写像アダプタと、その対応表テスト
- [ ] エンジン単体テスト（全文座標・境界跨ぎのブロックコメント/複数行文字列を含む）
- [ ] pbxproj 配線（+ A の場合は package 参照と `Package.resolved` 差分）
- [ ] 実測コスト（全文色付けのコスト）が PR 説明に記録されている

## 📝 備考

- **この issue はまだ画面に色を出さない。** コントローラ（afide-07）と結線（afide-08）で初めて見える
- 破壊的変更なし。既存ファイルの変更は pbxproj と（A の場合）package 参照のみ
- NFR-08 の観点では B / C が有利（`Package.resolved` の差分と upstream 依存追加が発生しない）

## 🔗 関連

- 依存: **afide-01 完了後に着手**（エンジンが決まっていないと実装できない）、**afide-05 完了後に着手**（seam プロトコルが必要）
- 由来: FR-01（シンタックスハイライト表示）、NFR-03（未使用時の追加負荷ゼロ）、NFR-04（メインスレッド外）、NFR-07（TextKit 1 維持）、NFR-11（ライブラリ選定基準）
- 設計書: `docs/fork/03_詳細設計.md` §5 D-2、§7.3、§15.2、§20.5、§20.6
- 未確定事項: **未確定-02 は afide-01 で解決済みである前提**。未解決のまま着手しない
