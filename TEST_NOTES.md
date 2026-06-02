# StringTie UCRT64 問題点とパッチ記録

日付: 2026-06-02

## 解決済み (2026-06-02 追記): guided / nascent 出力の非決定性

「残っている問題」に挙げていた guided / nascent-aware 系の出力揺れ・期待値不一致は **根本原因を特定し修正済み**。同梱テスト #1〜#9 すべてが、複数回実行で**完全に決定的**かつ**期待値GTFと完全一致**するようになった（release -O3 / マルチスレッドビルドで確認）。配布バイナリ `dist/stringtie-3.0.3-windows-ucrt64/stringtie.exe` も更新済み。

- 真因: `gclib/gff.h` の `GffObj` で、`gff_level:4` と `flag_USER_FLAGS:8`（共に `unsigned int` ビットフィールド）が、直前の `bool` ビットフィールド群とは別の格納ユニットに割り付けられるため、`flags=0`（32bit）でゼロ初期化されない。MinGW/UCRT の `operator new` は確保メモリをゼロ化しないので、これらは実行ごとに異なるゴミ値になる（Linux は新規ページがゼロなので顕在化しない）。
- 影響: `gff_level` はガイドの位置ソート `gfo_cmpByLoc` に使われ、同一座標のガイドの順序が毎回変わる → `keepguides` 順 → アセンブリ全体が非決定化。`flag_USER_FLAGS` は `getGuideStatus()` / `isNascent()` の実体で、ガイド/ナセント判定が毎回変わる。
- 修正: `gff.cpp` のパース用コンストラクタ2つ（`GffObj(GffReader&,GffLine&)` / `(…,BEDLine&)`）と `gff.h` のコンストラクタ2つで、`flags=0` の直後に `gff_level=0; flag_USER_FLAGS=0;` を明示的に追加（`PATCHES.md` 参照）。スレッド競合・未初期化ヒープ全般・アドレス依存などは切り分けで除外済みで、この1点が唯一の原因だった。

以下は調査当時の記録（経緯として保持）。

## 要約

この文書で扱う問題は、StringTieに同梱されているテストデータをMSYS2 UCRT64環境で実行して判明・再現・確認したものです。単なるコードレビュー上の推測ではなく、付属テストの実行結果を起点に整理しています。

同梱テストの実行で確認した問題は、大きく分けて次の4つです。

1. 付属 test #9 (`--nasc`) で segmentation fault または異常終了が出ていた。
2. Windows環境ではCRLFにより、単純な `diff` では失敗に見える差分があった。
3. クラッシュ修正後も、guided / nascent-aware 系の期待値差分と実行間の出力揺れが残っている。
4. test #9 の調査中に、UCRT64/MinGW では `drand48` が使えないため、htslib側の `HAVE_DRAND48` 判定をWindows向けに正す必要があることを確認した。

現在の状態:

- `make release` は MSYS2 UCRT64 で成功する。
- 配布用バイナリは `dist/stringtie-3.0.3-windows-ucrt64/stringtie.exe` に更新済み。
- test #9 の segmentation fault は現在再現していない。
- test #9 は `exit=0` で終了するが、期待値GTFとはまだ一致しない。

## 問題とパッチの対応

この表の「元の問題」は、同梱テストの実行と、その失敗原因を追ったビルド・実行確認で判明した内容です。

| 元の問題 | 入れたパッチ | 現在の状態 |
|---|---|---|
| UCRT64/MinGW に `drand48` がない | htslibで `HAVE_DRAND48` を定義せず、bundled `os/rand.c` fallbackを使う | 解決 |
| `--nasc` でparent guide / parent intronが存在しないnascentを無条件参照する可能性がある | `rlink.cpp` の nascent parent-intron coverage ガード | #9クラッシュ解消の主因 |
| 同じbundle内でsynthetic nascent guideが重複生成される可能性がある | `stringtie.cpp` で `generateAllNascents()` 後に `bundle_last_kept_guide=-1` | 重複生成を防止 |
| 終了時にsynthetic nascent guideの所有権が重なり、MinGWのheap cleanupで落ちる可能性がある | `stringtie.cpp` で `synrnas` を非所有にしてから `refguides.Clear()` | 終了時クラッシュ対策 |
| CRLF差でテスト差分が出る | 比較時に `diff --strip-trailing-cr -I "^#"` を使用 | 判定方法で対応 |
| guided / nascent-aware 系のGTF本文が期待値と一致しない | 未解決。順序依存性の追加調査が必要 | 残課題 |

