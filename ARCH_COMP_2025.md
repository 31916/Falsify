# Falsify × ARCH-COMP 2025 統合検証

## 現在の実装

ARCH-COMP 2025 の対象7モデルについて、Falsifyが生成した**すべての候補入力**を公式モデルで評価します。各episodeでは、入力条件の検査、公式モデルの実行、公式軌跡に対するSTL robustness計算を行います。その公式robustnessをFalsifyの終端報酬、最良候補選択、反例発見による早期終了に使用します。

評価方式は結果CSVの `EvaluationProtocol` に次の固定値で記録します。

```text
arch-comp-2025-official-per-episode-v1
```

`OfficialEvaluationCount` は各試行の `Episodes` と同じでなければなりません。Falsify用RL wrapperは候補入力を生成するために残しますが、wrapperのrobustnessと軌跡は診断専用であり、反例判定には使用しません。

| Model | Requirements | Instances | Cases |
|---|---:|---:|---:|
| SB | 5 | 2 | 20 |
| AT | 10 | 1 / 2 | 80 |
| AFC | 3 | 2 | 12 |
| CC | 6 | 1 / 2 | 48 |
| NN | 3 | 1 / 2 | 24 |
| F16 | 1 | 区別なし | 4 |
| SC | 1 | 1 / 2 | 8 |
| **合計** | **49条件** |  | **196** |

各条件で RAND、A3C、ACER、DDQN を扱います。変更後のコードは、まず49条件×4手法×1 episodeの196ケース横断試験で確認してから本実験へ使用します。

### 既存結果の扱い

次の既存ファイルは、変更前の「wrapperで探索し、選択候補だけを公式モデルで事後再生する」方式で作成された履歴です。

- [全ケース結果](results/arch2025/final/arch2025_all_summary.csv)
- [工程別ステータス](results/arch2025/final/arch2025_status.csv)
- [公式モデルで確認した要求違反候補](results/arch2025/final/arch2025_official_violations.csv)
- [集計レポート](results/arch2025/final/arch2025_final_report.txt)

全ケース結果内の `EvaluationTraceFile` / `InputTraceFile` / `StateTraceFile` は、実行時に生成されたローカル証跡へのリポジトリ相対パスです。`EvaluationTraceFile` には全episodeの公式目的robustnessとwrapper診断robustnessを保存します。容量の大きい生トレースはGit管理せず、再実行時に再生成します。

既存の196ケースでは符号判定は196/196件で一致しましたが、軌跡一致は6/196件でした。旧 `OverallPass` は軌跡一致を要求していなかったため、この結果を新しい公式episode評価方式の成功証拠として使用してはいけません。新しい集計・再開処理は、旧方式のCSVや完了マーカーを完了済みとして受理しません。

## ディレクトリ配置

公式モデルはFalsifyリポジトリへコピーせず、隣接ディレクトリで管理します。既定配置は次のとおりです。

```text
MATLAB/
├── Falsify/
└── ARCH-COMP/
    ├── ARCH-COMP-full/models/FALS/
    └── FalBenchGen/
```

別の配置を使う場合は環境変数で指定できます。

| Environment variable | Meaning |
|---|---|
| `FALSIFY_ARCH2025_OFFICIAL_ROOT` | `ARCH-COMP-full/models/FALS` の絶対パス |
| `FALSIFY_ARCH2025_FALBENCH_ROOT` | FalBenchGenルートの絶対パス |
| `FALSIFY_ARCH2025_PYTHON` | ChainerRL環境のPython実行ファイル |
| `FALSIFY_ARCH2025_AT_DATA` | `sldemo_autotrans_data.mat`、またはそれを含むディレクトリの絶対パス |
| `FALSIFY_ARCH2025_OUTPUT_DIR` | 結果出力先（相対指定はリポジトリ基準） |
| `FALSIFY_ARCH2025_CASE_FILTER` | CaseIDのワイルドカードフィルタ |
| `FALSIFY_ARCH2025_RESUME_PASSED` | `0`で成功済みケースも再実行 |
| `FALSIFY_ARCH2025_REBUILD_WRAPPERS` | `1`で生成ラッパーを再構築 |
| `FALSIFY_ARCH2025_MAX_EPISODES` | 各ケースの最大episode数（正の整数） |
| `FALSIFY_ARCH2025_SEED_OVERRIDE` | 全選択ケースで使うseed（未指定時はCaseIDごとの固定seed） |
| `FALSIFY_ARCH2025_FINAL_SOURCE` | 公開用最終表へ採用する完全summary CSV |

Python依存は [requirements-falsify.txt](requirements-falsify.txt) に記載しています。ローカル検証環境は MATLAB R2026a、Python 3.9.6、NumPy 1.23.5、Chainer 7.8.1、ChainerRL 0.8.0、Gym 0.22.0 です。

