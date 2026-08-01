# AutoKey — 类按键精灵的按键编排工具（AutoHotkey v2）

在 Windows 上自动按键、编排按键序列，并可指定目标应用程序。  
**全部在图形界面里配置**，无需手改配置文件。

本仓库在 macOS 上只负责编写脚本；**最终产物是 Windows 绿色版 exe**（约 1–2 MB）。

## 功能

- **连发模式**（默认）：可动态添加多个键位，按列表顺序轮流连发；每个键可单独设间隔
- **按键序列**：多步顺序编排（按键 / 等待 / 点击）
- **多套配置**：左侧新建、切换、删除多套方案
- 按进程名（`exe`）、窗口标题、窗口类定位目标程序
- 开始 / 停止 / 暂停热键（支持界面内「捕捉」）
- 循环次数与间隔可配
- `Send`（前台）或 `ControlSend`（尽量后台）
- 配置自动保存到 `data\`，关闭再开仍在
- 可导入旧版 `configs\*.ini`（兼容）
- 打包为绿色 `dist\` 目录，拷走就能跑

## 界面怎么用

1. 左侧选择或「新建」一套配置
2. 选模式：
   - **连发模式**：填按键（或「捕捉」直接加入）+ 间隔，可继续加入更多键位；上移/下移调顺序
   - **按键序列**：在列表里添加 / 编辑 / 排序步骤（可含等待、点击）
3. 按需设循环、热键、目标窗口（「取前台」可自动填入当前窗口）
4. 点 **保存并应用**，再点 **开始**（或按开始热键，默认 F6）

常用按键写法：`a`、`{Enter}`、`{Space}`、`{Tab}`、`{Esc}`、`{F1}`、`^c`（Ctrl+C）、`!{F4}`（Alt+F4）。

## 目录结构

```
autokey/
├── src/
│   ├── AutoKey.ahk          # 主程序（可视化配置 GUI）
│   └── lib/
│       ├── Config.ahk       # 多套配置 + 自动持久化
│       ├── Target.ahk       # 目标窗口定位
│       └── Sequencer.ahk    # 序列执行器
├── configs/                 # 旧版 ini 示例（可「导入旧 ini」）
├── data/                    # 运行时自动生成，保存你的 UI 配置
├── build/build.bat          # Windows 一键编译
├── tools/ahk/               # 自动下载的 AHK 便携版（gitignore）
├── dist/                    # 编译输出（gitignore）
└── .github/workflows/       # 在 GitHub 上自动打 Windows 包
```

## 在 Windows 上使用

### 方式 A：直接跑脚本（开发调试）

1. 安装 [AutoHotkey v2](https://www.autohotkey.com/v2/)
2. 双击 `src\AutoKey.ahk`
3. 在界面里配置 → 保存并应用 → 开目标程序 → 开始

### 方式 B：打成绿色 exe（推荐分发）

在 **Windows** 上双击：

```bat
build\build.bat
```

首次运行会自动把 AutoHotkey v2 和 Ahk2Exe 编译器的**便携版**下载解压到 `tools\ahk\`。  
完成后得到 `dist\AutoKey.exe`，拷到任意 Windows 机器即可。

#### 双击后没有生成 dist 怎么办

1. **必须下载整个仓库**，不能只单独下载 `build.bat`
2. **确认行尾是 CRLF**（仓库已用 `.gitattributes` 处理；若仍有问题见下方 PowerShell 修复）
3. **不要在压缩包里直接双击**，先解压到可写目录

```powershell
$p = "build\build.bat"
(Get-Content -Raw $p) -replace "`r?`n", "`r`n" | Set-Content -NoNewline $p
```

#### 提示「找不到 Ahk2Exe.exe」

到 [Ahk2Exe releases](https://github.com/AutoHotkey/Ahk2Exe/releases) 下载 zip，解压到 `tools\ahk\Compiler\`，确保存在 `Ahk2Exe.exe` 后重跑 `build.bat`。

### 方式 C：在 Mac 上开发，用 GitHub Actions 打包

1. 把仓库推到 GitHub  
2. Actions → **Build Windows EXE** → 下载 `AutoKey-windows`  
3. 解压后在 Windows 上运行 `AutoKey.exe`

## 注意

- 仅支持 **Windows**（Win7+，建议 Win10/11）
- 部分游戏使用反作弊 / DirectInput，普通 `Send` 可能无效
- `ControlSend` 后台发送对很多程序无效，默认用 `Send` 更稳
- 请遵守目标软件/游戏的使用条款

## 快速验证

1. 打开 Windows 记事本  
2. 连发模式：加入 `h`，间隔 `80`；或再加入更多键位轮流连发  
3. 目标 exe 填 `notepad.exe`（或「取前台」）  
4. 保存并应用 → F6 开始 / F7 停止
