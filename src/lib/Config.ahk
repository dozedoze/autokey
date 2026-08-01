#Requires AutoHotkey v2.0

/**
 * 单套宏配置（内存对象）。由 UI 编辑，自动写入 data\macros.ini。
 */
class MacroConfig {
    __New(opt := unset) {
        this.id := ""
        this.name := "新配置"
        this.mode := "single"          ; single(连发) | sequence(序列)
        this.singleKey := "{Space}"    ; 兼容旧字段；以 keys 为准
        this.singleInterval := 50
        this.keys := []                ; 连发键位 [{key, interval}]
        this.loop := 1
        this.loopDelay := 200
        this.repeat := 0
        this.startHotkey := "F6"
        this.stopHotkey := "F7"
        this.pauseHotkey := "F8"
        this.targetExe := ""
        this.targetTitle := ""
        this.targetClass := ""
        this.activate := 1
        this.sendMode := "Send"
        this.steps := []

        if IsSet(opt) && opt is Map {
            for k, v in opt
                this.%k% := v
        }
        this.EnsureKeys()
    }

    /** 保证 keys 至少有一项（从旧 singleKey 迁移） */
    EnsureKeys() {
        if (this.keys.Length > 0)
            return
        key := this.singleKey != "" ? this.singleKey : "{Space}"
        interval := Integer(this.singleInterval > 0 ? this.singleInterval : 50)
        this.keys.Push(MacroConfig.NewKey(key, interval))
    }

    /** 把 keys 同步回旧字段（便于兼容） */
    SyncLegacySingle() {
        this.EnsureKeys()
        this.singleKey := this.keys[1].key
        this.singleInterval := Integer(this.keys[1].interval)
    }

    /** 运行时实际步骤 */
    EffectiveSteps() {
        if (this.mode = "single") {
            this.EnsureKeys()
            out := []
            for i, k in this.keys {
                out.Push({
                    index: i,
                    kind: "key",
                    key: k.key,
                    delay: Integer(k.interval),
                    hold: 0,
                    x: 0,
                    y: 0
                })
            }
            return out
        }
        out := []
        for i, s in this.steps {
            out.Push({
                index: i,
                kind: s.kind,
                key: s.HasOwnProp("key") ? s.key : "",
                delay: Integer(s.HasOwnProp("delay") ? s.delay : 50),
                hold: Integer(s.HasOwnProp("hold") ? s.hold : 0),
                x: Integer(s.HasOwnProp("x") ? s.x : 0),
                y: Integer(s.HasOwnProp("y") ? s.y : 0)
            })
        }
        return out
    }

    Clone() {
        c := MacroConfig()
        for prop in [
            "id", "name", "mode", "singleKey", "singleInterval",
            "loop", "loopDelay", "repeat",
            "startHotkey", "stopHotkey", "pauseHotkey",
            "targetExe", "targetTitle", "targetClass",
            "activate", "sendMode"
        ]
            c.%prop% := this.%prop%
        c.keys := []
        for k in this.keys
            c.keys.Push(MacroConfig.CloneKey(k))
        c.steps := []
        for s in this.steps
            c.steps.Push(MacroConfig.CloneStep(s))
        return c
    }

    static NewKey(key := "{Space}", interval := 50) {
        return { key: key, interval: Integer(interval) }
    }

    static CloneKey(k) {
        return MacroConfig.NewKey(
            k.HasOwnProp("key") ? k.key : "{Space}",
            k.HasOwnProp("interval") ? k.interval : 50
        )
    }

    static CloneStep(s) {
        return {
            kind: s.kind,
            key: s.HasOwnProp("key") ? s.key : "",
            delay: s.HasOwnProp("delay") ? s.delay : 50,
            hold: s.HasOwnProp("hold") ? s.hold : 0,
            x: s.HasOwnProp("x") ? s.x : 0,
            y: s.HasOwnProp("y") ? s.y : 0
        }
    }

    static NewStep(kind := "key", key := "a", delay := 100, hold := 0, x := 0, y := 0) {
        return { kind: kind, key: key, delay: delay, hold: hold, x: x, y: y }
    }

