# AutoKey — 类按键精灵的按键编排工具（AutoHotkey v2）

在 Windows 上自动按键、编排按键序列，并可指定目标应用程序。  
本仓库在 macOS 上只负责编写脚本；**最终产物是 Windows 绿色版 exe**（约 1–2 MB）。

> 你提到的「autokey v2」对应的是 **[AutoHotkey v2](https://www.autohotkey.com/v2/)**——Windows 上最接近「按键精灵」的方案，体积小、可编译成独立 exe。

## 功能

- 单键连发 / 多步按键序列编排
- 按进程名（`exe`）、窗口标题、窗口类定位目标程序
- 开始 / 停止 / 暂停热键
- 循环次数与间隔可配
- `Send`（前台，兼容性最好）或 `ControlSend`（尽量后台）
- INI 配置，改完即用，无需改代码
- 打包为绿色 `dist\` 目录，拷走就能跑

## 目录结构

```
autokey/
├── src/
│   ├── AutoKey.ahk          # 主程序（GUI + 托盘）
│   └── lib/
│       ├── Config.ahk       # INI 配置加载
│       ├── Target.ahk       # 目标窗口定位
│       └── Sequencer.ahk    # 序列执行器
├── configs/                 # 宏配置（可自行添加）
│   ├── example.ini          # 记事本输入 hello
│   ├── spam_space.ini       # 空格连发
│   └── combo_demo.ini       # 组合序列
├── build/build.bat          # Windows 一键编译
├── dist/                    # 编译输出（gitignore）
└── .github/workflows/       # 在 GitHub 上自动打 Windows 包
```

## 配置说明（`configs/*.ini`）

```ini
[Macro]
Name=我的宏
Loop=1              ; 1=循环 0=单次
LoopDelay=200       ; 每轮结束后的间隔（毫秒）
Repeat=0            ; 循环轮数，0=无限

[Hotkeys]
Start=F6
Stop=F7
Pause=F8

[Target]
Exe=notepad.exe     ; 目标进程名（推荐），留空则打当前前台窗口
Title=              ; 标题包含匹配，可留空
Class=              ; 窗口类名，可留空
Activate=1          ; 发送前是否激活窗口
SendMode=Send       ; Send | ControlSend

[Sequence]
; 序号=按键|延迟ms
; 序号=按键|延迟ms|按住ms
; 序号=sleep|毫秒
; 序号=click|屏幕X|屏幕Y|延迟ms
1=a|100
2={Enter}|200
3=sleep|500
```

常用按键写法：`a`、`{Enter}`、`{Space}`、`{Tab}`、`{Esc}`、`{F1}`、`^c`（Ctrl+C）、`!{F4}`（Alt+F4）、`+a`（Shift+A）。

## 在 Windows 上使用

### 方式 A：直接跑脚本（开发调试）

1. 安装 [AutoHotkey v2](https://www.autohotkey.com/v2/)
2. 双击 `src\AutoKey.ahk`
3. 选择 `configs` 里的 ini → 加载 → 开目标程序 → 按开始热键（默认 F6）

### 方式 B：打成绿色 exe（推荐分发）

在 **Windows** 上双击：

```bat
build\build.bat
```

完成后得到：

```
dist/
  AutoKey.exe
  configs\*.ini
```

把整个 `dist` 拷到任意 Windows 机器即可，无需再装 AutoHotkey。  
开启 UPX 时体积通常约 **1MB 出头**；若本机无 UPX 会自动退回无压缩（约 1.5–2MB）。

#### 双击后没有生成 dist 怎么办

脚本执行到任何一步失败都会打印原因并 `pause`，窗口不会自动关闭，先看窗口里的提示。若窗口仍然一闪而过，说明 bat 在第一行就无法解析，按顺序排查：

1. **必须下载整个仓库**，不能只单独下载 `build.bat`。它依赖同级的 `..\src\AutoKey.ahk`。
2. **确认行尾是 CRLF**。若在 macOS/Linux 上编辑或用非 Git 方式传输过 `build.bat`，可能变成 LF 行尾，`cmd.exe` 会直接语法错误退出。在 Windows 上用 PowerShell 检查并修复：

```powershell
# 检查：输出 True 表示行尾正常
(Get-Content -Raw build\build.bat) -match "`r`n"

# 修复
$p = "build\build.bat"
(Get-Content -Raw $p) -replace "`r?`n", "`r`n" | Set-Content -NoNewline $p
```

3. **不要在压缩包里直接双击**，先解压到桌面等可写目录。
4. 想看完整报错，可在该目录打开 `cmd`，手动执行 `build\build.bat`。

仓库已用 `.gitattributes` 把 `*.bat` 标记为 `-text`，正常 `git clone` / Download ZIP 得到的都是 CRLF。

### 方式 C：在 Mac 上开发，用 GitHub Actions 打包

1. 把仓库推到 GitHub
2. 打开 Actions → **Build Windows EXE** → 下载 `AutoKey-windows` 产物
3. 解压后在 Windows 上运行 `AutoKey.exe`

本地也可手动触发：`workflow_dispatch`。

## 体积为什么能很小？

| 方案 | 大约体积 | 说明 |
|------|----------|------|
| **AutoHotkey 编译 exe** | ~1–2 MB | 本项目采用 |
| Python + PyInstaller | 20–40 MB+ | 偏大 |
| Electron / .NET 整包 | 更大 | 不适合这种工具 |

AHK 本身就是为 Windows 键鼠自动化设计的，编译后几乎是「脚本 + 精简运行时」。

## 注意

- 仅支持 **Windows**（Win7+，建议 Win10/11）
- 部分游戏使用反作弊 / DirectInput，普通 `Send` 可能无效；可尝试管理员运行，或改用驱动级方案（超出本项目范围）
- `ControlSend` 后台发送对很多程序无效，默认用 `Send` 更稳
- 请遵守目标软件/游戏的使用条款，勿用于破坏公平或违规场景

## 快速验证

1. 打开 Windows 记事本  
2. 加载 `configs\example.ini`  
3. 按 `F6`，应循环输入 `hello` 并回车；`F7` 停止
