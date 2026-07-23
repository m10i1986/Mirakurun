<#
.SYNOPSIS
  run.ps1 - WSL Container (wslc) を使った Windows 向け Mirakurun セットアップ／起動スクリプト

.DESCRIPTION
  Docker Desktop / Podman Desktop のような GUI アプリも、Podman machine
  (Hyper-V VM) も使用しません。Microsoft が WSL 2.9.3 以降で提供する
  WSL Container 機能 (wslc.exe) を用いて、Linux コンテナを直接実行します。
    参考: https://gihyo.jp/article/2026/06/wsl-container

  本スクリプトは wslc が Docker CLI 互換のコマンド体系
  (run / build / exec / ps / logs 等) を持つ前提で実装しています。
  2026-06 時点のパブリックプレビュー情報に基づいているため、
  正式リリースまでにコマンドやオプションが変更される可能性があります。

  USB チューナーは usbipd-win で WSL2 へアタッチできますが、コンテナへの
  パススルーは現時点では行えません。wslc run に --device 相当のオプションが
  無いためです ("wslc run --help" で確認: WSL 2.9.3 時点)。
  usb-list / usb-attach / usb-detach は WSL2 へのアタッチ手段として残して
  ありますが、コンテナ内の Mirakurun からチューナーは見えません。
  USB チューナーを使う場合は Linux ホストで docker/ 配下の構成を利用して
  ください。

  Linux 向けの docker/ 配下の構成に対応する Windows 版です。

  管理者権限が必要なコマンド (setup / usb-attach) は UAC により自動昇格するため、
  あらかじめ管理者としてプロンプトを開いておく必要はありません。

.PARAMETER Command
  setup             WSL2 の更新 + wslc の導入確認 (自動昇格)
  usb-list          USB デバイス一覧を表示 (アタッチ対象の busid 確認用)
  usb-attach        USB デバイスを WSL2 へアタッチ (自動昇格)
  usb-detach        USB デバイスのアタッチを解除
  build             イメージをビルド
  up                コンテナをデタッチ起動 (自動再起動は非対応)
  down              コンテナを停止・削除
  restart           コンテナを再起動 (down + up)
  rebuild           build + down + up を連続実行
  logs              コンテナのログを追従表示
  bash              起動中コンテナで bash を開く
  run               一度だけ対話起動 (--rm)
  setup-container   セットアップ用に一度だけ起動 (SETUP=true, --rm)
  debug             デバッグモードで一度だけ起動 (DEBUG=true, --rm)

.PARAMETER BusId
  usb-attach / usb-detach で使用する usbipd の bus id (例: 2-3)。

.PARAMETER NoElevate
  内部フラグ。昇格して再実行されたプロセスに自動付与され、昇格ループを防ぎます。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File wsl-container\run.ps1 setup

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File wsl-container\run.ps1 usb-attach 2-3

.NOTES
  環境変数 (実行前に設定):
    MIRAKURUN_VOLUMES_DIR   ボリューム配置先 (既定: %USERPROFILE%\mirakurun\volumes)
    MIRAKURUN_IMAGE_TAG     イメージタグ (既定: latest)
    USB_DEVICES             現時点では未使用 (既定: /dev/bus/usb)。wslc run が
                            --device に対応していないため、コンテナへは渡せません。
                            将来 wslc が対応した際に復帰させる想定で残しています。
    PUBLISH_PORTS           コンテナへ公開するポートを空白区切りで指定
                            (既定: 40772:40772)。wslc がホストモードネット
                            ワーキング非対応のため --publish で公開します。
                            例: set PUBLISH_PORTS=40772:40772 9229:9229
    DISABLE_PCSCD           1 でコンテナ内 pcscd を無効化 (既定: 0)
    DISABLE_B25_TEST        1 で arib-b25-stream-test の導入をスキップ (既定: 0)

  Windows 固有の制約:
    - チューナーは USB / PCIe いずれもコンテナへパススルーできません。USB は
      usbipd-win で WSL2 までアタッチできますが、wslc run に --device 相当の
      オプションが無いためコンテナへ渡せません。PT3/PX-W3PE 等の PCIe 接続
      チューナーは WSL2 自体がパススルーに対応していません。
      チューナーを使う場合は Linux ホストで docker/ 配下の構成を利用して
      ください。
    - usbipd-win でアタッチしたデバイスは Windows 再起動や USB の抜き差しの度に
      再アタッチが必要です。恒常運用する場合は "usbipd bind --persistent" や
      タスクスケジューラでの自動アタッチを検討してください。
    - wslc run は --cap-add / --log-driver / --log-opt / --restart に対応して
      いません。このため Docker / Podman と比べ、capability 追加・ログ
      ローテーション設定・コンテナの自動再起動が行えません。
    - wslc はホストモードネットワーキング (--network host) に対応していません。
      ポートは --publish で個別に公開します
      (既定: 40772)。Web UI へは http://localhost:40772/ でアクセスします。
    - wslc はプレビュー機能です。正式リリースまでにコマンドやオプションが
      変更される可能性があります。
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Command = 'help',

    [Parameter(Position = 1)]
    [string] $BusId,

    [switch] $NoElevate,

    # run.bat がダブルクリック起動を検知した際に付与する。
    # 引数無し起動を help ではなく setup として扱った旨を利用者へ知らせる。
    [switch] $FromDoubleClick
)

