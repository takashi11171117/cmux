# AFIDE-01 調査結果: シンタックスハイライトエンジン選定（未確定-02 の解決）

- 対象 issue: [`afide-01_syntax-highlight-engine-selection.md`](./afide-01_syntax-highlight-engine-selection.md)
- 由来: NFR-11（選定基準6軸）、FR-01 / FR-02 / FR-03 / FR-11、NFR-03 / NFR-04 / NFR-05 / NFR-07
- 設計書参照: [`../03_詳細設計.md`](../03_詳細設計.md) §5 D-2 / §6 / §7 / §15.2 / §20.2 / §20.5 / §20.6
- 調査日: 2026-08-16
- ブランチ: `fork/agent-first-ide`
- 本体差分: **なし**（`Sources/` / `cmux.xcodeproj` / `Package.resolved` を変更していない。検証用の一時変更は revert 済み）

出所表記は `[実コード: path:line]` / `[実測]` / `[設計判断]` を用いる。

---

## 1. 推奨

**選択肢 C（同梱済み `Resources/markdown-viewer/highlight.min.js` を JavaScriptCore で直接評価し、highlight.js の `__emitter` フックでトークン範囲を直接受け取る）を採用する。**

理由は3点。(1) Highlightr は **upstream 自身が「2026年以降メンテナンスしていない」と README で宣言している** `[実測: https://github.com/raspu/Highlightr README 冒頭 "As of 2026, Highlightr is no longer actively maintained."]` ため NFR-11 軸1 で落ちる。(2) Highlightr は CSS パーサの欠陥で **`github` テーマでは文字列が、`github-dark` テーマではキーワードが本文色のまま**になり FR-01 AC1 を満たさない `[実測: §3.5]`。(3) C は SPM 依存ゼロ・`Package.resolved` 差分ゼロ・pbxproj 差分ゼロ・バンドル増分ゼロで、Highlightr より **1.4〜1.5 倍速い** `[実測: §3.3]`。

---

## 2. 3案の比較表

判定に使った略号: ◎ 明確に有利 / ○ 問題なし / △ 条件付き / ✗ 要件を満たさない