## #9 のクラッシュはどのパッチで解決したか

test #9 は次のコマンドです。

```bash
stringtie --nasc -G mix_guides.gff -o mix_short_nasc_guided.out.gtf mix_short.bam
```

このクラッシュを直接解消した可能性が最も高いのは、`rlink.cpp` の nascent parent-intron coverage ガードです。

理由は、`--nasc` の処理中に次の前提が元コードにあったためです。

- synthetic nascent には必ずparent guideがある
- parent guide側には、nascent末端の次に来るexonが必ずある
- その間のparent intron coverageを必ず計算できる

しかし、実際には terminal nascent や orphan synthetic nascent ではこの前提が崩れます。元コードは `nascentFrom()` の戻り値や次exonの存在を確認せずに参照していたため、NULL参照、範囲外参照、または `GError()` による異常終了につながる可能性がありました。

入れたパッチでは、coverage補正を次の条件を満たす場合だけ実行します。

- `nascentFrom()` がparent guideを返す
- parent guide上で、補正に使う次exonが存在する

したがって、#9の実行中クラッシュに対する主修正はこのパッチです。

一方で、`stringtie.cpp` の shutdown ownership guard も #9 の安定化に関係します。もしクラッシュが「GTF出力後、プロセス終了時」に起きていた場合は、こちらのパッチが直接効いた可能性があります。今回の検証では、個別パッチごとの単独ビルドで切り分けたわけではないため、厳密には次の整理になります。

- 実行中のnascent処理で落ちる問題: `rlink.cpp` の parent-intron coverage guard が主因修正
- 出力後の終了処理で落ちる問題: `stringtie.cpp` の shutdown ownership guard が対策
- 重複生成による不安定化: `stringtie.cpp` の nascent guide generation guard が対策

## 各パッチの詳細

### 1. htslib drand48 fallback

対象: `stringtie-3.0.3.offline-patch/htslib/Makefile`

#### 元の問題

UCRT64/MinGW には `drand48` 系関数がありません。そのため、`HAVE_DRAND48` が定義された状態でビルドすると、存在しない関数を使う前提になります。

#### 入れたパッチ

MSYS2 UCRT64/MinGW では `HAVE_DRAND48` を定義しないようにしました。これにより htslib は同梱の `os/rand.c` fallback を使います。

#### 解決したこと

UCRT64/MinGW で自然な形で乱数fallbackが使われます。これはtest #9クラッシュの直接原因ではなく、htslibビルド/実行環境の前提を正す修正です。

### 2. nascent guide generation guard

対象: `stringtie-3.0.3.offline-patch/stringtie.cpp`

#### 元の問題

`generateAllNascents()` を一度呼んだあとも `bundle_last_kept_guide` が残るため、同じbundle内でread処理が進むたびに、同じguide群からsynthetic nascent guideを再生成する可能性がありました。

これにより次の問題が起こり得ます。

- synthetic nascent guideの重複
- `-N` / `--nasc` の候補数や選択順の不安定化
- 後段のguide処理で想定外の状態が増える

#### 入れたパッチ

`generateAllNascents()` の直後に `bundle_last_kept_guide=-1` を設定しました。

#### 解決したこと

同じguide群からsynthetic nascent guideを繰り返し生成しないようにしました。これはクラッシュそのものよりも、`-N` / `--nasc` の内部状態を安定させるための修正です。

### 3. nascent parent-intron coverage guard

対象: `stringtie-3.0.3.offline-patch/rlink.cpp`

#### 元の問題

`guides_pushmaxflow_onestep()` の `nasc` 処理では、synthetic nascent の最後のexon coverageを補正するため、parent guideのintron coverageを参照します。

元コードは、次の状態を無条件に仮定していました。

- `nascentFrom(guides[ng])` が必ず有効なparent guideを返す
- parent guideに、nascent末端の次に来るexonが存在する

しかし、terminal nascent や orphan synthetic nascent ではこの前提が成立しません。この場合、NULL参照、範囲外参照、または `GError()` による異常終了が起こり得ます。

