# Agent-first IDE（AFIDE）Issue 一覧

`fork/agent-first-ide` ブランチで実装する issue の一覧。prefix は `afide`。

## 概要

- 由来: [`../02_要件定義.md`](../02_要件定義.md)（FR-01〜11 / NFR-01〜15）と [`../03_詳細設計.md`](../03_詳細設計.md)
- 粒度: **1 issue = 1 ドラフト PR = 一度にレビューできる量**
- 全 issue 共通の完了条件: `./scripts/reload.sh --tag agent-first-ide` が通る / `scripts/test-unit.sh` が通る（**素の `xcodebuild` は禁止**）/ テストを足したら pbxproj の `PBXFileReference` + `PBXSourcesBuildPhase` を配線して `./scripts/lint-pbxproj-test-wiring.sh` を通す

> **出力先について**: `.github/ISSUE_TEMPLATE/` は upstream (`manaflow-ai/cmux`) のディレクトリなので使わない。fork 独自ファイルは `docs/fork/issues/` に置く（NFR-08: upstream への差分を局所化する）。

## Issue 一覧

| # | Issue | 種別 | 依存 | 由来 FR / NFR |
|---|-------|------|------|---------------|
| AFIDE-01 | [シンタックスハイライトエンジン選定（未確定-02 の解決）](./afide-01_syntax-highlight-engine-selection.md)（**調査完了** → [結果](./afide-01_調査結果.md)） | 調査 | なし | NFR-11, FR-01/02/03/11 |
| AFIDE-02 | [upstream 追従とビルド・テスト基準線の確立](./afide-02_upstream-sync-baseline.md)（**基準線は完了 / 追従は保留** → [記録](./afide-02_基準線記録.md)） | 準備 | なし | NFR-10, NFR-08, NFR-09 |
| AFIDE-03 | [Session Restore 回帰フィクスチャとテスト](./afide-03_session-restore-regression-fixture.md)（**完了**） | テスト | 02 | NFR-01, NFR-02 |
| AFIDE-04 | [設定キー `fileEditor.syntaxHighlight` / `.lineNumbers` の追加](./afide-04_file-editor-settings-keys.md)（**完了**） | 実装 | 02（03 完了後が望ましい） | FR-04, FR-06, D-02 |
| AFIDE-05 | [ハイライト基盤の値型と言語判定ポリシー](./afide-05_highlight-value-types-and-policy.md)（**完了**） | 実装 | 02 | FR-02, FR-03, FR-11, NFR-05 |
| AFIDE-06 | [シンタックスハイライトエンジンの実装](./afide-06_highlight-engine-implementation.md)（**完了**） | 実装 | 01, 05 | FR-01, NFR-03/04/07/11 |
| AFIDE-07 | [`FilePreviewSyntaxHighlightController` の実装](./afide-07_highlight-controller.md)（**完了**） | 実装 | 05 | FR-01, FR-03, FR-11, NFR-03/04 |
| AFIDE-08 | [ハイライトのエディタ結線と `applyTheme` 対処](./afide-08_highlight-editor-wiring.md)（**完了**） | 実装 | 04, 06, 07 | FR-01, FR-11, NFR-06/07 |
| AFIDE-09 | [`FilePreviewLineIndex` の実装](./afide-09_line-index.md)（**完了**） | 実装 | 02 | FR-05, NFR-04 |
| AFIDE-10 | [行番号表示](./afide-10_line-number-ruler.md)（**完了**） | 実装 | 04, 09 | FR-05, FR-06, NFR-14 |
| AFIDE-11 | [コード拡張子のルーティング確定と入口別検証](./afide-11_text-extensions-and-entrypoint-verification.md)（**完了**） | 実装 | 02 | FR-10, FR-02 AC1, NFR-13 |
| AFIDE-12 | [外部変更 × 未保存バッファの選択 UI](./afide-12_save-conflict-ui.md)（**Reload / Keep Mine 完了。Compare は AFIDE-13 待ち**） | 実装 | 02（マージ可否は 13 に依存） | FR-07, NFR-06, NFR-12 |
| AFIDE-13 | [Compare の実現方式決定（未確定-03 / 新規-D の解決）](./afide-13_compare-decision.md)（**調査完了** → [結果](./afide-13_調査結果.md)） | 調査 | 02 | FR-08, FR-07 AC1 |
| AFIDE-14 | [外部エディタへの行番号受け渡し](./afide-14_external-editor-line-number.md) | 実装（打ち切り可） | 02 | FR-09, D-04 |

