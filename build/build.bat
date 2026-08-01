@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>nul
cd /d "%~dp0.."

:: ============================================================
:: AutoKey - Windows 一键打包（体积优先）
:: 在 Windows 上双击运行；macOS 请用 GitHub Actions
::
:: 依赖走便携版：下载 zip 解压到 tools\ahk，
:: 不安装、不需要管理员权限。AutoHotkey v2 的安装包本身
:: 不含 Ahk2Exe，所以编译器必须单独取。
:: ============================================================

set "AHK_VERSION=2.0.19"
set "AHK2EXE_TAG=Ahk2Exe1.1.37.02a2"
set "MIRROR=https://ghproxy.net/"
set "ROOT=%CD%"
set "TOOLS_DIR=%ROOT%\tools\ahk"
set "OUT_DIR=%ROOT%\dist"
set "SRC=%ROOT%\src\AutoKey.ahk"
set "OUT_EXE=%OUT_DIR%\AutoKey.exe"
set "BUILD_LOG=%OUT_DIR%\build.log"

echo.
echo [AutoKey] 工作目录: %ROOT%

if not exist "%SRC%" goto :NoSrc

echo [AutoKey] 创建输出目录...
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
if not exist "%OUT_DIR%\data" mkdir "%OUT_DIR%\data"
if not exist "%TOOLS_DIR%\Compiler" mkdir "%TOOLS_DIR%\Compiler"
if not exist "%OUT_DIR%" goto :NoOutDir

set "AHK_BASE="
set "AHK2EXE="
call :FindAhk

set "RC=0"
if not defined AHK_BASE call :GetAhk
if not "%RC%"=="0" goto :GetAhkFail

set "RC=0"
if not defined AHK2EXE call :GetCompiler
if not "%RC%"=="0" goto :GetCompilerFail

if not defined AHK_BASE goto :NoBase
if not defined AHK2EXE goto :NoCompiler

echo.
echo [AutoKey] Base : %AHK_BASE%
echo [AutoKey] Comp : %AHK2EXE%

echo [AutoKey] 语法检查...
"%AHK_BASE%" /ErrorStdOut /validate "%SRC%"
if errorlevel 1 goto :SyntaxFail

echo [AutoKey] 编译中...

if exist "%OUT_EXE%" del /q "%OUT_EXE%" >nul 2>nul
if exist "%BUILD_LOG%" del /q "%BUILD_LOG%" >nul 2>nul

call :Compile 2
if exist "%OUT_EXE%" goto :Compiled

echo [警告] 压缩编译未生成 exe（通常是缺 MPRESS），改用无压缩重试...
call :Compile 0
if not exist "%OUT_EXE%" goto :CompileFail

:Compiled

if exist "%OUT_DIR%\configs" rmdir /s /q "%OUT_DIR%\configs" >nul 2>nul
if exist "%ROOT%\configs\*.ini" (
  mkdir "%OUT_DIR%\configs" >nul 2>nul
  xcopy /Y /Q "%ROOT%\configs\*.ini" "%OUT_DIR%\configs\" >nul
)

echo.
echo [完成] 输出: %OUT_EXE%
for %%A in ("%OUT_EXE%") do echo [体积] %%~zA bytes
echo.
echo 把整个 dist 文件夹拷到 Windows 任意位置即可运行。
echo 首次运行会在同目录生成 data\ 保存界面配置。
echo.
pause
exit /b 0

:: ============================================================
:: 子程序
:: ============================================================

:Compile
echo.>>"%BUILD_LOG%"
echo ===== Ahk2Exe /compress %~1 =====>>"%BUILD_LOG%"
"%AHK2EXE%" /in "%SRC%" /out "%OUT_EXE%" /base "%AHK_BASE%" /compress %~1 /silent verbose >>"%BUILD_LOG%" 2>&1
echo [Ahk2Exe] 退出码 %errorlevel%>>"%BUILD_LOG%"
exit /b 0

:FindAhk
if not defined AHK_BASE if exist "%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_BASE=%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK_BASE if exist "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_BASE=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK_BASE if exist "%ProgramFiles(x86)%\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_BASE=%ProgramFiles(x86)%\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK_BASE for /f "delims=" %%F in ('dir /b /s "%TOOLS_DIR%\AutoHotkey64.exe" 2^>nul') do if not defined AHK_BASE set "AHK_BASE=%%F"

if not defined AHK2EXE if exist "%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
if not defined AHK2EXE if exist "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe"
if not defined AHK2EXE if exist "%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe"
if not defined AHK2EXE for /f "delims=" %%F in ('dir /b /s "%TOOLS_DIR%\Ahk2Exe.exe" 2^>nul') do if not defined AHK2EXE set "AHK2EXE=%%F"
exit /b 0

