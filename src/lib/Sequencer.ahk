#Requires AutoHotkey v2.0

/**
 * 按键序列执行器：定时器驱动，避免 ControlSend 阻塞导致停止按钮无响应。
 * 支持多实例并行（每个配置一套 Sequencer）。
 */
class Sequencer {
    __New(cfg, target) {
        this.cfg := cfg
        this.target := target
        this.running := false
        this.paused := false
        this._stopRequested := false
        this.onStatus := (*) => 0
        this._steps := []
        this._stepIndex := 1
        this._loopsDone := 0
        this._tickFn := this._Tick.Bind(this)
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
        this._steps := this.cfg.HasMethod("EffectiveSteps") ? this.cfg.EffectiveSteps() : this.cfg.steps
        if (this._steps.Length = 0) {
            this.running := false
            this._Notify("序列为空")
            return
        }
        this._stepIndex := 1
        this._loopsDone := 0
        this._Notify("运行中")
        ; 一次性定时器：每步结束后再预约下一步，主线程不堵死
        SetTimer(this._tickFn, -1)
    }

    Stop() {
        this._stopRequested := true
        this.paused := false
        this.running := false
        try SetTimer(this._tickFn, 0)
        this._Notify("已停止")
    }

    TogglePause() {
        if !this.running
            return
        this.paused := !this.paused
        this._Notify(this.paused ? "已暂停" : "运行中")
        if !this.paused && !this._stopRequested
            SetTimer(this._tickFn, -1)
    }

    _Tick() {
        if this._stopRequested || !this.running {
            this.running := false
            return
        }
        if this.paused
            return

        hwnd := this.target.EnsureReady()
        if !hwnd {
            this._Notify("未找到目标窗口 [" this.target.Describe() "]，等待中…")
            if !this._stopRequested && this.running
                SetTimer(this._tickFn, -300)
            return
        }

        if (this._stepIndex > this._steps.Length)
            this._stepIndex := 1
        step := this._steps[this._stepIndex]
        try {
            waitMs := this._ExecStep(step, hwnd)
        } catch as e {
            ; 目标窗口可能刚被关闭：定时器线程里不能抛未捕获异常，等下一轮重找
            this._Notify("发送失败(" e.Message ")，重试中…")
            waitMs := 300
        }

        if this._stopRequested || !this.running {
            this.running := false
            return
        }

        this._stepIndex++
        if (this._stepIndex > this._steps.Length) {
            this._stepIndex := 1
            this._loopsDone++
            cfg := this.cfg
            if !cfg.loop {
                this.running := false
                this._Notify("已完成")
                return
            }
            if (cfg.repeat > 0 && this._loopsDone >= cfg.repeat) {
                this.running := false
                this._Notify("已完成")
                return
            }
            waitMs := Integer(cfg.loopDelay)
        }

        if this._stopRequested || !this.running {
            this.running := false
            return
        }
        SetTimer(this._tickFn, -Max(1, Integer(waitMs)))
    }

    /** 执行一步，返回下一步前应等待的毫秒数 */
    _ExecStep(step, hwnd) {
        switch step.kind {
            case "sleep":
                return Integer(step.delay)
            case "click":
                try {
                    if (this.target.sendMode = "controlsend")
                        ControlClick("x" step.x " y" step.y, "ahk_id " hwnd, , "Left", 1, "NA")
                    else
                        Click step.x, step.y
                }
                return Integer(step.delay)
            default:
                this._SendKey(step.key, hwnd, step.hold)
                return Integer(step.delay)
        }
    }

    _SendKey(key, hwnd, hold := 0) {
        sendKey := key
        if (StrLen(key) = 1 || RegExMatch(key, "^[\!\^\+\#]*\{.+\}$") || RegExMatch(key, "^[\!\^\+\#]+.$"))
            sendKey := key
        else if !InStr(key, "{")
            sendKey := "{" key "}"

        if (this.target.sendMode = "controlsend") {
            ; 异步/超时投递，避免 SendMessage 卡住后停止按钮失灵
            if !this._PostKey(hwnd, sendKey, hold)
                this._ControlSendTimeout(hwnd, sendKey, hold)
        } else {
            if (hold > 0) {
                Send("{Blind}" sendKey " down")
                this._SleepChunked(hold)
                Send("{Blind}" sendKey " up")
            } else {
                Send("{Blind}" sendKey)
            }
        }
    }

