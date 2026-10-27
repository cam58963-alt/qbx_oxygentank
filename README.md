# qbx_oxygentank

潜水用の酸素機器（酸素ボンベ・リブリーザー・簡易酸素マスク）を追加する Qbox (qbx_core) 向けリソースです。アイテムを使うと装着され、水中にいる間だけ酸素を消費します。

## 主な機能

- 3 種類の酸素機器（設定で追加・変更可）
  | アイテム | 種類 | 最大酸素量 | 使用できるジョブ | 装着プロップ |
  | --- | --- | --- | --- | --- |
  | `oxygen_tank` 酸素ボンベ | 補充型 | 300 秒 | `ambulance` | タンク + マスク |
  | `rebreather` リブリーザー | 使い捨て | 150 秒 | 全員 | マスク |
  | `oxygen_mask` 簡易酸素マスク | 使い捨て | 75 秒 | 全員 | なし |
- アイテムを使うと装着、同じアイテムをもう一度使うと取り外し
- 水中（潜水中）のみ酸素を消費し、残量を画面右（`lib.showTextUI`）に表示
- 残量が少なくなると警告・危険通知
- 酸素残量はアイテムのメタデータに保存され、`ox_inventory` の耐久ゲージに反映
- 使い捨て型は酸素が尽きるとアイテムが消滅
- 補充型は補充ステーションで満タンに補充（約 6 秒）
- ジョブ制限（機器ごと）

## 依存リソース

- [qbx_core](https://github.com/Qbox-project/qbx_core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_inventory](https://github.com/overextended/ox_inventory)
- [ox_target](https://github.com/overextended/ox_target)（補充ステーションで使用）

## インストール

1. このリポジトリを `resources` フォルダに配置します。
2. `_data/items.lua` の内容を `ox_inventory/data/items.lua` に追加します。
3. `_images` 内の画像を `ox_inventory/web/images/` にコピーします。
   - `oxygen_mask.png` は同梱されていないため、必要に応じて用意してください。
4. `server.cfg` に追加します。
   ```cfg
   ensure ox_lib
   ensure qbx_core
   ensure ox_inventory
   ensure ox_target
   ensure qbx_oxygentank
   ```

## 設定（`config.lua`）

| 項目 | 説明 |
| --- | --- |
| `Config.Debug` | デバッグモード（デバッグ用コマンドを有効化） |
| `Config.DefaultUnderwaterTime` | 機器を外しているときの潜水可能時間 |
| `Config.OxygenDevices` | 酸素機器の定義（下記） |
| `Config.RefillStations` | 補充ステーションの座標・プロップ・ブリップ・ターゲット範囲 |
| `Config.UI` | 残量表示の位置と更新間隔 |
| `Config.Notifications` | 通知メッセージ |

### 酸素機器の設定項目

| キー | 説明 |
| --- | --- |
| `type` | `'refillable'`（補充型）または `'disposable'`（使い捨て） |
| `label` | 表示名 |
| `allowedJobs` | 使用できるジョブ。空配列なら全員使用可 |
| `maxOxygen` | 最大酸素量（秒） |
| `consumeRate` | 水中での消費速度（秒/秒） |
| `refillRate` | 地上での自動回復速度（`autoRefillOnSurface = true` のとき） |
| `warningLevel` / `criticalLevel` | 警告・危険通知を出す残量（秒） |
| `underwaterTime` | 装着中のゲーム内潜水可能時間 |
| `props` | 装着するプロップ（モデル・ボーン・位置・回転） |
| `canRefillAtStation` | 補充ステーションで補充できるか |
| `autoRefillOnSurface` | 水面・陸上で自動回復するか |
| `showUI` | 残量表示の有無 |

## 補充ステーション

`Config.RefillStations` に設定した場所にプロップ（既定 `prop_compressor_01`）と `ox_target` のゾーンが作られます。補充できる機器を装着した状態で調べると、プログレスバーの後に満タンになります。

## デバッグ用コマンド

`Config.Debug = true` のときのみ登録されます。

| コマンド | 内容 |
| --- | --- |
| `/oxygeninfo` | 装着中の機器と酸素の詳細 |
| `/oxygencheck` | 水中判定の確認 |
| `/checkslot [番号]` | インベントリのスロット詳細 |
| `/propfix show` / `list` / `[番号] pos\|rot [軸] [値]` | 装着プロップの位置調整 |
| `/reattach` | プロップの再装着 |
| `/forcedetach` | プロップを強制的に外す |
| `/oxygenhelp` | デバッグコマンドのヘルプ |