| 軸 | A: Highlightr 2.3.0（SPM） | B: 自前スキャナ | **C: 同梱 highlight.js + JSC（推奨）** |
|---|---|---|---|
| **1. 依存の増加** | △ SPM remote package +1（`Package.resolved` の pin が 14 → 15）`[実コード: cmux.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved（pin 14件・Highlightr なし）]`。`XCRemoteSwiftPackageReference` +1、`cmux` / `cmuxTests` **両ターゲット**への product 追加 `[設計書: §15.2]`。リソースバンドル **+2.1 MB**（hljs 11.11.1 フル版 1,090,403 バイト + テーマ CSS 271枚 1.1 MB）`[実測: §3.4]` | ◎ ゼロ。JSC すらリンクしない | ◎ SPM 依存ゼロ。JavaScriptCore は **system framework** なのでバンドル増分 **0 バイト**。pbxproj 差分も **0**（Swift auto-link で入る）`[実測: §3.6]`。dart 文法 2,216 バイトの追加のみ `[実測: §3.7]` |
| **2. upstream 追従コスト** | ✗ 最大。`Package.resolved`（+1 pin）/ `project.pbxproj`（package reference + 2ターゲットの product）/ `THIRD_PARTY_LICENSES.md`（Highlightr MIT + hljs 11.11.1 の2件目）に差分。`scripts/check-package-resolved-policy.py` の drift 判定対象にも入る `[実コード: scripts/check-package-resolved-policy.py 存在確認]` | ◎ ゼロ。新規 `Sources/Panels/*.swift` のみ（upstream と衝突しえない） | ◎ ほぼゼロ。`Resources/markdown-viewer/` は pbxproj で **folder reference** `[実コード: cmux.xcodeproj/project.pbxproj:4120 lastKnownFileType = folder]` なので、dart 文法ファイルを足しても **pbxproj 変更が不要**。`Package.resolved` 差分なし |
| **3. 性能**（1000行相当 / 4,475行 / 18,893行、同一プロセス実測） | △ 38.1 ms（478行）/ 353.4 ms / 1,732.5 ms。C と同じ JS を回した後、自前で HTML を再走査するぶん **常に C より遅い** `[実測: §3.3]` | ◎ 0.54 ms（478行）/ 4.90 ms / 20.6 ms。**C の約 40〜55 倍速い**（ただし Swift 1言語のみの実装での計測）`[実測: §3.3]` | ○ 27.3 ms（478行）/ 233.9 ms / 1,131.9 ms。1000行なら **30〜50 ms** `[実測: §3.3, §3.8]` |
| **3'. `range` 交差だけ安く返せるか**（§6 の契約 / §20.2 の最大リスク） | ✗ 不可。`range` を無視して全文を色付けする | ◎ 可能。範囲外で早期打ち切りできる設計にできる `[設計判断]` | ✗ 不可。**実測で確定**: 全文 233.9 ms に対し 3,000 文字へクリップしても 231.2 ms（4,475行）で**削減幅ゼロ** `[実測: §3.3]`。§20.2 が挙げた最大リスクは**実在する** |
| **4. TextKit 1 との相性** | ○ `NSAttributedString` を返すだけで `NSTextLayoutManager` に依存しない。`CodeAttributedString`（`NSTextStorage` サブクラス）は使わない前提 `[設計書: §7.3]` | ◎ `[FilePreviewHighlightRun]` を直接返す。AppKit に一切触れない | ◎ 同上。JSC は AppKit と無関係。`textLayoutManager == nil` の不変条件 `[実コード: cmuxTests/FilePreviewTextEditorTextKitTests.swift:42]` と `NSTextStorage` 明示構築 `[実コード: Sources/Panels/FilePreviewTextEditor.swift:157-168]` のどちらにも触れない |
| **5. 13言語のカバー**（FR-02） | ◎ 192言語。dart を含め13言語すべて ok `[実測: §3.4]` | △ 実装量そのもの。13言語 × 4トークン種別を全部書く必要がある（§5 で規模を試算） | △ 36言語。**dart のみ欠落**、他12言語は ok `[実測: §3.1]`。2,216 バイトの `dart.min.js` を追加登録すれば解消 `[実測: §3.7]` |
| **6. テーマ連動**（FR-11） | ✗ **`github` / `github-dark` テーマが壊れている**（後述 §3.5）。使えるのは実質 `xcode` のみ。同梱 CSS の色とも一致しない | ◎ 同梱 `highlight-github{,-dark}.css` の色を自由に割り当てられる | ◎ scope 名が直接返るため、同梱 `highlight-github.css` / `highlight-github-dark.css` `[実コード: Resources/markdown-viewer/highlight-github.css, highlight-github-dark.css]` の色をそのまま `FilePreviewTokenRole` へ割り当てられる。Markdown プレビューと配色が揃う |
| **追加軸: maintenance**（NFR-11 軸1・`[要調査]` だった軸） | ✗ **upstream が明示的に「メンテ終了」を宣言**。最終リリース 2.3.0 = 2025-06-18、最終コミット 2026-02-13（内容は "Added Disclaimer"）。open issues 25 `[実測: §3.9]` | ○ 自分たちで持つ（＝自分たちの負債） | ○ highlight.js は活発。11.12.0 が 2026-08-12 リリース、open issues 91、star 24,979 `[実測: §3.9]`。ただし**同梱物は 11.10.0（2024-07-15）で2マイナー遅れ**であり、更新の主体は upstream cmux 側 |
| **追加軸: license**（NFR-11 軸4） | △ Highlightr = MIT `[実コード: 2.3.0 の LICENSE]`。**新規の表記義務が2件増える**（Highlightr 本体 + 同梱される hljs 11.11.1 = BSD-3-Clause の2つ目の写し） | ◎ 増えない | ◎ **増えない**。highlight.js 11.10.0 / BSD 3-Clause は既に `[実コード: THIRD_PARTY_LICENSES.md:145-150]` に記載済み。dart 文法は同一プロジェクト・同一バージョンなので同エントリで足りる `[設計判断]` |
| **追加軸: dependency 固定**（NFR-11 軸2） | ○ `exact: "2.3.0"` で pin 可能。iOS 側に運用実績 `[実コード: Packages/iOS/CmuxAgentChatUI/Package.swift:23-26]` | ◎ 依存なし | ◎ 依存なし。アセットはリポジトリに vendoring 済みなので実質固定 |
| **追加軸: エンジンに渡すファイル内容の範囲**（§20.5） | △ 任意のファイル全文を JSC へ渡す（入力面が拡大） | ◎ 拡大しない | △ A と同じ。ただし **highlight.js は新規の第三者コードではない**（Markdown プレビューが既に同梱・実行）`[実コード: Resources/markdown-viewer/highlight.min.js, Sources/Panels/MarkdownViewerAssets.swift:24]`。ローカル完結でネットワークには出ない |

---

## 3. 実測した内容と結果

### 3.0 計測環境

- Xcode 26.0.1 (Build 17A400) / Apple Swift 6.2 / `arm64-apple-macosx26.0` `[実測]`
- 計測中、同一マシンで別の Swift ビルドが並走しており load average は 5〜50 の範囲で変動した。**絶対値は最良値（min）寄りに読むこと**。案間の比較は後述 §3.3 の「同一プロセス・同一時刻」計測で行った `[実測]`
- スパイクはすべてスクラッチパッド配下で実施し、リポジトリには一切コミットしていない

### 3.1 同梱 highlight.min.js の素性と言語カバー

`Resources/markdown-viewer/highlight.min.js` を `JSContext.evaluateScript` に流し込むだけで `hljs` グローバルが取れる。**WebView は不要**で、DOM への参照も踏まない `[実測]`。

- バージョン: **11.10.0**（ファイル先頭のバナー、および `hljs.versionString`）、124,980 バイト
- `hljs.listLanguages()` = **36言語**（common ビルド相当）
- 初回 `evaluateScript` のコスト: **8.1 〜 14.8 ms**（プロセスあたり1回のみ）

FR-02 が要求する13言語の充足状況 `[実測]`:

| 言語 | 判定 | 言語 | 判定 |
|---|---|---|---|
| swift | ok | markdown | ok |
| typescript | ok | c | ok |
| javascript | ok | cpp | ok |
| **dart** | **MISSING** | rust | ok |
| php | ok | go | ok |
| python | ok | | |
| json | ok | | |
| yaml | ok | | |

