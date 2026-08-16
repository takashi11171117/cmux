# AFIDE-02 基準線記録: upstream 追従とビルド・テスト基準線

- 対象 issue: [`afide-02_upstream-sync-baseline.md`](./afide-02_upstream-sync-baseline.md)
- 由来: NFR-10（着手前に upstream 追従）、NFR-08（差分の局所化）、NFR-09（upstream PR を前提にしない）、NFR-06（既存テスト）
- 実施日: 2026-08-17
- ブランチ: `fork/agent-first-ide`
- 実施時 HEAD: `03cab6a0d`（docs のみ7コミット）
- ビルドタグ: `agent-first-ide`

出所表記は `[実コード: path:line]` / `[実測]` / `[設計判断]` を用いる。

---

## 1. 結論

**upstream 追従は延期する。ビルド・テストの基準線は現基点で確立した。**

upstream `manaflow-ai/cmux` の `main` は **macOS の `cmux` scheme がコンパイルできない状態**であり、取り込むと NFR-10 の受け入れ条件2（取り込み後にビルドが通る）を満たせない。現基点はビルドが通るため、追従によって**ビルド可能な状態からビルド不能な状態へ退行する**ことになる。

したがって AFIDE-02 を2つに割り、**「基準線確立」だけを完了とし、「upstream 追従」は upstream 側の修正待ちとする**。

---

## 2. upstream の状態（追従を延期した根拠）

### 2.1 upstream/main はビルドできない

upstream issue **#10225**（`state=OPEN` / 2026-08-16 起票 / 未クローズ）`[実測: gh issue view 10225 --repo manaflow-ai/cmux]`

> Commit 04ff18eea6 ("Remove iOS todo row sparkles and preserve native mobile surfaces", pushed directly to main on 2026-08-14) does not compile for the macOS `cmux` scheme. With `ci.yml` paused (workflow_dispatch-only), no PR or push CI caught it, so every branch cut from current main fails to build.

報告されているエラーは8件で、2ファイルに集中している `[実測: 同 issue 本文]`。

```
Sources/Workspace+PanelLifecycle.swift:455:30: error: extra argument 'workspaceID' in call
Sources/TerminalController+MobileSurfaces.swift:10:9:  error: switch must be exhaustive
Sources/TerminalController+MobileSurfaces.swift:57:17: error: cannot find 'panelArtifactAuthorizationStore' in scope
Sources/TerminalController+MobileSurfaces.swift:63:17: error: cannot find 'panelArtifactAuthorizationStore' in scope
Sources/TerminalController+MobileSurfaces.swift:146:9: error: switch must be exhaustive
Sources/TerminalController+MobileSurfaces.swift:264:13: error: switch must be exhaustive
Sources/TerminalController+MobileSurfaces.swift:370:13: error: cannot find 'panelArtifactAuthorizationStore' in scope
Sources/TerminalController+MobileSurfaces.swift:384:35: error: cannot find 'panelArtifactAuthorizationStore' in scope
```

### 2.2 壊れたコミットは回避できない位置にある

`[実測: git log --graph --oneline upstream/main]`

```
77adc69121 (upstream/main)  Merge pull request #10149 from manaflow-ai/issue-10146-dock-theme-mismatch
├─ ef536b04af … 01a6b04386   theme 系10コミット（PR #10149 のトピックブランチ）
└─ ec4389e94e                fix(ios): pin dogfood auth identity end to end (#10185)
   └─ 04ff18eea6  ★ ビルドを壊したコミット（main へ直接 push）
      └─ 5734a451cc  ★ 現在の fork の基点 = 壊れる「直前」
```

- `git merge-base --is-ancestor 04ff18eea6 upstream/main` → **真**（upstream/main は壊れたコミットを含む）`[実測]`
- `git merge-base --is-ancestor 04ff18eea6 5734a451cc` → **偽**（現基点は含まない）`[実測]`
- `04ff18eea6^` = `5734a451cc` `[実測]`。すなわち **fork の基点は壊れたコミットの親そのもの**

`04ff18eea6` は `main` の直系にあるため、**これを避けて upstream の新しいコミットだけを取り込む経路は存在しない**。PR #10149 の theme 系10コミットは別系統だが、それらを含むマージコミット `77adc69121` は `04ff18eea6` も同時に含む。

### 2.3 追従で得られるものと失うもの

