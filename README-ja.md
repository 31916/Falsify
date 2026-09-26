# 深層強化学習によるサイバーフィジカルシステムの改竄

## 導入

このコンテンツは、サイバーフィジカルシステムの改竄に対する深層強化学習技術を評価するためのものである。4 つのモデル (自動変速機モデル、風力タービンモデル、パワートレイン制御モデル、インスリンモデル) が含まれている。インスリンモデルは現在機能しません。

## 対象

このコンテンツは、技術を評価する研究者や開発者向けである。

## 環境 (テスト済みバージョン)

- MATLAB (R2023a)
- Simulink (10.7)
- Stateflow (10.8)
- Deep Learning Toolbox (14.6)
- Optimization Toolbox (9.5)
- Parallel Computing Toolbox (7.8)
- Python (3.8.9)
- Chainer (7.8.1)
- ChainerRL (0.8.0)
- Gym (0.22.0)
- s-taliro
- breach


## コンテンツ

- metascript.m : ATおよびPTCモデル用のスクリプト(インスリンモデルは現在機能しません)
- metascript_cars.m : CARSモデル用のスクリプト
- metascript_wind_turbine.m : 風力タービンモデルのスクリプト

## ARCH-COMP 2025 統合検証

SB・AT・AFC・CC・NN・F16・SC の49条件に対し、RAND・A3C・ACER・DDQNが生成する全候補入力を検査し、公式モデルでシミュレーションして、公式STL robustnessを計算します。この公式robustnessをFalsifyの探索目的と反例判定に使用します。

対象条件、固定する公式リポジトリのコミット、実験条件、外部モデル配置、実行方法は [ARCH_COMP_2025.md](ARCH_COMP_2025.md) を参照してください。生成された実験結果と生ログはGitでは管理しません。


## 実行例
### 準備
- 作業ディレクトリにPython仮想環境を構築
>詳しくは[Python virtual environments with MATLAB](https://jp.mathworks.com/matlabcentral/answers/1750425-python-virtual-environments-with-matlab)を参照

- ATを実行する場合は、MathWorksの例題に含まれる `sldemo_autotrans_data.mat` を用意
>自動検出されない場合は、環境変数 `FALSIFY_ARCH2025_AT_DATA` にファイルまたは格納ディレクトリの絶対パスを指定します。[MathWorksの説明](https://jp.mathworks.com/help/simulink/slref/modeling-an-automatic-transmission-controller.html)も参照してください。このデータは本リポジトリでは再配布しません。

### 実行
"Configuration" という名前のセクションを編集、スクリプトを実行


## ライセンス

(C) 2019 National Institute of Advanced Industrial Science and Technology (AIST)

The contents under the wind-turbine directory is copyrighted by the respective authors.

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.                                    

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.                           

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
