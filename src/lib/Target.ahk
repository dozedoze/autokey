#Requires AutoHotkey v2.0

/**
 * 按 exe / 标题 / 类名定位目标窗口。
 */
class WindowTarget {
    __New(cfg) {
        this.exe := cfg.targetExe
        this.title := cfg.targetTitle
        this.winClass := cfg.targetClass
        this.activate := cfg.activate
        this.sendMode := StrLower(cfg.sendMode)
    }

    /** @returns {Integer} 窗口 HWND，找不到返回 0 */
    Find() {
        if (this.exe != "") {
            wantExe := StrLower(this.exe)
            ; 有标题的窗口优先，避免命中同进程的隐形/工具窗口
            best := 0
            for hwnd in WinGetList() {
                try {
                    if (StrLower(WinGetProcessName(hwnd)) != wantExe)
                        continue
                    if (this.title != "" && !InStr(WinGetTitle(hwnd), this.title))
                        continue
                    if (this.winClass != "" && WinGetClass(hwnd) != this.winClass)
                        continue
                    if (WinGetTitle(hwnd) != "")
                        return hwnd
                    if !best
                        best := hwnd
                } catch {
                    continue
                }
            }
            return best
        }

        criteria := ""
        if (this.title != "")
            criteria .= this.title
        if (this.winClass != "")
            criteria .= " ahk_class " this.winClass

        if (criteria = "")
            return WinExist("A")

        hwnd := WinExist(criteria)
        return hwnd ? hwnd : 0
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

    Describe() {
        parts := []
        if (this.exe != "")
            parts.Push("exe=" this.exe)
        if (this.title != "")
            parts.Push("title~=" this.title)
        if (this.winClass != "")
            parts.Push("class=" this.winClass)
        if (parts.Length = 0)
            return "当前前台窗口"
        out := ""
        for i, v in parts
            out .= (i = 1 ? "" : ", ") v
        return out
    }
}
