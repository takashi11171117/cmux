---
name: Agent-first IDE - 外部エディタへの行番号受け渡し
about: 「このアプリで開く」でカーソル行を渡す。実装を進めながら成立可否を判断し、無理と分かった時点で打ち切る
title: '[AFIDE 14] 外部エディタへの行番号受け渡し（FR-09）'
labels: enhancement, agent-first-ide, afide-14, external-editor
assignees: ''
---

## 🎯 目的

File Preview / Markdown のエディタから外部エディタを開くとき、ファイルパスに加えて**現在のカーソル行**を渡す。

**この issue は「実装して差分を見てから判断する」方針で進める。** 差分が大きすぎる、または構造的に無理と分かった時点で**報告して打ち切る**（FR-09 を MVP から外す判断になる）。

## 📊 背景

### 未解決の構造的ギャップ（FR-09 の本丸）

外部起動の入口は少なくとも5つあり、2系統に分かれている。

- `FileExternalOpenAction.open(fileURL:applicationURL:)` / `openDefault(fileURL:)` 系（LaunchServices）: File Preview ヘッダの共有メニュー / File Explorer のコンテキストメニュー / File Explorer ダブルクリック（`.defaultEditor`）
- `PreferredEditorService.open(_:)` 系: File Explorer ダブルクリック（`.preferredEditor`）/ ターミナル Cmd-click のフォールバック

**カーソル行を持つのは File Preview / Markdown のエディタだけ**だが、そのヘッダメニューは `FileExternalOpenAction`（LaunchServices）にしか繋がっておらず、`PreferredEditorService` を経由しない。一方 `PreferredEditorService` の呼び出し元はカーソル行を持たない経路ばかりである。

つまり**「行番号を渡せる経路」と「行番号を持っている入口」が現状では交わっていない**。

### `OpenConfiguration.arguments` は使えるか（口はある。ただし信頼できない）

`NSWorkspace.OpenConfiguration` には `arguments: [String]` が**存在する**（「LaunchServices には引数を渡す口が構造的に無い」は誤り）。ただしヘッダ自身が「**新しいアプリインスタンスが作られるときに渡す引数**」と定めており、既存実装は `configuration.createsNewApplicationInstance = false` を明示している。**エディタが既に起動していれば引数は無視され、起動していなければ渡る — 同じ操作で挙動が変わる。**

FR-09 受け入れ条件2（指定行にカーソルが立つ）を「アプリが起動済みかどうかで変わる」形で満たすことはできない。詳細設計は `arguments` を**使わず** `preferredEditor` 経路に限定する案を仮採用している。

## ✅ タスクリスト

### 判断ポイント（新規-G。**この2つの許可が要る**）

- [ ] 1. **下位パッケージ `CmuxWorkspaces` の public API を1メソッド増やしてよいか**を、実装した差分を見たうえで判断する
- [ ] 2. **File Preview ヘッダの共有メニューに `preferredEditor` 経路の項目を足してよいか**を、実装した差分を見たうえで判断する
- [ ] **どちらも「否」なら FR-09 は実装できない。** その場合は FR-09 を MVP から外すことを報告する
- [ ] **差分が大きすぎる／構造的に無理と分かった時点で、そこまでの調査結果を添えて報告し打ち切る。** 無理に完成させない

### 実装（`Packages/macOS/CmuxWorkspaces/.../FileOpen/PreferredEditorService.swift`）

- [ ] `public func open(_ url: URL, line: Int?)` を追加し、既存 `open(_ url: URL)` はそれへ委譲する（`open(url, line: nil)`）
- [ ] **`FileOpening` プロトコルは変更しない。** 追加メソッドはプロトコル要件にしない。これで既存 consumer（terminal cmd-click / settings-file shortcuts / sidebar config opener）が無変更で通る
- [ ] **app target の型を引数にしない。** 下位パッケージは app target を import できないため、渡すのは `URL` と `Int?` という素の値だけ
- [ ] **`FileExternalOpenAction` のシグネチャは変更しない。** LaunchServices 経路は行番号を持たないまま従来どおり動かす

### 実装（app target）

- [ ] `Sources/Panels/FilePreviewExternalOpenLocation.swift` — `struct { fileURL: URL; line: Int? }`（1 始まり。`nil` は行指定なし＝従来挙動）。app target 内でのみ使う
- [ ] カーソル行は `textView.selectedRange().location` から求める。**`FilePreviewLineIndex` には依存させない**（行番号設定がオフのときインデックスは構築されないため）。`(textView.string as NSString)` に対する単発の走査で、メニューを開くという明示操作1回につき O(N) が1度だけ走る形にする。**インデックスが既にある場合はそれを使ってよいが、無い場合のフォールバックが正**
- [ ] ヘッダの共有メニューから `preferredEditor` 経路へ繋ぐ（判断ポイント2）