ATはMathWorksのSimulink例題「Modeling an Automatic Transmission Controller」に含まれる `sldemo_autotrans_data.mat` を必要とします。このファイルは本リポジトリでは再配布しません。MATLABパスまたは現在のreleaseのユーザーExamplesディレクトリから自動検出できない場合は、`FALSIFY_ARCH2025_AT_DATA` で場所を指定してください。

公式ARCH-COMP checkoutは変更せずに使用します。NNの公式helperにある行・列方向の不整合とbase workspace初期化、F16同梱AeroBenchVVの設定フィールド名差、SC helperのR2026aにおけるStopTime指定は、Falsify側の公式再生adapterで吸収します。

### 未修正の公式checkoutによる過去の確認

ARCH-COMP `5e8f72b8d5f30be002f40ae5df4a8e04d7f64e3c` の変更なしcheckoutを使い、旧方式で49条件を4手法・1 episodeで再実行しました。入力検査と公式再生は196/196件で完了しましたが、これは候補選択後の事後確認です。新方式では各episodeで同じ変更なしcheckoutを実行します。

## 実行

既定の隣接配置と `.venv-falsify` を使う場合は、MATLABで次を実行します。

```matlab
validate_arch2025_all
```

ターミナルからは次の形です。

```sh
/Applications/MATLAB_R2026a.app/bin/matlab -batch "validate_arch2025_all"
```

例としてSBだけを再実行する場合は、シェルで次を設定してから起動します。

```sh
export FALSIFY_ARCH2025_CASE_FILTER='sb_*'
export FALSIFY_ARCH2025_RESUME_PASSED=0
/Applications/MATLAB_R2026a.app/bin/matlab -batch "validate_arch2025_all"
```

中断後の再実行では、`OverallPass=true` に加えて、`EvaluationProtocol=arch-comp-2025-official-per-episode-v1` かつ `OfficialEvaluationCount=Episodes` のケースだけをスキップします。旧方式の結果は自動的に再実行対象になります。分割実行結果を最終表へ組み立てる補助スクリプトは [assemble_arch2025_final_results.m](assemble_arch2025_final_results.m) です。

完全な一括runを公開用 `results/arch2025/final` へ反映する場合は、sourceを明示して集計します。

```sh
/Applications/MATLAB_R2026a.app/bin/matlab -batch "setenv('FALSIFY_ARCH2025_FINAL_SOURCE','results/arch2025/all/arch2025_all_summary.csv'); assemble_arch2025_final_results"
```

## モデル固有の接続

- SB: 公式名SB1-SB5を、FalBenchGenの `s1`、`s3`、`s5`、`cc3`、`cc5` にそれぞれ対応付けます。ARCH-COMP 2025ではInstance 2のみを対象とし、4個の制御点を各6秒保持します。SB4とSB5の外側時間区間は公式表どおり `[0,19]` と `[0,17]` です。選択ネットワークは各仕様の `a2_k1_1_4_9_10_0.01_LSTM/*a2_k1_1.mat` です。
- SC: 公式 `steamcondense_RNN_22.slx` の物理サブシステムをラッパーへ直接使用します。Instance 2は35秒を20等分した区分一定入力です。
- F16: 時変入力ではなくroll・pitch・yawの初期条件を探索し、公式AeroBenchVVの非線形ODEを実行します。checkoutに不足するControl System Toolbox非依存の線形化構造体、使用モードのautopilot command関数、設定フィールド名の互換化は `arch2025_compat/f16` に限定して補っています。
- AT / AFC / CC / NN: 公式物理モデルを使う既存ラッパーに、Instanceごとの入力parameterization、ログ、公式再生adapterを追加しています。AT/CCは生成時に公式solver設定をコピーします。NNの正規化状態は `[Ref-2, 0.4*Pos-1]` の順で、公式再生時の入力行列方向と `u_ts` はadapterで設定します。NNは通常のβ=0.03、β=0.04の派生条件 `NNb`、`NNx` を両Instanceで扱います。

生成ラッパーのSimulinkバイナリはローカルパスを含み得るためGit管理せず、検証開始時に `arch2025_generated` へ構築します。

## 判定と既知の注意点

`OfficialRobustness < 0` を公式要求違反、`> 0` を要求成立として記録します。新方式の `FalsifyRobustness` はFalsifyが実際に最適化した値であり、同じepisodeの `OfficialRobustness` と一致します。`WrapperRobustness` は候補生成用wrapper上の診断値です。

早期終了は `OfficialRobustness < 0` の場合だけ発生します。`OverallPass` には、Falsify完走、入力検査、公式評価、評価方式の一致、`OfficialEvaluationCount=Episodes`、Falsify目的値と公式値の一致が必要です。wrapperと公式モデルの軌跡一致は診断列として残しますが、wrapper側の符号は反例判定に影響しません。

PMはローカルcheckoutに公式pacemakerモデルがないため第一段階から除外しています。FIM、複数seed性能比較、他ツール比較にはまだ着手していません。