**dart 以外の12言語は充足。dart のみ欠落**（§3.7 で解消手段を実測）。

参考: 設計書 §7.2 が複製元とする iOS 側の表 `[実コード: Packages/iOS/CmuxAgentChatUI/Sources/CmuxAgentChatUI/Artifacts/ChatArtifactSyntaxHighlightPolicy.swift:8-64]` が使う言語ID 34種のうち、同梱ビルドに無いのは **clojure / dart / elixir / fsharp / gradle / groovy / scala** の7種 `[実測]`。`html` は `xml` のエイリアスとして解決される `[実測]`。FR-02 の要求外なので必須ではないが、表をそのまま複製すると7種が無反応になる。

### 3.2 `__emitter` でトークン範囲を直接取得できる（HTML パース不要）

highlight.js 11 系の `hljs.configure({ __emitter: MyEmitter })` にカスタムエミッタを渡すと、HTML を組み立てずに `startScope(name)` / `endScope()` / `addText(text)` のコールバック列としてトークンを受け取れる `[実測]`。

- JS の文字列長は **UTF-16 コード単位**なので、`addText` の累積長がそのまま `NSRange.location` / `.length` になる。座標系の変換が要らない `[実測]`
- 得られる scope 名は CSS クラス名ではなく **ドット区切りの意味論名**（`keyword` / `string` / `comment` / `number` / `type` / `title.class` / `title.class.inherited` / `title.function` / `attr` / `meta` / `operator` / `punctuation` / `params` / `subst` / `literal` / `section` / `bullet` / `code` / `emphasis` …）`[実測]`

Swift サンプルでの実測出力（抜粋）:

```
[0,6]    keyword                "import"
[18,15]  comment                "// line comment"
[34,22]  comment                "/* block\n   comment */"
[64,5]   title.class            "Point"
[71,7]   title.class.inherited  "Codable"
[92,3]   type                   "Int"
[98,2]   number                 "42"
[133,1]  number                 "1"        ← 文字列補間の内側
[131,4]  subst                  "\(1)"
[124,12] string                 "\"hello \(1)\""
[141,10] meta                   "@MainActor"
[157,4]  title.function         "move"
```

**このフックの安定性を3バージョンで確認した** `[実測]`。同じエミッタ実装で 11.10.0（同梱物）/ 11.11.1（Highlightr 同梱物）/ 11.12.0（最新）が **バイト単位で同一の出力**を返した。`CHANGES.md` を 11.3.1 〜 11.12.0 まで grep しても emitter API の破壊的変更の記載はない `[実測]`。ただし `__` 接頭辞のとおり**公開 API ではない**（§6 の残リスクとして記録）。

### 3.3 性能（同一プロセス・同一時刻での head-to-head）

3案を1つのプロセス内で交互に走らせ、machine state を揃えて計測した（各9回、中央値）`[実測]`。

| 対象ファイル | C: JSC + 同梱 hljs + range emitter | C: 同左（3,000文字に clip） | A: Highlightr 2.3.0 | B: 自前スキャナ（Swift 1言語のみ） |
|---|---|---|---|---|
| `FilePreviewTextEditor.swift` 478行 / 18.9 KB | **27.3 ms** | 26.9 ms | 38.1 ms | **0.54 ms** |
| `MarkdownWebRenderer.swift` 900行 / 38.8 KB | **47.7 ms** | 49.9 ms | 76.8 ms | **0.92 ms** |
| `FilePreviewPanel.swift` 4,475行 / 163.3 KB | **233.9 ms** | 231.2 ms | 353.4 ms | **4.90 ms** |
| `AppDelegate.swift` 18,893行 / 816.5 KB | **1,131.9 ms** | 1,103.5 ms | 1,732.5 ms | **20.6 ms** |

読み取れること:

1. **1000行のソースは C で 30〜50 ms**（478行=27.3 ms、900行=47.7 ms）。issue が求めた実測値はこれ。
2. **`range` へのクリップは計算量をまったく減らさない**（233.9 ms → 231.2 ms）。highlight.js は範囲指定に関係なく全文を走査するためで、**設計書 §20.2 が最大リスクと呼んだ懸念は実在する**。クリップで減るのは JS→Swift の受け渡し量だけ（4,475行で 5,401 run → 85 run）。
3. **A は常に C より遅い**（1.4〜1.5倍）。A は C と同じ JS を回した後、生成した HTML を Swift 側で `Scanner` で再走査し、さらに HTML エンティティを正規表現で復号しているため `[実コード: Highlightr 2.3.0 src/classes/Highlightr.swift processHTMLString]`。
4. **B は C の約 40〜55 倍速く、行数に対して素直に線形**。

### 3.4 Highlightr が macOS ターゲットで実際にビルドできるか

**ビルドできる** `[実測]`。本体を汚さないため、スクラッチパッドに独立した SPM パッケージを作って検証した（`platforms: [.macOS(.v14)]`、`.package(url: "https://github.com/raspu/Highlightr.git", exact: "2.3.0")`）。