:GetAhk
echo.
echo [AutoKey] 未找到 AutoHotkey v2，下载便携版 %AHK_VERSION% ...
set "ZIP=%TEMP%\AutoHotkey_%AHK_VERSION%.zip"
if exist "%ZIP%" del /q "%ZIP%" >nul 2>nul
call :Download "https://github.com/AutoHotkey/AutoHotkey/releases/download/v%AHK_VERSION%/AutoHotkey_%AHK_VERSION%.zip" "%ZIP%"
if errorlevel 1 goto :GetAhkErr
call :Unzip "%ZIP%" "%TOOLS_DIR%"
if errorlevel 1 goto :GetAhkErr
del /q "%ZIP%" >nul 2>nul
call :FindAhk
exit /b 0
:GetAhkErr
set "RC=1"
exit /b 1

:GetCompiler
echo.
echo [AutoKey] 未找到 Ahk2Exe 编译器，下载 %AHK2EXE_TAG% ...
set "ZIP=%TEMP%\%AHK2EXE_TAG%.zip"
if exist "%ZIP%" del /q "%ZIP%" >nul 2>nul
call :Download "https://github.com/AutoHotkey/Ahk2Exe/releases/download/%AHK2EXE_TAG%/%AHK2EXE_TAG%.zip" "%ZIP%"
if errorlevel 1 goto :GetCompErr
call :Unzip "%ZIP%" "%TOOLS_DIR%\Compiler"
if errorlevel 1 goto :GetCompErr
del /q "%ZIP%" >nul 2>nul
call :FindAhk
exit /b 0
:GetCompErr
set "RC=1"
exit /b 1

:Download
echo [下载] %~1
call :Fetch "%~1" "%~2"
if not errorlevel 1 exit /b 0
echo [下载] 直连失败，改用镜像重试 ...
call :Fetch "%MIRROR%%~1" "%~2"
if not errorlevel 1 exit /b 0
exit /b 1

:Fetch
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%~1' -OutFile '%~2' -UseBasicParsing; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
exit /b %errorlevel%

:Unzip
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) { Expand-Archive -LiteralPath '%~1' -DestinationPath '%~2' -Force } else { Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory('%~1','%~2') }; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
exit /b %errorlevel%

:: ============================================================
:: 错误出口
:: ============================================================

:NoSrc
echo [错误] 找不到源码: %SRC%
echo         请确认 build.bat 在项目的 build\ 目录下，且 src\ 目录完整。
echo         如果你只单独下载了 build.bat，请把整个仓库都下载下来。
goto :Fail

:NoOutDir
echo [错误] 无法创建 %OUT_DIR%
echo         可能是所在目录只读（如压缩包内直接运行），请先解压到桌面再试。
goto :Fail

:GetAhkFail
echo [错误] 下载或解压 AutoHotkey 便携版失败。
echo         请手动下载 AutoHotkey_%AHK_VERSION%.zip:
echo         https://github.com/AutoHotkey/AutoHotkey/releases/tag/v%AHK_VERSION%
echo         解压到 %TOOLS_DIR%\ 后重新运行本脚本。
goto :Fail

:GetCompilerFail
echo [错误] 下载或解压 Ahk2Exe 编译器失败。
echo         请手动下载 %AHK2EXE_TAG%.zip:
echo         https://github.com/AutoHotkey/Ahk2Exe/releases
echo         解压到 %TOOLS_DIR%\Compiler\ 后重新运行本脚本。
goto :Fail

:NoBase
echo [错误] 仍找不到 AutoHotkey64.exe
echo         请检查 %TOOLS_DIR%\ 下是否有 AutoHotkey64.exe
goto :Fail

:NoCompiler
echo [错误] 仍找不到 Ahk2Exe.exe
echo         请检查 %TOOLS_DIR%\Compiler\ 下是否有 Ahk2Exe.exe
echo         下载地址: https://github.com/AutoHotkey/Ahk2Exe/releases
goto :Fail

:SyntaxFail
echo.
echo [错误] 脚本语法检查未通过，上面一行是 AutoHotkey 报的文件、行号与原因。
echo         按提示改 src\ 下对应的文件后重新运行本脚本。
goto :Fail

:CompileFail
echo [错误] 编译失败，未生成 %OUT_EXE%
echo.
echo ---------- Ahk2Exe 输出 ----------
if exist "%BUILD_LOG%" type "%BUILD_LOG%"
echo ----------------------------------
echo.
echo 上面就是真实原因。常见情况：
echo   * 脚本语法错误  - 按提示的行号改 src\AutoKey.ahk
echo   * 找不到 base   - 检查 %TOOLS_DIR%\AutoHotkey64.exe
echo   * 目录无写权限  - 换到桌面等可写目录再运行
echo 完整日志: %BUILD_LOG%
goto :Fail

:Fail
echo.
pause
exit /b 1
