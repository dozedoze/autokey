#Requires AutoHotkey v2.0+
#SingleInstance Force
Persistent
SetTitleMatchMode 2
SendMode "Input"
CoordMode "Mouse", "Screen"

;@Ahk2Exe-SetName AutoKey
;@Ahk2Exe-SetDescription 按键序列自动化（AutoHotkey v2）
;@Ahk2Exe-SetVersion 2.0.0
;@Ahk2Exe-ExeName AutoKey.exe

#Include lib\Config.ahk
#Include lib\Target.ahk
#Include lib\Sequencer.ahk

OnError(AutoKeyOnError)

global gApp := AutoKeyApp()

/** 把未捕获异常写进 data\error.log，方便定位；只结束出错的线程，不退出程序 */
AutoKeyOnError(err, mode) {
    msg := "[" A_Now "] "
    try {
        if IsObject(err) {
            if err.HasProp("Message")
                msg .= err.Message
            if err.HasProp("What")
                msg .= "`n  what: " err.What
            if err.HasProp("Extra")
                msg .= "`n  extra: " err.Extra
            if err.HasProp("File")
                msg .= "`n  file: " err.File
            if err.HasProp("Line")
                msg .= "`n  line: " err.Line
            if err.HasProp("Stack")
                msg .= "`n  stack: " err.Stack
        } else {
            msg .= err
        }
    }
    try FileAppend(msg "`n`n", RegExReplace(gApp.store.path, "[^\\]+$", "") "error.log", "UTF-8")
    try MsgBox("出错了（详情已写入 data\error.log）：`n`n" msg, "AutoKey", "Icon!")
    return 1
}

class AutoKeyApp {
    __New() {
        this.store := MacroStore()
        this.cfg := ""
        this.target := ""
        this.seq := ""
        this.runners := Map()   ; macroId -> Sequencer（可并行）
        this._boundHotkeys := []
        this._loadingUi := false
        this._capturing := false
        this._runMark := ""
        this._lockHwnd := 0

        this._InitTray()
        this._BuildGui()
        this._ReloadMacroList()
        this._LoadActiveIntoUi()
        this._ApplyFromUi(false)
    }

    _InitTray() {
        A_IconTip := "AutoKey"
        A_TrayMenu.Delete()
        A_TrayMenu.Add("显示主窗口", (*) => this.gui.Show())
        A_TrayMenu.Add()
        A_TrayMenu.Add("开始当前", (*) => this.Start())
        A_TrayMenu.Add("停止当前", (*) => this.Stop())
        A_TrayMenu.Add("全部停止", (*) => this.StopAll())
        A_TrayMenu.Add("暂停/继续当前", (*) => this.TogglePause())
        A_TrayMenu.Add()
        A_TrayMenu.Add("退出", (*) => this._Quit())
        A_TrayMenu.Default := "显示主窗口"
    }

    _BuildGui() {
        g := Gui("+OwnDialogs", "AutoKey — 可视化按键编排")
        g.SetFont("s9", "Segoe UI")
        g.OnEvent("Close", (*) => this._OnClose())
        g.OnEvent("Escape", (*) => g.Hide())

        ; ── 左侧：多套配置 ──
        g.AddText("xm w160 Section", "配置方案")
        this.lbMacros := g.AddListBox("xm w160 r18")
        this.lbMacros.OnEvent("Change", (*) => this._OnSelectMacro())

        g.AddButton("xm w76", "新建").OnEvent("Click", (*) => this._NewMacro())
        g.AddButton("x+8 w76", "复制").OnEvent("Click", (*) => this._CopyMacro())
        g.AddButton("xm w160", "删除").OnEvent("Click", (*) => this._DeleteMacro())
        g.AddButton("xm w160", "导入旧 ini…").OnEvent("Click", (*) => this._ImportIni())

        ; ── 右侧：编辑区 ──
        g.AddText("ys w540 Section", "名称")
        this.edName := g.AddEdit("xp w400")

        ; 点哪个 Tab，就只显示对应编辑区；另一套完全隐藏
        this.tabMode := g.AddTab3("xp w540 h285", ["连发模式", "按键序列"])
        this.tabMode.GetPos(&tabX, &tabY, &tabW, &tabH)
        this.tabMode.OnEvent("Change", (*) => this._OnModeChange())

        ; —— Tab1：连发模式 ——
        this.tabMode.UseTab(1)
        g.AddText("w516", "可添加多个键位，按列表顺序轮流连发")
        this.lvKeys := g.AddListView("w516 r7", ["#", "按键", "间隔ms"])
        this.lvKeys.ModifyCol(1, 36)
        this.lvKeys.ModifyCol(2, 340)
        this.lvKeys.ModifyCol(3, 110)

        g.AddText(, "按键")
        this.edSingleKey := g.AddEdit("x+6 yp-3 w88")
        this.btnCapSingle := g.AddButton("x+4 w52", "捕捉")
        this.btnCapSingle.OnEvent("Click", (*) => this._CaptureInto("single"))
        g.AddText("x+8 yp+3", "间隔")
        this.edInterval := g.AddEdit("x+4 yp-3 w52 Number", "50")
        this.btnKeyAdd := g.AddButton("x+6 w52", "加入")
        this.btnKeyAdd.OnEvent("Click", (*) => this._AddSpamKey())
        this.btnKeyEdit := g.AddButton("x+4 w52", "编辑")
        this.btnKeyEdit.OnEvent("Click", (*) => this._EditSpamKey())
        this.btnKeyDel := g.AddButton("x+4 w52", "删除")
        this.btnKeyDel.OnEvent("Click", (*) => this._RemoveSpamKey())
        this.btnKeyUp := g.AddButton("xm+184 y+8 w52", "上移")
        this.btnKeyUp.OnEvent("Click", (*) => this._MoveSpamKey(-1))
        this.btnKeyDown := g.AddButton("x+4 w52", "下移")
        this.btnKeyDown.OnEvent("Click", (*) => this._MoveSpamKey(1))

        ; —— Tab2：按键序列 ——
        this.tabMode.UseTab(2)
        g.AddText("w516", "按顺序执行步骤，可含按键 / 等待 / 点击")
        this.lvSteps := g.AddListView("w516 r7", ["#", "类型", "内容", "延迟ms", "按住ms"])
        this.lvSteps.ModifyCol(1, 36)
        this.lvSteps.ModifyCol(2, 60)
        this.lvSteps.ModifyCol(3, 230)
        this.lvSteps.ModifyCol(4, 80)
        this.lvSteps.ModifyCol(5, 80)
        this.lvSteps.OnEvent("DoubleClick", (*) => this._EditStep())

        this.btnStepKey := g.AddButton("w88", "添加按键")
        this.btnStepKey.OnEvent("Click", (*) => this._AddStep("key"))
        this.btnStepSleep := g.AddButton("x+6 w88", "添加等待")
        this.btnStepSleep.OnEvent("Click", (*) => this._AddStep("sleep"))
        this.btnStepClick := g.AddButton("x+6 w88", "添加点击")
        this.btnStepClick.OnEvent("Click", (*) => this._AddStep("click"))
        this.btnStepEdit := g.AddButton("x+6 w56", "编辑")
        this.btnStepEdit.OnEvent("Click", (*) => this._EditStep())
        this.btnStepDel := g.AddButton("x+6 w56", "删除")
        this.btnStepDel.OnEvent("Click", (*) => this._RemoveStep())
        this.btnStepUp := g.AddButton("x+6 w52", "上移")
        this.btnStepUp.OnEvent("Click", (*) => this._MoveStep(-1))
        this.btnStepDown := g.AddButton("x+6 w52", "下移")
        this.btnStepDown.OnEvent("Click", (*) => this._MoveStep(1))

        ; —— 公共设置（不在 Tab 内）——
        this.tabMode.UseTab(0)

        ; 明确放在 Tab 底部之后，避免被 Tab 遮挡
        g.AddGroupBox("x" tabX " y" (tabY + tabH + 10) " w540 h88", "循环与热键")
        this.chkLoop := g.AddCheckbox("xp+12 yp+22 Checked", "循环")
        g.AddText("x+8", "轮间隔 ms")
        this.edLoopDelay := g.AddEdit("x+6 w60 Number", "200")
        g.AddText("x+8", "次数(0∞)")
        this.edRepeat := g.AddEdit("x+6 w50 Number", "0")

        g.AddText("xm+184 y+10", "开始")
        this.edStartHk := g.AddEdit("x+6 w56", "F6")
        g.AddButton("x+4 w44", "捕捉").OnEvent("Click", (*) => this._CaptureInto("start"))
        g.AddText("x+8", "停止")
        this.edStopHk := g.AddEdit("x+6 w56", "F7")
        g.AddButton("x+4 w44", "捕捉").OnEvent("Click", (*) => this._CaptureInto("stop"))
        g.AddText("x+8", "暂停")
        this.edPauseHk := g.AddEdit("x+6 w56", "F8")
        g.AddButton("x+4 w44", "捕捉").OnEvent("Click", (*) => this._CaptureInto("pause"))

        g.AddGroupBox("x" tabX " y+14 w540 h110", "目标窗口（可留空 = 当前前台）")
        g.AddText("xp+12 yp+22", "进程 exe")
        this.edExe := g.AddEdit("x+6 w270")
        g.AddButton("x+6 w112", "选择目标窗口…").OnEvent("Click", (*) => this._ChooseTargetWindow())
        g.AddText("xm+184 y+8", "窗口 #")
        this.edWinIndex := g.AddEdit("x+6 w44 Number", "0")
        g.AddText("x+6 cGray", "0=自动")
        this.txtLock := g.AddText("x+8 w250 cGray", "未锁定具体窗口")
        this.chkActivate := g.AddCheckbox("xm+184 y+8", "发送前激活")
        g.AddText("x+12", "发送模式")
        this.ddlSend := g.AddDropDownList("x+6 w110", ["Send", "ControlSend"])
        this.ddlSend.Choose(2)

        ; 底部操作
        g.AddText("xm+172 y+16", "状态")
        this.txtStatus := g.AddEdit("x+8 w460 ReadOnly", "就绪")

        this.btnApply := g.AddButton("xm+172 y+10 w100 Default", "保存并应用")
        this.btnApply.OnEvent("Click", (*) => this._ApplyFromUi(true))
        this.btnStart := g.AddButton("x+8 w72", "开始")
        this.btnStart.OnEvent("Click", (*) => this.Start())
        this.btnStop := g.AddButton("x+8 w72", "停止")
        this.btnStop.OnEvent("Click", (*) => this.Stop())
        this.btnPause := g.AddButton("x+8 w72", "暂停")
        this.btnPause.OnEvent("Click", (*) => this.TogglePause())
        this.btnStopAll := g.AddButton("x+8 w88", "全部停止")
        this.btnStopAll.OnEvent("Click", (*) => this.StopAll())

        g.AddText("xm+172 y+10 cGray w540", "提示：点「选择目标窗口…」后 AutoKey 会最小化，点击目标即自动恢复；仅打开列表时才监听窗口。")

        this.gui := g
        this._OnModeChange()
        g.Show()
    }