| | 内容 |
|---|---|
| 得るもの | upstream 13コミット（iOS 認証の修正1件 + Dock/ブラウザのテーマ系10件 + マージ2件）。**いずれもエディタのハイライト・行番号・保存衝突とは無関係** |
| 失うもの | **ビルド可能な状態**。8件のコンパイルエラーが入る |

### 2.4 延期しても追従コストは増えない

NFR-10 が「実装コミットを積む前に追従せよ」と定める理由は、独自変更が少ないうちに取り込んでコンフリクトを抑えることである。本 fork の独自コミットは7本、**すべて `docs/` 配下のみでコード変更はゼロ** `[実測: git diff --name-only upstream/main...HEAD]`。`origin` へも未 push である `[実測: no upstream configured for branch]`。

`docs/fork/` は upstream に存在しないディレクトリなので、**いつ追従してもコンフリクトは発生しない**。したがって延期による追従コストの増加はない。

### 2.5 採らなかった代替案

| 案 | 却下理由 |
|---|---|
| 全部取り込んで `04ff18eea6` を revert する | `Sources/Workspace+PanelLifecycle.swift` / `Sources/TerminalController+MobileSurfaces.swift` に fork 独自の差分が生まれる。NFR-08 受け入れ条件3（`Sources/Workspace.swift` 等の構造的変更を行わない）に反し、upstream が #10225 を修正した時点でコンフリクトする |
| 全部取り込んで fork 側でコンパイルエラーを直す | 同上。さらに upstream の修正内容と食い違えば二重修正になる |
| PR #10149 のトピックブランチだけ cherry-pick する | 現基点から分岐した別系統であり、テーマ系の変更は本 fork の作業と無関係。差分を増やすだけで見返りがない |

### 2.6 追従の再開条件

**upstream issue #10225 がクローズされ、`upstream/main` で macOS の `cmux` scheme がビルドできるようになった時点**で、AFIDE-02 の追従部分を再開する。再開時の手順は変わらない（`git fetch upstream` → rebase → `reload.sh` → `test-unit.sh`）。fork の独自コミットが `docs/` のみである限り、rebase でのコンフリクトは想定されない。

---

## 3. 基準線（現基点での実測）

### 3.1 環境

- upstream リモート: **設定済み** `upstream → https://github.com/manaflow-ai/cmux.git` `[実測: git remote -v]`
- submodule: 初期化済み（`ghostty` / `homebrew-cmux` / `vendor/bonsplit`）`[実測: git submodule status]`
- `GhosttyKit.xcframework`: 存在（`ghostty/macos/GhosttyKit.xcframework`）。`./scripts/setup.sh` の再実行は不要 `[実測]`

> `git fetch upstream` は submodule fetch でエラーを出す（`upload-pack: not our ref` が `vendor/bonsplit` と `ghostty` で発生）。ただし**メインリポジトリの fetch 自体は成功する**（exit 0）。submodule のポインタが upstream 側に存在しないコミットを指しているためで、追従の障害にはならない `[実測]`。

### 3.2 ビルド

```
./scripts/reload.sh --tag agent-first-ide
```

**成功（684秒）** `[実測]`。素の `xcodebuild` / untagged ビルドは使用していない。

- 成果物: `~/Library/Developer/Xcode/DerivedData/cmux-agent-first-ide/Build/Products/Debug/cmux DEV agent-first-ide.app`
- ログ: `/tmp/cmux-reload-agent-first-ide.log`

### 3.3 静的チェック

| コマンド | 結果 |
|---|---|
| `./scripts/lint-pbxproj-test-wiring.sh` | **ok**（690 テストファイルを検査）`[実測]` |
| `./scripts/check-pbxproj.sh` | **通過**（出力なし）`[実測]` |
| `python3 scripts/check-package-resolved-policy.py` | **Package.resolved policy OK** `[実測]` |

### 3.4 ユニットテスト

#### NFR-06 が指定する5ファイル: **全55テスト通過** `[実測]`

```
scripts/test-unit.sh test -derivedDataPath ~/Library/Developer/Xcode/DerivedData/cmux-agent-first-ide \
  -only-testing:cmuxTests/FilePreviewTextEditorTextKitTests \
  -only-testing:cmuxTests/FilePreviewReloadTests \
  -only-testing:cmuxTests/FilePreviewReloadCompletionTests \
  -only-testing:cmuxTests/FilePreviewKindResolverTests \
  -only-testing:cmuxTests/MarkdownPanelTests
```

