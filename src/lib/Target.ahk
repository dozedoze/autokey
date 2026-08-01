#Requires AutoHotkey v2.0

/**
 * 按 exe / 标题 / 类名 / 窗口序号 / 窗口句柄定位目标窗口。
 *
 * 同一客户端多开时，只靠 exe（甚至标题）根本区分不出是哪一个，
 * 所以这里提供三层定位：锁定句柄 > 窗口序号 > 自动挑一个没被占用的。
 */
class WindowTarget {
    ; hwnd -> 占用它的配置 id。多套配置同时跑时用来避免全打到同一个窗口
    static reserved := Map()

    __New(cfg, ownerId := "") {
        this.exe := cfg.targetExe
        this.title := cfg.targetTitle
        this.winClass := cfg.targetClass
        this.activate := cfg.activate
        this.sendMode := StrLower(cfg.sendMode)
        this.lockHwnd := Integer(cfg.HasOwnProp("targetHwnd") ? cfg.targetHwnd : 0)
        this.index := Integer(cfg.HasOwnProp("targetIndex") ? cfg.targetIndex : 0)
        this.owner := ownerId != "" ? ownerId : cfg.id
        this.resolved := 0
    }

    /** @returns {Integer} 窗口 HWND，找不到返回 0 */
    Find() {
        ; 1) 锁定了具体窗口，且它还活着 —— 多开场景下这是唯一可靠的方式
        if (this.lockHwnd && this._Alive(this.lockHwnd)) {
            this._Claim(this.lockHwnd)
            return this.lockHwnd
        }

        ; 什么都没填 = 跟随当前前台窗口
        if (this.exe = "" && this.title = "" && this.winClass = "")
            return WinExist("A")

        list := this.Candidates()
        if (list.Length = 0) {
            this.Release()
            return 0
        }

        ; 2) 指定了第几个窗口
        if (this.index > 0) {
            if (this.index > list.Length) {
                this.Release()
                return 0
            }
            this._Claim(list[this.index])
            return list[this.index]
        }

        ; 3) 自动挑一个还没被别的配置占用的
        for hwnd in list {
            if !this._TakenByOther(hwnd) {
                this._Claim(hwnd)
                return hwnd
            }
        }
        this._Claim(list[1])
        return list[1]
    }

    /**
     * 符合条件的候选窗口，按 hwnd 升序。
     * 不能用 WinGetList 的原始顺序——那是 Z 序，你切一下窗口目标就变了。
     * @returns {Array}
     */
    Candidates() {
        out := []
        wantExe := StrLower(this.exe)
        for hwnd in WinGetList() {
            try {
                if (wantExe != "" && StrLower(WinGetProcessName(hwnd)) != wantExe)
                    continue
                if (this.title != "" && !InStr(WinGetTitle(hwnd), this.title))
                    continue
                if (this.winClass != "" && WinGetClass(hwnd) != this.winClass)
                    continue
                ; 无标题的多半是隐形/工具窗口，发过去没用
                if (WinGetTitle(hwnd) = "")
                    continue
                out.Push(hwnd + 0)
            } catch {
                continue
            }
        }
        return WindowTarget.SortAsc(out)
    }

    EnsureReady() {
        hwnd := this.Find()
        if !hwnd
            return 0
        if this.activate {
            try {
                WinActivate("ahk_id " hwnd)
                WinWaitActive("ahk_id " hwnd, , 1)
            }
        }
        return hwnd
    }

    /** 停止时释放占用，让别的配置能用这个窗口 */
    Release() {
        if !this.resolved
            return
        if (WindowTarget.reserved.Has(this.resolved) && WindowTarget.reserved[this.resolved] = this.owner)
            WindowTarget.reserved.Delete(this.resolved)
        this.resolved := 0
    }

    Describe() {
        parts := []
        if (this.lockHwnd)
            parts.Push("锁定窗口 " this.lockHwnd)
        if (this.exe != "")
            parts.Push("exe=" this.exe)
        if (this.title != "")
            parts.Push("title~=" this.title)
        if (this.winClass != "")
            parts.Push("class=" this.winClass)
        if (this.index > 0)
            parts.Push("第 " this.index " 个窗口")
        if (parts.Length = 0)
            return "当前前台窗口"
        out := ""
        for i, v in parts
            out .= (i = 1 ? "" : ", ") v
        return out
    }

    _Alive(hwnd) {
        try {
            if !WinExist("ahk_id " hwnd)
                return false
            ; 句柄可能被系统回收后复用，校验一下进程还是不是原来那个
            if (this.exe != "" && StrLower(WinGetProcessName("ahk_id " hwnd)) != StrLower(this.exe))
                return false
            return true
        }
        return false
    }

    _Claim(hwnd) {
        if (this.resolved && this.resolved != hwnd)
            this.Release()
        this.resolved := hwnd
        WindowTarget.reserved[hwnd] := this.owner
    }

    _TakenByOther(hwnd) {
        return WindowTarget.reserved.Has(hwnd) && WindowTarget.reserved[hwnd] != this.owner
    }

    /** 列出可选窗口（供界面挑选），顺序与 Candidates 的序号一致 */
    static ListWindows(exe := "") {
        hwnds := []
        want := StrLower(exe)
        for hwnd in WinGetList() {
            try {
                if (WinGetTitle(hwnd) = "")
                    continue
                if (want != "" && StrLower(WinGetProcessName(hwnd)) != want)
                    continue
                hwnds.Push(hwnd + 0)
            } catch {
                continue
            }
        }
        WindowTarget.SortAsc(hwnds)
        out := []
        for h in hwnds {
            try {
                out.Push({
                    hwnd: h,
                    title: WinGetTitle("ahk_id " h),
                    exe: WinGetProcessName("ahk_id " h),
                    cls: WinGetClass("ahk_id " h)
                })
            }
        }
        return out
    }

    static SortAsc(arr) {
        if (arr.Length < 2)
            return arr
        loop arr.Length - 1 {
            i := A_Index + 1
            v := arr[i]
            j := i - 1
            while (j >= 1 && arr[j] > v) {
                arr[j + 1] := arr[j]
                j--
            }
            arr[j + 1] := v
        }
        return arr
    }
}
