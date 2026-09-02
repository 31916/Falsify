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

最終成果物は次の3ファイルです。

- [全ケース結果](results/arch2025/final/arch2025_all_summary.csv)
- [工程別ステータス](results/arch2025/final/arch2025_status.csv)
- [公式モデルで確認した要求違反候補](results/arch2025/final/arch2025_official_violations.csv)
- [集計レポート](results/arch2025/final/arch2025_final_report.txt)

全ケース結果内の `InputTraceFile` / `StateTraceFile` は、実行時に生成されたローカル証跡へのリポジトリ相対パスです。容量の大きい生トレースはGit管理せず、再実行時に再生成します。

意味修正後の一括runで、公式側のrobustnessが負となった要求違反候補は15件です。ただし、この結果は接続検証用の1 episode実行であり、発見率や速度などのアルゴリズム性能を示すものではありません。

CC3 Instance 2では、4手法・共通20 seed・各30 episodeの固定予算性能実験も完走しました。80/80 runで入力検査と公式モデル再生に成功し、公式違反発見率はRAND 12/20、A3C 20/20、ACER 20/20、DDQN 13/20でした。この結果はCC3 Instance 2に限定した比較であり、全ベンチマークへの一般化はしていません。

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
| `FALSIFY_ARCH2025_OUTPUT_DIR` | 結果出力先（相対指定はリポジトリ基準） |
| `FALSIFY_ARCH2025_CASE_FILTER` | CaseIDのワイルドカードフィルタ |
| `FALSIFY_ARCH2025_RESUME_PASSED` | `0`で成功済みケースも再実行 |
| `FALSIFY_ARCH2025_REBUILD_WRAPPERS` | `1`で生成ラッパーを再構築 |
| `FALSIFY_ARCH2025_MAX_EPISODES` | 各ケースの最大episode数（正の整数） |
| `FALSIFY_ARCH2025_SEED_OVERRIDE` | 全選択ケースで使うseed（未指定時はCaseIDごとの固定seed） |
| `FALSIFY_ARCH2025_STOP_ON_VIOLATION` | `0`で負のFalsify robustness後も固定episode予算を完走 |
| `FALSIFY_ARCH2025_FINAL_SOURCE` | 公開用最終表へ採用する完全summary CSV |
| `FALSIFY_ARCH2025_DEBUG_RAW_ACTION` | `1`で重複除去・補間前の生ActionOut traceも保存 |

Python依存は [requirements-falsify.txt](requirements-falsify.txt) に記載しています。ローカル検証環境は MATLAB R2026a、Python 3.9.6、NumPy 1.23.5、Chainer 7.8.1、ChainerRL 0.8.0、Gym 0.22.0 です。

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

完全な一括runを公開用 `results/arch2025/final` へ反映する場合は、次のようにsourceを明示します。

```sh
/Applications/MATLAB_R2026a.app/bin/matlab -batch "setenv('FALSIFY_ARCH2025_FINAL_SOURCE','results/arch2025/corrected_full188_20260902/arch2025_all_summary.csv'); assemble_arch2025_final_results"
```

## RL性能実験

[run_arch2025_rl_pilot.py](run_arch2025_rl_pilot.py) は同一のCaseID、algorithm群、seed群、episode予算を指定し、各runを公式モデル再生まで実行して集計します。既定値はCC3 Instance 2、RAND/A3C/ACER/DDQN、3 seed、最大30 episodeです。

```sh
.venv-falsify/bin/python run_arch2025_rl_pilot.py \
  --case-prefix cc_cc3_i2 \
  --algorithms RAND A3C ACER DDQN \
  --seeds 20250903 20250904 20250905 \
  --episodes 30
```

2026-09-02のpilotは12/12 runがVALIDATEDで、公式違反発見率はRAND 1/3、A3C 3/3、ACER 3/3、DDQN 3/3でした。これは3 seed・1要求だけの予備実験であり、統計的な性能優位を示すものではありません。特にDDQNの全成功は `replay_start_size=500` より前なので、現時点では学習効果ではなく探索効果を含む結果として扱います。詳細は [ゼミ報告](SEMINAR_2026-09-03.md) と [pilot集計](results/arch2025/pilot_cc3_i2_20260902/pilot_summary.csv) にあります。

### 固定予算20-seed実験

早期停止pilotでは、Falsifyラッパーの可変ステップ数値差による浅い負値で探索が止まる場合があり、手法ごとのsimulation予算も揃いませんでした。そこで `--fixed-budget` を追加し、途中のFalsify robustnessに関係なく全手法で30 episodeを実行してから、保存された最良入力を公式モデルへ再投入する設計へ変更しました。