### シェルインジェクション対策（新規-E。プレースホルダを導入する場合の必須制約）

- [ ] 既存実装はパスを必ずシェルクォートしている（`process.arguments = ["-c", "\(command) \(url.path.posixShellSingleQuoted)"]`）。**`{file}` を素朴に文字列置換するとこの安全策が失われ、`'` を含むファイル名で `/bin/sh -c` へのコマンドインジェクションが成立する**
- [ ] **`{file}` は置換後も必ず `posixShellSingleQuoted` を通した文字列にする**（置換値をクォート済みの文字列にする、が正）
- [ ] **`{line}` は `Int` に限定し、文字列を受け付けない**（`Int` を `String(describing:)` した値だけを埋める）
- [ ] `app.preferredEditor` にプレースホルダ（`{file}` / `{line}`）を導入するか、既知コマンド名から形式（`code --goto <file>:<line>` / `xed --line <n> <file>`）を推定するかを決め、根拠を PR 説明に書く
- [ ] 対応 CLI が PATH にない場合のフォールバックを確認する（`PreferredEditorService` は既に非0終了時にシステム既定へフォールバックする）

### テスト（`cmuxTests/FilePreviewExternalOpenLocationTests.swift`）

- [ ] カーソル位置 → 行番号の変換が **`FilePreviewLineIndex` の有無に依存しない**こと（行番号設定オフでも同じ行番号が出る）
- [ ] `line == nil` のとき `PreferredEditorService.open(_:)` と**同じコマンド文字列**で起動すること（記録用の `SystemFileOpening` / `PreferredEditorReading` スタブで検証）
- [ ] `line != nil` でもパスが `posixShellSingleQuoted` を通っていること（**シェルインジェクション対策の固定**）
- [ ] `'` を含むファイル名でコマンドが壊れない／インジェクションが成立しないこと
- [ ] 行番号を渡せないアプリ（LaunchServices 経路）を選んだ場合でも従来どおりファイルが開くこと（FR-09 受け入れ条件1 の回帰）
- [ ] 新規テストファイルに **pbxproj の2エントリ**（`PBXFileReference` / `PBXSourcesBuildPhase`）を追加し `./scripts/lint-pbxproj-test-wiring.sh` を通す
- [ ] `Sources/Panels/FilePreviewExternalOpenLocation.swift` に pbxproj 4エントリ

### ビルド確認・dogfood

- [ ] `./scripts/reload.sh --tag agent-first-ide --launch`（**素の `xcodebuild` / untagged ビルド禁止**）
- [ ] 対応エディタで指定行にカーソルが立つこと（FR-09 受け入れ条件2）
- [ ] 非対応エディタでも従来どおり開くこと（受け入れ条件1）
- [ ] `scripts/test-unit.sh` / `./scripts/check-pbxproj.sh`

## 📦 成果物

- [ ] **判断1・判断2 の結論**（許容する / しない）と、その判断の根拠になった実差分
- [ ] （許容する場合）`PreferredEditorService.open(_:line:)` と app target 側の受け渡し経路
- [ ] （許容する場合）シェルクォート制約が効いていることを固定するテスト
- [ ] （打ち切る場合）**どこまで実装して何が障害だったかの報告**と、FR-09 を MVP から外す提案
- [ ] いずれの場合も `FileOpening` プロトコルと `FileExternalOpenAction` に差分が**無い**こと

## 📝 備考

- **破壊的変更の可能性あり**: 下位パッケージ `CmuxWorkspaces` の public API に1メソッド追加（P-5 のはみ出し。詳細設計 §18.4 に記録済み）。`open(_:)` は複数 consumer が呼ぶ中心 API なので upstream 追従時にコンフリクトしやすい
- ヘッダメニューへの項目追加は NFR-14（常時表示 UI を増やさない）には触れないが、**メニュー意味論の変更**である
- **この issue は他のどの issue のブロッカーでもない。** 打ち切っても afide-01〜13 の成果は影響を受けない

## 🔗 関連

- 依存: **afide-02 完了後に着手**（他の feature issue とは独立。並行可）。afide-09 / afide-10（行番号）には**依存しない**（カーソル行をインデックス非依存で求める設計のため）
- 由来: FR-09（外部エディタへの行番号受け渡し）、D-04（外部インターフェース）、NFR-08
- 設計書: `docs/fork/03_詳細設計.md` §10.2、§16.2、§18.4、§20.1、§20.3、新規-E、新規-G
- 未確定事項:
  - **新規-G は「実装して差分を見てから判断する」方針が決まっている。実装を進めながら判断し、差分が大きすぎる／構造的に無理と分かった時点で報告して打ち切ること。**
  - 未確定-04（外部エディタへの行番号の渡し方）と新規-E（`OpenConfiguration.arguments` を併用するか / プレースホルダか既知コマンド推定か）は**実装中に判断してよい**。採った案と根拠を PR 説明に書く
