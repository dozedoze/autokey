@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0.."

:: ============================================================
:: AutoKey — Windows 一键打包（体积优先）
:: 在 Windows 上运行；macOS 请用 GitHub Actions
:: ============================================================

set "AHK_VERSION=2.0.19"
set "TOOLS_DIR=%CD%\tools\ahk"
set "OUT_DIR=%CD%\dist"
set "SRC=%CD%\src\AutoKey.ahk"
set "OUT_EXE=%OUT_DIR%\AutoKey.exe"

echo.
echo [AutoKey] 准备打包环境...
if not exist "%OUT_DIR%\configs" mkdir "%OUT_DIR%\configs"
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"

set "AHK_BASE="
set "AHK2EXE="

call :FindAhk
if defined AHK_BASE if defined AHK2EXE goto :Compile

echo [AutoKey] 未找到 AutoHotkey，正在静默安装 %AHK_VERSION% ...
set "SETUP=%TEMP%\ahk_v2_setup.exe"
powershell -NoProfile -Command ^
  "$urls=@('https://github.com/AutoHotkey/AutoHotkey/releases/download/v%AHK_VERSION%/AutoHotkey_%AHK_VERSION%_setup.exe','https://www.autohotkey.com/download/ahk-v2.exe');" ^
  "foreach($u in $urls){ try { Invoke-WebRequest -Uri $u -OutFile '%SETUP%' -UseBasicParsing; exit 0 } catch {} }; exit 1"
if errorlevel 1 (
  echo [错误] 下载失败。请手动安装: https://www.autohotkey.com/v2/
  exit /b 1
)
start /wait "" "%SETUP%" /silent
call :FindAhk

if not defined AHK_BASE (
  echo [错误] 找不到 AutoHotkey64.exe
  exit /b 1
)
if not defined AHK2EXE (
  echo [错误] 找不到 Ahk2Exe.exe
  exit /b 1
)

:Compile
echo [AutoKey] Base : %AHK_BASE%
echo [AutoKey] Comp : %AHK2EXE%
echo [AutoKey] 编译中...

"%AHK2EXE%" /in "%SRC%" /out "%OUT_EXE%" /base "%AHK_BASE%" /compress 2
if not exist "%OUT_EXE%" (
  echo [警告] UPX 压缩失败，尝试无压缩...
  "%AHK2EXE%" /in "%SRC%" /out "%OUT_EXE%" /base "%AHK_BASE%" /compress 0
)
if not exist "%OUT_EXE%" (
  echo [错误] 编译失败
  exit /b 1
)

xcopy /Y /Q "%CD%\configs\*.ini" "%OUT_DIR%\configs\" >nul

echo.
echo [完成] 输出: %OUT_EXE%
for %%A in ("%OUT_EXE%") do echo [体积] %%~zA bytes
echo.
echo 把整个 dist 文件夹拷到 Windows 任意位置即可运行。
exit /b 0

:FindAhk
for %%P in (
  "%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
  "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
  "%TOOLS_DIR%\AutoHotkey64.exe"
) do if exist %%~P if not defined AHK_BASE set "AHK_BASE=%%~P"

for %%P in (
  "%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
  "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe"
  "%TOOLS_DIR%\Compiler\Ahk2Exe.exe"
) do if exist %%~P if not defined AHK2EXE set "AHK2EXE=%%~P"
exit /b 0