Set-StrictMode -Version Latest

# 'Stop' ではなく 'Continue' とする理由:
# 以降で呼び出す外部コマンド (wsl / wslc / usbipd / winget) は、すべて
# $LASTEXITCODE で明示的に成否を判定しています。'Stop' の場合、ネイティブ
# ツールが stderr へ出力しただけで終了エラーが発生し、その判定に到達しません。
# 「既にバインド済みの usbipd bind」のように、意図的に握り潰したいケースが
# 壊れてしまうため 'Continue' を選択しています。
$ErrorActionPreference = 'Continue'

# $LASTEXITCODE は最初のネイティブコマンド実行まで未定義です。Set-StrictMode
# 下では未定義変数の参照がエラーになるため、あらかじめ初期化しておきます。
$global:LASTEXITCODE = 0

# ---- パス解決 ----------------------------------------------------------------
$ScriptPath  = $MyInvocation.MyCommand.Path
$ScriptDir   = Split-Path -Parent $ScriptPath
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir '..')).Path

# ---- 設定値 (docker/docker-compose.yml と対応) -------------------------------
function Get-EnvOrDefault {
    param([string] $Name, [string] $Default)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

$ImageTag       = Get-EnvOrDefault 'MIRAKURUN_IMAGE_TAG'   'latest'
$VolumesDir     = Get-EnvOrDefault 'MIRAKURUN_VOLUMES_DIR' (Join-Path $env:USERPROFILE 'mirakurun\volumes')
$Dockerfile     = Get-EnvOrDefault 'DOCKERFILE'            'Containerfile'
# 現時点では未使用。wslc run が --device に対応していないため Get-RunOptions から
# 参照していません。将来 wslc が対応した際に復帰させる想定で残しています。
$UsbDevices     = Get-EnvOrDefault 'USB_DEVICES'           '/dev/bus/usb'
# wslc がホストモードネットワーキング非対応のため --publish で公開するポート。
# 40772 は Mirakurun の API / Web UI。9229 (Node デバッガ) は既定では公開しません。
$PublishPorts   = Get-EnvOrDefault 'PUBLISH_PORTS'         '40772:40772'
$DisablePcscd   = Get-EnvOrDefault 'DISABLE_PCSCD'         '0'
$DisableB25Test = Get-EnvOrDefault 'DISABLE_B25_TEST'      '0'

$Image     = "localhost/chinachu/mirakurun:${ImageTag}"
$Container = 'mirakurun'

# ---- コンソール出力ヘルパー --------------------------------------------------
function Write-Info  { param([string] $Message) Write-Host $Message }
function Write-Step  { param([string] $Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Warn  { param([string] $Message) Write-Host "[警告] $Message" -ForegroundColor Yellow }
function Write-Err   { param([string] $Message) Write-Host "[エラー] $Message" -ForegroundColor Red }

function Test-CommandExists {
    param([string] $Name)
    return [bool] (Get-Command $Name -ErrorAction SilentlyContinue)
}

# ---- 管理者権限の処理 --------------------------------------------------------
function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

<#
  UAC で自身を昇格して再実行し、終了を待ちます。

  昇格したプロセスは新しいコンソールウィンドウで起動するため、その出力は
  現在のウィンドウからは見えません。子プロセスの終了コードはここへ伝播させ、
  子プロセス側は Wait-ForKeyIfElevatedChild で結果を読める時間を確保します。
#>
function Invoke-SelfElevate {
    param(
        [Parameter(Mandatory)] [string]   $TargetCommand,
        [string[]] $ExtraArgs = @()
    )

    if ($NoElevate) {
        # 一度昇格して再実行したにもかかわらず、まだ管理者ではない場合。
        # 無限ループを避けるためここで中断します。
        Write-Err '管理者権限が必要ですが、昇格が反映されませんでした。'
        Write-Err 'PowerShell を「管理者として実行」で開き直してから再試行してください。'
        return 1
    }

    Write-Step "'$TargetCommand' には管理者権限が必要です。UAC による昇格を要求します..."

    # PowerShell 7 以降は pwsh.exe、Windows PowerShell は powershell.exe
    $psHost = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }

    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', $ScriptPath
        $TargetCommand
    )
    $argList += $ExtraArgs
    $argList += '-NoElevate'

    try {
        $proc = Start-Process -FilePath $psHost `
                              -ArgumentList $argList `
                              -Verb RunAs `
                              -PassThru `
                              -Wait
    }
    catch {
        # UAC ダイアログをキャンセルした場合など。
        Write-Err "昇格がキャンセルされたか、失敗しました: $($_.Exception.Message)"
        return 1
    }

    if ($proc.ExitCode -ne 0) {
        Write-Err "昇格したプロセスが終了コード $($proc.ExitCode) で終了しました。"
    }
    return $proc.ExitCode
}

<#
  現在のプロセスが昇格済みであることを確認します。
  そのまま処理を続行してよい場合は $true を返します。
  昇格した子プロセスへ処理を委譲した (または昇格を拒否された) 場合は $false を
  返し、伝播すべき終了コードを $script:ElevatedExitCode に格納します。
#>
$script:ElevatedExitCode = 0
function Assert-Administrator {
    param(
        [Parameter(Mandatory)] [string]   $TargetCommand,
        [string[]] $ExtraArgs = @()
    )

    if (Test-Administrator) { return $true }

    $script:ElevatedExitCode = Invoke-SelfElevate -TargetCommand $TargetCommand -ExtraArgs $ExtraArgs
    return $false
}

<#
  自動昇格したウィンドウを、結果を読める程度に開いたままにします。
  Invoke-SelfElevate から起動された場合のみ一時停止します
  (手動で昇格したシェルは自身のウィンドウが残るため不要)。
#>
function Wait-ForKeyIfElevatedChild {
    if (-not $NoElevate) { return }
    if ([Environment]::UserInteractive -eq $false) { return }
    Write-Info ''
    Write-Info '何かキーを押すとこのウィンドウを閉じます...'
    try { [void] $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { }
}

# ---- 共通 run オプションの組み立て (docker/docker-compose.yml と対応) --------
<#
  wslc run がサポートするオプションのみで構成します。
  Docker / Podman には存在するものの wslc run が受け付けないため、意図的に
  外しているオプションは以下の通りです
  ("wslc run --help" で確認: WSL 2.9.3 時点)。

    --cap-add SYS_ADMIN / SYS_NICE
        wslc に capability を追加する手段がありません。Mirakurun 本体の動作に
        必須ではないため省略します。
    --log-driver / --log-opt
        ログドライバを選択できません。ログは wslc の既定動作に従います
        (ローテーション設定は不可)。
    --device
        デバイスを個別にパススルーする手段がありません。詳細は下の
        USB チューナーに関する注記を参照してください。
    --network host
        wslc は "ホスト モード ネットワーキングはサポートされていません" と
        して拒否します。代わりに --publish でポートを個別に公開します。
        これに伴い DOCKER_NETWORK=host も渡しません (下記参照)。

  いずれも wslc 側が対応した時点で Docker / Podman 版と揃え直せます。
#>
function Get-RunOptions {
    $opts = @(
        '--name', $Container
        '--tmpfs', '/tmp'
        '--env', 'TZ=Asia/Tokyo'
        '--env', "DISABLE_PCSCD=$DisablePcscd"
        '--env', "DISABLE_B25_TEST=$DisableB25Test"
        '--volume', "${VolumesDir}\run:/var/run"
        '--volume', "${VolumesDir}\opt:/opt"
        '--volume', "${VolumesDir}\config:/app-config"
        '--volume', "${VolumesDir}\data:/app-data"
    )

    # ホストモードが使えないため、ポートを個別に公開します。
    #
    # DOCKER_NETWORK は意図的に設定していません。src/Mirakurun/config.ts では
    # DOCKER_NETWORK が "host" 以外のとき port=40772 / disableIPv6=true を
    # 強制します。これはまさにブリッジ接続時に必要な設定であり、--publish で
    # 公開するポートとも一致するため、未設定のままとするのが正しい挙動です。
    foreach ($port in ($PublishPorts -split '\s+' | Where-Object { $_ })) {
        $opts += @('--publish', $port)
    }

    # USB チューナーのパススルーは現時点では実現できません。
    # usbipd-win で WSL2 へアタッチするところまでは従来どおり動作しますが、
    # wslc run に --device 相当のオプションが無いため、アタッチしたデバイスを
    # コンテナへ渡せません。$UsbDevices は将来 wslc が対応した際に復帰させる
    # ため設定値としては残していますが、run オプションには反映しません。
    return $opts
}

function Assert-WslcAvailable {
    if (-not (Test-CommandExists 'wslc')) {
        Write-Err 'wslc コマンドが見つかりません。先に "run.ps1 setup" を実行し、PowerShell を開き直してください。'
        return $false
    }
    return $true
}

# ---- サブコマンド ------------------------------------------------------------
function Invoke-SetupEnv {
    if (-not (Assert-Administrator -TargetCommand 'setup')) { return $script:ElevatedExitCode }

    if (-not (Test-CommandExists 'wsl')) {
        Write-Err 'wsl コマンドが見つかりません。Windows 10 (2004+) / 11 で WSL2 が利用可能か確認してください。'
        return 1
    }

    Write-Step '[1/3] WSL2 を最新のプレリリース版へ更新しています (wslc を含む)...'
    & wsl --update --pre-release
    if ($LASTEXITCODE -ne 0) {
        Write-Err '"wsl --update --pre-release" が失敗しました。'
        return 1
    }

    if (Test-CommandExists 'wslc') {
        Write-Info '  wslc が利用可能です。'
    }
    else {
        Write-Warn 'wslc がまだ PATH 上に見つかりません。WSL2 更新後に PowerShell を開き直し、"wslc --version" で確認してください。'
    }

    Write-Step '[2/3] winget を確認し、usbipd-win を導入しています (USB チューナー対応用)...'
    if (-not (Test-CommandExists 'winget')) {
        Write-Warn 'winget が見つかりません。usbipd-win の自動導入をスキップします。'
        Write-Info '       USB チューナーが必要な場合は手動で導入してください: https://github.com/dorssel/usbipd-win'
    }
    elseif (Test-CommandExists 'usbipd') {
        Write-Info '  usbipd は導入済みです。'
    }
    else {
        & winget install --id dorssel.usbipd-win -e --source winget `
                 --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'usbipd-win の自動導入に失敗しました。手動で導入してください: https://github.com/dorssel/usbipd-win'
        }
        else {
            Write-Warn 'usbipd を PATH で認識させるため、PowerShell を開き直してから再試行してください。'
        }
    }

    Write-Step '[3/3] ボリュームディレクトリを作成しています:'
    foreach ($dir in @('run', 'opt', 'config', 'data')) {
        $path = Join-Path $VolumesDir $dir
        if (-not (Test-Path -LiteralPath $path)) {
            [void] (New-Item -ItemType Directory -Path $path -Force)
            Write-Info "  作成しました: $path"
        }
    }

    Write-Info ''
    Write-Info 'セットアップが完了しました。'
    Write-Info 'USB チューナーを使う場合は、以下でアタッチしてください:'
    Write-Info '  wsl-container\run.bat usb-list'
    Write-Info '  wsl-container\run.bat usb-attach <busid>'
    Write-Info ''
    Write-Info '続いて、以下で Mirakurun イメージのビルドと起動を行ってください:'
    Write-Info '  wsl-container\run.bat build'
    Write-Info '  wsl-container\run.bat up'
    return 0
}

function Invoke-UsbList {
    if (-not (Test-CommandExists 'usbipd')) {
        Write-Err 'usbipd が見つかりません。先に "run.bat setup" を実行して usbipd-win を導入してください。'
        return 1
    }
    & usbipd list
    return $LASTEXITCODE
}

function Invoke-UsbAttach {
    if ([string]::IsNullOrWhiteSpace($BusId)) {
        Write-Err 'busid を指定してください。"run.bat usb-list" で確認できます。'
        Write-Err '        例: wsl-container\run.bat usb-attach 2-3'
        return 1
    }

    if (-not (Assert-Administrator -TargetCommand 'usb-attach' -ExtraArgs @($BusId))) {
        return $script:ElevatedExitCode
    }

    if (-not (Test-CommandExists 'usbipd')) {
        Write-Err 'usbipd が見つかりません。先に "run.bat setup" を実行して usbipd-win を導入してください。'
        return 1
    }

    # 初回のみ必要。既にバインド済みの場合のエラーは無視する。
    & usbipd bind --busid $BusId 2>&1 | Out-Null

    & usbipd attach --wsl --busid $BusId
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'usbipd attach に失敗しました。busid が正しいか、WSL2 が起動しているか確認してください。'
        return 1
    }

    Write-Info "  アタッチしました (busid=$BusId)。WSL2 内で `"wsl -- lsusb`" 等を実行して確認してください。"
    Write-Info ''
    Write-Warn 'wslc run には --device 相当のオプションが無いため、アタッチしたチューナーをコンテナへ渡すことは現時点ではできません。'
    Write-Info '       WSL2 上ではデバイスを認識しますが、コンテナ内の Mirakurun からは利用できません。'
    Write-Info '       USB チューナーを使う場合は、当面 Linux ホストで docker/ 配下の構成を利用してください。'
    return 0
}

function Invoke-UsbDetach {
    if ([string]::IsNullOrWhiteSpace($BusId)) {
        Write-Err 'busid を指定してください。'
        Write-Err '        例: wsl-container\run.bat usb-detach 2-3'
        return 1
    }
    if (-not (Test-CommandExists 'usbipd')) {
        Write-Err 'usbipd が見つかりません。'
        return 1
    }
    & usbipd detach --busid $BusId
    return $LASTEXITCODE
}

function Invoke-Build {
    if (-not (Assert-WslcAvailable)) { return 1 }
    $dockerfilePath = Join-Path $ScriptDir $Dockerfile
    Write-Step "[ビルド] イメージ '$Image' をビルドしています..."
    Write-Info "  Containerfile: $dockerfilePath"
    Write-Info "  コンテキスト  : $ProjectRoot"
    Write-Info '  (ビルドログをそのまま表示します。完了まで数分かかる場合があります)'
    # wslc build の進捗ログはそのまま画面へ流れる。
    & wslc build -t $Image -f $dockerfilePath $ProjectRoot
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        Write-Info ''
        Write-Info "  ビルドが完了しました: $Image"
    }
    else {
        Write-Err "ビルドに失敗しました (終了コード $code)。上の wslc の出力を確認してください。"
    }
    return $code
}

function Invoke-Up {
    if (-not (Assert-WslcAvailable)) { return 1 }
    # splat には変数が必要 (@runOpts)。@(...) だと配列が 1 引数に潰れてしまうため、
    # 必ずいったんローカル変数へ格納してから渡す。
    $runOpts = Get-RunOptions
    Write-Step "[起動] イメージ '$Image' をデタッチ起動しています..."
    # Docker / Podman の "--restart always" に相当するオプションが wslc run には
    # ありません。ホストや WSL2 の再起動後は "run.bat up" で起動し直します。
    # wslc run -d の出力 (コンテナID) はそのまま画面へ表示されます。
    & wslc run -d @runOpts $Image
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        # デタッチ起動は run コマンド自体が即座に返るため、実際に起動したかは
        # wslc ps で確認して結果を見せる。
        Write-Step '[確認] 起動状態を確認しています (wslc ps)...'
        & wslc ps
        Write-Info ''
        Write-Info "  起動しました。Web UI: http://localhost:40772/"
        Write-Warn 'wslc は自動再起動 (--restart always) に対応していません。Windows や WSL2 を再起動した後は "wsl-container\run.bat up" で起動し直してください。'
    }
    else {
        Write-Err "コンテナの起動に失敗しました (終了コード $code)。上の wslc の出力を確認してください。"
    }
    return $code
}

function Invoke-Run {
    if (-not (Assert-WslcAvailable)) { return 1 }
    $runOpts = Get-RunOptions
    & wslc run --rm -it @runOpts $Image
    return $LASTEXITCODE
}

function Invoke-SetupContainer {
    if (-not (Assert-WslcAvailable)) { return 1 }
    $runOpts = Get-RunOptions
    Write-Step '[setup-container] SETUP=true で一度だけコンテナを起動します...'
    Write-Info  '  DB (services / programs) を読み込み、完了すると "setup is done." と表示して自動終了します。'
    Write-Info  '  コンテナ内のログをそのまま表示します。'
    # 注意: entrypoint.sh は SETUP の分岐 (server.js 内) に到達する前に pcscd を
    # 起動する。Windows / wslc 環境ではカードリーダーをコンテナへ渡せないため、
    # DISABLE_PCSCD=1 を指定していないと pcscd が検出に失敗し続け、
    # "starting pcscd..." / "failed!" を繰り返して SETUP 処理まで進まない。
    # その場合は Ctrl+C で中断し、環境変数 DISABLE_PCSCD=1 を設定して再実行する。
    if ($DisablePcscd -ne '1') {
        Write-Warn 'DISABLE_PCSCD=1 が未設定です。カードリーダー未接続の環境では pcscd の起動が'
        Write-Warn '        繰り返し失敗し、"setup is done." まで到達しないことがあります。'
        Write-Info  '       その場合は Ctrl+C で中断し、次のように再実行してください:'
        Write-Info  '         set DISABLE_PCSCD=1'
        Write-Info  '         wsl-container\run.bat setup-container'
    }
    & wslc run --rm -it --env SETUP=true @runOpts $Image
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        Write-Info ''
        Write-Info '  setup-container が完了しました。'
    }
    else {
        Write-Err "setup-container が終了コード $code で終了しました (Ctrl+C による中断も含みます)。"
    }
    return $code
}