- `swift build -c release` が **14.54 秒で成功**。Swift 6.2 ツールチェーンでエラーなし
- 実行時: `Highlightr()` の初期化に成功、`supportedLanguages()` = **192言語**（dart を含み FR-02 の13言語すべて充足）、`availableThemes()` = **271テーマ**（`github` / `github-dark` / `xcode` / `xcode-dark` すべて存在）
- ビルド生成物 `Highlightr_Highlightr.bundle` = **2.1 MB**（内訳: hljs 11.11.1 フル版 1,090,403 バイト + テーマ CSS 271枚 約 1.1 MB）
- `highlight(_:as:)` が返す `NSAttributedString` の `.string` は入力文字列と**一致した**（`<` `>` `&` `"` `'`・絵文字・日本語を含むサンプルで確認）。オフセットのズレは観測されなかった

### 3.5 Highlightr の致命的な欠陥（FR-01 AC1 / FR-11 に直撃）

`Highlightr` は CSS テーマを自前の正規表現でパースする `[実コード: Highlightr 2.3.0 src/classes/Theme.swift stripTheme]`。その正規表現は

```
(?:(\.[a-zA-Z0-9\-_]*(?:[, ]\.[a-zA-Z0-9\-_]*)*)\{([^\}]*?)\})
```

であり、セレクタ要素を `.名前` の**単一クラス**としか認識しない。したがって `.hljs-variable.constant_` や `.hljs-title.class_` のような**複合セレクタがグループ内に1つでも混ざると、そのルール全体がマッチせずに捨てられる**。

実測結果（Swift サンプルを各テーマでハイライトし、トークンごとの `.foregroundColor` を採取）`[実測]`:

| テーマ | 背景 | keyword | string | comment | number | type | attribute | plain | 判定 |
|---|---|---|---|---|---|---|---|---|---|
| `github` | #FFFFFF | #A71D5D | **#333333** | #969896 | **#333333** | #A71D5D | #A71D5D | #333333 | ✗ **文字列と数値が本文色**。FR-01 AC1 不成立 |
| `github-dark` | #0D1117 | **#C9D1D9** | #A5D6FF | #8B949E | #79C0FF | **#C9D1D9** | #A5D6FF | #C9D1D9 | ✗ **キーワードが本文色**。FR-01 AC1 不成立 |
| `xcode` | #FFFFFF | #AA0D91 | #C41A16 | #007400 | #1C00CF | #5C2699 | #808080 | #000000 | ○ 7色に分かれる |
| `xcode-dark` | #1F2024 | #FC5FA3 | #FC6A5D | #6C7986 | #41A1C0 | **#FFFFFF** | #FC5FA3 | #FFFFFF | △ 型が本文色 |

FR-01 AC1 は「キーワード・文字列・コメントが本文色と異なる色で描画される」ことを要求している `[要件定義: FR-01 受け入れ条件1]`。**`github` は文字列で、`github-dark` はキーワードでこれを満たさない。** FR-11 のために同梱 CSS と配色を揃えたい `github` 系が、A では両方とも使えない。

さらに §6 の seam に載せる際の問題が2つある `[実測]`:

1. **`.foregroundColor` → `FilePreviewTokenRole` の逆写像が単射でない。** 上表のとおり本文色と同じ色になるロールが存在するため、`github` では `string` と `number` を、`github-dark` では `keyword` と `type` を、色から復元できない。設計書 §5 D-2 が想定した「`.foregroundColor` 属性ランを走査してロールへ逆写像するアダプタ」は、**実測上そもそも成立しない**。
2. **`.font` 属性（`Courier` / `Courier-Bold`）が必ず付いてくる。** エディタのフォント設定（`applyCurrentPreviewFont()` `[実コード: Sources/Panels/FilePreviewTextEditor.swift:345-349]`）と衝突するため、アダプタ側で破棄する必要がある。

補足: iOS 側が `xcode` / `xcode-dark` を選んでいる `[実コード: .../ChatArtifactSyntaxHighlighter.swift:23]` のは、結果的にこの欠陥を踏まない数少ないテーマだったからである（意図的な回避かどうかは不明）。

### 3.6 JavaScriptCore が pbxproj 変更なしで app target にリンクされるか（対照実験）

**リンクされる。pbxproj の変更は不要** `[実測]`。

`cmux.xcodeproj/project.pbxproj` に `JavaScriptCore` の出現は **0件**。`import JavaScriptCore` はリポジトリ全体で `cmuxTests/HostedInspectorDockControlScriptTests.swift:1` の1件のみ `[実コード]`。app target で使えるかを対照実験で確かめた。

| 状態 | 手順 | app バイナリの link table |
|---|---|---|
| baseline（clean tree） | `./scripts/reload.sh --tag afide` | WebKit のみ。**JavaScriptCore なし** |
| probe | `Sources/Panels/FilePreviewWordWrapSettings.swift` に `import JavaScriptCore` + `JSContext` の実利用を一時追加し `./scripts/reload.sh --tag afide`（**74秒で成功**） | `/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/JavaScriptCore` が**出現** |

- Swift の auto-link によるもので、**pbxproj への framework 追加は一切不要**
- JavaScriptCore は **system framework** なので、アプリバンドルのサイズ増分は **0 バイト**
- 検証後に `Sources/Panels/FilePreviewWordWrapSettings.swift` を元に戻し、`git status` がクリーンであること、および clean tree で `./scripts/reload.sh --tag afide` が再度成功することを確認済み `[実測]`

