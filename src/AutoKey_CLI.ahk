#Requires AutoHotkey v2.0
#SingleInstance Force
; 无 GUI 轻量入口：AutoKey_CLI.ahk configs\xxx.ini
; 适合只想热键启停、不需要界面的场景；打包体积与主程序接近

#Include lib\Config.ahk
#Include lib\Target.ahk
#Include lib\Sequencer.ahk

if (A_Args.Length < 1) {
    MsgBox "用法: AutoKey_CLI.ahk <config.ini>`n例如: AutoKey_CLI.ahk example.ini", "AutoKey CLI"
    ExitApp
}

try {
    path := MacroConfig.ResolvePath(A_Args[1])
    cfg := MacroConfig(path)
} catch as e {
    MsgBox "加载失败:`n" e.Message, "AutoKey CLI", "Icon!"
    ExitApp
}

target := WindowTarget(cfg)
seq := Sequencer(cfg, target)
seq.onStatus := (t) => ToolTip("AutoKey: " t)

Hotkey(cfg.startHotkey, (*) => seq.Start())
Hotkey(cfg.stopHotkey, (*) => seq.Stop())
Hotkey(cfg.pauseHotkey, (*) => seq.TogglePause())

A_IconTip := "AutoKey CLI — " cfg.name
TrayTip("已加载: " cfg.name, "开始 " cfg.startHotkey " / 停止 " cfg.stopHotkey, "Iconi")
Persistent
