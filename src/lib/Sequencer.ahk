#Requires AutoHotkey v2.0

/**
 * 按键序列执行器：支持循环、暂停、停止，以及 Send / ControlSend。
 */
class Sequencer {
    __New(cfg, target) {
        this.cfg := cfg
        this.target := target
        this.running := false
        this.paused := false
        this._stopRequested := false
        this.onStatus := (*) => 0  ; 回调 (text)
    }

    IsRunning {
        get => this.running
    }
    IsPaused {
        get => this.paused
    }

    Start() {
        if this.running
            return
        this.running := true
        this.paused := false
        this._stopRequested := false
        this._Notify("运行中")
        SetTimer(() => this._Run(), -1)
    }

    Stop() {
        this._stopRequested := true
        this.paused := false
        this.running := false
        this._Notify("已停止")
    }

    TogglePause() {
        if !this.running
            return
        this.paused := !this.paused
        this._Notify(this.paused ? "已暂停" : "运行中")
    }

    _Run() {
        cfg := this.cfg
        loopsDone := 0
        try {
            loop {
                if this._stopRequested
                    break

                hwnd := this.target.EnsureReady()
                if !hwnd {
                    this._Notify("未找到目标窗口 [" this.target.Describe() "]，等待中…")
                    Sleep 500
                    if this._stopRequested
                        break
                    continue
                }

                steps := cfg.HasMethod("EffectiveSteps") ? cfg.EffectiveSteps() : cfg.steps
                for step in steps {
                    if this._stopRequested
                        break 2
                    while this.paused {
                        if this._stopRequested
                            break 3
                        Sleep 50
                    }
                    this._ExecStep(step, hwnd)
                }

                loopsDone++
                if !cfg.loop
                    break
                if (cfg.repeat > 0 && loopsDone >= cfg.repeat)
                    break

                delay := cfg.loopDelay
                elapsed := 0
                while (elapsed < delay) {
                    if this._stopRequested
                        break 2
                    while this.paused {
                        if this._stopRequested
                            break 3
                        Sleep 50
                    }
                    Sleep 20
                    elapsed += 20
                }
            }
        } catch as e {
            this._Notify("错误: " e.Message)
        }
        this.running := false
        this.paused := false
        if !this._stopRequested
            this._Notify("已完成")
    }

    _ExecStep(step, hwnd) {
        switch step.kind {
            case "sleep":
                Sleep step.delay
            case "click":
                if (this.target.sendMode = "controlsend") {
                    ; 后台点击不一定可靠，尽量用 ControlClick
                    try ControlClick("x" step.x " y" step.y, "ahk_id " hwnd)
                    catch
                        Click step.x, step.y
                } else {
                    Click step.x, step.y
                }
                Sleep step.delay
            default:
                this._SendKey(step.key, hwnd, step.hold)
                Sleep step.delay
        }
    }

    _SendKey(key, hwnd, hold := 0) {
        ; 规范化：单字母可直接发；功能键建议写成 {Enter} 形式
        sendKey := key
        if (StrLen(key) = 1 || RegExMatch(key, "^[\!\^\+\\#]*\{.+\}$") || RegExMatch(key, "^[\!\^\+\\#]+.$"))
            sendKey := key
        else if !InStr(key, "{")
            sendKey := "{" key "}"

        if (this.target.sendMode = "controlsend") {
            if (hold > 0) {
                ControlSend("{Blind}" sendKey " down", , "ahk_id " hwnd)
                Sleep hold
                ControlSend("{Blind}" sendKey " up", , "ahk_id " hwnd)
            } else {
                ControlSend("{Blind}" sendKey, , "ahk_id " hwnd)
            }
        } else {
            if (hold > 0) {
                Send("{Blind}" sendKey " down")
                Sleep hold
                Send("{Blind}" sendKey " up")
            } else {
                Send("{Blind}" sendKey)
            }
        }
    }

    _Notify(text) {
        try this.onStatus.Call(text)
    }
}
