#Requires AutoHotkey v2.0+
#SingleInstance Force
Persistent
SetTitleMatchMode 2
SendMode "Input"
CoordMode "Mouse", "Screen"

;@Ahk2Exe-SetName AutoKey
;@Ahk2Exe-SetDescription 按键序列自动化（AutoHotkey v2）
;@Ahk2Exe-SetVersion 2.0.0
;@Ahk2Exe-SetMainIcon
;@Ahk2Exe-ExeName AutoKey.exe

#Include lib\Config.ahk
#Include lib\Target.ahk
#Include lib\Sequencer.ahk

global gApp := AutoKeyApp()

class AutoKeyApp {
    __New() {
        this.store := MacroStore()
        this.cfg := ""
        this.target := ""
        this.seq := ""
        this._boundHotkeys := []
        this._loadingUi := false
        this._capturing := false

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
        A_TrayMenu.Add("开始", (*) => this.Start())
        A_TrayMenu.Add("停止", (*) => this.Stop())
        A_TrayMenu.Add("暂停/继续", (*) => this.TogglePause())
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
        g.AddButton("x+8 w76", "删除").OnEvent("Click", (*) => this._DeleteMacro())
        g.AddButton("xm w160", "导入旧 ini…").OnEvent("Click", (*) => this._ImportIni())

        ; ── 右侧：编辑区 ──
        g.AddText("ys w420 Section", "名称")
        this.edName := g.AddEdit("xp w280")

        g.AddText("xp", "模式")
        this.radSingle := g.AddRadio("xp Checked", "连发模式（默认）")
        this.radSequence := g.AddRadio("x+12", "按键序列")
        this.radSingle.OnEvent("Click", (*) => this._OnModeChange())
        this.radSequence.OnEvent("Click", (*) => this._OnModeChange())

        ; 连发区：可动态添加多键位，按列表顺序轮流按下
        this.grpSingle := g.AddGroupBox("xp w420 h188", "连发键位（可添加多个，按顺序轮流连发）")
        this.lvKeys := g.AddListView("xp+12 yp+22 w396 r4", ["#", "按键", "间隔ms"])
        this.lvKeys.ModifyCol(1, 36)
        this.lvKeys.ModifyCol(2, 220)
        this.lvKeys.ModifyCol(3, 90)

        g.AddText("xp", "按键")
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
        this.btnKeyUp := g.AddButton("xp w52", "上移")
        this.btnKeyUp.OnEvent("Click", (*) => this._MoveSpamKey(-1))
        this.btnKeyDown := g.AddButton("x+4 w52", "下移")
        this.btnKeyDown.OnEvent("Click", (*) => this._MoveSpamKey(1))

        ; 序列区
        this.grpSeq := g.AddGroupBox("xm+172 y+36 w420 h168", "按键序列（按顺序执行，可含等待/点击）")
        this.lvSteps := g.AddListView("xp+12 yp+22 w396 r5", ["#", "类型", "内容", "延迟ms", "按住ms"])
        this.lvSteps.ModifyCol(1, 30)
        this.lvSteps.ModifyCol(2, 50)
        this.lvSteps.ModifyCol(3, 140)
        this.lvSteps.ModifyCol(4, 70)
        this.lvSteps.ModifyCol(5, 70)

        this.btnStepAdd := g.AddButton("xp w72", "添加")
        this.btnStepAdd.OnEvent("Click", (*) => this._AddStep())
        this.btnStepEdit := g.AddButton("x+6 w72", "编辑")
        this.btnStepEdit.OnEvent("Click", (*) => this._EditStep())
        this.btnStepDel := g.AddButton("x+6 w72", "删除")
        this.btnStepDel.OnEvent("Click", (*) => this._RemoveStep())
        this.btnStepUp := g.AddButton("x+6 w72", "上移")
        this.btnStepUp.OnEvent("Click", (*) => this._MoveStep(-1))
        this.btnStepDown := g.AddButton("x+6 w72", "下移")
        this.btnStepDown.OnEvent("Click", (*) => this._MoveStep(1))

        ; 循环 / 热键 / 目标
        g.AddGroupBox("xm+172 y+14 w420 h88", "循环与热键")
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

        g.AddGroupBox("xm+172 y+14 w420 h100", "目标窗口（可留空 = 当前前台）")
        g.AddText("xp+12 yp+22", "进程 exe")
        this.edExe := g.AddEdit("x+6 w200")
        g.AddButton("x+6 w80", "取前台").OnEvent("Click", (*) => this._PickForeground())
        g.AddText("xm+184 y+8", "标题包含")
        this.edTitle := g.AddEdit("x+6 w140")
        g.AddText("x+8", "类名")
        this.edClass := g.AddEdit("x+6 w100")
        this.chkActivate := g.AddCheckbox("xm+184 y+8 Checked", "发送前激活")
        g.AddText("x+12", "发送模式")
        this.ddlSend := g.AddDropDownList("x+6 w110", ["Send", "ControlSend"])
        this.ddlSend.Choose(1)

        ; 底部操作
        g.AddText("xm+172 y+16", "状态")
        this.txtStatus := g.AddEdit("x+8 w340 ReadOnly", "就绪")

        this.btnApply := g.AddButton("xm+172 y+10 w100 Default", "保存并应用")
        this.btnApply.OnEvent("Click", (*) => this._ApplyFromUi(true))
        this.btnStart := g.AddButton("x+8 w80", "开始")
        this.btnStart.OnEvent("Click", (*) => this.Start())
        this.btnStop := g.AddButton("x+8 w80", "停止")
        this.btnStop.OnEvent("Click", (*) => this.Stop())
        this.btnPause := g.AddButton("x+8 w80", "暂停")
        this.btnPause.OnEvent("Click", (*) => this.TogglePause())

        g.AddText("xm+172 y+10 cGray w420", "提示：改完点「保存并应用」。配置自动存到 data，无需手改文件。停止热键始终有效。")

        this.gui := g
        this._OnModeChange()
        g.Show()
    }

