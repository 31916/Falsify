# Falsify × ARCH-COMP 2025 統合検証

## 現在の成果

ARCH-COMP 2025 の対象7モデルについて、Falsifyで候補入力を生成し、入力条件の検査後に同一入力を公式モデルへ再投入して公式STL robustnessを計算する経路を実装しました。

| Model | Requirements | Instances | Cases | Validated |
|---|---:|---:|---:|---:|
| SB | 5 | 1 | 20 | 20 |
| AT | 10 | 1 / 2 | 80 | 80 |
| AFC | 3 | 2 | 12 | 12 |
| CC | 6 | 1 / 2 | 48 | 48 |
| NN | 2 | 1 / 2 | 16 | 16 |
| F16 | 1 | 区別なし | 4 | 4 |
| SC | 1 | 1 / 2 | 8 | 8 |
| **合計** | **47条件** |  | **188** | **188** |

各条件で RAND、A3C、ACER、DDQN を1 episodeずつ実行しています。全188件で次を確認済みです。

1. Falsifyシミュレーション完走
2. 実際の入力の取得
3. 公式入力範囲とInstance構造への適合
4. 同一入力による公式モデル再生
5. 公式STL robustnessの計算
6. Falsify側と公式側の成立／違反判定の一致

最終成果物は次の4ファイルです。

- [全ケース結果](results/arch2025/final/arch2025_all_summary.csv)
- [工程別ステータス](results/arch2025/final/arch2025_status.csv)
- [公式モデルで確認した要求違反候補](results/arch2025/final/arch2025_official_violations.csv)
- [集計レポート](results/arch2025/final/arch2025_final_report.txt)

全ケース結果内の `InputTraceFile` / `StateTraceFile` は、実行時に生成されたローカル証跡へのリポジトリ相対パスです。容量の大きい生トレースはGit管理せず、再実行時に再生成します。

意味修正後の一括runで、公式側のrobustnessが負となった要求違反候補は15件です。ただし、この結果は接続検証用の1 episode実行であり、発見率や速度などのアルゴリズム性能を示すものではありません。

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

### 未修正の公式checkoutによる横断確認

ARCH-COMP `5e8f72b8d5f30be002f40ae5df4a8e04d7f64e3c` の変更なしcheckoutを使い、7モデルから代表1ケースずつをRAND・1 episodeで再実行しました。全7件で入力検査、公式再生、成立／違反分類の一致が成功しています。コンパクトな結果は [arch2025_clean_checkout_smoke.csv](results/arch2025/compatibility/arch2025_clean_checkout_smoke.csv) に保存しています。この横断確認は接続互換性の検査であり、アルゴリズム性能評価には数えません。

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

中断後の再実行では、既定で `OverallPass=true` のケースをスキップします。分割実行結果を最終表へ組み立てる補助スクリプトは [assemble_arch2025_final_results.m](assemble_arch2025_final_results.m) です。

完全な一括runを公開用 `results/arch2025/final` へ反映する場合は、sourceを明示して集計します。

```sh
/Applications/MATLAB_R2026a.app/bin/matlab -batch "setenv('FALSIFY_ARCH2025_FINAL_SOURCE','results/arch2025/corrected_full188_20260902/arch2025_all_summary.csv'); assemble_arch2025_final_results"
```

## モデル固有の接続

- SB: FalBenchGenの `s1`、`s3`、`s5`、`cc3`、`cc5` を接続し、4個の制御点を各6秒保持します。選択ネットワークは各仕様の `a2_k1_1_4_9_10_0.01_LSTM/*a2_k1_1.mat` です。
- SC: 公式 `steamcondense_RNN_22.slx` の物理サブシステムをラッパーへ直接使用します。Instance 2は35秒を20等分した区分一定入力です。
- F16: 時変入力ではなくroll・pitch・yawの初期条件を探索し、公式AeroBenchVVの非線形ODEを実行します。checkoutに不足するControl System Toolbox非依存の線形化構造体、使用モードのautopilot command関数、設定フィールド名の互換化は `arch2025_compat/f16` に限定して補っています。
- AT / AFC / CC / NN: 公式物理モデルを使う既存ラッパーに、Instanceごとの入力parameterization、ログ、公式再生adapterを追加しています。AT/CCは生成時に公式solver設定をコピーします。NNの正規化状態は `[Ref-2, 0.4*Pos-1]` の順で、公式再生時の入力行列方向と `u_ts` はadapterで設定します。

生成ラッパーのSimulinkバイナリはローカルパスを含み得るためGit管理せず、検証開始時に `arch2025_generated` へ構築します。

## 判定と既知の注意点

最終判定は公式モデルを優先します。`OfficialRobustness < 0` を公式要求違反、`> 0` を要求成立として記録します。`FalsifyClassification` と `OfficialClassification` は `VIOLATED`、`SATISFIED`、`BOUNDARY` のいずれかです。

`OverallPass` はFalsify完走、入力検査、公式再生、分類一致から決定します。数値軌道の一致は独立した診断列です。意味修正後の一括runで、`TrajectoryEquivalencePass` は6/188件です。残りには入力サンプリング、solver、logging、正規化等に由来する数値差があります。このため「公式判定一致」は確認済みですが、「全モデルで軌道が数値的に同一」とは主張しません。

PMはローカルcheckoutに公式pacemakerモデルがないため第一段階から除外しています。FIM、複数seed性能比較、他ツール比較にはまだ着手していません。