function Invoke-Debug {
    if (-not (Assert-WslcAvailable)) { return 1 }
    $runOpts = Get-RunOptions
    & wslc run --rm -it --env DEBUG=true @runOpts $Image
    return $LASTEXITCODE
}

function Invoke-Down {
    if (-not (Assert-WslcAvailable)) { return 1 }

    # 停止・削除 (コンテナが存在しなくてもエラーにしない)。
    # 従来は "2>&1 | Out-Null" で全出力を握り潰していたため、実行しても
    # 無反応に見えていた。ここでは wslc の生出力をそのまま画面へ流し、
    # 「対象コンテナが無い」場合のみ握り潰したい意図を残すため、終了コードは
    # 判定せず常に 0 を返す (存在しなくても正常終了扱い)。
    Write-Step "[停止] コンテナ '$Container' を停止しています..."
    & wslc stop $Container
    Write-Step "[削除] コンテナ '$Container' を削除しています..."
    & wslc rm   $Container
    Write-Info "  停止・削除の処理を実行しました (対象が無い場合は上のメッセージを無視してください)。"
    return 0
}

function Invoke-Restart {
    Write-Step '=== restart: down -> up を実行します ==='
    $code = Invoke-Down
    if ($code -ne 0) { return $code }
    return Invoke-Up
}

