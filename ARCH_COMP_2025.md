# Falsify × ARCH-COMP 2025 統合検証

## 現在の実装

ARCH-COMP 2025 の対象7モデルについて、Falsifyが生成した**すべての候補入力**を公式モデルで評価します。各episodeでは、入力条件の検査、公式モデルの実行、公式軌跡に対するSTL robustness計算を行います。その公式robustnessを、Falsify既定の指数変換 `exp(-robustness)-1` による終端報酬の入力、最良候補選択、反例発見による早期終了に使用します。

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

各条件で RAND、A3C、ACER、DDQN を扱います。実験結果、標準出力、標準エラー、生トレースは実行環境に保存し、Gitでは管理しません。

## ディレクトリ配置

公式モデルはFalsifyリポジトリへコピーせず、隣接ディレクトリで管理します。既定配置は次のとおりです。

```text
MATLAB/
├── Falsify/
├── ARCH-COMP/
│   └── models/FALS/
└── FalBenchGen/
```

別の配置を使う場合は環境変数で指定できます。

| Environment variable | Meaning |
|---|---|
| `FALSIFY_ARCH2025_OFFICIAL_ROOT` | ARCH-COMP checkout内の `models/FALS` の絶対パス |
| `FALSIFY_ARCH2025_FALBENCH_ROOT` | FalBenchGenルートの絶対パス |
| `FALSIFY_ARCH2025_PYTHON` | ChainerRL環境のPython実行ファイル |
| `FALSIFY_ARCH2025_AT_DATA` | `sldemo_autotrans_data.mat`、またはそれを含むディレクトリの絶対パス |
| `FALSIFY_ARCH2025_GENERATED_DIR` | 生成ラッパーの出力先（並列実行ではワーカーごとに分離） |
| `FALSIFY_ARCH2025_OUTPUT_DIR` | 結果出力先（相対指定はリポジトリ基準） |
| `FALSIFY_ARCH2025_CASE_FILTER` | CaseIDのワイルドカードフィルタ |
| `FALSIFY_ARCH2025_RESUME_PASSED` | `0`で成功済みケースも再実行 |
| `FALSIFY_ARCH2025_REBUILD_WRAPPERS` | `1`で生成ラッパーを再構築 |
| `FALSIFY_ARCH2025_MAX_EPISODES` | 各ケースの最大episode数（正の整数） |
| `FALSIFY_ARCH2025_SEED_OVERRIDE` | 全選択ケースで使うseed（未指定時はCaseIDごとの固定seed） |

Python依存は [requirements-falsify.txt](requirements-falsify.txt) に記載しています。確認済み構成は MATLAB R2026a、Python 3.9.6、NumPy 1.23.5、Chainer 7.8.1、ChainerRL 0.8.0、Gym 0.22.0 です。

ARCH-COMPの公式ATモデル `models/FALS/transmission/Autotrans_shift.mdl` は、MathWorksのSimulink例題「Modeling an Automatic Transmission Controller」に含まれる `sldemo_autotrans_data.mat` をモデル初期化時に読み込みます。この補助ファイルはARCH-COMP checkoutにもFalsifyにも含まれません。MATLAB R2023b以降では、次のコマンドでMathWorksの例題機構からGit管理外の `.deps` へ準備し、現在のMATLABセッションへ場所を設定できます。

```matlab
prepare_arch2025_at_data
```

既にファイルを管理している場合は、`FALSIFY_ARCH2025_AT_DATA` でそのファイルまたは格納ディレクトリを指定できます。補助ファイル自体は本リポジトリでは再配布しません。

公式ARCH-COMP checkoutは変更せずに使用します。NNの公式helperにある行・列方向の不整合とbase workspace初期化、F16同梱AeroBenchVVの設定フィールド名差、SC helperのR2026aにおけるStopTime指定は、Falsify側の公式再生adapterで吸収します。

検証に使用した基準revisionは、ARCH-COMP `5e8f72b8d5f30be002f40ae5df4a8e04d7f64e3c`、FalBenchGen `a6dc83d64e329a6183f910c512fc52ab27a13553` です。

## 実行

既定の隣接配置と `.venv-falsify` を使う場合は、MATLABで次を実行します。

```matlab
validate_arch2025_all
```

ターミナルからは次の形です。

```sh
matlab -batch "validate_arch2025_all"
```

例としてSBだけを再実行する場合は、シェルで次を設定してから起動します。

```sh
export FALSIFY_ARCH2025_CASE_FILTER='sb_*'
export FALSIFY_ARCH2025_RESUME_PASSED=0
matlab -batch "validate_arch2025_all"
```

## 正式実験ランナー

本研究の正式実験は、49条件、4手法、10 SEEDの `1960` 試行です。各試行は最大1500 episodeで、各episodeにつき公式モデルを1回評価します。早期終了が一度もなければ最大評価回数は `1960 × 1500 = 2,940,000` 回です。公式robustnessが負になった試行は、その時点で反例発見として終了します。

1500評価と10反復はARCH-COMP 2025の報告条件に合わせています。SEED値 `20250001`〜`20250010` と、比較対象をRAND、A3C、ACER、DDQNの4手法とする点は本研究の実験設計です。

正式ランナーは、ソースcheckoutと大容量の実験出力を分離します。

```text
experiment-root/
├── src/
│   ├── Falsify/
│   ├── ARCH-COMP/
│   └── FalBenchGen/
├── env/falsify-py39/
├── assets/mathworks/sldemo_autotrans_data.mat
├── build/mex/
├── manifests/formal/trials.csv
├── runs/
├── logs/
└── summaries/
```

