# wsl-container/ ディレクトリについて

**Windows 上で** Mirakurun をコンテナとして動かすための一式です。コンテナランタイムには
Microsoft が WSL 2.9.3 以降で提供する **WSL Container (`wslc`)** を使用します。

Linux ホストで動かす場合は、このディレクトリではなく `docker/` 配下の
`docker-compose.yml` ベースの構成を利用してください。

| ファイル | 用途 |
| --- | --- |
| `Containerfile` | イメージビルド定義（`docker/Dockerfile` 相当） |
| `entrypoint.sh` | コンテナ起動スクリプト |
| `wslc.ps1` | 操作スクリプト本体（WSL Container / `wslc` 使用） |
| `wslc.bat` | `wslc.ps1` を実行ポリシーに阻まれず起動するためのランチャー |

## Windows (CLI only, GUI 不使用)

**Docker Desktop / Podman Desktop（GUI アプリ）を使わずに**、コマンドプロンプトだけで
Mirakurun コンテナの導入から起動までを行うためのスクリプトです。コンテナランタイムには
Microsoft が WSL 2.9.3 以降で提供する **WSL Container (`wslc`)** を使用します
（[参考記事](https://gihyo.jp/article/2026/06/wsl-container)）。`wslc` は Docker CLI 互換
（`run` / `build` / `exec` / `logs` 等）のコマンド体系を持つ前提で本スクリプトを実装しています。

処理の本体は PowerShell スクリプト `wslc.ps1` です。`wslc.bat` は、実行ポリシーの設定を
変更せずに（`-ExecutionPolicy Bypass`）`wslc.ps1` を起動するだけの薄いランチャーで、
コマンドプロンプトからそのまま実行できます。PowerShell から直接実行しても構いません。

> **注意:** `wslc` は 2026-06 時点でパブリックプレビュー機能です。コマンドやオプションは
> 正式リリースまでに変更される可能性があります。
>
> **チューナーは利用できません。** `wslc run` に `--device` 相当のオプションが無いため、
> USB / PCIe いずれのチューナーもコンテナへパススルーできません。Windows 版は Mirakurun
> 本体の動作確認や Web UI の確認といった用途を想定しています。実運用は Linux ホストで
> `docker/` 配下の構成を利用してください。詳細は「[Windows 固有の制約](#windows-固有の制約)」を参照。

### 前提条件

- Windows 10 (2004+) / 11、WSL2 が利用できること
- [winget (App Installer)](https://apps.microsoft.com/detail/9nblggh4nns1) が利用可能なこと
  （USB チューナーを使わない場合は必須ではありません）

管理者権限が必要な操作（`setup` / `usb-attach`）は、スクリプトが **UAC により自動で昇格**します。
あらかじめ管理者としてプロンプトを開いておく必要はありません。昇格は別ウィンドウで実行され、
処理内容を確認できるようキー入力待ちで停止します。

### 使い方

初回セットアップは、エクスプローラで **`wsl-container\wslc.bat` をダブルクリック**するだけでも
実行できます（引数無しでの起動を `setup` として扱います）。UAC の昇格ダイアログが表示されるので
許可してください。処理ログは昇格した別ウィンドウに表示され、どちらのウィンドウも結果を
確認できるようキー入力待ちで停止します。

コマンドプロンプトから実行する場合は次のとおりです。

```bat
:: 1. WSL2 をプレリリース版へ更新 (wslc 導入) + usbipd-win 導入 (初回のみ、UAC で自動昇格)
wsl-container\wslc.bat setup

:: 2. イメージのビルド
wsl-container\wslc.bat build

:: 3. コンテナ起動 (デタッチ。自動再起動は wslc 非対応)
wsl-container\wslc.bat up

:: 起動後、Web UI は http://localhost:40772/ でアクセスできます

:: ログ確認
wsl-container\wslc.bat logs

:: 停止・削除
wsl-container\wslc.bat down
```

PowerShell から直接実行する場合は次のとおりです。

```powershell
powershell -ExecutionPolicy Bypass -File wsl-container\wslc.ps1 setup
```

サブコマンド一覧は `wsl-container\wslc.bat help` を参照してください。

### USB チューナーについて

> **現時点ではコンテナへパススルーできません。**
> `wslc run` には Docker/Podman の `--device` に相当するオプションが存在しないため
> （`wslc run --help` で確認: WSL 2.9.3 時点）、WSL2 へアタッチしたデバイスを
> コンテナへ渡す手段がありません。チューナーを使った実運用が必要な場合は、
> Linux ホストで `docker/` 配下の構成を利用してください。

`usb-list` / `usb-attach` / `usb-detach` は WSL2 ディストリビューションへの
アタッチ操作として引き続き利用できます（[usbipd-win](https://github.com/dorssel/usbipd-win)
を使用。`setup` 実行時に自動導入されます）。WSL2 上ではデバイスを認識しますが、
コンテナ内の Mirakurun からは見えません。

```bat
:: USB デバイス一覧を表示し、対象チューナーの busid を確認する
wsl-container\wslc.bat usb-list

:: 対象デバイスを WSL2 へアタッチする (UAC で自動昇格)
wsl-container\wslc.bat usb-attach 2-3

:: WSL2 側でデバイスを確認する
wsl -- lsusb

:: 不要になったらアタッチを解除する
wsl-container\wslc.bat usb-detach 2-3
```

環境変数 `USB_DEVICES` は将来 `wslc` が `--device` に対応した際に復帰させる想定で
残していますが、現時点では参照されません。

### Windows 固有の制約

- **チューナーは USB / PCIe いずれも非対応**: `wslc run` に `--device` 相当のオプションが
  無いため、USB チューナーを WSL2 へアタッチしてもコンテナへは渡せません。PT3/PX-W3PE 等の
  PCIe 接続チューナーは WSL2 自体がパススルーに対応していません。チューナーを使う場合は
  Linux ホストで `docker/` 配下の構成を利用してください。
- **`wslc run` の非対応オプション**: `--cap-add` / `--log-driver` / `--log-opt` /
  `--restart` に対応していないため、Docker / Podman と比べて capability の追加
  （`SYS_ADMIN` / `SYS_NICE`）、ログのローテーション設定、コンテナの自動再起動が
  行えません。Windows や WSL2 の再起動後は `wsl-container\wslc.bat up` で起動し直してください。
- **ホストモードネットワーキング非対応**: `--network host` は「ホスト モード
  ネットワーキングはサポートされていません」として拒否されるため、ポートを `--publish` で
  個別に公開します（既定 `40772:40772`）。Web UI へは
  `http://localhost:40772/` でアクセスしてください。公開ポートは環境変数
  `PUBLISH_PORTS` で変更できます。
- **USB アタッチは揮発性**: usbipd-win でアタッチしたデバイスは Windows 再起動や USB の
  抜き差しの度に再アタッチが必要です。恒常運用する場合は `usbipd bind --persistent` や
  タスクスケジューラでの自動アタッチを検討してください。
- **pcscd（カードリーダー常駐処理）**: `DISABLE_PCSCD=0`（既定）のままだとコンテナ内で
  カードリーダーを探索し続けます。カードリーダーを使わない検証用途では
  `set DISABLE_PCSCD=1` を実行してから `up` してください。

### 環境変数

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `MIRAKURUN_VOLUMES_DIR` | `%USERPROFILE%\mirakurun\volumes` | ボリューム配置先 |
| `MIRAKURUN_IMAGE_TAG` | `latest` | イメージタグ |
| `USB_DEVICES` | `/dev/bus/usb` | 現時点では未使用（`wslc` が `--device` 非対応のため） |
| `PUBLISH_PORTS` | `40772:40772` | 公開するポート（空白区切りで複数可）。例: `40772:40772 9229:9229` |
| `DISABLE_PCSCD` | `0` | `1` でコンテナ内 pcscd を無効化 |
| `DISABLE_B25_TEST` | `0` | `1` で arib-b25-stream-test の導入をスキップ |