### 3.7 dart 欠落の解消手段

hljs 11.10.0 用の dart 文法ファイル（`languages/dart.min.js`）は **2,216 バイト**で、末尾で `hljs.registerLanguage("dart", e)` を呼ぶ IIFE である `[実測]`。同梱 `highlight.min.js` を評価した JSContext に続けて評価すると:

- 評価コスト **0.16 ms**
- `listLanguages()` が 36 → **37** になり `dart` が登録される
- Dart サンプルで `comment` / `keyword` / `title` / `built_in` / `number` / `string` / `subst` の scope が正しく返る

`Resources/markdown-viewer` は pbxproj 上 **folder reference** `[実コード: cmux.xcodeproj/project.pbxproj:4120]` なので、ここへファイルを追加しても pbxproj の変更が要らない。ビルド時の圧縮スクリプトも `*.js` を一律 deflate するだけで、ファイル名の直書きはない `[実コード: scripts/compress-markdown-viewer-assets.sh:23-31]`。

> 置き場所（`Resources/markdown-viewer/` に相乗りするか、fork 独自の別ディレクトリを作るか）は `[要確認]`。相乗りは pbxproj 差分ゼロだが upstream 所有ディレクトリを汚す。別ディレクトリなら pbxproj に folder reference を1つ足す（4エントリ相当）。

### 3.8 言語別 1000行の実測（参考値）

代表スニペットを 1000 行相当まで繰り返した合成入力での C の所要時間（10回平均、別プロセス計測のため §3.3 とは machine state が異なる）`[実測]`:

| 言語 | 行数 | バイト数 | 所要 |
|---|---|---|---|
| swift | 1,001 | 17,000 | 45.4 ms |
| typescript | 1,001 | 19,600 | 45.7 ms |
| cpp | 1,001 | 17,200 | 31.3 ms |
| python | 1,001 | 11,800 | 24.9 ms |
| json | 1,001 | 9,400 | 24.6 ms |
| rust | 1,001 | 16,800 | 23.6 ms |
| go | 1,001 | 17,800 | 19.9 ms |
| yaml | 1,001 | 8,200 | 18.4 ms |

言語による差は 2.5 倍程度に収まる。**1000行なら最悪でも 50 ms 前後**。

### 3.9 maintenance / license（GitHub API 実測）

| 項目 | Highlightr | highlight.js |
|---|---|---|
| 最新リリース | **2.3.0 / 2025-06-18** | **11.12.0 / 2026-08-12** |
| その前 | 2.2.1 (2024-07-29), 2.2.0 (2024-06-18), 2.1.2 (**2021-04-22**) | 11.11.2 (2026-06-23), 11.11.1 (2024-12-25), 11.10.0 (2024-07-15) |
| 最終 push | 2026-02-13（コミット内容: "Added Disclaimer"） | 2026-08-14 |
| open issues | 25 | 91 |
| star | 1,868 | 24,979 |
| license | MIT | BSD-3-Clause |
| アーカイブ済み | いいえ | いいえ |

**決定的な事実**: Highlightr の README 冒頭に次の宣言がある `[実測]`。

> # DISCLAIMER
> As of 2026, Highlightr is no longer actively maintained. We recommend using [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) instead.

2026-02-13 の "Added Disclaimer" コミットがこれである。NFR-11 軸1（maintenance）の判定材料としてこれ以上明確なものはない。

なお、同梱 highlight.js 11.10.0 / BSD 3-Clause は **すでに** `[実コード: THIRD_PARTY_LICENSES.md:145-150]` に記載済みで、C を採っても表記義務は増えない。

---

## 4. 推奨案（C）で実装する場合の方針

### 4.1 seam への嵌め方 — **逆写像アダプタは不要**

設計書 §5 D-2 は「Highlightr / highlight.js 系なら `NSAttributedString` の `.foregroundColor` ラン → `FilePreviewTokenRole` への逆写像アダプタが必要になる」としていたが、**`__emitter` を使う C ではこの前提が不要になる** `[実測: §3.2]`。エンジンは scope 名を直接受け取るので、`FilePreviewSyntaxHighlighting` の要求どおり `[FilePreviewHighlightRun]`（`NSRange` + 意味論ロール、色なし）を**そのまま返せる**。自前スキャナ（B）と同じ形で seam に載る。

```swift
// afide-06 で実装する形（骨子。[設計判断]）
actor FilePreviewHighlightJSEngine: FilePreviewSyntaxHighlighting {
    private var context: JSContext?          // 初回 runs(for:) まで生成しない（NFR-03）

    func runs(for text: String, language: String, range: NSRange) async -> [FilePreviewHighlightRun] {
        // 1. 遅延初期化: highlight.min.js（+ dart.min.js）を評価し、__emitter を差し込む
        // 2. hljs.highlight(text, {language, ignoreIllegals: true}) を呼ぶ
        // 3. エミッタが貯めた (location, length, roleID) を Int32Array で受け取り、
        //    JSObjectGetTypedArrayBytesPtr で一括デコードする
        // 4. throws しない。失敗時は [] を返してプレーン表示へ落ちる（§20.8）
    }
}
```