    _IsSingleMode() {
        return this.tabMode.Value = 1
    }

    ; ───────── 列表 / 切换 ─────────

    _ReloadMacroList(selectId := "") {
        ; Delete 与 Add 之间若被运行中的定时器线程打断并重入，列表会被重复填充，
        ; 之后点击靠后的重复项就会索引越界，所以整段必须不可中断。
        prevCritical := A_IsCritical
        prevLoading := this._loadingUi
        Critical "On"
        this._loadingUi := true

        names := []
        mark := ""
        choose := 1
        want := selectId != "" ? selectId : this.store.activeId
        for i, m in this.store.macros {
            label := this._MacroListLabel(m)
            running := this._IsRunnerActive(m.id)
            mark .= running ? "1" : "0"
            names.Push(label)
            if (m.id = want)
                choose := i
        }
        this.lbMacros.Delete()
        if (names.Length) {
            this.lbMacros.Add(names)
            this.lbMacros.Choose(choose)
        }
        this._runMark := mark

        this._loadingUi := prevLoading
        Critical prevCritical
    }

    /** 运行标记有变化时才重建列表，避免定时器高频刷新和用户点击抢控件 */
    _RefreshRunMarks() {
        mark := ""
        for m in this.store.macros
            mark .= this._IsRunnerActive(m.id) ? "1" : "0"
        if (mark != this._runMark)
            this._ReloadMacroList(this.store.activeId)
    }

    _IsRunnerActive(id) {
        return this.runners.Has(id) && this.runners[id].IsRunning
    }

    /** 列表显示：名称保持用户输入，窗口信息只作为后缀标识 */
    _MacroListLabel(m) {
        label := this._CleanMacroName(m.name)
        if this._IsRunnerActive(m.id)
            label := "▶ " label
        tip := this._WindowTip(m)
        if (tip != "")
            label .= "  [" tip "]"
        return label
    }

    /** 去掉历史上误写入名称的 [窗口] 后缀 */
    _CleanMacroName(name) {
        name := Trim(name)
        ; 反复去掉末尾的 " [xxx]" / " (xxx)" 自动标识
        loop 3 {
            cleaned := RegExReplace(name, "\s*[\[\(][^\[\]\(\)]*[\]\)]\s*$", "")
            cleaned := Trim(cleaned)
            if (cleaned = "" || cleaned = name)
                break
            name := cleaned
        }
        return name != "" ? name : "未命名"
    }

    /** 目标窗口的简短标识：只用进程/序号，不用窗口标题，避免看起来像改了名称 */
    _WindowTip(m) {
        exe := m.targetExe != "" ? m.targetExe : ""
        if (m.targetIndex > 0) {
            if (exe != "")
                return exe " #" m.targetIndex
            return "#" m.targetIndex
        }
        if (m.targetHwnd) {
            if (exe != "")
                return exe
            return "已锁定"
        }
        if (exe != "")
            return exe
        return ""
    }

