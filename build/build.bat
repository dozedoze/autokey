@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>nul
cd /d "%~dp0.."

:: ============================================================
:: AutoKey - Windows 一键打包（体积优先）
:: 在 Windows 上双击运行；macOS 请用 GitHub Actions
:: ============================================================

set "AHK_VERSION=2.0.19"
set "ROOT=%CD%"
set "TOOLS_DIR=%ROOT%\tools\ahk"
set "OUT_DIR=%ROOT%\dist"
set "SRC=%ROOT%\src\AutoKey.ahk"
set "OUT_EXE=%OUT_DIR%\AutoKey.exe"

echo.
echo [AutoKey] 工作目录: %ROOT%

if not exist "%SRC%" goto :NoSrc

echo [AutoKey] 创建输出目录...
if not exist "%OUT_DIR%\configs" mkdir "%OUT_DIR%\configs"
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
if not exist "%OUT_DIR%" goto :NoOutDir

set "AHK_BASE="
set "AHK2EXE="
call :FindAhk
if defined AHK_BASE if defined AHK2EXE goto :Compile

echo [AutoKey] 未找到 AutoHotkey，正在下载安装 %AHK_VERSION% ...
set "SETUP=%TEMP%\ahk_v2_setup.exe"
set "DLURL=https://github.com/AutoHotkey/AutoHotkey/releases/download/v%AHK_VERSION%/AutoHotkey_%AHK_VERSION%_setup.exe"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%DLURL%' -OutFile '%SETUP%' -UseBasicParsing; exit 0 } catch { Write-Host $_; exit 1 }"
if errorlevel 1 goto :DownloadFail

echo [AutoKey] 静默安装中（可能需要几十秒）...
start /wait "" "%SETUP%" /silent
call :FindAhk

if not defined AHK_BASE goto :NoBase
if not defined AHK2EXE goto :NoCompiler

:Compile
echo [AutoKey] Base : %AHK_BASE%
echo [AutoKey] Comp : %AHK2EXE%
echo [AutoKey] 编译中...

"%AHK2EXE%" /in "%SRC%" /out "%OUT_EXE%" /base "%AHK_BASE%" /compress 2
if not exist "%OUT_EXE%" (
  echo [警告] UPX 压缩失败，改用无压缩重试...
  "%AHK2EXE%" /in "%SRC%" /out "%OUT_EXE%" /base "%AHK_BASE%" /compress 0
)
if not exist "%OUT_EXE%" goto :CompileFail

if exist "%ROOT%\configs\*.ini" xcopy /Y /Q "%ROOT%\configs\*.ini" "%OUT_DIR%\configs\" >nul

echo.
echo [完成] 输出: %OUT_EXE%
for %%A in ("%OUT_EXE%") do echo [体积] %%~zA bytes
echo.
echo 把整个 dist 文件夹拷到 Windows 任意位置即可运行。
echo.
pause
exit /b 0

:FindAhk
if not defined AHK_BASE if exist "%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_BASE=%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK_BASE if exist "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_BASE=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK_BASE if exist "%ProgramFiles(x86)%\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_BASE=%ProgramFiles(x86)%\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK_BASE if exist "%TOOLS_DIR%\AutoHotkey64.exe" set "AHK_BASE=%TOOLS_DIR%\AutoHotkey64.exe"

if not defined AHK2EXE if exist "%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
if not defined AHK2EXE if exist "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe"
if not defined AHK2EXE if exist "%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe"
if not defined AHK2EXE if exist "%TOOLS_DIR%\Compiler\Ahk2Exe.exe" set "AHK2EXE=%TOOLS_DIR%\Compiler\Ahk2Exe.exe"
exit /b 0

:NoSrc
echo [错误] 找不到源码: %SRC%
echo         请确认 build.bat 在项目的 build\ 目录下，且 src\ 目录完整。
echo         如果你只单独下载了 build.bat，请把整个仓库都下载下来。
goto :Fail

:NoOutDir
echo [错误] 无法创建 %OUT_DIR%
echo         可能是所在目录只读（如压缩包内直接运行），请先解压到桌面再试。
goto :Fail

:DownloadFail
echo [错误] 下载失败。请手动安装后重新运行本脚本:
echo         https://www.autohotkey.com/v2/
goto :Fail

:NoBase
echo [错误] 安装后仍找不到 AutoHotkey64.exe
goto :Fail

:NoCompiler
echo [错误] 找不到 Ahk2Exe.exe（AutoHotkey 安装时需勾选 Compiler）
echo         也可从 https://github.com/AutoHotkey/Ahk2Exe/releases 下载后
echo         解压到 %TOOLS_DIR%\Compiler\
goto :Fail

:CompileFail
echo [错误] 编译失败，未生成 %OUT_EXE%
goto :Fail

:Fail
echo.
pause
exit /b 1
