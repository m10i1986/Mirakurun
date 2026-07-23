@echo off
setlocal EnableDelayedExpansion
rem =============================================================================
rem wslc.bat - Windows (CLI only) setup & Mirakurun launch script using WSL Container (wslc)
rem
rem Does not use GUI apps such as Docker Desktop / Podman Desktop, nor Podman
rem machine (Hyper-V VM). Runs Linux containers directly using Microsoft's
rem WSL Container feature (wslc.exe, "WSL container"), available in
rem WSL 2.9.3 and later.
rem   Reference: https://gihyo.jp/article/2026/06/wsl-container
rem
rem This script assumes wslc has a Docker CLI compatible command set
rem (run/build/exec/ps/logs, etc). It is based on information from the
rem 2026-06 public preview; command/option names may change before general
rem availability.
rem
rem USB tuners are attached to WSL2 via usbipd-win and passed through to the
rem container. Since wslc runs containers directly on WSL2 (no extra VM layer
rem like the Podman machine approach), a device attached via usbipd shows up
rem as a plain Linux device and can be passed with --device as-is.
rem
rem This is the Windows equivalent of container/podman.sh (Linux rootless).
rem
rem Prerequisites:
rem   - Windows 10 (2004+) / 11 with WSL2 available
rem   - Run as Administrator (needed for WSL2 feature update, usbipd-win
rem     install, and USB attach)
rem   - winget (App Installer) available
rem
rem Usage (from Command Prompt):
rem   container\wslc.bat setup        Update WSL2 + verify wslc install (admin required)
rem   container\wslc.bat usb-list     List USB devices (to find the busid to attach)
rem   container\wslc.bat usb-attach ^<busid^>  Attach a USB device to WSL2
rem   container\wslc.bat usb-detach ^<busid^>  Detach a USB device
rem   container\wslc.bat build        Build the image
rem   container\wslc.bat up           Start the container detached (restart=always)
rem   container\wslc.bat down         Stop and remove the container
rem   container\wslc.bat restart      Restart the container (down + up)
rem   container\wslc.bat rebuild      Run build + down + up in sequence
rem   container\wslc.bat logs         Follow the container logs
rem   container\wslc.bat bash         Open bash in the running container
rem   container\wslc.bat run          Start once, interactively (--rm)
rem   container\wslc.bat setup-container  Start once for setup (SETUP=true, --rm)
rem   container\wslc.bat debug        Start once in debug mode (DEBUG=true, --rm)
rem
rem Environment variables (set before running setup):
rem   MIRAKURUN_VOLUMES_DIR   Volume directory (default: %USERPROFILE%\mirakurun\volumes)
rem   MIRAKURUN_IMAGE_TAG     Image tag (default: latest)
rem   USB_DEVICES             Space-separated USB device paths to pass to the
rem                           container (default: /dev/bus/usb). After
rem                           usb-attach, check the actual device path inside
rem                           WSL2 with `wsl -- lsusb` etc.
rem   DISABLE_PCSCD           1 to disable pcscd inside the container (default: 0)
rem   DISABLE_B25_TEST        1 to skip installing arib-b25-stream-test (default: 0)
rem
rem Notes (Windows-specific limitations):
rem   - USB tuners are attached to WSL2 via usbipd-win. PCIe tuners
rem     (PT3/PX-W3U4, etc) cannot be passed through this way. Use a Linux
rem     host (container/podman.sh) if a PCIe tuner is required.
rem   - Devices attached with usbipd-win must be re-attached after a Windows
rem     reboot or USB unplug/replug. For persistent operation, consider
rem     "usbipd bind --persistent" or an auto-attach Scheduled Task.
rem   - wslc is a preview feature. Commands/options may change before
rem     general availability.
rem =============================================================================

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_ROOT=%%~fI"