依存リポジトリは次のrevisionへ固定します。

```sh
git clone https://gitlab.com/goranf/ARCH-COMP.git "$ROOT/src/ARCH-COMP"
git -C "$ROOT/src/ARCH-COMP" checkout 5e8f72b8d5f30be002f40ae5df4a8e04d7f64e3c

git clone https://github.com/Fenking/FalBenchGen.git "$ROOT/src/FalBenchGen"
git -C "$ROOT/src/FalBenchGen" checkout a6dc83d64e329a6183f910c512fc52ab27a13553
```

Falsifyは対象PRのmerge commitまたは確認対象commitへ固定します。Python環境、`dp_taliro` MEX、1960試行のmanifestは次のように準備します。

```sh
python3.9 -m venv "$ROOT/env/falsify-py39"
"$ROOT/env/falsify-py39/bin/python" -m pip install \
  -r "$ROOT/src/Falsify/requirements-falsify.txt"

matlab -batch "addpath('$ROOT/src/Falsify/arch2025_experiment'); build_arch2025_mex('$ROOT/build/mex')"

mkdir -p "$ROOT/manifests/formal"
"$ROOT/env/falsify-py39/bin/python" \
  "$ROOT/src/Falsify/arch2025_experiment/formal_tools.py" build-manifest \
  --catalog "$ROOT/src/Falsify/arch2025_experiment/catalog.csv" \
  --output "$ROOT/manifests/formal/trials.csv"
```

AT補助データは `prepare_arch2025_at_data` で取得したファイルを指定します。ランナーはファイルを変更せず、開始時にSHA-256を記録します。

```sh
export FALSIFY_ARCH2025_EXPERIMENT_ROOT="$ROOT"
export FALSIFY_ARCH2025_EXPECTED_SHA=使用するFalsifyの完全なcommit_SHA
export FALSIFY_ARCH2025_AT_DATA=/absolute/path/to/sldemo_autotrans_data.mat
export FALSIFY_ARCH2025_WORKER_COUNT=1
export FALSIFY_ARCH2025_CPUS_PER_WORKER=1
bash "$ROOT/src/Falsify/arch2025_experiment/start_parallel_formal_experiment.sh"
```

既定値は1ワーカー、ワーカー当たり1 CPU、CPU固定なしです。ワーカー数はMATLABライセンス、CPU、メモリ、共有サーバの規則を確認したうえで明示的に増やします。各試行は完了マーカーを持ち、完了済み試行を再実行せずに再開できます。標準出力、標準エラー、実行コマンド、環境変数、Git SHA、所要時間、最大メモリ、終了理由は実験ルートへ保存されます。

## モデル固有の接続

- SB: 公式名SB1-SB5を、FalBenchGenの `s1`、`s3`、`s5`、`cc3`、`cc5` にそれぞれ対応付けます。ARCH-COMP 2025ではInstance 2のみを対象とし、4個の制御点を各6秒保持します。SB4とSB5の外側時間区間は公式表どおり `[0,19]` と `[0,17]` です。選択ネットワークは各仕様の `a2_k1_1_4_9_10_0.01_LSTM/*a2_k1_1.mat` です。
- SC: 公式 `steamcondense_RNN_22.slx` の物理サブシステムをラッパーへ直接使用します。Instance 2は35秒を20等分した区分一定入力です。
- F16: 時変入力ではなくroll・pitch・yawの初期条件を探索し、公式AeroBenchVVの非線形ODEを実行します。固定したARCH-COMP revisionでは `getAutopilotCommands.m` がなくHTML化されたソースだけがあり、さらに `getDefaultSettings.m` が返す旧フィールド名と `RunF16Sim.m` が要求する新フィールド名が一致しません。この2点とControl System Toolbox非依存の線形化構造体を `arch2025_compat/f16` に限定して補っています。
- AT / AFC / CC / NN: 公式物理モデルを使う既存ラッパーに、Instanceごとの入力parameterization、ログ、公式再生adapterを追加しています。AT/CCは生成時に公式solver設定をコピーします。NNの正規化状態は `[Ref-2, 0.4*Pos-1]` の順で、公式再生時の入力行列方向と `u_ts` はadapterで設定します。NNは通常のβ=0.03、β=0.04の派生条件 `NNb`、`NNx` を両Instanceで扱います。

生成ラッパーのSimulinkバイナリはローカルパスを含み得るためGit管理せず、検証開始時に `arch2025_generated` へ構築します。

## 判定と既知の注意点

`OfficialRobustness < 0` を公式要求違反、`> 0` を要求成立として記録します。新方式の `FalsifyRobustness` はFalsifyが最小化対象として候補比較に使う値であり、同じepisodeの `OfficialRobustness` と一致します。RL agentへ渡す終端報酬はFalsify既定の `exp(-FalsifyRobustness)-1` です。したがって、robustnessが大きな正値の場合に報酬がほぼ `-1` になるのは本統合が新設した判定規則ではなく、Falsifyの報酬変換です。`WrapperRobustness` は候補生成用wrapper上の診断値です。

早期終了は `OfficialRobustness < 0` の場合だけ発生します。`OverallPass` には、Falsify完走、入力検査、公式評価、評価方式の一致、`OfficialEvaluationCount=Episodes`、Falsify目的値と公式値の一致が必要です。wrapperと公式モデルの軌跡一致は診断列として残しますが、wrapper側の符号は反例判定に影響しません。

PMは固定した公式checkoutにpacemakerモデルがないため対象外です。FIMと他ツールとの性能比較は、この統合の対象外です。