    _OnSelectMacro() {
        if this._loadingUi
            return
        idx := this.lbMacros.Value
        if (idx < 1)
            return
        if (idx > this.store.macros.Length) {
            ; 列表与数据不同步，重建后忽略本次点击
            this._ReloadMacroList(this.store.activeId)
            return
        }
        m := this.store.macros[idx]
        if (m.id = this.store.activeId)
            return
        ; 允许切换查看其它配置；其它配置可继续在后台跑
        this.store.SetActive(m.id)
        this._LoadActiveIntoUi()
        ; 同步当前编辑器对应的 cfg/seq 引用（不打断其它 runner）
        this._SyncActiveRefs(false)
    }

    _NewMacro() {
        Result := InputBox("输入新配置名称", "新建配置", , "新配置")
        if (Result.Result = "Cancel")
            return
        name := Trim(Result.Value)
        if (name = "")
            name := "新配置"
        name := this._UniqueName(name)
        m := MacroConfig()
        m.name := name
        m.mode := "single"
        m.keys := [MacroConfig.NewKey("{Space}", 50)]
        m.SyncLegacySingle()
        m.activate := 0
        m.sendMode := "ControlSend"
        this.store.Add(m)
        this._ReloadMacroList(m.id)
        this._LoadActiveIntoUi()
        this._SyncActiveRefs(false)
        this._SetStatus("已新建: " name)
    }

    _CopyMacro() {
        src := this.store.Active()
        if !src
            return
        m := src.Clone()
        m.id := ""
        m.name := this._UniqueName(src.name " 副本")
        this.store.Add(m)
        this._ReloadMacroList(m.id)
        this._LoadActiveIntoUi()
        this._SyncActiveRefs(false)
        this._RebindAllHotkeys()
        this._SetStatus("已复制: " m.name)
    }

    _DeleteMacro() {
        if (this.store.macros.Length <= 1) {
            MsgBox("至少保留一套配置。", "AutoKey", "Icon!")
            return
        }
        m := this.store.Active()
        if this._IsRunnerActive(m.id) {
            MsgBox("请先停止「" m.name "」再删除。", "AutoKey", "Icon!")
            return
        }
        if MsgBox("确定删除「" m.name "」？", "AutoKey", "YesNo Icon?") != "Yes"
            return
        this.runners.Delete(m.id)
        this.store.Remove(m.id)
        this._ReloadMacroList()
        this._LoadActiveIntoUi()
        this._SyncActiveRefs(false)
        this._RebindAllHotkeys()
        this._SetStatus("已删除")
    }

    /** 保证配置名称在列表里唯一 */
    _UniqueName(base, exceptId := "") {
        name := base
        n := 2
        loop {
            clash := false
            for m in this.store.macros {
                if (exceptId != "" && m.id = exceptId)
                    continue
                if (m.name = name) {
                    clash := true
                    break
                }
            }
            if !clash
                return name
            name := base " #" n
            n++
        }
    }

    /**
     * 同 exe 多套且未区分窗口时给个提示；不改名称。
     */
    _WarnIfSameAppAmbiguous(m) {
        if (m.targetExe = "")
            return
        peers := 0
        for other in this.store.macros {
            if (other.id = m.id)
                continue
            if (StrLower(other.targetExe) = StrLower(m.targetExe))
                peers++
        }
        if (peers = 0)
            return
        if (!m.targetHwnd && m.targetIndex <= 0)
            this._SetStatus("同进程已有其它配置：请用「选择目标窗口…」锁定具体窗口")
    }

    _ImportIni() {
        path := FileSelect(1, , "导入旧版 ini 配置", "INI (*.ini)")
        if (path = "")
            return
        try {
            m := MacroConfig.FromIniFile(path)
            this.store.Add(m)
            this._ReloadMacroList(m.id)
            this._LoadActiveIntoUi()
            this._ApplyFromUi(true)
            this._SetStatus("已导入: " m.name)
        } catch as e {
            MsgBox("导入失败:`n" e.Message, "AutoKey", "Icon!")
        }
    }

    ; ───────── UI ↔ 配置 ─────────

    _LoadActiveIntoUi() {
        prevLoading := this._loadingUi
        this._loadingUi := true
        m := this.store.Active()
        m.EnsureKeys()
        ; 清理历史误写入的窗口后缀，名称字段只保留用户自己的名字
        cleanName := this._CleanMacroName(m.name)
        if (cleanName != m.name) {
            m.name := cleanName
            this.store.Save()
        }
        this.edName.Value := m.name
        this.tabMode.Value := (m.mode = "sequence") ? 2 : 1
        this.edSingleKey.Value := ""
        this.edInterval.Value := m.keys.Length ? m.keys[1].interval : 50
        this.chkLoop.Value := m.loop ? 1 : 0
        this.edLoopDelay.Value := m.loopDelay
        this.edRepeat.Value := m.repeat
        this.edStartHk.Value := m.startHotkey
        this.edStopHk.Value := m.stopHotkey
        this.edPauseHk.Value := m.pauseHotkey
        this.edExe.Value := m.targetExe
        this.edWinIndex.Value := Integer(m.targetIndex)
        this._lockHwnd := Integer(m.targetHwnd)
        this._UpdateLockText()
        this.chkActivate.Value := m.activate ? 1 : 0
        this.ddlSend.Choose(m.sendMode = "ControlSend" ? 2 : 1)
        this._RefreshKeyList(m)
        this._RefreshStepList(m)
        this._OnModeChange()
        this._loadingUi := prevLoading
    }

    _RefreshKeyList(m := unset) {
        if !IsSet(m)
            m := this.store.Active()
        m.EnsureKeys()
        this.lvKeys.Delete()
        for i, k in m.keys
            this.lvKeys.Add(, i, k.key, k.interval)
    }

    _RefreshStepList(m := unset) {
        if !IsSet(m)
            m := this.store.Active()
        this.lvSteps.Delete()
        for i, s in m.steps {
            content := this._StepContent(s)
            this.lvSteps.Add(, i, this._StepKindLabel(s.kind), content, s.delay, s.kind = "key" ? s.hold : "-")
        }
    }

    _StepKindLabel(kind) {
        switch kind {
            case "sleep": return "等待"
            case "click": return "点击"
            default: return "按键"
        }
    }

    _StepContent(s) {
        switch s.kind {
            case "sleep": return s.delay " ms"
            case "click":
                btn := MacroConfig.NormalizeButton(s.HasOwnProp("button") ? s.button : "Left")
                clicks := MacroConfig.NormalizeClicks(s.HasOwnProp("clicks") ? s.clicks : 1)
                gap := MacroConfig.NormalizeClickGap(s.HasOwnProp("clickGap") ? s.clickGap : 80)
                label := (btn = "Right" ? "右键" : "左键")
                if (clicks = 2)
                    label .= "双击"
                else if (clicks > 2)
                    label .= "×" clicks
                else
                    label .= "单击"
                if (clicks > 1)
                    label .= " /" gap "ms"
                return label " (" s.x ", " s.y ")"
            default: return s.key
        }
    }

    _OnModeChange() {
        if this._loadingUi
            return
        ; Tab 一切换就落盘模式，避免「配了序列步骤却仍按连发跑」
        m := this.store.Active()
        if !m
            return
        want := this._IsSingleMode() ? "single" : "sequence"
        if (m.mode != want) {
            m.mode := want
            try this.store.Save()
        }
        this._SetStatus(want = "single" ? "当前编辑区: 连发模式" : "当前编辑区: 按键序列")
    }