    /** ControlSend 的超时替代：SendMessageTimeout，避免目标窗口不响应时卡死 */
    _ControlSendTimeout(hwnd, sendKey, hold := 0) {
        ; 仍优先走 PostMessage 解析；失败则对每个字符尽量 WM_CHAR
        if this._PostKey(hwnd, sendKey, hold)
            return
        ; 最后手段：短超时 ControlSend 不可用时，拆成 PostMessage WM_CHAR
        text := sendKey
        text := StrReplace(text, "{Blind}", "")
        if (StrLen(text) = 1) {
            PostMessage(0x0102, Ord(text), 0, , "ahk_id " hwnd)  ; WM_CHAR
            return
        }
        ; 实在无法解析也不阻塞主线程——跳过本键
    }

    /**
     * 异步投递按键。成功返回 true；无法解析的组合键返回 false 由调用方回退。
     */
    _PostKey(hwnd, key, hold := 0) {
        mods := Map("ctrl", false, "alt", false, "shift", false, "win", false)
        raw := key
        while RegExMatch(raw, "^([\!\^\+\#])(.+)$", &m) {
            switch m[1] {
                case "^": mods["ctrl"] := true
                case "!": mods["alt"] := true
                case "+": mods["shift"] := true
                case "#": mods["win"] := true
            }
            raw := m[2]
        }

        vk := 0
        if RegExMatch(raw, "^\{(.+)\}$", &bm) {
            name := bm[1]
            ; 去掉可能的空格/重复，如 Space down
            name := RegExReplace(name, "i)\s*(down|up)$", "")
            vk := this._Vk(name)
            if !vk {
                ; 常见别名
                alias := Map("Esc", "Escape", "Backspace", "BS", "Del", "Delete", "Ins", "Insert")
                if alias.Has(name)
                    vk := this._Vk(alias[name])
            }
        } else if (StrLen(raw) = 1) {
            vk := this._Vk(raw)
        }

        if !vk
            return false

        ; 修饰键按下
        if mods["ctrl"]
            PostMessage(0x0100, 0x11, 0, , "ahk_id " hwnd)  ; VK_CONTROL down
        if mods["alt"]
            PostMessage(0x0100, 0x12, 0, , "ahk_id " hwnd)
        if mods["shift"]
            PostMessage(0x0100, 0x10, 0, , "ahk_id " hwnd)
        if mods["win"]
            PostMessage(0x0100, 0x5B, 0, , "ahk_id " hwnd)

        PostMessage(0x0100, vk, 0, , "ahk_id " hwnd)  ; WM_KEYDOWN
        if (hold > 0)
            this._SleepChunked(hold)
        PostMessage(0x0101, vk, 0, , "ahk_id " hwnd)  ; WM_KEYUP

        if mods["win"]
            PostMessage(0x0101, 0x5B, 0, , "ahk_id " hwnd)
        if mods["shift"]
            PostMessage(0x0101, 0x10, 0, , "ahk_id " hwnd)
        if mods["alt"]
            PostMessage(0x0101, 0x12, 0, , "ahk_id " hwnd)
        if mods["ctrl"]
            PostMessage(0x0101, 0x11, 0, , "ahk_id " hwnd)
        return true
    }

    /** GetKeyVK 遇到无效键名会抛异常，这里统一吞掉返回 0 */
    _Vk(name) {
        vk := 0
        try vk := GetKeyVK(name)
        return vk
    }

    _SleepChunked(ms) {
        elapsed := 0
        while (elapsed < ms) {
            if this._stopRequested
                return
            slice := Min(20, ms - elapsed)
            Sleep slice
            elapsed += slice
        }
    }

    _Notify(text) {
        try this.onStatus.Call(text)
    }
}