#### 入れたパッチ

coverage補正処理を次の条件でガードしました。

- `refg` がNULLではない
- 計算対象のparent intronが存在する、つまり `i>0 && i<refg->exons.Count()`

条件を満たさない場合は、補正をスキップします。

#### 解決したこと

test #9 (`--nasc`) の segmentation fault / 異常終了を解消した主修正です。

### 4. shutdown ownership guard

対象: `stringtie-3.0.3.offline-patch/stringtie.cpp`

#### 元の問題

synthetic nascent guide は、処理中に `keepguides` や `refguides[i].synrnas` から参照されます。終了時にこれらの所有権が重なると、MinGW環境でheap cleanupや `GffNames` 参照解放のタイミングにより、出力後に落ちる可能性があります。

#### 入れたパッチ

終了時に次を行うようにしました。

- `refguides[i].synrnas.setFreeItem(false)` でsynthetic nascent追跡リストを非所有にする
- `gffnames_unref(gseqNames)` の前に `refguides.Clear()` を実行する

#### 解決したこと

GTF出力後、プロセス終了時のMinGW heap cleanup / 参照解放に由来するクラッシュを避けます。#9のクラッシュが出力後に起きていた場合は、このパッチが直接効いた可能性があります。

## テスト方法

問題の確認は、付属テストデータを MSYS2 UCRT64 で実行して行いました。特に、#9 のクラッシュ、CRLFによる見かけ上の差分、guided / nascent-aware 系のGTF本文差分は、この同梱テスト実行で判明しました。

比較には次を使いました。

```bash
diff --strip-trailing-cr -I "^#" -u expected.gtf actual.gtf
```

この比較では次を無視しています。

- CRLF と LF の違い
- コマンドラインヘッダの違い
- StringTie versionヘッダの違い

したがって、この条件でも `diff=1` になる場合は、単なるCRLFやヘッダ差ではなく、GTF本文の差分です。

## cleanup前の最終テスト結果

すべてのコマンドは `exit=0` で終了しました。

| test | command summary | exit | CRLF/header無視後のdiff |
|---|---|---:|---:|
| short_reads | `stringtie -o short_reads.out.gtf short_reads.bam` | 0 | 0 |
| short_reads_and_superreads | `stringtie -o short_reads_and_superreads.out.gtf short_reads_and_superreads.bam` | 0 | 0 |
| short_guided | `stringtie -G mix_guides.gff -o short_guided.out.gtf mix_short.bam` | 0 | 1 |
| long_reads | `stringtie -L -o long_reads.out.gtf long_reads.bam` | 0 | 0 |
| long_reads_guided | `stringtie -L -G human-chr19_P.gff -o long_reads_guided.out.gtf long_reads.bam` | 0 | 0 |
| mix_reads | `stringtie --mix -o mix_reads.out.gtf mix_short.bam mix_long.bam` | 0 | 0 |
| mix_reads_guided | `stringtie --mix -G mix_guides.gff -o mix_reads_guided.out.gtf mix_short.bam mix_long.bam` | 0 | 1 |
| mix_short_N_guided | `stringtie -N -G mix_guides.gff -o mix_short_N_guided.out.gtf mix_short.bam` | 0 | 1 |
| mix_short_nasc_guided | `stringtie --nasc -G mix_guides.gff -o mix_short_nasc_guided.out.gtf mix_short.bam` | 0 | 1 |

## oracleとの差分量

ここでの oracle は、同梱テストの `*.out_expected.gtf` です。dist版バイナリの出力と比較しました。

まず、コメント行とCRLF差を除き、GTF本文の行全体を完全一致で比較すると次の結果です。

| test | oracle行数 | 実出力行数 | 完全一致行数 | oracleのみ | 実出力のみ |
|---|---:|---:|---:|---:|---:|
| short_reads | 56 | 56 | 56 | 0 | 0 |
| short_reads_and_superreads | 55 | 55 | 55 | 0 | 0 |
| short_guided | 90 | 81 | 0 | 90 | 81 |
| long_reads | 56 | 56 | 56 | 0 | 0 |
| long_reads_guided | 61 | 61 | 61 | 0 | 0 |
| mix_reads | 98 | 98 | 98 | 0 | 0 |
| mix_reads_guided | 124 | 62 | 0 | 124 | 62 |
| mix_short_N_guided | 72 | 38 | 0 | 72 | 38 |
| mix_short_nasc_guided | 351 | 330 | 0 | 351 | 330 |

