#Requires AutoHotkey v2.0

/**
 * 从 INI 加载宏配置。
 */
class MacroConfig {
    __New(path) {
        if !FileExist(path)
            throw Error("配置文件不存在: " path)

        this.path := path
        this.name := IniRead(path, "Macro", "Name", "未命名宏")
        this.loop := Integer(IniRead(path, "Macro", "Loop", "1"))
        this.loopDelay := Integer(IniRead(path, "Macro", "LoopDelay", "200"))
        this.repeat := Integer(IniRead(path, "Macro", "Repeat", "0"))
        this.startHotkey := IniRead(path, "Hotkeys", "Start", "F6")
        this.stopHotkey := IniRead(path, "Hotkeys", "Stop", "F7")
        this.pauseHotkey := IniRead(path, "Hotkeys", "Pause", "F8")

        this.targetExe := IniRead(path, "Target", "Exe", "")
        this.targetTitle := IniRead(path, "Target", "Title", "")
        this.targetClass := IniRead(path, "Target", "Class", "")
        this.activate := Integer(IniRead(path, "Target", "Activate", "1"))
        this.sendMode := IniRead(path, "Target", "SendMode", "Send")

        this.steps := []
        section := IniRead(path, "Sequence")
        if (section = "ERROR" || section = "")
            throw Error("配置缺少 [Sequence] 段落: " path)

        for line in StrSplit(section, "`n", "`r") {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 1) = ";")
                continue
            eq := InStr(line, "=")
            if !eq
                continue
            key := Trim(SubStr(line, 1, eq - 1))
            val := Trim(SubStr(line, eq + 1))
            if !IsInteger(key)
                continue
            this.steps.Push(this._ParseStep(Integer(key), val))
        }

        this._SortByIndex()
        if (this.steps.Length = 0)
            throw Error("序列为空，请在 [Sequence] 中至少写一步: " path)
    }

    /**
     * 步骤格式：
     *   key|delayMs
     *   key|delayMs|holdMs
     *   click|x|y|delayMs
     *   sleep|ms
     */
    _ParseStep(index, raw) {
        parts := StrSplit(Trim(raw), "|")
        kind := StrLower(parts[1])
        step := { index: index, kind: "key", key: "", delay: 50, hold: 0, x: 0, y: 0 }

        if (kind = "sleep") {
            step.kind := "sleep"
            step.delay := Integer(parts.Length >= 2 ? parts[2] : 100)
            return step
        }
        if (kind = "click") {
            step.kind := "click"
            step.x := Integer(parts.Length >= 2 ? parts[2] : 0)
            step.y := Integer(parts.Length >= 3 ? parts[3] : 0)
            step.delay := Integer(parts.Length >= 4 ? parts[4] : 50)
            return step
        }

        step.key := parts[1]
        step.delay := Integer(parts.Length >= 2 ? parts[2] : 50)
        step.hold := Integer(parts.Length >= 3 ? parts[3] : 0)
        return step
    }

    _SortByIndex() {
        n := this.steps.Length
        loop n - 1 {
            swapped := false
            loop n - A_Index {
                j := A_Index
                if (this.steps[j].index > this.steps[j + 1].index) {
                    tmp := this.steps[j]
                    this.steps[j] := this.steps[j + 1]
                    this.steps[j + 1] := tmp
                    swapped := true
                }
            }
            if !swapped
                break
        }
    }

    static ResolvePath(nameOrPath) {
        if FileExist(nameOrPath)
            return nameOrPath

        candidates := [
            A_ScriptDir "\configs\" nameOrPath,
            A_ScriptDir "\..\configs\" nameOrPath,
            A_WorkingDir "\configs\" nameOrPath,
            A_ScriptDir "\configs\" nameOrPath ".ini",
            A_ScriptDir "\..\configs\" nameOrPath ".ini",
            nameOrPath ".ini"
        ]
        for p in candidates {
            if FileExist(p)
                return p
        }
        throw Error("找不到配置: " nameOrPath)
    }
}
