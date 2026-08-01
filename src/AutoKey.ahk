#Requires AutoHotkey v2.0+
#SingleInstance Force
Persistent
SetTitleMatchMode 2
SendMode "Input"
CoordMode "Mouse", "Screen"

;@Ahk2Exe-SetName AutoKey
;@Ahk2Exe-SetDescription 按键序列自动化（AutoHotkey v2）
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-SetMainIcon
;@Ahk2Exe-ExeName AutoKey.exe

#Include lib\Config.ahk
#Include lib\Target.ahk
#Include lib\Sequencer.ahk

global gApp := AutoKeyApp()

class AutoKeyApp {
    __New() {
        this.cfg := ""
        this.target := ""
        this.seq := ""
        this.statusText := "就绪"
        this.configPath := ""
        this._boundHotkeys := []

        this._InitTray()
        this._BuildGui()

        ; 命令行：AutoKey.exe configs\xxx.ini
        if (A_Args.Length >= 1) {
            try this.LoadConfig(A_Args[1])
            catch as e
                MsgBox("加载配置失败:`n" e.Message, "AutoKey", "Icon!")
        } else {
            ; 默认尝试 example.ini
            try this.LoadConfig("example.ini")
        }
    }

    _InitTray() {
        A_IconTip := "AutoKey"
        A_TrayMenu.Delete()
        A_TrayMenu.Add("显示主窗口", (*) => this.gui.Show())
        A_TrayMenu.Add()
        A_TrayMenu.Add("开始 (热键)", (*) => this.Start())
        A_TrayMenu.Add("停止 (热键)", (*) => this.Stop())
        A_TrayMenu.Add("暂停/继续", (*) => this.TogglePause())
        A_TrayMenu.Add()
        A_TrayMenu.Add("退出", (*) => ExitApp())
        A_TrayMenu.Default := "显示主窗口"
    }

    _BuildGui() {
        g := Gui("+AlwaysOnTop -MaximizeBox", "AutoKey — 按键编排")
        g.SetFont("s10", "Segoe UI")
        g.OnEvent("Close", (*) => g.Hide())
        g.OnEvent("Escape", (*) => g.Hide())

        g.AddText(, "配置文件")
        this.ddlConfigs := g.AddDropDownList("w320")
        this._RefreshConfigList()

        btnRow := g.AddButton("w100", "刷新列表")
        btnRow.OnEvent("Click", (*) => this._RefreshConfigList())
        btnLoad := g.AddButton("x+8 w100", "加载")
        btnLoad.OnEvent("Click", (*) => this._LoadSelected())
        btnBrowse := g.AddButton("x+8 w100", "浏览…")
        btnBrowse.OnEvent("Click", (*) => this._BrowseConfig())

        g.AddText("xm Section", "宏名称")
        this.txtName := g.AddEdit("w320 ReadOnly", "-")

        g.AddText("xm", "目标窗口")
        this.txtTarget := g.AddEdit("w320 ReadOnly", "-")

        g.AddText("xm", "热键")
        this.txtHotkeys := g.AddEdit("w320 ReadOnly", "-")

        g.AddText("xm", "序列预览")
        this.txtPreview := g.AddEdit("w320 r6 ReadOnly", "")

        g.AddText("xm", "状态")
        this.txtStatus := g.AddEdit("w320 ReadOnly", "就绪")

        this.btnStart := g.AddButton("xm w100 Default", "开始")
        this.btnStart.OnEvent("Click", (*) => this.Start())
        this.btnStop := g.AddButton("x+8 w100", "停止")
        this.btnStop.OnEvent("Click", (*) => this.Stop())
        this.btnPause := g.AddButton("x+8 w100", "暂停")
        this.btnPause.OnEvent("Click", (*) => this.TogglePause())

        g.AddText("xm cGray w320", "提示：可先打开目标程序，再开始。停止热键始终有效。")

        this.gui := g
        g.Show()
    }

    _ConfigsDir() {
        ; 编译后 configs 与 exe 同级；开发时在 src 的上一级
        d1 := A_ScriptDir "\configs"
        d2 := A_ScriptDir "\..\configs"
        if DirExist(d1)
            return d1
        if DirExist(d2)
            return d2
        DirCreate(d1)
        return d1
    }