    ; ───────── 列表 / 切换 ─────────

    _ReloadMacroList(selectId := "") {
        this._loadingUi := true
        this.lbMacros.Delete()
        names := []
        choose := 1
        want := selectId != "" ? selectId : this.store.activeId
        for i, m in this.store.macros {
            names.Push(m.name)
            if (m.id = want)
                choose := i
        }
        if (names.Length)
            this.lbMacros.Add(names)
        if (names.Length)
            this.lbMacros.Choose(choose)
        this._loadingUi := false
    }

    _OnSelectMacro() {
        if this._loadingUi
            return
        idx := this.lbMacros.Value
        if (idx < 1)
            return
        m := this.store.macros[idx]
        if this.seq && this.seq.IsRunning {
            MsgBox("请先停止当前运行，再切换配置。", "AutoKey", "Icon!")
            this._ReloadMacroList(this.store.activeId)
            return
        }
        this.store.SetActive(m.id)
        this._LoadActiveIntoUi()
        this._ApplyFromUi(false)
    }

    _NewMacro() {
        if this.seq && this.seq.IsRunning {
            MsgBox("请先停止运行。", "AutoKey", "Icon!")
            return
        }
        Result := InputBox("输入新配置名称", "新建配置", , "新配置")
        if (Result.Result = "Cancel")
            return
        name := Trim(Result.Value)
        if (name = "")
            name := "新配置"
        m := MacroConfig()
        m.name := name
        m.mode := "single"
        m.keys := [MacroConfig.NewKey("{Space}", 50)]
        m.SyncLegacySingle()
        this.store.Add(m)
        this._ReloadMacroList(m.id)
        this._LoadActiveIntoUi()
        this._ApplyFromUi(false)
        this._SetStatus("已新建: " name)
    }