    /** 编辑序列步骤时强制写成 sequence，避免只改了 steps 却还是 single */
    _EnsureSequenceMode() {
        m := this.store.Active()
        if !m
            return
        if (m.mode != "sequence") {
            m.mode := "sequence"
            try this.store.Save()
        }
        if this._IsSingleMode()
            this.tabMode.Value := 2
    }

    /** 编辑连发键位时强制写成 single */
    _EnsureSingleMode() {
        m := this.store.Active()
        if !m
            return
        if (m.mode != "single") {
            m.mode := "single"
            try this.store.Save()
        }
        if !this._IsSingleMode()
            this.tabMode.Value := 1
    }

    _CollectFromUi() {
        m := this.store.Active().Clone()
        m.name := Trim(this.edName.Value)
        m.name := this._CleanMacroName(m.name)
        if (m.name = "")
            m.name := "未命名"
        m.mode := this._IsSingleMode() ? "single" : "sequence"
        m.loop := this.chkLoop.Value ? 1 : 0
        m.loopDelay := Integer(this.edLoopDelay.Value || 0)
        m.repeat := Integer(this.edRepeat.Value || 0)
        m.startHotkey := Trim(this.edStartHk.Value) || "F6"
        m.stopHotkey := Trim(this.edStopHk.Value) || "F7"
        m.pauseHotkey := Trim(this.edPauseHk.Value) || "F8"
        m.targetExe := Trim(this.edExe.Value)
        m.targetTitle := ""
        m.targetClass := ""
        m.targetIndex := Integer(this.edWinIndex.Value || 0)
        m.targetHwnd := Integer(this._lockHwnd)
        m.activate := this.chkActivate.Value ? 1 : 0
        m.sendMode := this.ddlSend.Text

        m.keys := []
        for k in this.store.Active().keys
            m.keys.Push(MacroConfig.CloneKey(k))
        m.EnsureKeys()
        m.SyncLegacySingle()

        m.steps := []
        for s in this.store.Active().steps
            m.steps.Push(MacroConfig.CloneStep(s))

        if (m.mode = "sequence" && m.steps.Length = 0)
            throw Error("按键序列为空，请至少添加一步。")
        if (m.mode = "single" && m.keys.Length = 0)
            throw Error("请至少添加一个连发键位。")
        return m
    }

    /** @returns {Integer} 1=已应用 0=失败（已提示原因） */
    _ApplyFromUi(showTip := true) {
        id := this.store.activeId
        if this._IsRunnerActive(id) {
            MsgBox("「" this.store.Active().name "」正在运行，请先停止再保存。", "AutoKey", "Icon!")
            return 0
        }
        try {
            m := this._CollectFromUi()
        } catch as e {
            MsgBox(e.Message, "AutoKey", "Icon!")
            return 0
        }
        m.name := this._UniqueName(m.name, m.id)
        this._WarnIfSameAppAmbiguous(m)
        this.store.ReplaceActive(m)
        this._ReloadMacroList(m.id)
        this._SyncActiveRefs(true)
        this._RebindAllHotkeys()
        if showTip
            this._SetStatus("已保存并应用: " m.name)
        else
            this._RefreshStatusBar()
        return 1
    }

    /** 把当前 active 配置同步到 this.cfg / this.target / this.seq（不启动） */
    _SyncActiveRefs(rebuildSeq := true) {
        m := this.store.Active()
        this.cfg := m
        this.target := WindowTarget(m)
        ; 正在跑的实例不能被替换，否则旧定时器失去引用、再也停不下来
        if (rebuildSeq && this._IsRunnerActive(m.id))
            rebuildSeq := false
        if (rebuildSeq || !this.runners.Has(m.id))
            this.runners[m.id] := this._MakeRunner(m)
        this.seq := this.runners[m.id]
    }

    _MakeRunner(m) {
        mid := m.id
        seq := Sequencer(m, WindowTarget(m))
        seq.onStatus := (t) => this._OnRunnerStatus(mid, t)
        return seq
    }

    _OnRunnerStatus(id, text) {
        try {
            m := this.store.GetById(id)
            name := m ? m.name : id
            ; 只在状态栏详细显示当前选中配置；其它配置变化时刷新列表标记
            if (id = this.store.activeId)
                this._SetStatus(name ": " text)
            else
                this._RefreshStatusBar()
            this._RefreshRunMarks()
        }
    }

    _RefreshStatusBar() {
        running := []
        ; 按 macros 顺序取，避免枚举 runners 时被其它线程插入新条目
        for m in this.store.macros {
            if this._IsRunnerActive(m.id)
                running.Push(m.name)
        }
        if (running.Length = 0) {
            cur := this.store.Active()
            this._SetStatus("就绪 — " (cur ? cur.name : ""))
            return
        }
        out := "运行中(" running.Length "): "
        for i, n in running
            out .= (i = 1 ? "" : ", ") n
        this._SetStatus(out)
    }

    ; ───────── 连发键位编辑 ─────────

    _AddSpamKey(key := unset) {
        if !this._IsSingleMode() {
            MsgBox("请先切换到「连发模式」页。", "AutoKey", "Icon!")
            return
        }
        if !IsSet(key)
            key := Trim(this.edSingleKey.Value)
        if (key = "") {
            MsgBox("请填写或捕捉要加入的按键。", "AutoKey", "Icon!")
            return
        }
        interval := Integer(this.edInterval.Value || 50)
        if (interval < 0)
            interval := 0
        this._EnsureSingleMode()
        this.store.Active().keys.Push(MacroConfig.NewKey(key, interval))
        this.store.Active().SyncLegacySingle()
        this.store.Save()
        this._RefreshKeyList()
        this.edSingleKey.Value := ""
        this._SetStatus("已加入键位: " key)
    }

    _EditSpamKey() {
        if !this._IsSingleMode()
            return
        row := this.lvKeys.GetNext()
        if !row {
            MsgBox("请先选中一个键位。", "AutoKey", "Icon!")
            return
        }
        cur := this.store.Active().keys[row]
        item := this._KeyDialog(cur)
        if !item
            return
        this.store.Active().keys[row] := item
        this.store.Active().SyncLegacySingle()
        this.store.Save()
        this._RefreshKeyList()
        this.lvKeys.Modify(row, "Select Focus Vis")
    }

    _RemoveSpamKey() {
        if !this._IsSingleMode()
            return
        row := this.lvKeys.GetNext()
        if !row
            return
        if (this.store.Active().keys.Length <= 1) {
            MsgBox("至少保留一个连发键位。", "AutoKey", "Icon!")
            return
        }
        this.store.Active().keys.RemoveAt(row)
        this.store.Active().SyncLegacySingle()
        this.store.Save()
        this._RefreshKeyList()
    }