    /**
     * 兼容旧版 INI 单文件加载（CLI / 迁移）。
     */
    static FromIniFile(path) {
        if !FileExist(path)
            throw Error("配置文件不存在: " path)

        cfg := MacroConfig()
        cfg.id := "imported_" A_TickCount
        cfg.name := IniRead(path, "Macro", "Name", "未命名宏")
        cfg.mode := "sequence"
        cfg.loop := Integer(IniRead(path, "Macro", "Loop", "1"))
        cfg.loopDelay := Integer(IniRead(path, "Macro", "LoopDelay", "200"))
        cfg.repeat := Integer(IniRead(path, "Macro", "Repeat", "0"))
        cfg.startHotkey := IniRead(path, "Hotkeys", "Start", "F6")
        cfg.stopHotkey := IniRead(path, "Hotkeys", "Stop", "F7")
        cfg.pauseHotkey := IniRead(path, "Hotkeys", "Pause", "F8")
        cfg.targetExe := IniRead(path, "Target", "Exe", "")
        cfg.targetTitle := IniRead(path, "Target", "Title", "")
        cfg.targetClass := IniRead(path, "Target", "Class", "")
        cfg.activate := Integer(IniRead(path, "Target", "Activate", "1"))
        cfg.sendMode := IniRead(path, "Target", "SendMode", "Send")

        section := IniRead(path, "Sequence")
        if (section = "ERROR" || section = "")
            throw Error("配置缺少 [Sequence] 段落: " path)

        rawSteps := []
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
            rawSteps.Push({ index: Integer(key), step: MacroConfig._ParseStepValue(val) })
        }
        ; 按 index 排序
        n := rawSteps.Length
        loop n - 1 {
            swapped := false
            loop n - A_Index {
                j := A_Index
                if (rawSteps[j].index > rawSteps[j + 1].index) {
                    tmp := rawSteps[j]
                    rawSteps[j] := rawSteps[j + 1]
                    rawSteps[j + 1] := tmp
                    swapped := true
                }
            }
            if !swapped
                break
        }
        for item in rawSteps
            cfg.steps.Push(item.step)

        if (cfg.steps.Length = 0)
            throw Error("序列为空: " path)

