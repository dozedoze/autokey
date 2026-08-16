#Requires AutoHotkey v2.0

/**
 * 按键序列执行器：定时器驱动，避免 ControlSend 阻塞导致停止按钮无响应。
 * 支持多实例并行（每个配置一套 Sequencer）。
 *
 * 真实鼠标点击通过全局门闩排队：多窗口可同时跑，点击会轮流执行，互不抢乱。
 */
class Sequencer {
    ; 全局鼠标门闩：同一时刻只允许一次真实点击（含激活窗口）
    static mouseBusy := false
    static mouseOwner := ""
    static mouseSince := 0
    ; 持锁过久视为泄漏（线程被掐断/异常），允许其它配置抢回，避免全体假死
    static mouseStaleMs := 5000

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
        this._hasExecutedStep := false
        this._tickFn := this._Tick.Bind(this)
    }

    IsRunning {
        get => this.running
    }
    IsPaused {
        get => this.paused
    }
    HasExecutedStep {
        get => this._hasExecutedStep
    }

    Start() {
        if this.running
            return
        this.running := true
        this.paused := false
        this._stopRequested := false
        this._hasExecutedStep := false
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
        ; 若正好持有鼠标锁，立刻释放，避免其它配置一直重试
        if (Sequencer.mouseBusy && Sequencer.mouseOwner = (this.cfg.HasOwnProp("id") ? this.cfg.id : ""))
            this._ReleaseMouse()
        try this.target.Release()
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
            ; 鼠标正被其它配置占用：不前进步骤，稍后再试同一点击
            ; （禁止在定时器里 Sleep 死等拿锁，否则多开时易占满 AHK 线程，
            ;  一次性 SetTimer 再也唤不醒，界面仍显示运行中但实际已停）
            if (waitMs < 0) {
                if !this._stopRequested && this.running
                    SetTimer(this._tickFn, -40)
                return
            }
            this._hasExecutedStep := true
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
                try this.target.Release()
                this._Notify("已完成")
                return
            }
            if (cfg.repeat > 0 && this._loopsDone >= cfg.repeat) {
                this.running := false
                try this.target.Release()
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

    /**
     * 执行一步，返回下一步前应等待的毫秒数。
     * 返回 -1 表示本步（点击）需重试，调用方不得前进 stepIndex。
     */
    _ExecStep(step, hwnd) {
        switch step.kind {
            case "sleep":
                return Integer(step.delay)
            case "click":
                button := MacroConfig.NormalizeButton(step.HasOwnProp("button") ? step.button : "Left")
                clicks := MacroConfig.NormalizeClicks(step.HasOwnProp("clicks") ? step.clicks : 1)
                gap := MacroConfig.NormalizeClickGap(step.HasOwnProp("clickGap") ? step.clickGap : 80)
                if !this._RealClick(hwnd, Integer(step.x), Integer(step.y), button, clicks, gap)
                    return -1
                return Integer(step.delay)
            default:
                this._SendKey(step.key, hwnd, step.hold)
                return Integer(step.delay)
        }
    }

    /**
     * 真实鼠标点击（对游戏更有效）。
     * 通过全局门闩排队，多套配置同时跑时轮流点各自窗口，不会两只“手”互抢乱点。
     * 点击期间屏蔽滚轮/中键，避免游戏把杂讯当成拉镜头。
     * @returns {Integer} 1=已点击 0=暂时拿不到鼠标（调用方应重试同一步）
     */
    _RealClick(hwnd, clientX, clientY, button := "Left", clicks := 1, clickGap := 80) {
        if !this._TryAcquireMouse()
            return 0
        wheelBlocked := false
        savedPos := false
        origX := 0
        origY := 0
        clicks := MacroConfig.NormalizeClicks(clicks)
        clickGap := MacroConfig.NormalizeClickGap(clickGap)
        try {
            point := Buffer(8, 0)
            NumPut("Int", clientX, point, 0)
            NumPut("Int", clientY, point, 4)
            if !DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", point)
                throw Error("无法换算目标窗口点击坐标")
            screenX := NumGet(point, 0, "Int")
            screenY := NumGet(point, 4, "Int")

            if !WinExist("ahk_id " hwnd)
                throw Error("目标窗口已关闭")

            this._BlockCameraNoise(true)
            wheelBlocked := true

            ; 记下点击前光标，点完立刻挪回去，减轻游戏把 MouseMove 当成转视角
            CoordMode "Mouse", "Screen"
            MouseGetPos(&origX, &origY)
            savedPos := true

            try {
                WinActivate("ahk_id " hwnd)
                WinWaitActive("ahk_id " hwnd, , 0.25)
            }
            ; 置前后再换算一次，避免边框/DPI 造成偏移
            NumPut("Int", clientX, point, 0)
            NumPut("Int", clientY, point, 4)
            if DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", point) {
                screenX := NumGet(point, 0, "Int")
                screenY := NumGet(point, 4, "Int")
            }

            ; 先挪到目标再点。部分 Win10/游戏会吃掉「零时长」Click，
            ; 所以用 mouse_event 显式按下→按住→抬起，比 AHK Click 更稳。
            DllCall("SetCursorPos", "Int", screenX, "Int", screenY)
            Sleep 30
            loop clicks {
                if this._stopRequested
                    break
                this._PhysicalMouseButton(button, true)
                this._SleepChunked(35)
                this._PhysicalMouseButton(button, false)
                if (A_Index < clicks && clickGap > 0)
                    this._SleepChunked(clickGap)
            }
            Sleep 15
            return 1
        } finally {
            if savedPos {
                DllCall("SetCursorPos", "Int", origX, "Int", origY)
                Sleep 10
            }
            ; 先解锁，避免关热键异常时门闩泄漏导致三开全体假死
            this._ReleaseMouse()
            if wheelBlocked
                this._BlockCameraNoise(false)
        }
    }

    /**
     * 底层鼠标按下/抬起。mousemove 能到但 Click 无反应时，
     * 常见原因是合成点击过短或被过滤；mouse_event 对这类环境更有效。
     */
    _PhysicalMouseButton(button := "Left", down := true) {
        ; MOUSEEVENTF_LEFTDOWN/UP = 0x0002/0x0004；RIGHT = 0x0008/0x0010
        if (button = "Right")
            flag := down ? 0x0008 : 0x0010
        else
            flag := down ? 0x0002 : 0x0004
        DllCall("mouse_event", "UInt", flag, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    }

    /**
     * 屏蔽滚轮与中键：游戏常把它们绑成缩放镜头；
     * 激活窗口 / 模拟点击时驱动或系统偶发会吐出滚轮消息。
     */
    _BlockCameraNoise(enable) {
        nop := Sequencer._Noop
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

    /**
     * 非阻塞抢鼠标锁。拿不到立刻返回 0，由定时器稍后重试，
     * 避免多套配置在 Sleep 里互相堵死占满线程。
     * @returns {Integer} 1=拿到锁 0=忙或已停止
     */
    _TryAcquireMouse() {
        if this._stopRequested || !this.running
            return 0
        owner := this.cfg.HasOwnProp("id") ? this.cfg.id : ""
        Critical "On"
        if !Sequencer.mouseBusy {
            Sequencer.mouseBusy := true
            Sequencer.mouseOwner := owner
            Sequencer.mouseSince := A_TickCount
            Critical "Off"
            return 1
        }
        ; 持锁超时：视为泄漏，抢回以免全体卡在「运行中」
        held := A_TickCount - Sequencer.mouseSince
        if (Sequencer.mouseSince > 0 && held >= Sequencer.mouseStaleMs) {
            Sequencer.mouseBusy := true
            Sequencer.mouseOwner := owner
            Sequencer.mouseSince := A_TickCount
            Critical "Off"
            return 1
        }
        Critical "Off"
        return 0
    }

    _ReleaseMouse() {
        Critical "On"
        Sequencer.mouseBusy := false
        Sequencer.mouseOwner := ""
        Sequencer.mouseSince := 0
        Critical "Off"
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