    _MoveSpamKey(dir) {
        if !this._IsSingleMode()
            return
        row := this.lvKeys.GetNext()
        if !row
            return
        keys := this.store.Active().keys
        newRow := row + dir
        if (newRow < 1 || newRow > keys.Length)
            return
        tmp := keys[row]
        keys[row] := keys[newRow]
        keys[newRow] := tmp
        this.store.Active().SyncLegacySingle()
        this.store.Save()
        this._RefreshKeyList()
        this.lvKeys.Modify(newRow, "Select Focus Vis")
    }

    _KeyDialog(existing := unset) {
        isEdit := IsSet(existing)
        cur := isEdit ? MacroConfig.CloneKey(existing) : MacroConfig.NewKey("{Space}", 50)
        d := Gui("+Owner" this.gui.Hwnd " +AlwaysOnTop", isEdit ? "编辑键位" : "添加键位")
        d.SetFont("s9", "Segoe UI")
        d.AddText(, "按键（如 a / {Space} / {F1} / ^c）")
        edKey := d.AddEdit("w220", cur.key)
        d.AddButton("w220", "捕捉按键").OnEvent("Click", (*) => this._CaptureToEdit(edKey))
        d.AddText(, "间隔 ms")
        edInterval := d.AddEdit("w220 Number", cur.interval)
        result := ""

        OnOk(*) {
            key := Trim(edKey.Value)
            if (key = "") {
                MsgBox("请填写按键。", "AutoKey", "Icon!")
                return
            }
            result := MacroConfig.NewKey(key, Integer(edInterval.Value || 50))
            d.Destroy()
        }
        OnCancel(*) {
            result := ""
            d.Destroy()
        }

        d.AddButton("w100 Default", "确定").OnEvent("Click", OnOk)
        d.AddButton("x+10 w100", "取消").OnEvent("Click", OnCancel)
        d.OnEvent("Close", OnCancel)
        hwnd := d.Hwnd
        d.Show()
        WinWaitClose("ahk_id " hwnd)
        return result
    }

    ; ───────── 步骤编辑 ─────────

    _AddStep(kind) {
        if this._IsSingleMode() {
            MsgBox("请先切换到「按键序列」页。", "AutoKey", "Icon!")
            return
        }
        step := this._StepDialog(kind)
        if !step
            return
        this._EnsureSequenceMode()
        this.store.Active().steps.Push(step)
        this.store.Save()
        this._RefreshStepList()
        row := this.store.Active().steps.Length
        this.lvSteps.Modify(row, "Select Focus Vis")
        this._SetStatus("已添加" this._StepKindLabel(kind) "步骤")
    }

    _EditStep() {
        row := this.lvSteps.GetNext()
        if !row {
            MsgBox("请先选中一步。", "AutoKey", "Icon!")
            return
        }
        cur := this.store.Active().steps[row]
        step := this._StepDialog(cur.kind, cur)
        if !step
            return
        this._EnsureSequenceMode()
        this.store.Active().steps[row] := step
        this.store.Save()
        this._RefreshStepList()
        this.lvSteps.Modify(row, "Select Focus Vis")
    }

    _RemoveStep() {
        row := this.lvSteps.GetNext()
        if !row
            return
        this._EnsureSequenceMode()
        this.store.Active().steps.RemoveAt(row)
        this.store.Save()
        this._RefreshStepList()
    }

    _MoveStep(dir) {
        row := this.lvSteps.GetNext()
        if !row
            return
        this._EnsureSequenceMode()
        steps := this.store.Active().steps
        newRow := row + dir
        if (newRow < 1 || newRow > steps.Length)
            return
        tmp := steps[row]
        steps[row] := steps[newRow]
        steps[newRow] := tmp
        this.store.Save()
        this._RefreshStepList()
        this.lvSteps.Modify(newRow, "Select Focus Vis")
    }

    _StepDialog(kind, existing := unset) {
        isEdit := IsSet(existing)
        s := isEdit ? MacroConfig.CloneStep(existing) : MacroConfig.NewStep(kind, kind = "key" ? "a" : "", kind = "sleep" ? 500 : 100)

        title := (isEdit ? "编辑" : "添加") this._StepKindLabel(kind)
        d := Gui("+Owner" this.gui.Hwnd " +AlwaysOnTop", title)
        d.SetFont("s9", "Segoe UI")
        edKey := ""
        edDelay := ""
        edHold := ""
        edPoint := ""
        ddlButton := ""
        ddlClicks := ""
        edClicks := ""
        edClickGap := ""
        pickedX := Integer(s.x)
        pickedY := Integer(s.y)
        hasPoint := isEdit && kind = "click"
        curClicks := MacroConfig.NormalizeClicks(s.HasOwnProp("clicks") ? s.clicks : 1)
        curGap := MacroConfig.NormalizeClickGap(s.HasOwnProp("clickGap") ? s.clickGap : 80)

        switch kind {
            case "key":
                d.AddText(, "按键（如 a / {Enter} / {Space} / ^c）")
                edKey := d.AddEdit("w240", s.key)
                d.AddButton("w240", "捕捉按键").OnEvent("Click", (*) => this._CaptureToEdit(edKey))
                d.AddText(, "执行后延迟 ms")
                edDelay := d.AddEdit("w240 Number", s.delay)
                d.AddText(, "按住 ms（0=单击）")
                edHold := d.AddEdit("w240 Number", s.hold)
            case "sleep":
                d.AddText(, "等待时长 ms")
                edDelay := d.AddEdit("w240 Number", s.delay)
            case "click":
                d.AddText(, "目标窗口客户区坐标")
                pointText := hasPoint ? "X=" pickedX "，Y=" pickedY : "尚未拾取"
                edPoint := d.AddEdit("w240 ReadOnly", pointText)
                d.AddButton("w240", "拾取坐标…").OnEvent("Click", PickPoint)
                d.AddText(, "鼠标按键")
                ddlButton := d.AddDropDownList("w240", ["左键", "右键"])
                ddlButton.Choose(MacroConfig.NormalizeButton(s.button) = "Right" ? 2 : 1)
                d.AddText(, "点击方式")
                ddlClicks := d.AddDropDownList("w240", ["单击", "双击", "自定义次数"])
                if (curClicks = 1)
                    ddlClicks.Choose(1)
                else if (curClicks = 2)
                    ddlClicks.Choose(2)
                else
                    ddlClicks.Choose(3)
                d.AddText(, "自定义次数（选「自定义」时生效，1–20）")
                edClicks := d.AddEdit("w240 Number", curClicks)
                d.AddText(, "连点间隔 ms（双击/多次之间，游戏建议 60–120）")
                edClickGap := d.AddEdit("w240 Number", curGap)
                ddlClicks.OnEvent("Change", (*) => SyncClicksUi())
                SyncClicksUi()
                d.AddText(, "执行后延迟 ms")
                edDelay := d.AddEdit("w240 Number", s.delay)
        }

        result := ""

        SyncClicksUi(*) {
            if !ddlClicks || !edClicks
                return
            ; 单击/双击时次数框只读展示；自定义才可改
            if (ddlClicks.Value = 1) {
                edClicks.Value := 1
                edClicks.Opt("+ReadOnly")
            } else if (ddlClicks.Value = 2) {
                edClicks.Value := 2
                edClicks.Opt("+ReadOnly")
            } else {
                edClicks.Opt("-ReadOnly")
                if (Integer(edClicks.Value || 0) < 3)
                    edClicks.Value := Max(3, curClicks)
            }
            if edClickGap {
                if (ddlClicks.Value = 1)
                    edClickGap.Opt("+ReadOnly")
                else
                    edClickGap.Opt("-ReadOnly")
            }
        }

        PickPoint(*) {
            point := this._PickClickPoint(d)
            if !point
                return
            pickedX := point.x
            pickedY := point.y
            hasPoint := true
            edPoint.Value := "X=" pickedX "，Y=" pickedY "（" SubStr(point.title, 1, 24) "）"
        }

        OnOk(*) {
            step := this._BuildStepFromDialog(kind, edKey, edDelay, edHold, pickedX, pickedY, hasPoint, ddlButton, ddlClicks, edClicks, edClickGap)
            if !step
                return
            result := step
            d.Destroy()
        }
        OnCancel(*) {
            result := ""
            d.Destroy()
        }

        d.AddButton("w95 Default", "确定").OnEvent("Click", OnOk)
        d.AddButton("x+10 w95", "取消").OnEvent("Click", OnCancel)
        d.OnEvent("Close", OnCancel)
        hwnd := d.Hwnd
        d.Show()
        WinWaitClose("ahk_id " hwnd)
        return result
    }