if not defined MIRAKURUN_IMAGE_TAG set "MIRAKURUN_IMAGE_TAG=latest"
if not defined MIRAKURUN_VOLUMES_DIR set "MIRAKURUN_VOLUMES_DIR=%USERPROFILE%\mirakurun\volumes"
if not defined DOCKERFILE set "DOCKERFILE=Containerfile"
if not defined USB_DEVICES set "USB_DEVICES=/dev/bus/usb"

set "IMAGE=localhost/chinachu/mirakurun:%MIRAKURUN_IMAGE_TAG%"
set "CONTAINER=mirakurun"

set "SUBCOMMAND=%~1"
if "%SUBCOMMAND%"=="" set "SUBCOMMAND=help"

goto :dispatch

rem -----------------------------------------------------------------------------
:dispatch
if /i "%SUBCOMMAND%"=="setup"           goto :cmd_setup_env
if /i "%SUBCOMMAND%"=="usb-list"        goto :cmd_usb_list
if /i "%SUBCOMMAND%"=="usb-attach"      goto :cmd_usb_attach
if /i "%SUBCOMMAND%"=="usb-detach"      goto :cmd_usb_detach
if /i "%SUBCOMMAND%"=="build"           goto :cmd_build
if /i "%SUBCOMMAND%"=="up"              goto :cmd_up
if /i "%SUBCOMMAND%"=="down"            goto :cmd_down
if /i "%SUBCOMMAND%"=="restart"         goto :cmd_restart
if /i "%SUBCOMMAND%"=="rebuild"         goto :cmd_rebuild
if /i "%SUBCOMMAND%"=="logs"            goto :cmd_logs
if /i "%SUBCOMMAND%"=="bash"            goto :cmd_bash
if /i "%SUBCOMMAND%"=="run"             goto :cmd_run
if /i "%SUBCOMMAND%"=="setup-container" goto :cmd_setup_container
if /i "%SUBCOMMAND%"=="debug"           goto :cmd_debug
if /i "%SUBCOMMAND%"=="help"            goto :usage
if /i "%SUBCOMMAND%"=="-h"              goto :usage
if /i "%SUBCOMMAND%"=="--help"          goto :usage

echo unknown command: %SUBCOMMAND% 1>&2
echo.
call :usage
exit /b 1

rem -----------------------------------------------------------------------------
rem Administrator privilege check
rem -----------------------------------------------------------------------------
:require_admin
net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Administrator privileges are required. Reopen Command Prompt with "Run as administrator". 1>&2
  exit /b 1
)
exit /b 0

rem -----------------------------------------------------------------------------
rem setup: update WSL2 (installs wslc) + install usbipd-win
rem -----------------------------------------------------------------------------
:cmd_setup_env
call :require_admin
if errorlevel 1 exit /b 1

where wsl >nul 2>&1
if errorlevel 1 (
  echo [ERROR] wsl command not found. Verify WSL2 is available on Windows 10 (2004+) / 11. 1>&2
  exit /b 1
)

echo [1/3] Updating WSL2 to the latest pre-release build (includes wslc)...
wsl --update --pre-release
if errorlevel 1 (
  echo [ERROR] "wsl --update --pre-release" failed. 1>&2
  exit /b 1
)

where wslc >nul 2>&1
if errorlevel 1 (
  echo [ERROR] wslc command not found. Reopen Command Prompt after the WSL2 update and retry. 1>&2
  exit /b 1
) else (
  echo   wslc is available.
)

echo [2/3] Checking winget and installing usbipd-win (for USB tuner support)...
where winget >nul 2>&1
if errorlevel 1 (
  echo [WARN] winget not found. Skipping automatic usbipd-win install.
  echo        Install it manually if you need USB tuner support: https://github.com/dorssel/usbipd-win
) else (
  where usbipd >nul 2>&1
  if errorlevel 1 (
    winget install --id dorssel.usbipd-win -e --source winget --accept-package-agreements --accept-source-agreements
    if errorlevel 1 (
      echo [WARN] Failed to install usbipd-win automatically. Install it manually: https://github.com/dorssel/usbipd-win
    ) else (
      echo [WARN] Reopen Command Prompt so usbipd is picked up on PATH, then retry.
    )
  ) else (
    echo   usbipd is already installed.
  )
)