## 推奨着手順（依存フロー）

```
Phase 0（前提。ここが終わるまで実装コミットを積まない）
  AFIDE-01 エンジン選定（未確定-02）      AFIDE-02 upstream 追従（NFR-10）
       │  ※ 06 のブロッカー                    │  ※ 03 以降すべての前提
       │                                       ↓
       │                              AFIDE-03 Session Restore 基準線
       │                                （実装前ビルドでフィクスチャを取る必要があるため、
       │                                  04 以降より先に完了させる）
       │                                       │
       ├───────────────────────────────────────┤
       ↓                                       ↓
Phase 1（土台。並行可）
  AFIDE-04 設定キー2本    AFIDE-05 ハイライト値型    AFIDE-09 LineIndex
  （未確定-05 で          （エンジン非依存）         （純 Foundation）
    ブロック）                  │                        │
       │                        ├──→ AFIDE-06 エンジン実装（要 AFIDE-01）
       │                        └──→ AFIDE-07 コントローラ
       │                                  │
       ↓                                  ↓
Phase 2（結線。ここで初めて画面に出る）
  AFIDE-08 ハイライト結線（要 04 + 06 + 07）
  AFIDE-10 行番号結線  （要 04 + 09）

Phase 3（独立。Phase 0 完了後いつでも並行可）
  AFIDE-11 拡張子ルーティング（依存なし・小粒）
  AFIDE-12 保存衝突 UI ── マージ可否は AFIDE-13 の判断に依存
  AFIDE-13 Compare 方式決定（調査）
  AFIDE-14 外部エディタ行番号（新規-G。無理と分かった時点で打ち切る）
```

**最短の直列パス**: `02 → 03 → 04 → 05 → 07 → 08`（+ `01 → 06` を 08 までに合流）

**並行のさばき方**
- AFIDE-01 と AFIDE-02 は最初から並行してよい
- AFIDE-11 / AFIDE-12 / AFIDE-13 / AFIDE-14 は Phase 1・2 と完全に並行してよい（互いに触るファイルが重ならない）
- AFIDE-04 と AFIDE-05 / AFIDE-09 は並行可。ただし AFIDE-08 / AFIDE-10 は AFIDE-04 のマージを待つ

## 着手前に解決が必要な未確定事項（**issue に着手する前に本人判断が要る**）

| 未確定 | 内容 | ブロックする issue | 解決手段 |
|---|---|---|---|
| ~~**未確定-02**~~ **解決済み** | ハイライトエンジンの選定 → **同梱 highlight.js + JavaScriptCore（選択肢 C）を採用**。根拠は [AFIDE-01 調査結果](./afide-01_調査結果.md) | AFIDE-06 | AFIDE-01 で解決済み |
| ~~**未確定-05**~~ **解決済み** | `fileEditor.syntaxHighlight` / `.lineNumbers` の既定値 → **両方 `true`**（2026-08-17 決定）。FR-04 AC3 の実装ブロックは解除。閾値（`maximumHighlightBytes`）は定数のまま AFIDE-07 で決める | AFIDE-04 | 決定済み |
| **未確定-03** | ~~Compare の実体~~ → **技術的には (i) `.patch` 経由で成立すると判明**（[AFIDE-13 調査結果](./afide-13_調査結果.md)）。ただし**当面実装しないことを推奨**。残るのは**「Reload / Keep Mine の2択で先行リリースしてよいか」の本人判断**。2択で確定するなら 02 の FR-07 受け入れ条件1（3択を要求）の修正が要る | AFIDE-12 の**マージ可否** | 本人判断 |
| ~~**未確定-11**~~ **解決済み** | upstream 追従の実施時期 → **upstream #10225 のクローズまで延期**（2026-08-17 決定）。`upstream/main` は `04ff18eea6` により macOS がビルド不能で、取り込むと NFR-10 の受け入れ条件2 を満たせない。リモート追加は完了済み。根拠は [AFIDE-02 基準線記録](./afide-02_基準線記録.md) | AFIDE-02 | AFIDE-02 で解決済み |