    _BuildStepFromDialog(kind, edKey, edDelay, edHold, x, y, hasPoint := false, ddlButton := "", ddlClicks := "", edClicks := "", edClickGap := "") {
        delay := Integer(edDelay.Value || 50)
        if (kind = "sleep")
            return MacroConfig.NewStep("sleep", "", delay)
        if (kind = "click") {
            if !hasPoint {
                MsgBox("请先拾取点击位置。", "AutoKey", "Icon!")
                return ""
            }
            button := (ddlButton && ddlButton.Value = 2) ? "Right" : "Left"
            clicks := 1
            if (ddlClicks && ddlClicks.Value = 2)
                clicks := 2
            else if (ddlClicks && ddlClicks.Value = 3)
                clicks := Integer(edClicks ? edClicks.Value : 3)
            else if (ddlClicks && ddlClicks.Value = 1)
                clicks := 1
            else
                clicks := Integer(edClicks ? edClicks.Value : 1)
            gap := Integer(edClickGap ? (edClickGap.Value || 80) : 80)
            return MacroConfig.NewStep("click", "", delay, 0, x, y, button, clicks, gap)
        }
        key := Trim(edKey.Value)
        if (key = "") {
            MsgBox("请填写按键。", "AutoKey", "Icon!")
            return ""
        }
        return MacroConfig.NewStep("key", key, delay, Integer(edHold.Value || 0))
    }

    /**
     * 隐藏 AutoKey 后用十字准星拾取窗口客户区坐标。
     * 左键确认，Esc 取消；确认后同时把鼠标下窗口绑定为当前目标。
     */
    _PickClickPoint(dialog) {
        if this._capturing
            return ""
        this._capturing := true
        result := ""
        failureMessage := ""
        this._pickConfirmed := false
        this._pickCancelled := false
        confirmClick := (*) => this._pickConfirmed := true
        cancelPick := (*) => this._pickCancelled := true
        clickHookOn := false
        escapeHookOn := false
        cameraNoiseBlocked := false

        try {
            this._UnbindHotkeys()
            dialog.Hide()
            this.gui.Hide()
            KeyWait "LButton"
            Hotkey "*LButton", confirmClick, "On"
            clickHookOn := true
            Hotkey "*Escape", cancelPick, "On"
            escapeHookOn := true
            ; 拾取时游戏常在前台：屏蔽滚轮/中键，否则一碰就缩放镜头
            this._BlockCameraNoise(true)
            cameraNoiseBlocked := true

            crossCursor := DllCall("LoadCursor", "Ptr", 0, "Ptr", 32515, "Ptr")
            thisPid := DllCall("GetCurrentProcessId", "UInt")

            loop {
                MouseGetPos(&screenX, &screenY, &hoverHwnd)
                DllCall("SetCursor", "Ptr", crossCursor)
                ToolTip("十字准星拾取：移到目标后左键确认（已屏蔽滚轮）`n屏幕坐标 " screenX ", " screenY "　Esc 取消", screenX + 18, screenY + 18)

                if this._pickCancelled {
                    KeyWait "Escape"
                    break
                }
                if this._pickConfirmed {
                    rootHwnd := hoverHwnd ? DllCall("GetAncestor", "Ptr", hoverHwnd, "UInt", 2, "Ptr") : 0
                    if !rootHwnd
                        rootHwnd := hoverHwnd
                    if (!rootHwnd || WinGetPID("ahk_id " rootHwnd) = thisPid) {
                        KeyWait "LButton"
                        this._pickConfirmed := false
                        continue
                    }

                    point := Buffer(8, 0)
                    NumPut("Int", screenX, point, 0)
                    NumPut("Int", screenY, point, 4)
                    if !DllCall("ScreenToClient", "Ptr", rootHwnd, "Ptr", point) {
                        KeyWait "LButton"
                        this._pickConfirmed := false
                        continue
                    }
                    clientX := NumGet(point, 0, "Int")
                    clientY := NumGet(point, 4, "Int")
                    rect := Buffer(16, 0)
                    DllCall("GetClientRect", "Ptr", rootHwnd, "Ptr", rect)
                    width := NumGet(rect, 8, "Int")
                    height := NumGet(rect, 12, "Int")
                    if (clientX < 0 || clientY < 0 || clientX >= width || clientY >= height) {
                        KeyWait "LButton"
                        this._pickConfirmed := false
                        ToolTip("请点击窗口的内容区域，不要点击标题栏或边框。")
                        Sleep 900
                        continue
                    }

                    pickedTitle := WinGetTitle("ahk_id " rootHwnd)
                    this._BindPickedWindow(rootHwnd)
                    result := {
                        x: clientX,
                        y: clientY,
                        hwnd: rootHwnd + 0,
                        title: pickedTitle
                    }
                    KeyWait "LButton"
                    break
                }
                Sleep 15
            }
        } catch as e {
            result := ""
            failureMessage := e.Message
        } finally {
            if clickHookOn {
                KeyWait "LButton"
                try Hotkey "*LButton", "Off"
            }
            if escapeHookOn {
                KeyWait "Escape"
                try Hotkey "*Escape", "Off"
            }
            if cameraNoiseBlocked
                this._BlockCameraNoise(false)
            ToolTip()
            arrowCursor := DllCall("LoadCursor", "Ptr", 0, "Ptr", 32512, "Ptr")
            DllCall("SetCursor", "Ptr", arrowCursor)
            this._capturing := false
            if this.cfg
                this._RebindAllHotkeys()
            this.gui.Show()
            dialog.Show()
        }

        if result
            this._SetStatus("已拾取 " result.title "：客户区坐标 (" result.x ", " result.y ")")
        else if (failureMessage != "")
            this._SetStatus("坐标拾取失败: " failureMessage)
        else
            this._SetStatus("已取消坐标拾取")
        return result
    }