```sh
.venv-falsify/bin/python run_arch2025_rl_pilot.py \
  --case-prefix cc_cc3_i2 \
  --algorithms RAND A3C ACER DDQN \
  --seeds 20251001 20251002 20251003 20251004 20251005 \
          20251006 20251007 20251008 20251009 20251010 \
          20251011 20251012 20251013 20251014 20251015 \
          20251016 20251017 20251018 20251019 20251020 \
  --episodes 30 \
  --fixed-budget \
  --rebuild-wrappers \
  --output-root results/arch2025/cc3_i2_fixed30_20seed_20260903
```

| Algorithm | 有効run | 公式違反 | 発見率 | Wilson 95% CI | Falsify時間中央値 | 公式robustness中央値 |
|---|---:|---:|---:|---:|---:|---:|
| RAND | 20/20 | 12/20 | 60% | 38.7–78.1% | 56.96秒 | -0.203 |
| A3C | 20/20 | 20/20 | 100% | 83.9–100% | 81.32秒 | -3.120 |
| ACER | 20/20 | 20/20 | 100% | 83.9–100% | 60.22秒 | -4.781 |
| DDQN | 20/20 | 13/20 | 65% | 43.3–81.9% | 79.77秒 | -4.429 |

共通seedを対応付けた正確McNemar検定では、RANDとの差はA3CとACERでそれぞれ未補正 `p=0.0078125`、3比較のHolm補正後 `p=0.0234375`、DDQNでは `p=1.0` でした。この1要求・20 seedの範囲ではA3C/ACERの発見率がRANDより高いという結果ですが、他要求でも再現するかは未確認です。DDQNは約600遷移の後半で `replay_start_size=500` に到達するため学習は開始しますが、学習区間は短く、収束済みとは主張しません。

- [実行manifest](results/arch2025/cc3_i2_fixed30_20seed_20260903/pilot_manifest.json)
- [80 runの結果](results/arch2025/cc3_i2_fixed30_20seed_20260903/pilot_runs.csv)
- [手法別集計](results/arch2025/cc3_i2_fixed30_20seed_20260903/pilot_summary.csv)
- [RANDとの対応比較](results/arch2025/cc3_i2_fixed30_20seed_20260903/pairwise_vs_rand.csv)
- [95%信頼区間付き図](results/arch2025/cc3_i2_fixed30_20seed_20260903/official_violation_rate.png)

## モデル固有の接続

- SB: FalBenchGenの `s1`、`s3`、`s5`、`cc3`、`cc5` を接続し、4個の制御点を各6秒保持します。選択ネットワークは各仕様の `a2_k1_1_4_9_10_0.01_LSTM/*a2_k1_1.mat` です。
- SC: 公式 `steamcondense_RNN_22.slx` の物理サブシステムをラッパーへ直接使用します。Instance 2は35秒を20等分した区分一定入力です。
- F16: 時変入力ではなくroll・pitch・yawの初期条件を探索し、公式AeroBenchVVの非線形ODEを実行します。checkoutに不足するControl System Toolbox非依存の線形化構造体と、使用モードのautopilot command関数は `arch2025_compat/f16` に限定して補っています。
- AT / AFC / CC / NN: 公式物理モデルを使う既存ラッパーに、Instanceごとの入力parameterization、ログ、公式再生adapterを追加しています。AT/CCは生成時に公式solver設定をコピーします。NNの正規化状態は `[Ref-2, 0.4*Pos-1]` の順です。

生成ラッパーのSimulinkバイナリはローカルパスを含み得るためGit管理せず、検証開始時に `arch2025_generated` へ構築します。

## 判定と既知の注意点

最終判定は公式モデルを優先します。`OfficialRobustness < 0` を公式要求違反、`> 0` を要求成立として記録します。`FalsifyClassification` と `OfficialClassification` は `VIOLATED`、`SATISFIED`、`BOUNDARY` のいずれかです。

`OverallPass` はFalsify完走、入力検査、公式再生、分類一致から決定します。数値軌道の一致は独立した診断列です。意味修正後の一括runで、`TrajectoryEquivalencePass` は6/188件です。CCでは同一入力による公式モデルとFalsify基礎モデルの誤差が`1.1e-13`以下で、wrapperと公式モデルを固定ステップ`ode4, 0.01秒`へ揃えた診断では誤差`0`でした。通常runの残差はonline monitor等が可変ステップsolverの積分経路を変えるためであり、正式判定では公式runnerの軌道を優先します。このため「公式判定一致」と物理モデルの動的一致は確認済みですが、「通常の可変ステップ実行で全軌道が数値的に同一」とは主張しません。

PMはローカルcheckoutに公式pacemakerモデルがないため第一段階から除外しています。複数seed性能比較はCC3 Instance 2で完了しました。他要求への性能実験展開、FIM、他ツール比較にはまだ着手していません。