**`** TEST SUCCEEDED **` / EXIT=0** `[実測]`

| ファイル | フレームワーク | テスト数 | 結果 |
|---|---|---|---|
| `FilePreviewTextEditorTextKitTests` | Swift Testing | 8 | ✅ |
| `FilePreviewReloadTests` | Swift Testing | 13 | ✅ |
| `FilePreviewReloadCompletionTests` | Swift Testing | 2 | ✅ |
| `FilePreviewKindResolverTests` | Swift Testing | 4 | ✅ |
| `MarkdownPanelTests` | **XCTest** | 28 | ✅ |
| **合計** | | **55** | **✅ 0 failures** |

pbxproj 配線もファイルごとに4エントリ揃っている `[実測: grep -c "<name>.swift" cmux.xcodeproj/project.pbxproj]`。

> **⚠️ 実行結果の読み方（重要）**: このスイートは **Swift Testing と XCTest が混在**しており、**出力形式が2系統に分かれる**。
> - XCTest: `Test Suite 'MarkdownPanelTests' passed` / `Executed 28 tests, with 0 failures`
> - Swift Testing: `◇ Test run started.` / `✔ Test run with 27 tests in 4 suites passed after 1.833 seconds.`
>
> **`Test Suite` だけを grep すると Swift Testing の27件が丸ごと見えず、「28件しか走っていない」と誤読する。** `AGENTS.md:97` が警告する「Executed 0 tests で CI が緑になる」問題と症状が似ているため、テスト結果を確認するときは**必ず両方の形式を見ること**。

#### フルスイートは**ローカルでは完走しない** `[実測]`

`scripts/test-unit.sh`（絞り込みなし）を実行すると、**5スイート目でハングする**。

- `AppDelegateShortcutRoutingTests` が `started` のまま **3分以上進行せず**停止（他スイートはいずれも数秒で完了）
- その間ログは **49万行**まで膨張。中身は終了しなかった `cmux DEV` プロセスの `[generic_renderer]` / `[io_exec]` ログ
- 手動で `pkill -f "xcodebuild.*cmux-unit"` するまで終わらない

ハングまでに観測できた結果 `[実測]`:

| スイート | 結果 |
|---|---|
| `AccessibilityInsertTextRegressionTests` | ❌ 3件中 **2 failures** |
| `AgentSessionAutoResumeSettingsTests` | ✅ 13件 |
| `AppDelegateBareSpaceShortcutRoutingTests` | ✅ 3件 |
| `AppDelegateIssue2907RoutingTests` | ❌ 28件中 **3 failures** |
| `AppDelegateLaunchServicesRegistrationTests` | ✅ 2件 |
| `AppDelegateShortcutRoutingTests` | ⏸ **ハング** |

失敗もハングも **AppDelegate / Accessibility 系（GUI 依存）に集中している**。`AGENTS.md` は「Agent verification (iOS simulator checks, tagged macOS GUI checks) runs on the Mac mini fleet, not on the local Mac」と定めており、この領域をローカルで回すのは想定された使い方ではない。

> **未解明**: これらの失敗が **upstream 由来で元から赤いのか**、**このローカル環境固有（アクセシビリティ権限・フォーカス・ウィンドウサーバ）なのか**は切り分けていない `[要調査]`。現時点で言えるのは「**ローカルのフルスイートは基準線として使えない**」ことだけである。**「既存テストは全部通る」と書いてはならない。**

#### 基準線としての結論

- **AFIDE-03 以降の回帰判定には、NFR-06 の5ファイル（55件）を使う。** これが本 fork の変更が壊してはいけない本丸であり、GUI 依存が薄く安定して完走する
- **フルスイートの緑判定はローカルで行わない。** `scripts/verify-remote.sh mac --tag agent-first-ide` でフリートに投げるか、CI に委ねる

### 3.5 設計書の行番号検証

`03_詳細設計.md` が参照している行番号を抜き取り15件で照合した結果、**すべて現在のコードと一致していた** `[実測]`。後続 issue は設計書の行番号をそのまま頼ってよい。