    /** 拾取时屏蔽滚轮/中键，避免游戏镜头被缩放 */
    _BlockCameraNoise(enable) {
        nop := AutoKeyApp._Noop
        for key in ["WheelUp", "WheelDown", "WheelLeft", "WheelRight", "MButton"] {
            try {
                if enable
                    Hotkey("*" key, nop, "On")
                else
                    Hotkey("*" key, "Off")
            }
        }
    }

    static _Noop(*) {
    }

    _BindPickedWindow(hwnd) {
        exe := WinGetProcessName("ahk_id " hwnd)
        index := this._IndexOfWindow(exe, hwnd)

        this.edExe.Value := exe
        this.edWinIndex.Value := index
        this._lockHwnd := hwnd + 0
        this._UpdateLockText()
        this._SaveTargetFields(exe, index, hwnd)
        this._ReloadMacroList(this.store.activeId)
    }

    /** 只更新目标窗口字段，不改配置名称 */
    _SaveTargetFields(exe, index, hwnd) {
        m := this.store.Active()
        m.targetExe := exe
        m.targetTitle := ""
        m.targetClass := ""
        m.targetIndex := Integer(index)
        m.targetHwnd := Integer(hwnd)
        ; 顺带清掉名称里历史残留的 [窗口标题]，绝不写入新窗口名
        cleanName := this._CleanMacroName(m.name)
        if (cleanName != m.name) {
            m.name := cleanName
            this.edName.Value := cleanName
        }
        try this.store.Save()
    }

    ; ───────── 捕捉按键 / 选择目标窗口 ─────────

    _CaptureInto(which) {
        this._SetStatus("请按下要绑定的键…（Esc 取消）")
        key := this._CaptureKey()
        if (key = "") {
            this._SetStatus("已取消捕捉")
            return
        }
        switch which {
            case "single":
                this.edSingleKey.Value := key
                if this._IsSingleMode() {
                    this._AddSpamKey(key)
                    return
                }
            case "start": this.edStartHk.Value := key
            case "stop": this.edStopHk.Value := key
            case "pause": this.edPauseHk.Value := key
        }
        this._SetStatus("已捕捉: " key)
    }

    _CaptureToEdit(ed) {
        this._SetStatus("请按下要绑定的键…（Esc 取消）")
        key := this._CaptureKey()
        if (key = "") {
            this._SetStatus("已取消捕捉")
            return
        }
        ed.Value := key
        this._SetStatus("已捕捉: " key)
    }

    _CaptureKey() {
        if this._capturing
            return ""
        this._capturing := true
        this._UnbindHotkeys()
        ih := InputHook("T15")
        ih.KeyOpt("{All}", "ES")  ; 任意键结束并屏蔽
        ih.Start()
        ih.Wait()
        this._capturing := false
        out := ""
        if (ih.EndReason = "EndKey") {
            if (ih.EndKey != "Escape")
                out := this._FormatKeyName(ih.EndKey)
        }
        if this.cfg
            this._RebindAllHotkeys()
        return out
    }

    _FormatKeyName(name) {
        if (name = "")
            return ""
        ; 功能键、空格等用花括号
        if RegExMatch(name, "i)^(F\d+|Esc|Escape|Enter|Space|Tab|Backspace|Delete|Insert|Home|End|PgUp|PgDn|Up|Down|Left|Right|AppsKey|LWin|RWin|CapsLock|PrintScreen|Pause)$") {
            if (name = "Escape")
                name := "Esc"
            return "{" name "}"
        }
        if (StrLen(name) = 1)
            return StrLower(name)
        return "{" name "}"
    }

    _UpdateLockText() {
        if !this._lockHwnd {
            this.txtLock.Value := "未锁定具体窗口"
            return
        }
        title := ""
        try title := WinGetTitle("ahk_id " this._lockHwnd)
        if (title = "")
            this.txtLock.Value := "锁定窗口 " this._lockHwnd "（已关闭）"
        else
            this.txtLock.Value := "已锁定 " this._lockHwnd "：" SubStr(title, 1, 24)
    }

    /** 该窗口在同 exe 窗口里排第几（与运行时的「窗口 #」一致） */
    _IndexOfWindow(exe, hwnd) {
        for i, w in WindowTarget.ListWindows(exe) {
            if (w.hwnd = hwnd + 0)
                return i
        }
        return 0
    }

    /** 统一的目标窗口入口：实时窗口列表 + 最小化后直接点选 */
    _ChooseTargetWindow() {
        d := Gui("+Owner" this.gui.Hwnd " +AlwaysOnTop", "选择目标窗口")
        d.SetFont("s9", "Segoe UI")
        d.AddText("w520", "推荐让 AutoKey 最小化后直接点击目标；也可从下方列表选择。")
        d.AddButton("w520 h36 Default", "最小化 AutoKey，然后点击目标窗口").OnEvent("Click", OnPick)
        txtListStatus := d.AddText("w520 cGray", "仅在本窗口打开时监听；正在读取…")
        lv := d.AddListView("w520 r12", ["#", "窗口标题", "进程", "句柄"])
        lv.ModifyCol(1, 34)
        lv.ModifyCol(2, 280)
        lv.ModifyCol(3, 110)
        lv.ModifyCol(4, 80)

        wins := []
        lastSignature := ""
        listening := false

        StopListen(*) {
            if listening {
                SetTimer(RefreshList, 0)
                listening := false
            }
        }
        StartListen(*) {
            if listening
                return
            RefreshList()
            SetTimer(RefreshList, 700)
            listening := true
        }

        RefreshList(*) {
            if !WinExist("ahk_id " d.Hwnd) {
                StopListen()
                return
            }
            selectedHwnd := this._lockHwnd
            row := lv.GetNext()
            if (row && row <= wins.Length)
                selectedHwnd := wins[row].hwnd

            fresh := []
            signature := ""
            thisPid := DllCall("GetCurrentProcessId", "UInt")
            for w in WindowTarget.ListWindows() {
                try {
                    if (WinGetPID("ahk_id " w.hwnd) = thisPid)
                        continue
                    fresh.Push(w)
                    signature .= w.hwnd "|" w.exe "|" w.title "`n"
                }
            }
            if (signature = lastSignature)
                return

            wins := fresh
            lastSignature := signature
            lv.Delete()
            for i, w in wins {
                lv.Add(, i, w.title, w.exe, w.hwnd)
                if (w.hwnd = selectedHwnd)
                    lv.Modify(i, "Select Focus Vis")
            }
            if (wins.Length = 0)
                lv.Add(, "-", "没有找到可见窗口", "", "")
            txtListStatus.Value := "列表打开中监听：当前 " wins.Length " 个可见窗口"
        }

        OnPick(*) {
            StopListen()
            pickedHwnd := this._PickTargetInteractively(d)
            if !pickedHwnd {
                StartListen()
                return
            }
            this._BindTargetWindow(pickedHwnd)
            d.Destroy()
        }
        OnOk(*) {
            row := lv.GetNext()
            if (!row || row > wins.Length) {
                MsgBox("请先选中一个窗口。", "AutoKey", "Icon!")
                return
            }
            sel := wins[row]
            StopListen()
            this._BindTargetWindow(sel.hwnd)
            d.Destroy()
        }
        OnUnlock(*) {
            StopListen()
            this._lockHwnd := 0
            this._UpdateLockText()
            this._SaveTargetFields(Trim(this.edExe.Value), Integer(this.edWinIndex.Value || 0), 0)
            this._ReloadMacroList(this.store.activeId)
            this._SetStatus("已取消窗口锁定，按「窗口 #」序号匹配")
            d.Destroy()
        }
        OnCancel(*) {
            StopListen()
            d.Destroy()
        }

        lv.OnEvent("DoubleClick", OnOk)
        d.AddButton("w120", "选择列表窗口").OnEvent("Click", OnOk)
        d.AddButton("x+10 w100", "取消锁定").OnEvent("Click", OnUnlock)
        d.AddButton("x+10 w100", "关闭").OnEvent("Click", OnCancel)
        d.OnEvent("Close", OnCancel)
        hwnd := d.Hwnd
        d.Show()
        StartListen()
        WinWaitClose("ahk_id " hwnd)
        StopListen()
    }

