# FIMによるAT故障注入実験

研究用コードをこのフォルダに集約しています。既存のARCH2025要件やFalsify coreは変更しません。
現在の実験は **トルクコンバーター内部のトルク比低下と加速性能** です。
最初に [実験手順](docs/torque-acceleration.md) と `config/fim_torque_spec.m` を読んでください。
故障注入の入口は `matlab/run_fim_torque_acceleration.m` の `prepare_` です。
実行済みの [結果](docs/torque-acceleration-results.md) と
[全波形・入力・CSV集計](evidence/torque-acceleration-20260925/) をGit管理しています。

旧RPM加算量調査の設定・専用コード・資料は削除しました。
必要ならGit commit `1cb9fbf` から復元できます。Git管理外の過去の実行結果は削除していません。
初回10故障の凍結プロファイル `fim_at_spec.m` と旧接続コードは、共通基盤の参照用として残しています。
**現行のギア要件は `fim_torque_spec.m` の1～4と離散値検査**です。旧プロファイルを使わないでください。

## 配置

| フォルダ | 内容 | Git管理 |
|---|---|---|
| `config/` | 故障・要件・実験条件 | する |
| `matlab/` | FIMモデル生成、実行、Falsify接続 | する |
| `python/` | Ψ-TaLiRo接続と結果監査・集計 | する |
| `tests/` | モニタ、エージェント、配置の検査 | する |
| `dependencies/` | 取得元・commit固定、互換修正差分、環境定義 | する |
| `docs/` | 実験方法・検証記録 | する |
| `evidence/` | 確認済み予備実験の全24波形CSV・入力・集計・監査 | する |
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
test_fim_torque_spec();
runDirectory = run_fim_torque_acceleration('all');
```

`all` はモデル生成→正常6入力→正常結果から要件固定→故障18入力→集計の順です。
故障無効化で正常モデルに戻るかの追加検証18回を含め、合計42回シミュレーションします。
Falsify / Ψ-TaLiRoの探索・学習はまだ実行しません。
元の10故障の接続実装は [初回実験の方法](docs/preliminary-experiment.md) に記録しています。
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

現行実験は6種類の固定入力を用いた予備実験です。入力範囲全体の安全性や手法の優劣は主張しません。
加速要件の期限20秒と車速選定ルールを先に決め、正常波形だけで車速しきい値を選びます。
トルク比の減算は次元なしの固定値で、百分率低下ではありません。
ギア範囲は両端を含む1～4、離散値は1・2・3・4です。0の余裕は違反ではありません。
ギアの余裕と加速の余裕を最小値でまとめると1速/4速で探索指標が0になるため、別々に評価します。

初回実験は最大10候補・3 seedsの疎通／予備比較でした。
DDQNの学習更新とConBO-LSの追加BO評価は0回で、学習・最適化の性能比較ではありません。
RPM・gearの出力信号の故障と、内部トルク故障を区別してください。
有限の入力集合に対する未発見を、全入力で安全だという保証にしてはいけません。

設定・コードを変えたら、新しい実験フォルダに条件とコードを保存します。
探索の準備・条件調整に使った入力群と、本評価用の入力／seedは区別します。
