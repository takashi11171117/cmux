# AFIDE-13 調査結果: Compare の実現方式

- 対象 issue: [`afide-13_compare-decision.md`](./afide-13_compare-decision.md)
- 由来: FR-08（Compare の実体）、FR-07 受け入れ条件1、未確定-03、新規-D
- 調査日: 2026-08-17 / HEAD `e168d155d4`
- 本体差分: **なし**（コードは読んだだけ）

出所表記は `[実コード: path:line]` / `[要調査]` を用いる。

---

## 1. 結論

**(i) 既存 Diff Viewer に `.patch` で渡す方式は成立する。** マニフェストはアプリ側から書ける形式で、セキュリティ上の最大の懸念だった trusted root のパーミッションは**既に対処済み**だった。

ただし **Compare を今すぐ実装することは推奨しない**。理由は §5。

---

## 2. マニフェストの契約（(b) の答え）

`Native/DiffSidecar`（Rust）が中核だが、**マニフェストは単純な JSON で、アプリ側から直接書ける** `[実コード: Packages/macOS/CmuxBrowser/Sources/CmuxBrowser/DiffViewer/CmuxDiffViewerSessionPreparer.swift の prepareFromManifest]`。

- 置き場所: `<trusted root>/.manifest-<token>.json`
- 形式（`snake_case` のキー名に注意）:

```json
{
  "token": "<token>",
  "files": [
    {
      "request_path": "/diff.patch",
      "file_path": "/tmp/cmux-diff-viewer-<uid>/diff.patch",
      "mime_type": "text/x-diff",
      "remote_url": null
    }
  ]
}
```

検証される条件 `[実コード: 同ファイル]`:

| 条件 | 内容 |
|---|---|
| token | `isValidToken` を満たし、マニフェスト内の `token` と一致すること |
| `remote_url` | **`nil` でなければ拒否**（ローカル専用） |
| `file_path` | 空でないこと。trusted root の**内側**であること |
| MIME | `text/html` / `text/javascript` / `text/x-diff` の3種のみ |
| 拡張子と MIME の一致 | `text/x-diff` は `.patch` のみ `[実コード: 同:295-306]` |
| ファイル数 | `maximumRegisteredFiles` 以下 |

したがって **Rust sidecar を起動せずに、アプリが JSON を1本書くだけでファイルを登録できる**。

---

## 3. セキュリティ制約の判定（(c) の答え）

新規-D が必須条件として挙げた4点のうち、**1点目は既に満たされていた**。

| # | 制約 | 判定 |
|---|---|---|
| 1 | root を `0700` で作る | ✅ **既に対処済み**。`prepareRootDirectory()` が `attributes: [.posixPermissions: 0o700]` で作り、さらに `setAttributes` で既存ディレクトリにも `0700` を強制する `[実コード: Sources/Panels/DiffSidecarBridge.swift:458-468]` |
| 2 | `.patch` を `0600` で作る | ⬜ 未対処。Compare を実装するなら書き出し時に指定が要る |
| 3 | 確実な unlink | ⬜ 未対処。「パネル close」「衝突の解決」「アプリ終了」の3経路すべてで消す必要がある |
| 4 | 24時間セッションとの整合 | ⬜ 未検証。`maxSessionAge = 24 * 60 * 60` `[実コード: Sources/Panels/CmuxDiffViewerURLSchemeHandler.swift:33]` |

> **設計書の訂正**: 03_詳細設計 §9.4 と §20.5 は「trusted root の検証は `lstat` でディレクトリと uid しか見ておらず mode を検証していないので、root が `0755` で作られていれば同一マシンの他ユーザーから未保存内容が読める」と書いている。**検証側が mode を見ないのは事実だが `[実コード: CmuxDiffViewerSessionPreparer.swift の validatedCanonicalRoot]`、作成側が `0700` を強制しているため実害は無い。** 新規-D の必須条件1は「満たすべき」ではなく「既に満たされている」。

---

## 4. `.patch` を置く実験について

**実施していない** `[要調査]`。実験にはアプリを起動して WebView を動かす必要があり、それ自体が dogfood 相当の作業になる。§2 でマニフェスト契約が確定し、§3 でセキュリティ条件が確定したので、**実装に着手する判断には足りている**と考える。実験は実装時の最初のステップとして行うのが妥当。

---

## 5. 判断: Compare は当面実装しない（(iii) 相当）

方式 (i) は技術的に成立する。それでも今は実装しない方がよいと考える理由:

1. **Compare が無くても FR-07 の目的は満たされている。** 目的は「外部変更を検出したとき人間の編集中内容を勝手に消さない」（REQ-09）で、Reload / Keep Mine の2択で達成済み。Compare は「消さない」ためではなく「決めやすくする」ための補助である
2. **平文の書き出しという新しいリスク面を、補助機能のために開く。** `.patch` にはディスク側の内容と未保存バッファの**両方が平文で載る**。root は `0700` だが、書き出し・unlink・24時間セッションの3点は新規に正しく実装する必要がある
3. **cmux にはもっと直接的な差分の見方がある。** ユーザーは Keep Mine を選んでから、通常の Diff Viewer やターミナルで確認できる。バナーは「どちらを残すか」を聞く場所であって、差分ビューアである必要はない
4. **AFIDE-12 は既に動いている。** Compare を待つとマージが止まる

## 6. 「2択で先行リリースしてよいか」

**技術的には問題ない。ただしこれは本人判断が要る。**

02_要件定義 FR-07 の受け入れ条件1 は「Reload / Compare / Keep Mine の**3択**が提示される」と書いている。2択で確定するなら、**要件定義側を修正する必要がある**（要件を満たさないまま実装を完了扱いにしない）。

修正するなら FR-07 AC1 を次のように改める案:

> 1. 未保存の編集がある状態でファイルを外部から書き換えると、Reload / Keep Mine の2択が提示される。Compare は将来の拡張とし、`FilePreviewSaveConflictResolution` にケースだけを保持する。

現状のコードは `.compare` を enum のケースとして持ち、`resolve(.compare:)` は pending を保持したまま何もしない `[実コード: Sources/Panels/FilePreviewSaveConflictCoordinator.swift]`。UI にボタンは出していないので、ユーザーから見て中途半端な状態は存在しない。

---

## 7. 後続に必要なタスク（(i) を採る場合）

決定が (i) に変わった場合に必要なもの:

1. unified diff の生成（ディスク側とバッファの両方がメモリにあるので I/O は不要）
2. `.patch` を trusted root 内へ `0600` で書き出す
3. マニフェスト JSON を `.manifest-<token>.json` として書く（§2 の形式、`snake_case`）
4. token の発行方法を既存経路と揃える `[要調査: 誰が token を発行しているか未確認]`
5. unlink を3経路（パネル close / 衝突の解決 / アプリ終了）に配線
6. 24時間セッションとの整合確認
7. `.patch` の内容が平文であることを踏まえたテスト（パーミッション、削除）