    _BindTargetWindow(hwnd) {
        exe := WinGetProcessName("ahk_id " hwnd)
        index := this._IndexOfWindow(exe, hwnd)
        this.edExe.Value := exe
        this.edWinIndex.Value := index
        this._lockHwnd := hwnd + 0
        this._UpdateLockText()
        this._SaveTargetFields(exe, index, hwnd)
        this._ReloadMacroList(this.store.activeId)
        title := WinGetTitle("ahk_id " hwnd)
        this._SetStatus("已锁定 " exe " #" index "：" title)
    }

    /** 最小化 AutoKey 后点选顶层窗口；选择点击不会传给目标程序 */
    _PickTargetInteractively(dialog) {
        if this._capturing
            return 0
        this._capturing := true
        this._pickConfirmed := false
        this._pickCancelled := false
        pickedHwnd := 0
        failureMessage := ""
        confirmClick := (*) => this._pickConfirmed := true
        cancelPick := (*) => this._pickCancelled := true
        clickHookOn := false
        escapeHookOn := false

        try {
            this._UnbindHotkeys()
            dialog.Hide()
            WinMinimize("ahk_id " this.gui.Hwnd)
            KeyWait "LButton"
            Hotkey "*LButton", confirmClick, "On"
            clickHookOn := true
            Hotkey "*Escape", cancelPick, "On"
            escapeHookOn := true
            thisPid := DllCall("GetCurrentProcessId", "UInt")

            loop {
                MouseGetPos(&screenX, &screenY, &hoverHwnd)
                ToolTip("请点击要控制的目标窗口`nEsc 取消", screenX + 18, screenY + 18)
                if this._pickCancelled {
                    KeyWait "Escape"
                    break
                }
                if this._pickConfirmed {
                    rootHwnd := hoverHwnd ? DllCall("GetAncestor", "Ptr", hoverHwnd, "UInt", 2, "Ptr") : 0
                    if (!rootHwnd || WinGetPID("ahk_id " rootHwnd) = thisPid) {
                        KeyWait "LButton"
                        this._pickConfirmed := false
                        continue
                    }
                    pickedHwnd := rootHwnd + 0
                    KeyWait "LButton"
                    break
                }
                Sleep 15
            }
        } catch as e {
            pickedHwnd := 0
            failureMessage := e.Message
        } finally {
            if clickHookOn {
                KeyWait "LButton"
                try Hotkey "*LButton", "Off"
            }
            if escapeHookOn {
                KeyWait "Escape"
                try Hotkey "*Escape", "Off"
            }
            ToolTip()
            this._capturing := false
            if this.cfg
                this._RebindAllHotkeys()
            try WinRestore("ahk_id " this.gui.Hwnd)
            this.gui.Show()
            dialog.Show()
            try WinActivate("ahk_id " dialog.Hwnd)
        }
        if (failureMessage != "")
            this._SetStatus("选择窗口失败: " failureMessage)
        else if !pickedHwnd
            this._SetStatus("已取消选择窗口")
        return pickedHwnd
    }

    ; ───────── 热键 / 运行 ─────────

    _RebindAllHotkeys() {
        this._UnbindHotkeys()
        used := Map()
        for m in this.store.macros {
            mid := m.id
            this._TryBind(m.startHotkey, used, (*) => this.StartMacro(mid))
            this._TryBind(m.stopHotkey, used, (*) => this.StopMacro(mid))
            this._TryBind(m.pauseHotkey, used, (*) => this.TogglePauseMacro(mid))
        }
    }

    _TryBind(hk, used, fn) {
        hk := Trim(hk)
        if (hk = "")
            return
        key := StrLower(hk)
        if used.Has(key) {
            ; 多套配置热键冲突时，后写的不覆盖先绑定的
            return
        }
        try {
            Hotkey(hk, fn, "On")
            this._boundHotkeys.Push(hk)
            used[key] := true
        }
    }

    _UnbindHotkeys() {
        for hk in this._boundHotkeys {
            try Hotkey(hk, "Off")
        }
        this._boundHotkeys := []
    }

    _SetStatus(text) {
        try this.txtStatus.Value := text
        A_IconTip := "AutoKey — " text
    }

    Start() {
        this.StartMacro(this.store.activeId)
    }

    Stop() {
        this.StopMacro(this.store.activeId)
    }

    TogglePause() {
        this.TogglePauseMacro(this.store.activeId)
    }

    StartMacro(id) {
        if this._IsRunnerActive(id) {
            cur := this.store.GetById(id)
            this._SetStatus("已在运行: " (cur ? cur.name : id))
            return
        }
        ; 若开始的是当前编辑项，先把界面同步进去
        if (id = this.store.activeId && !this._ApplyFromUi(false))
            return
        m := this.store.GetById(id)
        if !m
            return
        if !this.runners.Has(id)
            this.runners[id] := this._MakeRunner(m)
        ; 保存时配置对象会被整体替换，这里把 runner 指向最新的一份
        seq := this.runners[id]
        seq.cfg := m
        seq.target := WindowTarget(m)
        seq.Start()
        this._ReloadMacroList(this.store.activeId)
        this._RefreshStatusBar()
    }

    StopMacro(id) {
        if this.runners.Has(id)
            this.runners[id].Stop()
        this._ReloadMacroList(this.store.activeId)
        this._RefreshStatusBar()
    }

    StopAll() {
        ids := []
        for id in this.runners
            ids.Push(id)
        for id in ids
            try this.runners[id].Stop()
        this._ReloadMacroList(this.store.activeId)
        this._SetStatus("已全部停止")
    }

    TogglePauseMacro(id) {
        if this.runners.Has(id)
            this.runners[id].TogglePause()
        this._RefreshStatusBar()
    }

    _OnClose() {
        ; 关闭窗口不打断正在跑的任务，只隐藏
        this.gui.Hide()
    }

    _Quit() {
        this.StopAll()
        try {
            if !this._IsRunnerActive(this.store.activeId)
                this._ApplyFromUi(false)
        }
        ExitApp()
    }
}