function Invoke-Rebuild {
    Write-Step '=== rebuild: build -> down -> up を実行します ==='
    $code = Invoke-Build
    if ($code -ne 0) { return $code }
    return Invoke-Restart
}

function Invoke-Logs {
    if (-not (Assert-WslcAvailable)) { return 1 }
    & wslc logs -f $Container
    return $LASTEXITCODE
}

function Invoke-Bash {
    if (-not (Assert-WslcAvailable)) { return 1 }
    & wslc exec -it $Container bash
    return $LASTEXITCODE
}

function Show-Usage {
    Write-Info 'run.ps1 - WSL Container (wslc) を使った Windows 向け Mirakurun セットアップ／起動スクリプト'
    Write-Info ''
    Write-Info '使い方: wsl-container\run.bat <command> [busid]'
    Write-Info ''
    Write-Info 'command:'
    Write-Info '  setup           WSL2 を更新 (wslc 導入) + usbipd-win を導入 (自動昇格)'
    Write-Info '  usb-list        USB デバイス一覧を表示'
    Write-Info '  usb-attach <busid>  USB デバイスを WSL2 へアタッチ (自動昇格)'
    Write-Info '  usb-detach <busid>  USB デバイスのアタッチを解除'
    Write-Info '  build           イメージをビルド'
    Write-Info '  setup-container セットアップ用に一度だけ起動 (SETUP=true, --rm)'
    Write-Info '  run             一度だけ起動 (--rm)'
    Write-Info '  debug           デバッグモードで一度だけ起動 (DEBUG=true, --rm)'
    Write-Info '  up              コンテナをデタッチ起動 (自動再起動は非対応)'
    Write-Info '  down            コンテナを停止・削除'
    Write-Info '  restart         コンテナを再起動 (down + up)'
    Write-Info '  rebuild         build + down + up を連続実行'
    Write-Info '  logs            コンテナのログを追従表示'
    Write-Info '  bash            起動中コンテナで bash を開く'
    Write-Info ''
    Write-Info '環境変数:'
    Write-Info '  MIRAKURUN_VOLUMES_DIR   ボリューム配置先 (既定: %USERPROFILE%\mirakurun\volumes)'
    Write-Info '  MIRAKURUN_IMAGE_TAG     イメージタグ (既定: latest)'
    Write-Info '  USB_DEVICES             現時点では未使用 (wslc が --device 非対応のため)'
    Write-Info '  PUBLISH_PORTS           公開するポート (既定: 40772:40772)'
    Write-Info '  DISABLE_PCSCD           1 でコンテナ内 pcscd を無効化 (既定: 0)'
    Write-Info '  DISABLE_B25_TEST        1 で arib-b25-stream-test の導入をスキップ (既定: 0)'
    return 0
}