        ; 仅一步按键 → 识别为连发模式
        if (cfg.steps.Length = 1 && cfg.steps[1].kind = "key") {
            cfg.mode := "single"
            cfg.keys := [MacroConfig.NewKey(cfg.steps[1].key, cfg.steps[1].delay)]
            cfg.SyncLegacySingle()
        } else if (cfg.steps.Length > 0) {
            ; 多步全是按键也可导入为连发键位
            allKeys := true
            for s in cfg.steps {
                if (s.kind != "key") {
                    allKeys := false
                    break
                }
            }
            if allKeys {
                cfg.mode := "single"
                cfg.keys := []
                for s in cfg.steps
                    cfg.keys.Push(MacroConfig.NewKey(s.key, s.delay))
                cfg.SyncLegacySingle()
            }
        }
        cfg.EnsureKeys()
        return cfg
    }

    static _ParseStepValue(raw) {
        parts := StrSplit(Trim(raw), "|")
        kind := StrLower(parts[1])
        if (kind = "sleep")
            return MacroConfig.NewStep("sleep", "", Integer(parts.Length >= 2 ? parts[2] : 100))
        if (kind = "click")
            return MacroConfig.NewStep(
                "click", "",
                Integer(parts.Length >= 4 ? parts[4] : 50), 0,
                Integer(parts.Length >= 2 ? parts[2] : 0),
                Integer(parts.Length >= 3 ? parts[3] : 0)
            )
        return MacroConfig.NewStep(
            "key", parts[1],
            Integer(parts.Length >= 2 ? parts[2] : 50),
            Integer(parts.Length >= 3 ? parts[3] : 0)
        )
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

/**
 * 多套宏配置仓库：自动读写 data\macros.ini，用户无需手改。
 */
class MacroStore {
    __New() {
        this.path := this._DataPath()
        this.macros := []      ; MacroConfig[]
        this.activeId := ""
        this._Load()
        if (this.macros.Length = 0)
            this._SeedDefaults()
        if (this.activeId = "" || !this.GetById(this.activeId))
            this.activeId := this.macros[1].id
    }

    _DataDir() {
        if this.HasProp("_dataDir")
            return this._dataDir

        ; 优先用 exe/脚本同级目录，便携；不可写时退回用户目录
        candidates := [A_ScriptDir "\data", A_ScriptDir "\..\data"]
        for d in candidates {
            if (DirExist(d) && this._IsWritable(d)) {
                this._dataDir := d
                return d
            }
        }
        for d in candidates {
            try {
                DirCreate(d)
                if this._IsWritable(d) {
                    this._dataDir := d
                    return d
                }
            }
        }

        fallback := A_AppData "\AutoKey"
        try DirCreate(fallback)
        this._dataDir := fallback
        return fallback
    }

    _IsWritable(dir) {
        probe := dir "\.write_test"
        try {
            FileAppend("", probe)
            FileDelete(probe)
            return true
        }
        return false
    }

    _DataPath() {
        return this._DataDir() "\macros.ini"
    }

    Active() {
        m := this.GetById(this.activeId)
        return m ? m : this.macros[1]
    }

    GetById(id) {
        for m in this.macros {
            if (m.id = id)
                return m
        }
        return ""
    }

    IndexOf(id) {
        for i, m in this.macros {
            if (m.id = id)
                return i
        }
        return 0
    }

    Add(cfg := unset) {
        if !IsSet(cfg)
            cfg := this._DefaultSingle()
        if (cfg.id = "")
            cfg.id := this._NewId()
        this.macros.Push(cfg)
        this.activeId := cfg.id
        this.Save()
        return cfg
    }

    Remove(id) {
        idx := this.IndexOf(id)
        if !idx
            return false
        if (this.macros.Length <= 1)
            return false
        this.macros.RemoveAt(idx)
        if (this.activeId = id)
            this.activeId := this.macros[Min(idx, this.macros.Length)].id
        this.Save()
        return true
    }

    SetActive(id) {
        if !this.GetById(id)
            return false
        this.activeId := id
        this.Save()
        return true
    }

    ReplaceActive(cfg) {
        idx := this.IndexOf(this.activeId)
        if !idx
            return
        cfg.id := this.activeId
        this.macros[idx] := cfg
        this.Save()
    }

    Save() {
        path := this.path
        dir := this._DataDir()
        if !DirExist(dir)
            DirCreate(dir)
        if FileExist(path)
            FileDelete(path)

        IniWrite(this.activeId, path, "App", "ActiveId")
        ids := ""
        for i, m in this.macros {
            ids .= (i = 1 ? "" : "|") m.id
            sec := "M_" m.id
            IniWrite(m.name, path, sec, "Name")
            IniWrite(m.mode, path, sec, "Mode")
            m.EnsureKeys()
            m.SyncLegacySingle()
            IniWrite(m.singleKey, path, sec, "SingleKey")
            IniWrite(m.singleInterval, path, sec, "SingleInterval")
            IniWrite(m.keys.Length, path, sec, "KeyCount")
            for ki, k in m.keys
                IniWrite(k.key "|" Integer(k.interval), path, sec, "Key" ki)
            IniWrite(m.loop, path, sec, "Loop")
            IniWrite(m.loopDelay, path, sec, "LoopDelay")
            IniWrite(m.repeat, path, sec, "Repeat")
            IniWrite(m.startHotkey, path, sec, "StartHotkey")
            IniWrite(m.stopHotkey, path, sec, "StopHotkey")
            IniWrite(m.pauseHotkey, path, sec, "PauseHotkey")
            IniWrite(m.targetExe, path, sec, "TargetExe")
            IniWrite(m.targetTitle, path, sec, "TargetTitle")
            IniWrite(m.targetClass, path, sec, "TargetClass")
            IniWrite(m.activate, path, sec, "Activate")
            IniWrite(m.sendMode, path, sec, "SendMode")
            IniWrite(m.steps.Length, path, sec, "StepCount")
            for si, s in m.steps {
                ; kind|key|delay|hold|x|y
                line := s.kind "|" (s.HasOwnProp("key") ? s.key : "") "|"
                    . Integer(s.HasOwnProp("delay") ? s.delay : 50) "|"
                    . Integer(s.HasOwnProp("hold") ? s.hold : 0) "|"
                    . Integer(s.HasOwnProp("x") ? s.x : 0) "|"
                    . Integer(s.HasOwnProp("y") ? s.y : 0)
                IniWrite(line, path, sec, "Step" si)
            }
        }
        IniWrite(ids, path, "App", "Ids")
    }

    _Load() {
        path := this.path
        this.macros := []
        this.activeId := ""
        if !FileExist(path)
            return

        this.activeId := IniRead(path, "App", "ActiveId", "")
        idsRaw := IniRead(path, "App", "Ids", "")
        if (idsRaw = "" || idsRaw = "ERROR")
            return

        for id in StrSplit(idsRaw, "|") {
            id := Trim(id)
            if (id = "")
                continue
            sec := "M_" id
            m := MacroConfig()
            m.id := id
            m.name := IniRead(path, sec, "Name", "未命名")
            m.mode := IniRead(path, sec, "Mode", "single")
            m.singleKey := IniRead(path, sec, "SingleKey", "{Space}")
            m.singleInterval := Integer(IniRead(path, sec, "SingleInterval", "50"))
            m.keys := []
            keyCount := Integer(IniRead(path, sec, "KeyCount", "0"))
            if (keyCount > 0) {
                loop keyCount {
                    line := IniRead(path, sec, "Key" A_Index, "")
                    if (line = "" || line = "ERROR")
                        continue
                    parts := StrSplit(line, "|")
                    m.keys.Push(MacroConfig.NewKey(
                        parts.Length >= 1 ? parts[1] : "{Space}",
                        Integer(parts.Length >= 2 ? parts[2] : m.singleInterval)
                    ))
                }
            }
            m.EnsureKeys()
            m.loop := Integer(IniRead(path, sec, "Loop", "1"))
            m.loopDelay := Integer(IniRead(path, sec, "LoopDelay", "200"))
            m.repeat := Integer(IniRead(path, sec, "Repeat", "0"))
            m.startHotkey := IniRead(path, sec, "StartHotkey", "F6")
            m.stopHotkey := IniRead(path, sec, "StopHotkey", "F7")
            m.pauseHotkey := IniRead(path, sec, "PauseHotkey", "F8")
            m.targetExe := IniRead(path, sec, "TargetExe", "")
            m.targetTitle := IniRead(path, sec, "TargetTitle", "")
            m.targetClass := IniRead(path, sec, "TargetClass", "")
            m.activate := Integer(IniRead(path, sec, "Activate", "1"))
            m.sendMode := IniRead(path, sec, "SendMode", "Send")
            count := Integer(IniRead(path, sec, "StepCount", "0"))
            loop count {
                line := IniRead(path, sec, "Step" A_Index, "")
                if (line = "" || line = "ERROR")
                    continue
                parts := StrSplit(line, "|")
                m.steps.Push(MacroConfig.NewStep(
                    parts.Length >= 1 ? parts[1] : "key",
                    parts.Length >= 2 ? parts[2] : "",
                    Integer(parts.Length >= 3 ? parts[3] : 50),
                    Integer(parts.Length >= 4 ? parts[4] : 0),
                    Integer(parts.Length >= 5 ? parts[5] : 0),
                    Integer(parts.Length >= 6 ? parts[6] : 0)
                ))
            }
            this.macros.Push(m)
        }
    }

    _SeedDefaults() {
        single := this._DefaultSingle()
        seq := MacroConfig()
        seq.id := this._NewId()
        seq.name := "示例序列"
        seq.mode := "sequence"
        seq.loop := 1
        seq.loopDelay := 500
        seq.repeat := 0
        seq.startHotkey := "F9"
        seq.stopHotkey := "F10"
        seq.pauseHotkey := "F11"
        seq.steps := [
            MacroConfig.NewStep("key", "1", 300),
            MacroConfig.NewStep("key", "2", 500),
            MacroConfig.NewStep("key", "r", 200),
            MacroConfig.NewStep("sleep", "", 800)
        ]
        this.macros := [single, seq]
        this.activeId := single.id
        this.Save()
    }

    _DefaultSingle() {
        m := MacroConfig()
        m.id := this._NewId()
        m.name := "连发"
        m.mode := "single"
        m.keys := [MacroConfig.NewKey("{Space}", 50)]
        m.SyncLegacySingle()
        m.loop := 1
        m.loopDelay := 0
        m.repeat := 0
        m.startHotkey := "F6"
        m.stopHotkey := "F7"
        m.pauseHotkey := "F8"
        return m
    }

    _NewId() {
        return "m" A_TickCount Random(1000, 9999)
    }
}