| 引用 | 実際の行内容 |
|---|---|
| `FilePreviewTextEditor.swift:143` | `static func makeFilePreviewTextView() -> SavingTextView {` |
| `FilePreviewTextEditor.swift:157` | `let textStorage = NSTextStorage()` |
| `FilePreviewTextEditor.swift:95` | `static func applyTheme(` |
| `FilePreviewTextEditor.swift:109` | `textView.textColor = foregroundColor` |
| `FilePreviewTextEditor.swift:194` | `func applyFilePreviewWordWrap(_ wrap: Bool, scrollView: NS…` |
| `FilePreviewTextEditor.swift:345` | `func applyCurrentPreviewFont() {` |
| `FilePreviewTextEditor.swift:7` | `protocol FilePreviewTextEditingPanel: AnyObject {` |
| `FilePreviewPanel.swift:906` | `static let maximumLoadedTextBytes: UInt64 = 16 * 1024 * 10…` |
| `FilePreviewPanel.swift:669` | `private static let textExtensions: Set<String> = [` |
| `FilePreviewPanel.swift:1286` | `if !replacingDirtyContent && isDirty {` |
| `FilePreviewPanel.swift:1381` | `@AppStorage(FilePreviewWordWrapSettings.key) private var f…` |
| `MarkdownPanel.swift:373` | `if !replacingDirtyContent && isDirty {` |
| `MarkdownPanelView.swift:32` | `@AppStorage(FilePreviewWordWrapSettings.key) private var f…` |
| `FilePreviewTextEditorTextKitTests.swift:42` | `#expect(textView.textLayoutManager == nil)` |
| `Panel.swift:66` | `throw DecodingError.dataCorruptedError(` |

> 例外として **`01_要求定義.md` §12 の引用（`FilePreviewPanel.swift:648,682,718`）はずれていた**が、これは追従によるずれではなく初回検証時点の誤りであり、2026-08-17 の再検証で該当節ごと差し替え済み。

---

## 4. AFIDE-02 の受け入れ条件に対する達成状況

| 成果物 | 状態 |
|---|---|
| `upstream` リモートが設定されている | ✅ 設定済み |
| `fork/agent-first-ide` が upstream 最新を含んでいる | ❌ **意図的に見送り**（§2。upstream/main がビルド不能） |
| `./scripts/reload.sh --tag agent-first-ide` が成功する | ✅ 684秒 |
| `scripts/test-unit.sh` が成功し「Executed 0 tests」ではない | ⚠️ **条件付き**。NFR-06 の5ファイル55件は成功。フルスイートはローカルでハングするため未達（§3.4） |
| 取り込みハッシュ・テスト結果・行番号ずれの記録 | ✅ 本書 |

**AFIDE-02 は「基準線確立」部分を完了とし、「upstream 追従」部分を保留として残す。**

---

## 5. 次にやること

1. **AFIDE-03**（Session Restore 回帰フィクスチャ）に進む。本記録の基準線ビルド（タグ `agent-first-ide`、HEAD `03cab6a0d`）が「実装前ビルド」に該当するので、**このビルドでフィクスチャを取得すること**
2. upstream #10225 を定期的に確認し、クローズされたら AFIDE-02 の追従部分を再開する
3. フルスイートの緑判定が必要になった時点で `scripts/verify-remote.sh mac --tag agent-first-ide` を使う。ローカルでは回さない
4. `AccessibilityInsertTextRegressionTests` / `AppDelegateIssue2907RoutingTests` の失敗が upstream 由来かローカル環境固有かの切り分け `[要調査]`。**本 fork の変更とは無関係**（この時点でコード変更はゼロ）だが、後で「自分が壊した」と誤認しないために記録しておく

---

## 6. 決定事項の記録（本 issue の作業中に確定したもの）

| 未確定 | 決定 | 反映先 |
|---|---|---|
| **未確定-11**（upstream 追従の実施時期） | **#10225 のクローズまで延期**。リモート追加は完了済み | 本書 §2 |
| **未確定-05**（設定キーの既定値） | **`fileEditor.syntaxHighlight` / `.lineNumbers` とも `true`**。FR-04 AC3 の実装ブロックは解除 | `02` 未確定-05 / `03` §12.1 / `issues/README.md` / `afide-04_*.md` |

閾値（`FilePreviewHighlightPolicy.maximumHighlightBytes`）は未決のまま。定数として持ち `init` 注入の形にしておき、AFIDE-07 で実測しながら決める（新規-N: iOS 側の 1,500,000 バイトをそのまま採ると最悪ケースで約2秒の JS 実行になる）。