echo [3/3] Creating volume directories:
for %%D in (run opt config data) do (
  if not exist "%MIRAKURUN_VOLUMES_DIR%\%%D" (
    mkdir "%MIRAKURUN_VOLUMES_DIR%\%%D"
    echo   created: %MIRAKURUN_VOLUMES_DIR%\%%D
  )
)

echo.
echo Setup complete.
echo To use a USB tuner, attach it with:
echo   container\wslc.bat usb-list
echo   container\wslc.bat usb-attach ^<busid^>
echo.
echo Next, build and start the Mirakurun image with:
echo   container\wslc.bat build
echo   container\wslc.bat up
exit /b 0

rem -----------------------------------------------------------------------------
rem USB device operations (attach to WSL2 via usbipd-win)
rem -----------------------------------------------------------------------------
:cmd_usb_list
where usbipd >nul 2>&1
if errorlevel 1 (
  echo [ERROR] usbipd not found. Run "wslc.bat setup" first to install usbipd-win. 1>&2
  exit /b 1
)
usbipd list
exit /b %errorlevel%

:cmd_usb_attach
call :require_admin
if errorlevel 1 exit /b 1
where usbipd >nul 2>&1
if errorlevel 1 (
  echo [ERROR] usbipd not found. Run "wslc.bat setup" first to install usbipd-win. 1>&2
  exit /b 1
)
set "BUSID=%~2"
if "%BUSID%"=="" (
  echo [ERROR] Please specify a busid. Find it with "wslc.bat usb-list". 1>&2
  echo         Example: container\wslc.bat usb-attach 2-3 1>&2
  exit /b 1
)
rem Only needed the first time; ignore errors if already bound
usbipd bind --busid "%BUSID%" >nul 2>&1
usbipd attach --wsl --busid "%BUSID%"
if errorlevel 1 (
  echo [ERROR] usbipd attach failed. Verify the busid is correct and WSL2 is running. 1>&2
  exit /b 1
)
echo   Attached (busid=%BUSID%). Verify inside WSL2 with "wsl -- lsusb" etc.
exit /b 0

:cmd_usb_detach
where usbipd >nul 2>&1
if errorlevel 1 (
  echo [ERROR] usbipd not found. 1>&2
  exit /b 1
)
set "BUSID=%~2"
if "%BUSID%"=="" (
  echo [ERROR] Please specify a busid. 1>&2
  echo         Example: container\wslc.bat usb-detach 2-3 1>&2
  exit /b 1
)
usbipd detach --busid "%BUSID%"
exit /b %errorlevel%

rem -----------------------------------------------------------------------------
rem Mirakurun container operations (equivalent to container/podman.sh, assuming
rem a Docker-compatible wslc command set)
rem -----------------------------------------------------------------------------
:build_run_opts
rem RUN_OPTS is assembled per-command, so only shared variables are defined here
set "OPT_NAME=--name %CONTAINER%"
set "OPT_NETWORK=--network host"
set "OPT_CAPS=--cap-add SYS_ADMIN --cap-add SYS_NICE"
set "OPT_TMPFS=--tmpfs /tmp"
set "OPT_LOG=--log-driver json-file --log-opt max-size=10m"
if not defined DISABLE_PCSCD set "DISABLE_PCSCD=0"
if not defined DISABLE_B25_TEST set "DISABLE_B25_TEST=0"
set "OPT_ENV=--env TZ=Asia/Tokyo --env DISABLE_PCSCD=%DISABLE_PCSCD% --env DISABLE_B25_TEST=%DISABLE_B25_TEST% --env DOCKER_NETWORK=host"
set "OPT_VOLUMES=--volume %MIRAKURUN_VOLUMES_DIR%\run:/var/run --volume %MIRAKURUN_VOLUMES_DIR%\opt:/opt --volume %MIRAKURUN_VOLUMES_DIR%\config:/app-config --volume %MIRAKURUN_VOLUMES_DIR%\data:/app-data"