- **座標系**: JS 文字列は UTF-16 なので、エミッタの累積長がそのまま `NSRange` になる。変換不要 `[実測: §3.2]`
- **JS→Swift の受け渡し**: `Int32Array` を返し `JSObjectGetTypedArrayBytesPtr` で生ポインタから読むのが最も安い。`JSValue.toArray()` は要素ごとに `NSNumber` を作るため避ける `[実測]`
- **`range` の扱い**: 契約どおり「交差するトークンだけ返せばよい」ので、エミッタ側の `endScope` で `range` と交差しないランを捨てて転送量を減らす。**ただし計算量は減らない**（§3.3-2）

### 4.2 scope → `FilePreviewTokenRole` の写像

`FilePreviewTokenRole`（7ケース）への割り当て `[設計判断]`。表にない scope は `.plain` に落とす（＝属性を付けない）。

| ロール | hljs scope |
|---|---|
| `keyword` | `keyword`, `variable.language` |
| `string` | `string`, `subst`, `regexp`, `char`, `template-variable`, `code`, `formula` |
| `comment` | `comment`, `doctag`, `quote` |
| `number` | `number`, `literal`, `symbol` |
| `type` | `type`, `title`, `title.class`, `title.class.inherited`, `title.function`, `title.function.invoke`, `built_in`, `class`, `name`, `tag`, `section`, `selector-tag` |
| `attribute` | `attr`, `attribute`, `meta`, `meta.prompt`, `property`, `selector-attr`, `selector-class`, `selector-id`, `selector-pseudo` |
| `plain` | 上記以外（`operator`, `punctuation`, `params`, `variable`, `bullet`, `emphasis`, `strong` …） |

### 4.3 入れ子ランの適用順（**実装上の必須事項**）

エミッタは `endScope` で確定するため、**内側のランが先に出る**。実測例では `[133,1] number`（文字列補間の中の `1`）が `[124,12] string` より先に出た `[実測: §3.2]`。配列順のまま `addAttribute` すると**外側が内側を上書きしてしまう**。

**対策**: `location` 昇順 → `length` **降順**の**安定ソート**を行い、その順で適用する。こうすると内側が最後に適用されて勝ち、ブラウザの CSS 入れ子（内側の `<span>` が勝つ）と同じ見え方になる。同一 range に複数 scope が付く場合（JSON の `true` に `keyword` と `literal` が両方付く例を実測）も、安定ソートで後発が勝ち、ブラウザと一致する `[実測: §3.2]`。

### 4.4 パレットの出所（FR-11）

`FilePreviewHighlightPalette` の色は **同梱 CSS をそのまま出所にする** `[実コード: Resources/markdown-viewer/highlight-github.css, highlight-github-dark.css]`。

| ロール | light（`highlight-github.css`） | dark（`highlight-github-dark.css`） | CSS 上の出所 |
|---|---|---|---|
| `plain` | `#24292e` | `#c9d1d9` | `.hljs` |
| `keyword` | `#d73a49` | `#ff7b72` | `.hljs-keyword` |
| `string` | `#032f62` | `#a5d6ff` | `.hljs-string` |
| `comment` | `#6a737d` | `#8b949e` | `.hljs-comment` |
| `number` | `#005cc5` | `#79c0ff` | `.hljs-number` |
| `type` | `#6f42c1` | `#d2a8ff` | `.hljs-title` / `.hljs-title.class_` / `.hljs-title.function_` |
| `attribute` | `#005cc5` | `#79c0ff` | `.hljs-attr` |
| （背景の基準） | `#fff` | `#0d1117` | `.hljs` の `background` |

**注意点2つ**:

1. GitHub テーマでは `.hljs-attr` と `.hljs-number` が**同じセレクタグループにあり同色**である `[実コード: highlight-github.css の `.hljs-attr,.hljs-attribute,.hljs-literal,.hljs-meta,.hljs-number,.hljs-operator,…{color:#005cc5}`]`。つまり 7 ロールが **6 色**に落ちる。視覚的に分けたい場合、同 CSS 内の `.hljs-built_in`（light `#e36209` / dark `#ffa657`）が未使用の7色目として使える `[設計判断]`
2. この2枚は背景 `#fff` / `#0d1117` を前提に作られている。cmux のエディタ背景は `themeBackgroundColor` 由来で任意の色になりうるため、**light / dark の選択は背景輝度で行う**必要がある（§6 のとおりパレットが `background` から決める）。中間輝度のカスタムテーマでのコントラストは §6 の未確定事項に記録した

### 4.5 FR-03 / NFR-04 への影響

- **`range` クリップでは計算量が減らない**（§3.3-2）ため、NFR-04 の「可視範囲優先」は**転送量の削減としてしか効かない**。実効的な軽量化はデバウンス幅と FR-03 の閾値で行うことになる
- 参考値: 816.5 KB で 1,131.9 ms。iOS 側の閾値 1,500,000 バイト `[実コード: .../ChatArtifactSyntaxHighlightPolicy.swift:5]` をそのまま使うと**最悪ケースで約2秒**の JS 実行になる（線形外挿。`[設計判断]`）。256 KB なら約 350 ms に収まる。数値の決定は未確定-08 / 未確定-05 の範囲なので本 issue では決めない
- NFR-03（未使用時ゼロ負荷）は、`JSContext` と `highlight.min.js` の評価を actor 内で初回 `runs(for:)` まで遅延させることで満たす。iOS 側 `ChatArtifactSyntaxHighlighter` と同じ形 `[実コード: .../ChatArtifactSyntaxHighlighter.swift:14-21]`。評価コストは 8〜15 ms の一度きり `[実測: §3.1]`

---

## 5. 却下した2案の却下理由

### 5.1 選択肢 A（Highlightr）を却下する理由

1. **upstream がメンテナンス終了を宣言している**（README 冒頭、2026-02-13 のコミット）`[実測: §3.9]`。NFR-11 軸1 で落ちる。代替として案内されている HighlighterSwift への乗り換えは、依存を1本増やす点で C に対する優位が何もない
2. **FR-01 AC1 を満たさないテーマがある**。CSS パーサが複合セレクタを含むルールを丸ごと落とすため、`github` では文字列と数値が、`github-dark` ではキーワードが本文色のままになる `[実測: §3.5]`
3. **§6 の seam に載せられない**。設計書が想定した「色 → ロールの逆写像アダプタ」は、色が本文色と衝突するロールがある以上**原理的に成立しない** `[実測: §3.5]`
4. **常に C より遅い**（1.4〜1.5倍）。C と同じ JS を回した上に、生成した HTML を Swift 側で再走査するため `[実測: §3.3]`
5. **upstream 追従コストが3案で最大**。`Package.resolved`（14→15 pin）、`project.pbxproj`（package reference + 2ターゲット）、`THIRD_PARTY_LICENSES.md`（2件追加）に差分が出る。NFR-08 に正面から反する
6. **バンドルが 2.1 MB 増える** `[実測: §3.4]`。しかもその中身は、すでに 124 KB 版を同梱しているのと**同じ highlight.js の別バージョン（11.11.1）フル版**である
7. 実装が `Scanner.scanLocation` / `scanUpTo(_:into:)` という非推奨 API に依存している `[実コード: Highlightr 2.3.0 src/classes/Highlightr.swift processHTMLString]`

**ただし A に対する評価は「技術的に動かない」ではない**。macOS でビルドも実行もでき、192言語をカバーし、`xcode` テーマなら7色に分かれる `[実測: §3.4, §3.5]`。落とす理由はメンテ終了・テーマ欠陥・seam 不適合・追従コストであって、動作不能ではない。

### 5.2 選択肢 B（自前スキャナ）を却下する理由

性能は圧倒的（C の 40〜55倍）で、依存も入力面も増えず、`FilePreviewTokenRole` を直接返せる `[実測: §3.3]`。**技術的には最も筋がよい**。それでも今回は採らない。

1. **実装量が FR-02 の要求に対して見合わない**。今回の計測用に書いた Swift 専用スキャナは約 60 行（キーワード集合 + 4トークン種別 + 型らしき識別子）で、これで **13言語のうち1言語**である。同水準を13言語ぶん用意すると 700〜900 行規模になる `[設計判断: 計測用実装からの外挿であり、実際に13言語を書いて確かめたわけではない]`
2. **言語ごとの落とし穴が多い**。実測用スキャナですら、Swift の複数行文字列（`"""`）、raw string（`#"..."#`）、ネストしたブロックコメント（Swift は入れ子可）を扱えていない。PHP の `<?php` 境界、Markdown の入れ子、YAML の複数行スカラ、C/C++ の行継続（`\` + 改行）などを含めると、正しさの検証コストがハイライトの価値を上回る
3. **同梱 highlight.js を使えば同じ結果がタダで手に入る**。C は依存も追従コストもゼロで13言語（+ dart 2.2 KB）をカバーする。B の唯一の優位は速度だが、**C の 30〜50 ms/1000行はメインアクター外の actor で回る**ため、NFR-04 AC1 / AC3 の観点では十分である
4. **§20.5 の入力面の議論では B が有利**だが、highlight.js は macOS 本体がすでに Markdown プレビューで実行している既存コードであり `[実コード: Resources/markdown-viewer/highlight.min.js, Sources/Panels/MarkdownViewerAssets.swift:24]`、新しい第三者コードの持ち込みではない

**将来の再検討条件**: C の実測（4,475行で 234 ms、816 KB で 1,132 ms）が実機の dogfood で許容できないと判明した場合、B への差し替えは `FilePreviewSyntaxHighlighting` の実装を1本足すだけで済む（§20.3 の拡張性がそのまま効く）。C を選ぶことは B を閉ざさない。

---

## 6. この調査で新たに判明した未確定事項

| # | 内容 | 影響する issue | 扱い |
|---|---|---|---|
| **新規-H** | **`range` へのクリップでエンジンの計算量が減らないことが実測で確定した**（233.9 ms → 231.2 ms）。したがって `FilePreviewSyntaxHighlightController` が**スクロールのたびに `runs(for:language:range:)` を呼ぶと、そのたびに全文を再走査する**。4,475行のファイルで 234 ms ×スクロール回数となり、CPU を焼き続ける。**コントローラは「テキスト世代が変わったときだけ」エンジンを呼び、結果をキャッシュして可視範囲での絞り込みは Swift 側で行う設計にする必要がある** | AFIDE-06 / **AFIDE-07** | 設計書 §7.3 の「スクロール追従で再計算」を見直す必要がある。**本人判断が要る** |
| **新規-I** | dart 文法ファイル（2,216 バイト）の**置き場所**。`Resources/markdown-viewer/` に相乗りすると pbxproj 差分ゼロだが upstream 所有ディレクトリを汚す。fork 独自ディレクトリなら pbxproj に folder reference 4エントリ | AFIDE-06 | `[要確認]` |
| **新規-J** | `__emitter` は **highlight.js の公開 API ではない**（`__` 接頭辞）。11.10.0 / 11.11.1 / 11.12.0 で同一出力を確認済みだが、upstream cmux が同梱アセットを更新した際に壊れる可能性は残る。**回帰テストで固定する必要がある**（既知の入力に対する scope 列を assert する） | AFIDE-06 | テストで担保する方針を推奨。`[設計判断]` |
| **新規-K** | GitHub テーマでは `number` と `attribute` が同色（light `#005cc5` / dark `#79c0ff`）。7ロールが6色に落ちる。視覚的に分けるなら `.hljs-built_in` の色を流用する | AFIDE-05 / AFIDE-08 | `[要確認]`（見た目の好みの問題） |
| **新規-L** | 同梱 CSS は背景 `#fff` / `#0d1117` 前提。cmux の `themeBackgroundColor` は任意色になりうるため、**中間輝度のカスタムテーマでのコントラスト**（FR-11 AC1）が保証されない | AFIDE-08 | `[要確認]`。輝度しきい値による light/dark 二択で足りるかは実機確認が要る |
| **新規-M** | 設計書 §7.2 が複製するとしている iOS 側の55エントリ表のうち、**clojure / elixir / fsharp / gradle / groovy / scala の6言語は同梱ビルドに存在しない**（dart を除く）。表をそのまま複製すると、これらの拡張子で `.highlight(language:)` に落ちたのに何も色が付かない | AFIDE-05 | 表から落とすか、文法ファイルを追加するかの判断が要る。FR-02 の要求外なので**落とす方を推奨** `[設計判断]` |
| **新規-N** | FR-03 の閾値に iOS 側の 1,500,000 バイトをそのまま使うと、最悪ケースで約2秒の JS 実行になる（816.5 KB = 1,132 ms からの線形外挿） | AFIDE-04（既定値）/ AFIDE-07 | 未確定-05 / 未確定-08 の材料として提供。本 issue では決めない |

---

## 7. 調べたが分からなかったこと

1. **実機での体感**。本調査はすべてコマンドラインのスパイクであり、`NSTextView` へ実際に属性を適用したときの描画コスト・スクロール追従の滑らかさは測っていない。NFR-04 AC2（「体感で悪化しない」）の判定はできていない `[要調査: AFIDE-08 の dogfood で確認する]`
2. **`NSTextStorage.addAttribute` 側のコスト**。§3.3 の数値はエンジンが `[FilePreviewHighlightRun]` を返すまでで、`beginEditing()` → 属性適用 → `endEditing()` のコストを含まない。4,475行で 5,401 ラン、18,893行で 22,869 ランを適用する時間は未計測 `[要調査]`
3. **計測値の絶対精度**。計測中、同一マシンで別の Swift ビルドが並走しており load average が 5〜50 で変動した。**案間の相対比較（§3.3 は同一プロセス・同一時刻）は信頼できるが、絶対値には数十%の誤差がありうる** `[実測の限界]`
4. **`ignoreIllegals: true` を外した場合の挙動**。全計測で `ignoreIllegals: true` を使った。false にすると不正な構文でエンジンが例外を投げ、`[]` フォールバック（§20.8）に落ちる頻度が変わるはずだが、その頻度は測っていない `[要調査]`
5. **Highlightr の代替として README が案内する HighlighterSwift の評価**。C を推奨する結論に影響しない（SPM 依存を1本増やす点で C に劣ることが自明）ため、ビルドも実行もしていない `[要調査: 必要になった場合のみ]`
6. **自前スキャナ（B）の 13 言語ぶんの実装規模**。§5.2 の「700〜900行」は Swift 1言語ぶん約60行からの外挿であり、**実際に13言語を書いて確かめたわけではない** `[設計判断]`
7. **`FilePreviewHighlightPalette` の light/dark 判定に使う輝度しきい値**。同梱 CSS が2枚しかないこと以上のことは決めていない `[要調査: AFIDE-05 / AFIDE-08]`

---

## 8. NFR-11 受け入れ条件との対応

| 受け入れ条件 | 状態 |
|---|---|
| 1. 6軸すべてについて候補ごとの評価を書いた比較表を `docs/fork/` に残す | 満たす（§2。6軸 + 追加軸4本、候補3件） |
| 2. 比較表がない状態でライブラリを本体に追加しない | 満たす（本体差分ゼロ。検証は独立 SPM パッケージと一時 probe で行い、いずれも revert 済み） |
| 3. 工数見積もりは比較表の完成後に出す | **未実施**。AFIDE-06 の着手時に出す |
