@echo off
rem =============================================================================
rem wslc.bat - Launcher for container\wslc.ps1
rem
rem All logic lives in wslc.ps1. This wrapper only exists so the script can be
rem started from Command Prompt or by double-clicking, without relaxing the
rem PowerShell execution policy machine-wide.
rem
rem Administrator elevation is handled by wslc.ps1 itself (UAC prompt), so this
rem file deliberately contains no privilege checks and no goto/call labels.
rem (Labels would break with "batch label not found" if the line endings were
rem  ever normalized to LF.)
rem
rem NOTE: This file is intentionally kept ASCII-only. A .bat cannot carry a
rem UTF-8 BOM (cmd would try to execute it), and Japanese text written as raw
rem UTF-8 would be mojibake under the CP932 console default. All user-facing
rem Japanese messages therefore live in wslc.ps1, saved as UTF-8 with BOM.
rem
rem Usage:
rem   container\wslc.bat ^<command^> [busid]
rem
rem When launched by double-click there are no arguments, so "setup" is run
rem automatically and the window is held open at the end.
rem =============================================================================

setlocal EnableDelayedExpansion

rem ---- Detect double-click launch ---------------------------------------------
rem When started from Explorer, cmdcmdline looks like
rem   cmd /c ""C:\...\wslc.bat" "
rem and therefore contains this batch file's name. When run interactively from
rem an existing Command Prompt, cmdcmdline is the shell itself
rem (e.g. "C:\WINDOWS\system32\cmd.exe") and does not contain it.
set "LAUNCHED_BY_EXPLORER="
if "%~1"=="" (
    echo !cmdcmdline! | find /i "%~nx0" >nul 2>&1 && set "LAUNCHED_BY_EXPLORER=1"
)

rem ---- Decide the arguments to forward ----------------------------------------
rem Explicit arguments always win. Only a double-click (no arguments) defaults
rem to "setup"; running "wslc.bat" from a prompt still shows the usage text.
set "PS_ARGS=%*"
if defined LAUNCHED_BY_EXPLORER set "PS_ARGS=setup -FromDoubleClick"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0wslc.ps1" !PS_ARGS!
set "RC=!ERRORLEVEL!"

rem Hold the window open so the result stays readable after a double-click.
rem The actual setup log appears in the UAC-elevated window, which pauses too.
if defined LAUNCHED_BY_EXPLORER pause

endlocal & exit /b %RC%