> **AFIDE-01 の調査で新規-H 〜 新規-N の7件が追加で判明した**。一覧と扱いは [AFIDE-01 調査結果 §6](./afide-01_調査結果.md#6-この調査で新たに判明した未確定事項) を見ること。
>
> **解決済み**: 新規-H は AFIDE-07 で「テキスト世代が変わったときだけエンジンを1回呼び、結果をキャッシュしてスクロールは可視範囲の再描画だけにする」形に解決した。新規-B（属性変更が Undo に乗らないか）は成り立つことを実測で確認。新規-C は (i)（`NSTextStorageDelegate` で `editedRange`/`changeInLength` を受ける）を採用し、ルーラ自身が delegate になった。新規-K は CSS 忠実（`number` と `attribute` が同色）、新規-M は同梱エンジンに無い6言語を表から落とす、新規-F は既存どおり App セクション、でそれぞれ確定。
>
> **未解決**: 新規-I（dart 文法ファイルの置き場所。**そもそも未取得**）、新規-L（中間輝度テーマのコントラスト）、新規-N（FR-03 閾値の実値）、新規-D / 新規-E / 新規-G（AFIDE-13 / AFIDE-14 の範囲）。

## 実装中に判断してよい未確定事項

| 未確定 | 内容 | 扱う issue |
|---|---|---|
| 新規-A | `applyTheme` の `textColor` 一括代入への対処（引数追加 / 打ち消し / 呼び分けの3案） | AFIDE-08 |
| 新規-B | 属性のみの変更が Undo に乗らないか（**成り立たなければ設計を見直す**） | AFIDE-08 の最初のステップで検証 |
| 新規-C | `FilePreviewLineIndex` の増分更新をどこで受けるか（判断次第で AFIDE-09 の保留シフト方式が成立しなくなる） | AFIDE-10 |
| 新規-E | `OpenConfiguration.arguments` の併用可否 / プレースホルダか既知コマンド推定か | AFIDE-14 |
| 新規-F | Settings 行を独立「File Editor」セクションに分けるか | AFIDE-04 |
| **新規-G** | 下位パッケージの public API 追加とヘッダメニューへの経路追加を許容するか。**「実装して差分を見てから判断する」方針が決定済み。差分が大きすぎる／構造的に無理と分かった時点で報告して打ち切る** | AFIDE-14 |
| 未確定-04 | 外部エディタへの行番号の渡し方 | AFIDE-14 |
| 未確定-08 | 性能の数値目標（デバウンス幅・オーバースキャン行数を含む） | AFIDE-07 で暫定値を実装し、目標決定後に調整 |

## issue 化しなかったもの（要確認）

| 項目 | 理由 |
|---|---|
| **FR-08（Compare）の実装 issue** | 実現方式が未決で **§20.1 が「未設計」と明記している**。タスクリストも成果物も単体で書けないため、実装 issue を作らず **AFIDE-13（方式決定の調査 issue）に置き換えた**。AFIDE-13 で (i) Diff Viewer に `.patch` で渡す / (ii) 独立 UI / (iii) 実装しない のいずれかが決まった後、必要なら AFIDE-15 として起こす |
| 未確定-06（File Watch の粒度） | 本設計は File Watch を変更しないため作業が発生しない（NFR-12 は「変えないこと」のみ） |
| 未確定-07（Inspector のショートカット衝突） | Inspector は MVP 対象外。本設計は新規ショートカットを追加しない。着手する場合は `KeyboardShortcutSettings` + Settings + `cmux.json` + docs の4点セットに乗せる |
| 未確定-09（Phase 0 変更箇所マップ） | 詳細設計が「既存 `FilePreviewTextEditor` の読解」「Diff Viewer 方式の読解」を消化済み。**未消化は「競合4 PR（#1909 / #4801 / #5638 / #2864）の方式比較」のみ**。未確定-01 が D-1 で解決済みのため判断材料としては不要になっており、issue 化していない。**必要かどうかは要確認** |
| 未確定-10（Image Preview の残り2点） | **2026-08-17 に問いを差し替え**（旧版「QuickLook 依存範囲」は 01 §12 訂正の初版が誤りだったため無効）。画像は `.image` モードの独自実装で、**Fit / 100% / Zoom / Pan は実装済み** `[実コード: Sources/Panels/FilePreviewPanel.swift:3631-3681]`。残るのは **(1) 背景切替を足すか、(2) SVG が実際に表示されるか**の2点のみ。どちらも MVP 外として閉じてよく、入れるなら別 issue が要る |
| REQ-24（Live Diff）/ REQ-25（LSP）/ REQ-26（Git Worktree） | 要件定義で MVP 対象外と明記済み |

## 詳細仕様への参照

- 要求定義: [`../01_要求定義.md`](../01_要求定義.md)
- 要件定義: [`../02_要件定義.md`](../02_要件定義.md)（FR-01〜11 / NFR-01〜15 / D-01〜05 / 未確定-01〜11）
- 詳細設計: [`../03_詳細設計.md`](../03_詳細設計.md)（§5 主要な設計判断 / §7 ハイライト / §8 行番号 / §9 保存衝突 / §10 Actions / §12 設定13箇所 / §13 ローカライズ / §16 テスト戦略 / §18.4 NFR-08 のはみ出し記録 / §19 新規-A〜G）
- **技術メモ（実測値・実装構造・落とし穴の集約）**: [`../技術メモ.md`](../技術メモ.md)
- cmux 規約: `CLAUDE.md`（`AGENTS.md` は同一実体へのシンボリックリンク）、`skills/cmux-*/SKILL.md`

## 全 issue に共通する cmux 規約（各 issue のタスクリストにも展開済み）

- **テスト配線**: `cmuxTests/` に `.swift` を置くだけでは `PBXFileReference` + `PBXSourcesBuildPhase` が無いと**無言でスキップされ、CI は「Executed 0 tests」で緑になる**。必ず2エントリを足し `./scripts/lint-pbxproj-test-wiring.sh` を通す
- **回帰テストは2コミット**: テスト先行（CI red）→ 修正（CI green）。**コミット1にテストファイル + pbxproj 2エントリを含める**（配線が無いと red にならない）。対象は AFIDE-12（既存挙動を変える唯一の issue）
- **ユーザー向け文字列**: `String(localized:)` + `Resources/Localizable.xcstrings`（en / ja）+ `web/messages/{en,ja}.json`。対象は AFIDE-04（Settings 6キー + web スキーマ）と AFIDE-12（バナー 4〜5キー）
- **設定キー追加は13箇所**: 1本足すのに13箇所の登録が要る（詳細設計 §12.2）。全リストは AFIDE-04 のタスクリストに展開済み
- **ビルド確認**: `./scripts/reload.sh --tag agent-first-ide`（**素の `xcodebuild` / untagged ビルドは禁止**）と `scripts/test-unit.sh`
- **テスト結果の読み方**: `cmuxTests/` は **Swift Testing と XCTest が混在**しており出力形式が2系統に分かれる。XCTest は `Test Suite '...' passed` / `Executed N tests`、Swift Testing は `◇ Test run started.` / `✔ Test run with N tests in M suites passed`。**`Test Suite` だけを見ると Swift Testing 側が丸ごと見えず件数を誤読する**（AFIDE-02 で実際に踏んだ。詳細は [基準線記録 §3.4](./afide-02_基準線記録.md)）
- **フルスイートはローカルで回さない**: `scripts/test-unit.sh` を絞り込みなしで実行すると `AppDelegateShortcutRoutingTests` でハングする。回帰判定は NFR-06 の5ファイル（55件）を `-only-testing` で回し、フルスイートの緑判定は `scripts/verify-remote.sh mac --tag agent-first-ide` かCI に委ねる
- **Shared behavior policy**: 複数入口から使える振る舞いは単一の共有アクション経路にする。AFIDE-11（分岐を増やさない）/ AFIDE-10（フォント同期点を `applyCurrentPreviewFont()` に集約）/ AFIDE-12（解決を coordinator の1メソッドに閉じる）/ AFIDE-14（行番号は `PreferredEditorService` 1箇所にだけ口を開ける）
- **触らないファイル**: `Sources/Workspace.swift` / `Sources/TerminalPanel*.swift` / `Sources/ContentView.swift` / `Sources/GhosttyTerminalView.swift` / `Sources/TerminalWindowPortal.swift` / `Sources/SessionPersistence.swift` / `Sources/CommandClickFileOpenRouter.swift` / `Sources/FileExplorerKeyboardShortcuts.swift`