完全一致で `0` になっている4件は、座標だけでなく `transcript_id`、`gene_id`、`cov`、`FPKM`、`TPM` などの属性値も含めて1行全体を比較しているためです。構造がまったく一致しないという意味ではありません。

属性とsource列を除き、`seqname`、feature種別、start、end、strand で構造レベルの一致を見た場合は次の通りです。

| test | oracle構造数 | 実出力構造数 | 共通構造数 | oracle再現率 | 実出力精度 | oracleのみ | 実出力のみ |
|---|---:|---:|---:|---:|---:|---:|---:|
| short_guided | 90 | 81 | 81 | 90.0% | 100.0% | 9 | 0 |
| mix_reads_guided | 124 | 62 | 59 | 47.6% | 95.2% | 65 | 3 |
| mix_short_N_guided | 72 | 38 | 38 | 52.8% | 100.0% | 34 | 0 |
| mix_short_nasc_guided | 351 | 330 | 330 | 94.0% | 100.0% | 21 | 0 |

つまり、oracleとの差は主に「oracleにある構造が実出力に出ていない」方向です。実出力側に余分な構造が出ているのは `mix_reads_guided` の3構造だけです。差が最も大きいのは `mix_reads_guided` と `mix_short_N_guided` で、oracle構造の再現率がそれぞれ47.6%と52.8%に下がっています。

## test #9 の現在の確認結果

現在のdist版バイナリで直接確認しました。

```bash
../../dist/stringtie-3.0.3-windows-ucrt64/stringtie.exe \
  --nasc -G mix_guides.gff \
  -o /c/tmp/stringtie-test9-check.gtf \
  mix_short.bam
```

結果:

```text
test9_exit=0
test9_diff=1
```

結論:

- segmentation fault は解消したと見てよい。
- 期待値とのGTF本文差分はまだ残っている。

## 残っている問題

### guided / nascent-aware 系の出力差

同梱テストを実行した結果、CRLFとヘッダ行を無視しても、次のテストは期待値と一致しません。

- `short_guided`
- `mix_reads_guided`
- `mix_short_N_guided`
- `mix_short_nasc_guided`

これは、単なる改行コード差ではなく、GTF本文の差分です。

### `-N` / `--nasc` の出力揺れ

同梱テストの `-N` と `--nasc` ケースを複数回実行すると、行数や内容が変わることがありました。一方で、終了コードは `0` でした。

このため、現時点の残課題はクラッシュではなく、アルゴリズム内部の順序依存性と考えられます。

診断用に `-ftrivial-auto-var-init=zero` を付けたビルドも試しましたが、`-N` / `--nasc` の出力揺れは消えませんでした。単純な未初期化stack変数だけが原因である可能性は低いです。

また、`-p 1` を完全同期処理にする試験パッチも試しましたが、guided / nascent系の差分を安定して解消できませんでした。そのため、この挙動変更は採用していません。

## 残課題の推定原因

残っている不安定性は、guided / nascent assembly 内部の順序依存性が原因である可能性が高いです。候補は次の通りです。

- 同順位のsort比較で `0` が返り、stableなtie-breakerがない
- pointer順に依存した処理
- hashのiteration / insertion順が後続のgraphやguide選択に影響している
- nascent guide生成とguide abundance rankingの組み合わせで、等価候補の選択順が変わる

これは、今回の `drand48` / htslib build問題やCRLF問題とは別の問題です。

## cleanup状態

確認後に次を実行しました。

- source treeで `make clean-all`
- 生成された htslib/lzma ファイルとテスト `.gtf` 出力を `git clean` で削除
- 比較用worktree `C:/tmp/stringtie-head` を削除
- test #9確認用の一時出力 `C:/tmp/stringtie-test9-check.gtf` を削除

現在、意図して残っている変更は次のファイルです。

- `PATCHES.md`
- `stringtie-3.0.3.offline-patch/stringtie.cpp`
- `stringtie-3.0.3.offline-patch/rlink.cpp`
- `TEST_NOTES.md`
