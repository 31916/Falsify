# FIMによるAT故障注入実験

研究用コードをこのフォルダに集約しています。既存のARCH2025要件やFalsify coreは変更しません。
最初に `config/fim_at_spec.m`（初回予備実験の凍結設定）を読み、
`matlab/run_fim_at_experiments.m` の `prepare_` でFIMへの接続を確認できます。

RPM正加算の調査は [準備実験の説明](docs/rpm-calibration.md) と
`config/rpm_calibration.json` を使います。初回の10故障設定は上書きしません。
確認済みの結果は [RPM調査結果](docs/rpm-calibration-results.md)、
全入力の境界と監査要約は [数値根拠](docs/rpm-calibration-evidence.json)、
実際に使った入力波形の値は [固定入力](docs/rpm-calibration-inputs.json) です。

## 配置

| フォルダ | 内容 | Git管理 |
|---|---|---|
| `config/` | 故障・要件・実験条件 | する |
| `matlab/` | FIMモデル生成、実行、Falsify接続 | する |
| `python/` | Ψ-TaLiRo接続と結果監査・集計 | する |
| `tests/` | モニタ、エージェント、配置の検査 | する |
| `dependencies/` | 取得元・commit固定、互換修正差分、環境定義 | する |
| `docs/` | 実験方法・検証記録 | する |
| リポジトリ直下 `.deps/fim/` | 固定版の外部コード、MATLABデータ | しない |
| リポジトリ直下 `results/fim/` | 実験ごとの生成モデル・入力・全波形 | 大容量生成物はしない |

`../FIM/` は過去の導入確認の保管場所で、移行後のランナーは参照しません。
古い結果フォルダのモデル・CSV・MAT・コードスナップショットは変更しません。
旧スナップショットと新コードは異なるため、既存探索を再開せず新しい出力フォルダを使ってください。

## 外部依存の準備（Python標準ライブラリ・Git・patch）

FIM本体はMITライセンスです。上流のLICENSEを保持して取得します。
適用する互換修正のライセンス表示は `dependencies/FIM-LICENSE.txt` に保存しています。
`versions.json` でFIM、ATモデル、ARCH再現パッケージ、ConBOを固定します。
MATLAB R2026a・Simulink・Stateflowと、必要に応じてCコンパイラが必要です。

MATLABのAutomatic Transmission Controllerの例を開き、
`sldemo_autotrans_data.mat` を取得してください（MathWorksのデータはGitへ再配布しません）。
MATLABで `which('sldemo_autotrans_data.mat')` により場所を確認できます。

リポジトリ直下から:

```sh
python3 experiments/fim/dependencies/prepare.py --model-data /path/to/sldemo_autotrans_data.mat
```

既存クローンがあれば、ネットワークなしで固定commitから生成できます:

```sh
python3 experiments/fim/dependencies/prepare.py \
  --fim-source /path/to/fimtool \
  --arch-source /path/to/ARCH-COMP \
  --model-data /path/to/sldemo_autotrans_data.mat
```

元クローンの作業ツリーはコピーせず、指定commitの `git archive` を使用します。
新しい `.deps/fim/` を作り、既存インストールがあれば内容のハッシュを照合します。
既存データを自動削除・上書きすることはありません。

互換修正は、配置例外の限定的な処理、ライブラリ読み込み、コンパイルモード、
モデル設定の保持、Offset内部値の反映、注入階層の完全一致です。
上流FIMの未修正版と修正版を分離し、各実験には修正版をさらにコピーします。

## MATLABから使う

リポジトリ直下で:

```matlab
addpath('experiments/fim');
setup_fim();
test_fim_at_spec();
runDirectory = run_fim_at_experiments('prepare'); % モデル生成のみ
```

元の10故障予備実験を再実行する場合の手順は [初回実験の方法](docs/preliminary-experiment.md)。
`run_fim_at_experiments()` の引数省略は全実験実行なので、目的のstageを明示してください。
`s-taliro/dp_taliro` のMEXが未構築なら [Falsify README](../../README.md) の環境準備が必要です。
同名モデルを手動で開いている場合は、編集を保存して手動で閉じてから実行してください。

## Python環境とテスト

Falsify用 `.venv-falsify` は既存環境を維持します。
Ψ-TaLiRoの依存は別のPython 3.9環境 `.venv-fim-psy` にインストールします:

```sh
python3.9 -m venv .venv-fim-psy
.venv-fim-psy/bin/python -m pip install -r experiments/fim/dependencies/requirements-psy.txt
.venv-falsify/bin/python experiments/fim/tests/test_fim_driver.py
.venv-fim-psy/bin/python experiments/fim/tests/test_fim_psy.py /path/to/previous-run
```

既存の別環境を使う場合は、同じ固定依存を満たすPython実行ファイルを明示して呼び出せます。
仮想環境フォルダは絶対パスを内部に保持するため、フォルダ移動で移行しません。

## 実験上の注意

初回実験は最大10候補・3 seedsの疎通／予備比較でした。
DDQNの学習更新とConBO-LSの追加BO評価は0回で、学習・最適化の性能比較ではありません。
RPM・gearの出力信号の故障と、内部トルク故障を区別してください。
有限の入力集合に対する未発見を、全入力で安全だという保証にしてはいけません。

設定・コードを変えたら、新しい実験フォルダに条件とコードを保存します。
探索の準備・条件調整に使った入力群と、本評価用の入力／seedは区別します。