rem USB tuner: pass device paths attached to WSL2 via usbipd-win with --device
set "OPT_DEVICES="
if not "%USB_DEVICES%"=="" (
  for %%V in (%USB_DEVICES%) do set "OPT_DEVICES=!OPT_DEVICES! --device %%V"
)
exit /b 0

:cmd_build
wslc build -t "%IMAGE%" -f "%SCRIPT_DIR%%DOCKERFILE%" "%PROJECT_ROOT%"
exit /b %errorlevel%

:cmd_up
call :build_run_opts
wslc run -d --restart always %OPT_NAME% %OPT_NETWORK% %OPT_CAPS% %OPT_TMPFS% %OPT_LOG% %OPT_ENV% %OPT_VOLUMES% %OPT_DEVICES% "%IMAGE%"
exit /b %errorlevel%

:cmd_run
call :build_run_opts
wslc run --rm -it %OPT_NAME% %OPT_NETWORK% %OPT_CAPS% %OPT_TMPFS% %OPT_LOG% %OPT_ENV% %OPT_VOLUMES% %OPT_DEVICES% "%IMAGE%"
exit /b %errorlevel%

:cmd_setup_container
call :build_run_opts
wslc run --rm -it --env SETUP=true %OPT_NAME% %OPT_NETWORK% %OPT_CAPS% %OPT_TMPFS% %OPT_LOG% %OPT_ENV% %OPT_VOLUMES% %OPT_DEVICES% "%IMAGE%"
exit /b %errorlevel%

:cmd_debug
call :build_run_opts
wslc run --rm -it --env DEBUG=true %OPT_NAME% %OPT_NETWORK% %OPT_CAPS% %OPT_TMPFS% %OPT_LOG% %OPT_ENV% %OPT_VOLUMES% %OPT_DEVICES% "%IMAGE%"
exit /b %errorlevel%

:cmd_down
wslc stop "%CONTAINER%" >nul 2>&1
wslc rm "%CONTAINER%" >nul 2>&1
exit /b 0

:cmd_restart
call :cmd_down
call :cmd_up
exit /b %errorlevel%

:cmd_rebuild
call :cmd_build
if errorlevel 1 exit /b 1
call :cmd_restart
exit /b %errorlevel%

:cmd_logs
wslc logs -f "%CONTAINER%"
exit /b %errorlevel%

:cmd_bash
wslc exec -it "%CONTAINER%" bash
exit /b %errorlevel%

rem -----------------------------------------------------------------------------
:usage
echo wslc.bat - Windows (CLI only) setup ^& Mirakurun launch script using WSL Container (wslc)
echo.
echo Usage: container\wslc.bat ^<command^>
echo.
echo command:
echo   setup           Update WSL2 (installs wslc) + install usbipd-win (admin required)
echo   usb-list        List USB devices
echo   usb-attach ^<busid^>  Attach a USB device to WSL2 (admin required)
echo   usb-detach ^<busid^>  Detach a USB device
echo   build           Build the image
echo   setup-container Start once for setup (SETUP=true, --rm)
echo   run             Start once (--rm)
echo   debug           Start once in debug mode (DEBUG=true, --rm)
echo   up              Start the container detached (restart=always)
echo   down            Stop and remove the container
echo   restart         Restart the container (down + up)
echo   rebuild         Run build + down + up in sequence
echo   logs            Follow the container logs
echo   bash            Open bash in the running container
echo.
echo Environment variables:
echo   MIRAKURUN_VOLUMES_DIR   Volume directory (default: %%USERPROFILE%%\mirakurun\volumes)
echo   MIRAKURUN_IMAGE_TAG     Image tag (default: latest)
echo   USB_DEVICES             USB device paths to pass to the container (default: /dev/bus/usb)
echo   DISABLE_PCSCD           1 to disable pcscd inside the container (default: 0)
echo   DISABLE_B25_TEST        1 to skip installing arib-b25-stream-test (default: 0)
exit /b 0
