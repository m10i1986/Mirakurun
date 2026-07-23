# container/ ディレクトリについて

Podman（および Podman 互換の `docker` コマンド）で Mirakurun を動かすための一式です。
`docker/` 配下の `docker-compose.yml` ベースの構成を、podman-compose を使わずに
素の `podman` コマンドへ翻訳したものです。

Windows 向けには、Podman ではなく Microsoft 製の **WSL Container (`wslc`)** を使う
スクリプトを用意しています。詳細は下記「Windows (CLI only)」を参照してください。

| ファイル | 用途 |
| --- | --- |
| `Containerfile` | イメージビルド定義（`docker/Dockerfile` 相当） |
| `entrypoint.sh` | コンテナ起動スクリプト |
| `podman.sh` | Linux 向け操作スクリプト（rootless 運用を想定） |
| `wslc.ps1` | **Windows (CLI only) 向け**操作スクリプト本体（WSL Container / `wslc` 使用） |
| `wslc.bat` | `wslc.ps1` を実行ポリシーに阻まれず起動するためのランチャー |
| `mirakurun.container` | Linux + systemd (Quadlet) で常駐運用する場合のユニット定義 |

## Linux

`podman.sh` を参照してください（スクリプト先頭のコメントに使い方を記載）。

```sh
./container/podman.sh build
./container/podman.sh up
./container/podman.sh logs
```

物理チューナー（USB/PCIe）をコンテナへパススルーする場合は Linux ホストでの運用を推奨します。

## Windows (CLI only, GUI 不使用)

**Docker Desktop / Podman Desktop（GUI アプリ）を使わずに**、コマンドプロンプトだけで
Mirakurun コンテナの導入から起動までを行うためのスクリプトです。コンテナランタイムには
Podman ではなく、Microsoft が WSL 2.9.3 以降で提供する **WSL Container (`wslc`)** を使用します
（[参考記事](https://gihyo.jp/article/2026/06/wsl-container)）。`wslc` は Docker CLI 互換
（`run` / `build` / `exec` / `logs` 等）のコマンド体系を持つ前提で本スクリプトを実装しています。

処理の本体は PowerShell スクリプト `wslc.ps1` です。`wslc.bat` は、実行ポリシーの設定を
変更せずに（`-ExecutionPolicy Bypass`）`wslc.ps1` を起動するだけの薄いランチャーで、
コマンドプロンプトからそのまま実行できます。PowerShell から直接実行しても構いません。

> **注意:** `wslc` は 2026-06 時点でパブリックプレビュー機能です。コマンドやオプションは
> 正式リリースまでに変更される可能性があります。

### 前提条件

- Windows 10 (2004+) / 11、WSL2 が利用できること
- [winget (App Installer)](https://apps.microsoft.com/detail/9nblggh4nns1) が利用可能なこと
  （USB チューナーを使わない場合は必須ではありません）

管理者権限が必要な操作（`setup` / `usb-attach`）は、スクリプトが **UAC により自動で昇格**します。
あらかじめ管理者としてプロンプトを開いておく必要はありません。昇格は別ウィンドウで実行され、
処理内容を確認できるようキー入力待ちで停止します。

### 使い方

初回セットアップは、エクスプローラで **`container\wslc.bat` をダブルクリック**するだけでも
実行できます（引数無しでの起動を `setup` として扱います）。UAC の昇格ダイアログが表示されるので
許可してください。処理ログは昇格した別ウィンドウに表示され、どちらのウィンドウも結果を
確認できるようキー入力待ちで停止します。

コマンドプロンプトから実行する場合は次のとおりです。

```bat
:: 1. WSL2 をプレリリース版へ更新 (wslc 導入) + usbipd-win 導入 (初回のみ、UAC で自動昇格)
container\wslc.bat setup

:: 2. イメージのビルド
container\wslc.bat build

:: 3. コンテナ起動 (デタッチ, restart=always)
container\wslc.bat up

:: ログ確認
container\wslc.bat logs

:: 停止・削除
container\wslc.bat down
```

PowerShell から直接実行する場合は次のとおりです。

```powershell
powershell -ExecutionPolicy Bypass -File container\wslc.ps1 setup
```

サブコマンド一覧は `container\wslc.bat help` を参照してください。

### USB チューナーを使う

`wslc` は WSL2 上で直接コンテナを実行するため、USB デバイスを WSL2 ディストリビューションへ
アタッチすれば、Linux のデバイスファイルとしてそのままコンテナへ `--device` で渡せます。
デバイスの WSL2 へのアタッチには Microsoft 公式の [usbipd-win](https://github.com/dorssel/usbipd-win)
を使用します（`setup` 実行時に自動導入されます）。

```bat
:: 1. USB デバイス一覧を表示し、対象チューナーの busid を確認する
container\wslc.bat usb-list

:: 2. 対象デバイスを WSL2 へアタッチする (UAC で自動昇格)
container\wslc.bat usb-attach 2-3

:: 3. WSL2 側でデバイスを確認する (任意)
wsl -- lsusb

:: 4. コンテナ起動 (既定で /dev/bus/usb を渡す)
container\wslc.bat up

:: 不要になったらアタッチを解除する
container\wslc.bat usb-detach 2-3
```

コンテナへ渡すデバイスパスは環境変数 `USB_DEVICES`（既定 `/dev/bus/usb`）で変更できます。
複数指定する場合は空白区切りで指定してください。

```bat
set USB_DEVICES=/dev/bus/usb /dev/dvb
container\wslc.bat up
```

### Windows 固有の制約

- **PCIe デバイスは非対応**: usbipd-win は USB デバイスのみが対象のため、PT3/PX-W3U4 等の
  PCIe 接続チューナーはこの方式ではパススルーできません。PCIe チューナーが必要な場合は
  Linux ホスト（`podman.sh` / `mirakurun.container`）を利用してください。
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
| `USB_DEVICES` | `/dev/bus/usb` | コンテナへ渡す USB デバイスパス（空白区切りで複数可） |
| `DISABLE_PCSCD` | `0` | `1` でコンテナ内 pcscd を無効化 |
| `DISABLE_B25_TEST` | `0` | `1` で arib-b25-stream-test の導入をスキップ |