    _RefreshConfigList() {
        this.ddlConfigs.Delete()
        dir := this._ConfigsDir()
        names := []
        loop files dir "\*.ini" {
            names.Push(A_LoopFileName)
        }
        if (names.Length = 0) {
            this.ddlConfigs.Add(["(无配置)"])
            return
        }
        this.ddlConfigs.Add(names)
        this.ddlConfigs.Choose(1)
    }

    _LoadSelected() {
        name := this.ddlConfigs.Text
        if (name = "" || name = "(无配置)")
            return
        try this.LoadConfig(name)
        catch as e
            MsgBox("加载失败:`n" e.Message, "AutoKey", "Icon!")
    }

    _BrowseConfig() {
        path := FileSelect(1, this._ConfigsDir(), "选择宏配置", "INI (*.ini)")
        if (path = "")
            return
        try this.LoadConfig(path)
        catch as e
            MsgBox("加载失败:`n" e.Message, "AutoKey", "Icon!")
    }

    LoadConfig(nameOrPath) {
        path := MacroConfig.ResolvePath(nameOrPath)
        cfg := MacroConfig(path)
        target := WindowTarget(cfg)
        seq := Sequencer(cfg, target)
        seq.onStatus := (t) => this._SetStatus(t)

        this._UnbindHotkeys()
        this.cfg := cfg
        this.target := target
        this.seq := seq
        this.configPath := path

        this._BindHotkeys(cfg)
        this._UpdateUi()
        this._SetStatus("已加载: " cfg.name)
    }

    _BindHotkeys(cfg) {
        this._boundHotkeys := []
        try {
            Hotkey(cfg.startHotkey, (*) => this.Start(), "On")
            this._boundHotkeys.Push(cfg.startHotkey)
        } catch as e {
            this._SetStatus("开始热键无效: " cfg.startHotkey)
        }
        try {
            Hotkey(cfg.stopHotkey, (*) => this.Stop(), "On")
            this._boundHotkeys.Push(cfg.stopHotkey)
        }
        try {
            Hotkey(cfg.pauseHotkey, (*) => this.TogglePause(), "On")
            this._boundHotkeys.Push(cfg.pauseHotkey)
        }
    }

    _UnbindHotkeys() {
        for hk in this._boundHotkeys {
            try Hotkey(hk, "Off")
        }
        this._boundHotkeys := []
    }

    _UpdateUi() {
        cfg := this.cfg
        if !cfg
            return
        this.txtName.Value := cfg.name
        this.txtTarget.Value := this.target.Describe() " | 模式=" cfg.sendMode
        this.txtHotkeys.Value := "开始 " cfg.startHotkey " / 停止 " cfg.stopHotkey " / 暂停 " cfg.pauseHotkey

        preview := ""
        for step in cfg.steps {
            preview .= step.index ". "
            switch step.kind {
                case "sleep":
                    preview .= "等待 " step.delay "ms"
                case "click":
                    preview .= "点击 (" step.x "," step.y ") +" step.delay "ms"
                default:
                    preview .= "按键 " step.key " +" step.delay "ms"
                    if (step.hold > 0)
                        preview .= " (按住" step.hold "ms)"
            }
            preview .= "`r`n"
        }
        if cfg.loop
            preview .= "`r`n[循环] 间隔 " cfg.loopDelay "ms"
            . (cfg.repeat > 0 ? "，共 " cfg.repeat " 轮" : "，无限")
        else
            preview .= "`r`n[单次]"
        this.txtPreview.Value := preview
    }

    _SetStatus(text) {
        this.statusText := text
        try this.txtStatus.Value := text
        A_IconTip := "AutoKey — " text
    }

    Start() {
        if !this.seq {
            MsgBox("请先加载配置。", "AutoKey", "Icon!")
            return
        }
        if this.seq.IsRunning {
            this._SetStatus("已在运行")
            return
        }
        this.seq.Start()
    }

    Stop() {
        if this.seq
            this.seq.Stop()
    }

    TogglePause() {
        if this.seq
            this.seq.TogglePause()
    }
}
