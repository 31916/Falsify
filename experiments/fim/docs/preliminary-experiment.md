# FIM / AT 初回予備実験（2026-09-17、凍結プロファイル）

この文書は初回実験の方法を保存しています。現在の配置・準備手順は
[README](../README.md)を参照してください。以下のファイル名は移動後も同名です。

## 要件と正常系の根拠

`fim_at_spec.m` が本実験の唯一の要件・予算・故障カタログ定義です。
既存 ARCH-COMP 2025 の要件定義や公式モデルは変更しません。
これは元の ARCH 要件をすべて満たすようにした実験ではなく、**FIM 用の新しい要件**です。

\[
\varphi_{FIM}=\Box_{[0,30]}(599<n<6001\ \land\ 0.5<g<4.5)
\]

- `n`: モデルの RPM 出力、`g`: モデルの gear 出力。
- 正常 AT の `Engine/Integrator` は出力制限 600～6000 rpm、初期値 1000 rpm。
- 正常 AT の ShiftLogic のギア状態の代入値は 1, 2, 3, 4。初期状態は first（gear=1）。
- この構造から、正しく初期化され正常終了するモデルの出力範囲を説明できます。
  これは形式検証ツールによる到達可能性証明ではありません。実測だけから「全入力で成立」とは結論しません。
- 1 rpm と 0.5 gear の余裕は境界でロバストネスが 0 になることを避けるためです。
  シミュレータのエラー、NaN/Inf は違反発見に数えません。
- 入力は throttle ∈ [0,100]、brake ∈ [0,325]、5 秒刻みの区分定数、30 秒間。
  コピーしたモデルのルート Inport は補間なし（ZOH）、SampleTime=5。
  これにより入力の更新を離散主時刻に揃えます。公式 ode5 / 0.01 秒設定を保持します。

これは論理的な恒真式ではありません。RPM/gear の観測信号への故障は制限器・状態機械の
下流にあるので違反が可能です。一方、内部のトルク故障は出力制限を破らないことがあり、
**この要件ではすべての故障を検出できません**。要件設計の限界を示す対照例として残します。

## 10 個の単一故障

各モデルに 1 個だけ挿入。すべて t=5 秒に発生し、終了まで継続します。

| ID | 対象（宛先） | 種類・値 |
|---|---|---|
| F01 | ルート RPM 出力 | Bias +500 rpm |
| F02 | ルート RPM 出力 | Bias +1500 rpm |
| F03 | ルート RPM 出力 | Bias −500 rpm |
| F04 | ルート RPM 出力 | Bias −1500 rpm |
| F05 | ルート RPM 出力 | Negate |
| F06 | ルート RPM 出力 | Stuck-at 0 |
| F07 | ルート gear 出力 | Bias +1 |
| F08 | ルート gear 出力 | Bias −1 |
| F09 | Transmission/TransmissionRatio/Tout | Bias +10 |
| F10 | Transmission/TransmissionRatio/Tout | Bias +100 |

10 種類・3 か所であり、10 か所ではありません。RPM と gear は観測枝だけのセンサ故障、
Tout は伝達トルクの内部信号故障です。トランスミッションのギア比自体の変更ではありません。
実測の結果を見て故障値や要件を変更しません。

## 実験 1

共通の 12 入力（境界値、一定入力、段階的入力、固定 seed のランダム入力）で、
正常 1 モデルと故障 10 モデルを比較します。さらに各故障を無効化して正常系と一致するか、
有効化前に一致するか、故障ブロックの入出力が指定演算と一致するかも検査します。
STL 判定に使う信号はクリップしません。

## 実験 2

既存 `falsify.m` / `driver.py` の RAND と ACER を使用します。
正常モデルも対照として探索します。各モデル・手法で seed 101, 202, 303、
最大 10 エピソード／seed、違反時に早期停止します。
短い予備実験であり、手法の優劣や未発見ケースの安全性は主張しません。

RL ラッパーは FIM が生成したモデルのコピーにエージェント・モニタを追加して作成します。
**全候補**について独立した入力付き FIM モデルで再実行し、波形一致・入力範囲・変更時刻を検査します。
同じ入力を正常モデルでも再実行し、その要件充足を確認します。
この再実行のロバストネスが探索の終了・最良候補・終端報酬を決定します。

ロバストネスは各述語の距離を RPM 3000、gear 1.5 で除した値の最小値です。
これは観測の正規化による尺度で、物理単位の距離もトレースに残します。
判定しきい値は −1e−9（それより小さければ違反）。
ρ ≈ 0 は境界として扱い、厳密不等式の充足とは断定しません。
オンライン途中報酬は既存 ARCH 連携と同じ alpha=0、終端には再実行結果を使います。

## 実行と成果物

