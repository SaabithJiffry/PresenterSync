; ==============================================================================
; Library: JsonCodec.ahk
; Description: Pure AutoHotkey v2 RFC 8259 structural JSON parser, serializer,
;              string escaper/unescaper, and typed top-level object accessors.
;              Eliminates regex substring key collisions, "]" truncation,
;              "\\n" path corruption, and unescaped < 0x20 control failures.
; ==============================================================================

class JsonCodec {
    static _lastRaw := ""
    static _lastMap := ""

    class _BoolBox {
        __New(val) {
            this.value := !!val
        }
    }

    class _NullBox {
    }

    static Bool(val) {
        return JsonCodec._BoolBox(val)
    }

    static Null() {
        return JsonCodec._NullBox()
    }

    static Escape(str) {
        s := StrReplace(String(str), "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`b", "\b")
        s := StrReplace(s, "`f", "\f")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`t", "\t")
        if (RegExMatch(s, "[\x00-\x1f]")) {
            out := ""
            Loop Parse, s {
                code := Ord(A_LoopField)
                out .= (code < 32) ? Format("\u{:04x}", code) : A_LoopField
            }
            return out
        }
        return s
    }

    static Unescape(str) {
        s := String(str)
        if (!InStr(s, "\"))
            return s
        out := ""
        i := 1
        len := StrLen(s)
        while (i <= len) {
            ch := SubStr(s, i, 1)
            if (ch = "\" && i < len) {
                nxt := SubStr(s, i + 1, 1)
                switch nxt {
                    case '"': out .= '"'
                    case "\": out .= "\"
                    case "/": out .= "/"
                    case "b": out .= "`b"
                    case "f": out .= "`f"
                    case "n": out .= "`n"
                    case "r": out .= "`r"
                    case "t": out .= "`t"
                    case "u":
                        if (i + 5 <= len && RegExMatch(SubStr(s, i + 2, 4), "^[0-9A-Fa-f]{4}$")) {
                            cp := Integer("0x" SubStr(s, i + 2, 4))
                            if (cp >= 0xD800 && cp <= 0xDBFF && i + 11 <= len && SubStr(s, i + 6, 2) = "\u" && RegExMatch(SubStr(s, i + 8, 4), "^[0-9A-Fa-f]{4}$")) {
                                lo := Integer("0x" SubStr(s, i + 8, 4))
                                if (lo >= 0xDC00 && lo <= 0xDFFF) {
                                    cp := 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                                    out .= Chr(cp)
                                    i += 12
                                    continue
                                }
                            }
                            out .= Chr(cp)
                            i += 6
                            continue
                        }
                        out .= "\u"
                    default: out .= nxt
                }
                i += 2
            } else {
                out .= ch
                i += 1
            }
        }
        return out
    }

    static Parse(jsonStr, &errOut := "", maxDepth := 32) {
        errOut := ""
        s := String(jsonStr)
        len := StrLen(s)
        if (len = 0) {
            errOut := "Empty JSON"
            return ""
        }
        ctx := { src: s, len: len, pos: 1, err: "", maxDepth: maxDepth }
        this._SkipWs(ctx)
        val := this._ParseValue(ctx, 0)
        if (ctx.err != "") {
            errOut := ctx.err
            return ""
        }
        this._SkipWs(ctx)
        if (ctx.pos <= ctx.len) {
            errOut := "Trailing characters at position " ctx.pos
            return ""
        }
        return val
    }

    static _SkipWs(ctx) {
        while (ctx.pos <= ctx.len) {
            code := Ord(SubStr(ctx.src, ctx.pos, 1))
            if (code == 32 || code == 9 || code == 10 || code == 13)
                ctx.pos += 1
            else
                break
        }
    }

    static _ParseValue(ctx, depth) {
        if (ctx.err != "")
            return ""
        if (ctx.pos > ctx.len) {
            ctx.err := "Unexpected end of JSON"
            return ""
        }
        ch := SubStr(ctx.src, ctx.pos, 1)
        if (ch = "{")
            return this._ParseObject(ctx, depth + 1)
        if (ch = "[")
            return this._ParseArray(ctx, depth + 1)
        if (ch = '"')
            return this._ParseString(ctx)
        if (ch = "t" && SubStr(ctx.src, ctx.pos, 4) == "true") {
            ctx.pos += 4
            return true
        }
        if (ch = "f" && SubStr(ctx.src, ctx.pos, 5) == "false") {
            ctx.pos += 5
            return false
        }
        if (ch = "n" && SubStr(ctx.src, ctx.pos, 4) == "null") {
            ctx.pos += 4
            return ""
        }
        if (ch = "-" || (Ord(ch) >= 48 && Ord(ch) <= 57))
            return this._ParseNumber(ctx)
        ctx.err := "Unexpected token '" ch "' at position " ctx.pos
        return ""
    }

    static _ParseString(ctx) {
        ctx.pos += 1 ; skip opening quote
        out := ""
        chunkStart := ctx.pos
        while (ctx.pos <= ctx.len) {
            ch := SubStr(ctx.src, ctx.pos, 1)
            if (ch = '"') {
                if (ctx.pos > chunkStart)
                    out .= SubStr(ctx.src, chunkStart, ctx.pos - chunkStart)
                ctx.pos += 1
                return out
            }
            if (ch = "\") {
                if (ctx.pos > chunkStart)
                    out .= SubStr(ctx.src, chunkStart, ctx.pos - chunkStart)
                ctx.pos += 1
                if (ctx.pos > ctx.len) {
                    ctx.err := "Unterminated escape sequence"
                    return ""
                }
                esc := SubStr(ctx.src, ctx.pos, 1)
                switch esc {
                    case '"': out .= '"'
                    case "\": out .= "\"
                    case "/": out .= "/"
                    case "b": out .= "`b"
                    case "f": out .= "`f"
                    case "n": out .= "`n"
                    case "r": out .= "`r"
                    case "t": out .= "`t"
                    case "u":
                        if (ctx.pos + 4 > ctx.len || !RegExMatch(SubStr(ctx.src, ctx.pos + 1, 4), "^[0-9A-Fa-f]{4}$")) {
                            ctx.err := "Invalid unicode escape at position " ctx.pos
                            return ""
                        }
                        cp := Integer("0x" SubStr(ctx.src, ctx.pos + 1, 4))
                        ctx.pos += 5
                        if (cp >= 0xD800 && cp <= 0xDBFF && ctx.pos + 5 <= ctx.len && SubStr(ctx.src, ctx.pos, 2) = "\u" && RegExMatch(SubStr(ctx.src, ctx.pos + 2, 4), "^[0-9A-Fa-f]{4}$")) {
                            lo := Integer("0x" SubStr(ctx.src, ctx.pos + 2, 4))
                            if (lo >= 0xDC00 && lo <= 0xDFFF) {
                                cp := 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                                ctx.pos += 6
                            }
                        }
                        out .= Chr(cp)
                        chunkStart := ctx.pos
                        continue
                    default:
                        ctx.err := "Invalid escape '\\" esc "' at position " ctx.pos
                        return ""
                }
                ctx.pos += 1
                chunkStart := ctx.pos
                continue
            }
            code := Ord(ch)
            if (code < 32) {
                ctx.err := "Unescaped control char in string at position " ctx.pos
                return ""
            }
            ctx.pos += 1
        }
        ctx.err := "Unterminated JSON string"
        return ""
    }

    static _ParseNumber(ctx) {
        rest := SubStr(ctx.src, ctx.pos)
        if (!RegExMatch(rest, "^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?", &m)) {
            ctx.err := "Invalid JSON number at position " ctx.pos
            return 0
        }
        numStr := m[0]
        ctx.pos += StrLen(numStr)
        if (InStr(numStr, ".") || InStr(numStr, "e") || InStr(numStr, "E"))
            return Float(numStr)
        try return Integer(numStr)
        catch
            return Float(numStr)
    }

    static _ParseArray(ctx, depth) {
        if (depth > ctx.maxDepth) {
            ctx.err := "Max JSON nesting depth exceeded"
            return ""
        }
        arr := []
        ctx.pos += 1 ; skip '['
        this._SkipWs(ctx)
        if (ctx.pos <= ctx.len && SubStr(ctx.src, ctx.pos, 1) = "]") {
            ctx.pos += 1
            return arr
        }
        Loop {
            this._SkipWs(ctx)
            val := this._ParseValue(ctx, depth)
            if (ctx.err != "")
                return ""
            arr.Push(val)
            this._SkipWs(ctx)
            if (ctx.pos > ctx.len) {
                ctx.err := "Unterminated JSON array"
                return ""
            }
            ch := SubStr(ctx.src, ctx.pos, 1)
            ctx.pos += 1
            if (ch = "]")
                return arr
            if (ch != ",") {
                ctx.err := "Expected ',' or ']' at position " (ctx.pos - 1)
                return ""
            }
        }
    }

    static _ParseObject(ctx, depth) {
        if (depth > ctx.maxDepth) {
            ctx.err := "Max JSON nesting depth exceeded"
            return ""
        }
        obj := Map()
        obj.CaseSense := "On"
        ctx.pos += 1 ; skip '{'
        this._SkipWs(ctx)
        if (ctx.pos <= ctx.len && SubStr(ctx.src, ctx.pos, 1) = "}") {
            ctx.pos += 1
            return obj
        }
        Loop {
            this._SkipWs(ctx)
            if (ctx.pos > ctx.len || SubStr(ctx.src, ctx.pos, 1) != '"') {
                ctx.err := "Expected string key at position " ctx.pos
                return ""
            }
            k := this._ParseString(ctx)
            if (ctx.err != "")
                return ""
            this._SkipWs(ctx)
            if (ctx.pos > ctx.len || SubStr(ctx.src, ctx.pos, 1) != ":") {
                ctx.err := "Expected ':' at position " ctx.pos
                return ""
            }
            ctx.pos += 1
            this._SkipWs(ctx)
            v := this._ParseValue(ctx, depth)
            if (ctx.err != "")
                return ""
            obj[k] := v
            this._SkipWs(ctx)
            if (ctx.pos > ctx.len) {
                ctx.err := "Unterminated JSON object"
                return ""
            }
            ch := SubStr(ctx.src, ctx.pos, 1)
            ctx.pos += 1
            if (ch = "}")
                return obj
            if (ch != ",") {
                ctx.err := "Expected ',' or '}' at position " (ctx.pos - 1)
                return ""
            }
        }
    }

    static Stringify(val) {
        if (val is JsonCodec._BoolBox)
            return val.value ? "true" : "false"
        if (val is JsonCodec._NullBox)
            return "null"
        t := Type(val)
        if (t = "Integer" || t = "Float")
            return String(val)
        if (t = "String")
            return '"' this.Escape(val) '"'
        if (val is Array) {
            out := "["
            for idx, item in val
                out .= (idx > 1 ? "," : "") this.Stringify(item)
            return out "]"
        }
        if (val is Map) {
            out := "{"
            first := true
            for k, v in val {
                out .= (first ? "" : ",") '"' this.Escape(k) '":' this.Stringify(v)
                first := false
            }
            return out "}"
        }
        if (IsObject(val)) {
            out := "{"
            first := true
            for k, v in val.OwnProps() {
                out .= (first ? "" : ",") '"' this.Escape(k) '":' this.Stringify(v)
                first := false
            }
            return out "}"
        }
        return '"' this.Escape(val) '"'
    }

    static _EnsureMap(src) {
        if (IsObject(src))
            return (src is Map) ? src : ""
        s := String(src)
        if (s = "")
            return ""
        if (this._lastRaw == s && IsObject(this._lastMap))
            return this._lastMap
        parsed := this.Parse(s)
        if (parsed is Map) {
            this._lastRaw := s
            this._lastMap := parsed
            return parsed
        }
        return ""
    }

    static HasKey(src, key) {
        m := this._EnsureMap(src)
        return (m is Map) ? m.Has(key) : false
    }

    static GetStr(src, key, defaultVal := "") {
        m := this._EnsureMap(src)
        if !(m is Map) || !m.Has(key)
            return defaultVal
        v := m[key]
        if (IsObject(v))
            return defaultVal
        return String(v)
    }

    static GetBool(src, key, defaultVal := false) {
        m := this._EnsureMap(src)
        if !(m is Map) || !m.Has(key)
            return defaultVal
        v := m[key]
        if (v is JsonCodec._BoolBox)
            return v.value
        t := Type(v)
        if (t = "Integer" || t = "Float")
            return v != 0
        if (t = "String") {
            low := StrLower(Trim(v))
            if (low = "true" || low = "1")
                return true
            if (low = "false" || low = "0")
                return false
        }
        return defaultVal
    }

    static GetInt(src, key, defaultVal := 0) {
        m := this._EnsureMap(src)
        if !(m is Map) || !m.Has(key)
            return defaultVal
        v := m[key]
        t := Type(v)
        if (t = "Integer")
            return v
        if (t = "Float")
            return Integer(v)
        if (t = "String" && IsInteger(Trim(v)))
            return Integer(Trim(v))
        return defaultVal
    }

    static GetFloat(src, key, defaultVal := 0.0) {
        m := this._EnsureMap(src)
        if !(m is Map) || !m.Has(key)
            return defaultVal
        v := m[key]
        if (IsNumber(v))
            return Float(v)
        return defaultVal
    }

    static GetStrArray(src, key) {
        out := []
        m := this._EnsureMap(src)
        if !(m is Map) || !m.Has(key)
            return out
        arr := m[key]
        if !(arr is Array)
            return out
        for _, item in arr {
            if (!IsObject(item)) {
                s := String(item)
                if (s != "")
                    out.Push(s)
            }
        }
        return out
    }

    static GetArray(src, key) {
        m := this._EnsureMap(src)
        if !(m is Map) || !m.Has(key)
            return []
        arr := m[key]
        return (arr is Array) ? arr : []
    }

    static GetMap(src, key) {
        m := this._EnsureMap(src)
        if !(m is Map) || !m.Has(key)
            return ""
        v := m[key]
        return (v is Map) ? v : ""
    }
}