    _DeleteMacro() {
        if (this.store.macros.Length <= 1) {
            MsgBox("至少保留一套配置。", "AutoKey", "Icon!")
            return
        }
        if this.seq && this.seq.IsRunning {
            MsgBox("请先停止运行。", "AutoKey", "Icon!")
            return
        }
        m := this.store.Active()
        if MsgBox("确定删除「" m.name "」？", "AutoKey", "YesNo Icon?") != "Yes"
            return
        this.store.Remove(m.id)
        this._ReloadMacroList()
        this._LoadActiveIntoUi()
        this._ApplyFromUi(false)
        this._SetStatus("已删除")
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
        this._loadingUi := true
        m := this.store.Active()
        m.EnsureKeys()
        this.edName.Value := m.name
        if (m.mode = "sequence") {
            this.radSequence.Value := 1
        } else {
            this.radSingle.Value := 1
        }
        this.edSingleKey.Value := ""
        this.edInterval.Value := m.keys.Length ? m.keys[1].interval : 50
        this.chkLoop.Value := m.loop ? 1 : 0
        this.edLoopDelay.Value := m.loopDelay
        this.edRepeat.Value := m.repeat
        this.edStartHk.Value := m.startHotkey
        this.edStopHk.Value := m.stopHotkey
        this.edPauseHk.Value := m.pauseHotkey
        this.edExe.Value := m.targetExe
        this.edTitle.Value := m.targetTitle
        this.edClass.Value := m.targetClass
        this.chkActivate.Value := m.activate ? 1 : 0
        this.ddlSend.Choose(m.sendMode = "ControlSend" ? 2 : 1)
        this._RefreshKeyList(m)
        this._RefreshStepList(m)
        this._OnModeChange()
        this._loadingUi := false
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
            case "click": return "(" s.x ", " s.y ")"
            default: return s.key
        }
    }

    _OnModeChange() {
        isSingle := !!this.radSingle.Value
        this.lvKeys.Enabled := isSingle
        this.edSingleKey.Enabled := isSingle
        this.edInterval.Enabled := isSingle
        this.btnCapSingle.Enabled := isSingle
        this.btnKeyAdd.Enabled := isSingle
        this.btnKeyEdit.Enabled := isSingle
        this.btnKeyDel.Enabled := isSingle
        this.btnKeyUp.Enabled := isSingle
        this.btnKeyDown.Enabled := isSingle
        this.lvSteps.Enabled := !isSingle
        this.btnStepAdd.Enabled := !isSingle
        this.btnStepEdit.Enabled := !isSingle
        this.btnStepDel.Enabled := !isSingle
        this.btnStepUp.Enabled := !isSingle
        this.btnStepDown.Enabled := !isSingle
        if isSingle
            this._SetStatus("模式: 连发 — 可添加多个键位，按列表顺序轮流按下")
        else
            this._SetStatus("模式: 按键序列 — 编排按键/等待/点击步骤")
    }

    _CollectFromUi() {
        m := this.store.Active().Clone()
        m.name := Trim(this.edName.Value)
        if (m.name = "")
            m.name := "未命名"
        m.mode := this.radSingle.Value ? "single" : "sequence"
        m.loop := this.chkLoop.Value ? 1 : 0
        m.loopDelay := Integer(this.edLoopDelay.Value || 0)
        m.repeat := Integer(this.edRepeat.Value || 0)
        m.startHotkey := Trim(this.edStartHk.Value) || "F6"
        m.stopHotkey := Trim(this.edStopHk.Value) || "F7"
        m.pauseHotkey := Trim(this.edPauseHk.Value) || "F8"
        m.targetExe := Trim(this.edExe.Value)
        m.targetTitle := Trim(this.edTitle.Value)
        m.targetClass := Trim(this.edClass.Value)
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

    _ApplyFromUi(showTip := true) {
        if this.seq && this.seq.IsRunning {
            MsgBox("运行中无法保存，请先停止。", "AutoKey", "Icon!")
            return
        }
        try {
            m := this._CollectFromUi()
        } catch as e {
            MsgBox(e.Message, "AutoKey", "Icon!")
            return
        }
        this.store.ReplaceActive(m)
        this._ReloadMacroList(m.id)

        this._UnbindHotkeys()
        this.cfg := m
        this.target := WindowTarget(m)
        this.seq := Sequencer(m, this.target)
        this.seq.onStatus := (t) => this._SetStatus(t)
        this._BindHotkeys(m)
        if showTip
            this._SetStatus("已保存并应用: " m.name)
        else
            this._SetStatus("就绪 — " m.name)
    }

    ; ───────── 连发键位编辑 ─────────

    _AddSpamKey(key := unset) {
        if !this.radSingle.Value {
            MsgBox("请先切换到「连发模式」。", "AutoKey", "Icon!")
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
        this.store.Active().keys.Push(MacroConfig.NewKey(key, interval))
        this.store.Active().SyncLegacySingle()
        this.store.Save()
        this._RefreshKeyList()
        this.edSingleKey.Value := ""
        this._SetStatus("已加入键位: " key)
    }

    _EditSpamKey() {
        if !this.radSingle.Value
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
        if !this.radSingle.Value
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
        if !this.radSingle.Value
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
        d.AddButton("w100 Default", "确定").OnEvent("Click", (*) => {
            key := Trim(edKey.Value)
            if (key = "") {
                MsgBox("请填写按键。", "AutoKey", "Icon!")
                return
            }
            result := MacroConfig.NewKey(key, Integer(edInterval.Value || 50))
            d.Destroy()
        })
        d.AddButton("x+10 w100", "取消").OnEvent("Click", (*) => (result := "", d.Destroy()))
        d.OnEvent("Close", (*) => (result := "", d.Destroy()))
        d.Show()
        WinWaitClose("ahk_id " d.Hwnd)
        return result
    }

    ; ───────── 步骤编辑 ─────────

    _AddStep() {
        if this.radSingle.Value {
            MsgBox("请先切换到「按键序列」模式。", "AutoKey", "Icon!")
            return
        }
        step := this._StepDialog()
        if !step
            return
        this.store.Active().steps.Push(step)
        this.store.Save()
        this._RefreshStepList()
    }

    _EditStep() {
        row := this.lvSteps.GetNext()
        if !row {
            MsgBox("请先选中一步。", "AutoKey", "Icon!")
            return
        }
        cur := this.store.Active().steps[row]
        step := this._StepDialog(cur)
        if !step
            return
        this.store.Active().steps[row] := step
        this.store.Save()
        this._RefreshStepList()
    }

    _RemoveStep() {
        row := this.lvSteps.GetNext()
        if !row
            return
        this.store.Active().steps.RemoveAt(row)
        this.store.Save()
        this._RefreshStepList()
    }

    _MoveStep(dir) {
        row := this.lvSteps.GetNext()
        if !row
            return
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

    _StepDialog(existing := unset) {
        isEdit := IsSet(existing)
        s := isEdit ? MacroConfig.CloneStep(existing) : MacroConfig.NewStep("key", "a", 100)

        d := Gui("+Owner" this.gui.Hwnd " +AlwaysOnTop", isEdit ? "编辑步骤" : "添加步骤")
        d.SetFont("s9", "Segoe UI")
        d.AddText(, "类型")
        ddl := d.AddDropDownList("w200", ["按键", "等待", "点击"])
        kindMap := Map("key", 1, "sleep", 2, "click", 3)
        ddl.Choose(kindMap.Has(s.kind) ? kindMap[s.kind] : 1)

        d.AddText(, "按键（如 a / {Enter} / {Space} / ^c）")
        edKey := d.AddEdit("w200", s.key)
        btnCap := d.AddButton("w200", "捕捉按键")
        btnCap.OnEvent("Click", (*) => this._CaptureToEdit(edKey))

        d.AddText(, "延迟 ms")
        edDelay := d.AddEdit("w200 Number", s.delay)

        d.AddText(, "按住 ms（仅按键，0=单击）")
        edHold := d.AddEdit("w200 Number", s.hold)

        d.AddText(, "点击 X（屏幕坐标）")
        edX := d.AddEdit("w200 Number", s.x)
        d.AddText(, "点击 Y")
        edY := d.AddEdit("w200 Number", s.y)

        result := ""
        d.AddButton("w95 Default", "确定").OnEvent("Click", (*) => {
            step := this._BuildStepFromDialog(ddl, edKey, edDelay, edHold, edX, edY)
            if !step
                return
            result := step
            d.Destroy()
        })
        d.AddButton("x+10 w95", "取消").OnEvent("Click", (*) => (result := "", d.Destroy()))
        d.OnEvent("Close", (*) => (result := "", d.Destroy()))
        d.Show()
        WinWaitClose("ahk_id " d.Hwnd)
        return result
    }

    _BuildStepFromDialog(ddl, edKey, edDelay, edHold, edX, edY) {
        kind := ["key", "sleep", "click"][ddl.Value]
        delay := Integer(edDelay.Value || 50)
        if (kind = "sleep")
            return MacroConfig.NewStep("sleep", "", delay)
        if (kind = "click")
            return MacroConfig.NewStep("click", "", delay, 0, Integer(edX.Value || 0), Integer(edY.Value || 0))
        key := Trim(edKey.Value)
        if (key = "") {
            MsgBox("请填写按键。", "AutoKey", "Icon!")
            return ""
        }
        return MacroConfig.NewStep("key", key, delay, Integer(edHold.Value || 0))
    }

    ; ───────── 捕捉按键 / 取前台 ─────────

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
                if this.radSingle.Value {
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
            this._BindHotkeys(this.cfg)
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

    _PickForeground() {
        this._SetStatus("3 秒内切换到目标窗口…")
        Sleep 3000
        hwnd := WinExist("A")
        if !hwnd {
            this._SetStatus("未获取到窗口")
            return
        }
        try {
            this.edExe.Value := WinGetProcessName(hwnd)
            this.edTitle.Value := WinGetTitle(hwnd)
            this.edClass.Value := WinGetClass(hwnd)
            this._SetStatus("已填入: " this.edExe.Value)
        } catch as e {
            this._SetStatus("获取失败: " e.Message)
        }
    }

    ; ───────── 热键 / 运行 ─────────

    _BindHotkeys(cfg) {
        this._boundHotkeys := []
        try {
            Hotkey(cfg.startHotkey, (*) => this.Start(), "On")
            this._boundHotkeys.Push(cfg.startHotkey)
        } catch {
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

    _SetStatus(text) {
        try this.txtStatus.Value := text
        A_IconTip := "AutoKey — " text
    }

    Start() {
        if !this.seq {
            ; 尝试先应用
            this._ApplyFromUi(false)
        }
        if !this.seq {
            MsgBox("请先保存并应用配置。", "AutoKey", "Icon!")
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

    _OnClose() {
        try this._ApplyFromUi(false)
        this.gui.Hide()
    }

    _Quit() {
        try {
            if !(this.seq && this.seq.IsRunning)
                this._ApplyFromUi(false)
        }
        ExitApp()
    }
}