Mac の MATLAB R2026a とリポジトリ内 `.venv-falsify` を使用します。
`test_fim_at_spec` はモニタの境界・違反・終了時刻の判定テスト、
`.venv-falsify/bin/python test_fim_driver.py` は ACER の有限出力と重み更新の疎通テストです。

Chainer は macOS を公式サポートしていません（[公式注意事項](https://docs.chainer.org/en/stable/tips.html#mnist-example-does-not-converge-in-cpu-mode-on-mac-os-x)）。
実行時の Accelerate 警告は `numpy.distutils.system_info` による環境探索で出ますが、
インストール済み NumPy 1.23.5 のビルド情報と `otool -L` は OpenBLAS の使用を示します。
この警告だけを理由に NumPy を変更していません。古い依存関係による移植上の制約は残ります。

```matlab
cd('/Users/harry/Documents/MATLAB/Falsify');
addpath('experiments/fim'); setup_fim();
runDirectory = run_fim_at_experiments('prepare');
run_fim_at_experiments('exp1', runDirectory);
run_fim_at_experiments('pilot', runDirectory); % 経路の疎通確認、集計対象外
run_fim_at_experiments('exp2', runDirectory);  % 完了済み探索はスキップ
summarize_fim_at(runDirectory);
open_fim_at_case(runDirectory, 'F02');        % 任意: 故障モデルを開いて強調表示
```

最後に `.venv-falsify/bin/python experiments/fim/python/audit_fim_at.py <runDirectory>` で、
保存された全候補の入力制約・正常系・故障演算・ロバストネス・探索集計を独立検査できます。

`results/fim/runs/<一意 ID>/` に manifest、故障カタログ、モデル、FIM の Fault_table、
CSV 集計、入力・波形・履歴 MAT を保存します。上流 FIM はコピーして実行します。
R2026a 互換修正に加え、挿入先の階層は部分一致から完全一致に絞り込み、
意図せず複数箇所へ注入しないことを Fault_table の行数で検査します。
元モデルと上流 vendor は変更しません。生成物は Git から除外します。
同名のモデルやFIMライブラリを既に開いている場合、実験ランナーは停止します。
保存していない手動変更を閉じたり、別の実験モデルを誤って使ったりしないための保護です。

## A3C・DDQN・Ψ-TaLiRoの追加比較

元の `fim_at_spec` / protocol は凍結したまま、追加設定と結果を別フォルダに保存します。
Gitの `FIM` ブランチで管理します。公開操作はユーザーの指示に従います。

```matlab
options = struct('Algorithms',{{'A3C','DDQN'}},'MaxEpisodes',10,'Folder','additional_rl10_v2');
run_fim_at_experiments('additional', runDirectory, options);
```

Ψ-TaLiRoは独立したPython 3.9環境を使用します（初回は `../FIM/.venv-psy-arch`）。
依存関係は `dependencies/requirements-psy.txt`、実際の全バージョンは結果フォルダのlockに保存します。
FalsifyのPython環境・coreファイルは変更しません。

```sh
.venv-fim-psy/bin/python experiments/fim/tests/test_fim_psy.py <runDirectory>
.venv-fim-psy/bin/python -u experiments/fim/python/run_fim_psy.py <runDirectory>
.venv-falsify/bin/python experiments/fim/python/compare_fim_tools.py <runDirectory>
```

ARCH2025論文の公式再現リンクは `ARCH-Comp-2024-Repeatability` です。
そのパッケージが固定している ConBO `532c4cd` / psy-taliro `1.0.0b9` を使い、
ConBO-LSを選びます（通常サンプルのDual AnnealingやMATLAB版S-TaLiRoではありません）。
GPラッパーのCUDA配置だけをCPUへ移植し、元のMaternカーネル・fit設定を保持します。
モデル接続はMATLAB Engine R2026aと `fim_at_external` 経由で、同じ独立FIM再実行処理を使います。
RPM・gearの正規化述語余裕4本に対してRTAMTを適用し、毎候補で解析式と照合します。

**10候補では、DDQNの経験500件の学習開始条件を満たしません。**
**ConBO-LSでも100点の初期LHS設計の先頭10点までであり、BO最適化には入りません。**
初期設計を10点へ変更するのではなく、100点の設計を生成したまま候補予算で打ち切ります。
連言の最初の反例で停止する共通ルールを、初期サンプリング中にも適用します。
A3Cは既存の単一ワーカー構成です。学習更新回数は結果に明示します。
この予備比較を、学習・最適化を含む各手法の性能順位とは解釈しないでください。

`compare_fim_tools.py` は165探索の完了を要求し、全候補を独立監査して
`COMPARISON.md` を生成します。pilotや中断した保存処理の結果は集計対象外です。