# ---- ダブルクリック起動時の案内 ----------------------------------------------
# run.bat は引数無し (= ダブルクリック) を setup として扱う。利用者には
# 何が起きているかと、他のコマンドの実行方法を明示する。
if ($FromDoubleClick -and -not $NoElevate) {
    Write-Step 'ダブルクリックで起動されたため、setup を実行します。'
    Write-Info '他のコマンドを実行する場合は、コマンドプロンプトから'
    Write-Info '  run.bat <command>'
    Write-Info 'のように指定してください。使い方は "run.bat help" で確認できます。'
    Write-Info ''
}

# ---- ディスパッチ ------------------------------------------------------------
$exitCode = switch ($Command.ToLowerInvariant()) {
    'setup'           { Invoke-SetupEnv }
    'usb-list'        { Invoke-UsbList }
    'usb-attach'      { Invoke-UsbAttach }
    'usb-detach'      { Invoke-UsbDetach }
    'build'           { Invoke-Build }
    'up'              { Invoke-Up }
    'down'            { Invoke-Down }
    'restart'         { Invoke-Restart }
    'rebuild'         { Invoke-Rebuild }
    'logs'            { Invoke-Logs }
    'bash'            { Invoke-Bash }
    'run'             { Invoke-Run }
    'setup-container' { Invoke-SetupContainer }
    'debug'           { Invoke-Debug }
    { $_ -in 'help', '-h', '--help' } { Show-Usage }
    default {
        Write-Err "不明なコマンド: $Command"
        Write-Info ''
        [void] (Show-Usage)
        1
    }
}

Wait-ForKeyIfElevatedChild
exit $exitCode
