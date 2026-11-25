; ==============================================================================
; Module: HudRenderer.ahk
; Description: Layered GDI+ HUD rendering, Secondary Mic Pill, Animations, Snap & Auto-Dodge
; ==============================================================================
; --- HUD STATE SYNCHRONIZATION & APPEARANCE ---
GetCornerRadius(cfg, h) {
    return cfg.SleekCorners ? (h / 2.0) : Min(UIConstants.CORNER_RADIUS_DEFAULT * cfg.IndicatorScale, h / 2.0)
}

IsHudSuppressed(cfg) {
    return !IsObject(cfg) || !cfg.ShowIndicator || (IsSet(HudSnake) && HudSnake.IsActive)
}

HasActiveHudAlert(state) {
    if (!IsObject(state))
        return false
    return (state.HasOwnProp("voiceWhileMuted") && state.voiceWhileMuted)
        || (state.HasOwnProp("deadMicWarn") && state.deadMicWarn)
        || (state.HasOwnProp("osMicMutedDrift") && state.osMicMutedDrift)
        || (state.HasOwnProp("streamDropWarn") && state.streamDropWarn)
        || (state.HasOwnProp("lowDiskWarnLevel") && state.lowDiskWarnLevel > 0)
}

ShouldHideForMutedOrAlertMode(cfg, state) {
    if (!IsObject(cfg) || !cfg.HasOwnProp("HudVisibilityMode"))
        return false
    if (cfg.HudVisibilityMode != "MutedOrAlert")
        return false
    if (IsObject(state) && (state.isMuted || HasActiveHudAlert(state)))
        return false
    return true
}

IsCornerTallyDotActive(cfg, state) {
    if (!IsObject(cfg) || !cfg.HasOwnProp("HudVisibilityMode"))
        return false
    if (cfg.HudVisibilityMode != "CornerTallyDot")
        return false
    if (IsObject(state) && (state.isMuted || HasActiveHudAlert(state)))
        return false
    return true
}

SnapHudToCorner(cfg, state, corner := "BR", margin := 0) {
    if (!IsObject(cfg) || !IsObject(state))
        return { x: 0, y: 0, w: 0, h: 0 }
    w := (state.HasOwnProp("baseWidth") && state.baseWidth > 0) ? state.baseWidth : UIConstants.BASE_WIDTH_ICON
    h := (state.HasOwnProp("baseHeight") && state.baseHeight > 0) ? state.baseHeight : UIConstants.BASE_HEIGHT
    curX := state.HasOwnProp("savedX") ? Integer(state.savedX) : 0
    curY := state.HasOwnProp("savedY") ? Integer(state.savedY) : 0
    mons := IsSet(CaptureSafety) ? CaptureSafety.GetMonitorWorkAreas() : [{ left: 0, top: 0, right: A_ScreenWidth, bottom: A_ScreenHeight }]
    targetMon := mons[1]
    bestDist := 1e15
    cx := curX + (w / 2.0), cy := curY + (h / 2.0)
    for _, m in mons {
        if (curX + w > m.left && curX < m.right && curY + h > m.top && curY < m.bottom) {
            targetMon := m
            break
        }
        d := ((cx - (m.left + m.right) / 2.0) ** 2) + ((cy - (m.top + m.bottom) / 2.0) ** 2)
        if (d < bestDist) {
            bestDist := d
            targetMon := m
        }
    }
    mgn := Max(0, Integer(margin))
    c := StrUpper(Trim(String(corner)))
    nx := (c = "TL" || c = "BL") ? (targetMon.left + mgn) : (targetMon.right - w - mgn)
    ny := (c = "TL" || c = "TR") ? (targetMon.top + mgn) : (targetMon.bottom - h - mgn)
    state.savedX := nx
    state.savedY := ny
    cfg.savedX := nx
    cfg.savedY := ny
    try cfg.Write("Position", "SavedX", String(nx))
    try cfg.Write("Position", "SavedY", String(ny))
    if (state.HasOwnProp("MicGui") && IsGuiValid(state.MicGui))
        UpdateHudLayout(state, nx, ny)
    return { x: nx, y: ny, w: w, h: h }
}

GetHudPixelReadout(cfg, state) {
    if (!IsObject(state))
        return "0×0 px @ (0, 0)"
    w := (state.HasOwnProp("baseWidth") && state.baseWidth > 0) ? state.baseWidth : UIConstants.BASE_WIDTH_ICON
    h := (state.HasOwnProp("baseHeight") && state.baseHeight > 0) ? state.baseHeight : UIConstants.BASE_HEIGHT
    x := state.HasOwnProp("savedX") ? Integer(state.savedX) : 0
    y := state.HasOwnProp("savedY") ? Integer(state.savedY) : 0
    return Format("{}×{} px @ ({}, {})", w, h, x, y)
}

IsSecondaryHudSuppressed(cfg) {
    return !IsObject(cfg) || !cfg.HasOwnProp("ShowSecondaryMicHud") || !cfg.ShowSecondaryMicHud || (IsSet(HudSnake) && HudSnake.IsActive)
}

IsAnyMicHudVisible(cfg) {
    return !IsHudSuppressed(cfg) || !IsSecondaryHudSuppressed(cfg)
}

ComputeSecondaryMicLayout(cfg, state) {
    defaultW := (IsObject(cfg) && cfg.HasOwnProp("ShowText") && cfg.ShowText) ? UIConstants.BASE_WIDTH_TEXT : UIConstants.BASE_WIDTH_ICON
    w := (IsObject(state) && state.HasOwnProp("baseWidth") && state.baseWidth > 0) ? state.baseWidth : defaultW
    h := (IsObject(state) && state.HasOwnProp("baseHeight") && state.baseHeight > 0) ? state.baseHeight : UIConstants.BASE_HEIGHT
    rawX := (IsObject(cfg) && cfg.HasOwnProp("savedSecondaryX")) ? cfg.savedSecondaryX : "Default"
    rawY := (IsObject(cfg) && cfg.HasOwnProp("savedSecondaryY")) ? cfg.savedSecondaryY : "Default"

    vLeft := SysGet(76), vTop := SysGet(77)
    vRight := vLeft + SysGet(78), vBottom := vTop + SysGet(79)
    if (vRight <= vLeft)
        vRight := vLeft + 1920
    if (vBottom <= vTop)
        vBottom := vTop + 1080

    if (rawX != "Default" && rawY != "Default" && IsInteger(rawX) && IsInteger(rawY)) {
        if (IsSet(CaptureSafety)) {
            clamped := CaptureSafety.ClampRectToMonitors(Integer(rawX), Integer(rawY), w, h)
            sx := clamped.x, sy := clamped.y
        } else {
            sx := Max(vLeft, Min(Integer(rawX), vRight - w))
            sy := Max(vTop, Min(Integer(rawY), vBottom - h))
        }
    } else {
        MonitorGetWorkArea(1, &Left, &Top, &Right, &Bottom)
        primX := (IsObject(state) && state.HasOwnProp("savedX")) ? Integer(state.savedX) : (Right - w - UIConstants.SCREEN_MARGIN_X)
        primY := (IsObject(state) && state.HasOwnProp("savedY")) ? Integer(state.savedY) : (Bottom - h - UIConstants.SCREEN_MARGIN_Y)
        gapX := 18
        candLeft := primX - w - gapX
        candRight := primX + w + gapX
        if (candLeft >= Left + UIConstants.SCREEN_MIN_PAD) {
            sx := candLeft
            sy := Max(Top + UIConstants.SCREEN_MIN_PAD, Min(primY, Bottom - h - UIConstants.SCREEN_MIN_PAD))
        } else if (candRight + w <= Right - UIConstants.SCREEN_MIN_PAD) {
            sx := candRight
            sy := Max(Top + UIConstants.SCREEN_MIN_PAD, Min(primY, Bottom - h - UIConstants.SCREEN_MIN_PAD))
        } else {
            sx := Left + UIConstants.SCREEN_MIN_PAD
            sy := Top + UIConstants.SCREEN_MIN_PAD
        }
    }
    if (IsObject(state)) {
        state.savedSecondaryX := sx
        state.savedSecondaryY := sy
    }
    return { x: sx, y: sy, w: w, h: h }
}

_RenderMicPillSurface(hwnd, x, y, w, h, cfg, state, alpha, overrideMuted := "", holdProgress := 0.0) {
    if (!hwnd || !IsObject(cfg) || !IsObject(state))
        return false

    mutedState := (overrideMuted != "") ? overrideMuted : state.isMuted
    isRemoteOffline := (overrideMuted == "" && state.HasOwnProp("activeHost") && state.HasOwnProp("obsConnected") && !state.obsConnected)

    if (isRemoteOffline) {
        connSt := state.HasOwnProp("connStatus") ? state.connStatus : ""
        isPwReq := (connSt = "pw_required")
        isAuthErr := (connSt = "auth_failed")
        bgRgb := isPwReq ? "452809" : (isAuthErr ? "450A0A" : state.colors.recOff)
        brdBgr := isPwReq ? UIConstants.RgbHexToBgrInt("F59E0B") : (isAuthErr ? state.colors.borderMuted : state.colors.recBorderOff)
        icHex := cfg.MonoIcon ? state.colors.recIconOff : (isPwReq ? "FCD34D" : (isAuthErr ? "FCA5A5" : "E5E7EB"))
        glyph := isPwReq ? Chr(0xE72E) : (isAuthErr ? Chr(0xE783) : Chr(0xF781))
        lbl := isPwReq ? "PW REQ" : (isAuthErr ? "AUTH ERR" : "OFFLINE")
    } else {
        bgRgb := mutedState ? state.colors.muted : state.colors.live
        brdBgr := mutedState ? state.colors.borderMuted : state.colors.borderLive
        if (IsSet(GetRemotePillAlertBorderArgb) && GetRemotePillAlertBorderArgb(cfg, state) != 0)
            brdBgr := UIConstants.RgbHexToBgrInt("F59E0B")
        useCustomContrast := (cfg.HasOwnProp("HudColorPreset") && NormalizeHudColorPreset(cfg.HudColorPreset) = "Custom")
        icHex := cfg.MonoIcon ? (mutedState ? state.colors.iconMuted : state.colors.iconLive) : (useCustomContrast ? PickReadableIconHex(bgRgb) : "FFFFFF")
        glyph := mutedState ? Chr(0xF781) : Chr(0xE720)
        lbl := mutedState ? "MUTED" : "LIVE"
        if (IsSet(BuildRemotePillBadgeText)) {
            badgeTxt := BuildRemotePillBadgeText(cfg, state)
            if (badgeTxt != "")
                lbl .= " " badgeTxt
        }
    }
    contentArgb := Gdip.HexToArgb(icHex)

    if (cfg.ShowText) {
        offsetX := Round((w - state.baseWidth) / 2)
        iconW := Round(UIConstants.MIC_ICON_W * cfg.IndicatorScale)
        iconX := offsetX + Round(UIConstants.ICON_OFFSET_X * cfg.IndicatorScale)
        textW := Round(UIConstants.MIC_TEXT_W * cfg.IndicatorScale)
        textX := offsetX + Round(UIConstants.TEXT_OFFSET_X * cfg.IndicatorScale)
        iconCfg := {text: glyph, font: state.IconFont, size: state.iconSize, color: contentArgb, x: iconX, w: iconW}
        labelCfg := {text: lbl, size: state.textSize, bold: true, color: contentArgb, x: textX, w: textW, align: 0}
    } else {
        iconCfg := {text: glyph, font: state.IconFont, size: state.iconSize, color: contentArgb, x: 0, w: w}
        labelCfg := ""
    }

    meterLevel := (!mutedState && !isRemoteOffline && cfg.HasOwnProp("ShowVoiceMeter") && cfg.ShowVoiceMeter && state.HasOwnProp("voicePeak")) ? state.voicePeak : 0.0
    meterArgb := cfg.MonoIcon ? Gdip.HexToArgb(icHex, 216) : 0xD8FFFFFF
    holdArgb := mutedState ? 0xFF22C55E : 0xFFEF4444
    return Gdip.RenderPill(hwnd, x, y, w, h, Gdip.HexToArgb(bgRgb), Gdip.BgrToArgb(brdBgr), alpha, GetCornerRadius(cfg, h), iconCfg, labelCfg, meterLevel, meterArgb, holdProgress, holdArgb)
}

ApplySecondaryMicAppearance(cfg, state, customX := "", customY := "", customW := "", customH := "", customAlpha := "", overrideMuted := "") {
    if (!IsObject(state) || !state.HasOwnProp("SecondaryMicGui") || !IsGuiValid(state.SecondaryMicGui))
        return false

    secPos := ComputeSecondaryMicLayout(cfg, state)
    sx := (customX != "") ? customX : secPos.x
    sy := (customY != "") ? customY : secPos.y
    sw := (customW != "") ? customW : secPos.w
    sh := (customH != "") ? customH : secPos.h
    defAlpha := state.HasOwnProp("secondaryCurrentAlpha") ? state.secondaryCurrentAlpha : state.currentAlpha
    sAlpha := (customAlpha != "") ? customAlpha : defAlpha
    secHold := state.HasOwnProp("secondaryMicHoldProgress") ? Float(state.secondaryMicHoldProgress) : 0.0
    return _RenderMicPillSurface(state.SecondaryMicGui.Hwnd, sx, sy, sw, sh, cfg, state, sAlpha, overrideMuted, secHold)
}

ApplyMicAppearance(cfg, state, customX := "", customY := "", customW := "", customH := "", customAlpha := "", overrideMuted := "") {
    if (!IsObject(state) || !state.HasOwnProp("MicGui") || !IsGuiValid(state.MicGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    x := (customX != "") ? customX : pos.micX
    y := (customY != "") ? customY : pos.micY
    w := (customW != "") ? customW : pos.micW
    h := (customH != "") ? customH : pos.micH
    alpha := (customAlpha != "") ? customAlpha : state.currentAlpha
    micHold := state.HasOwnProp("micHoldProgress") ? Float(state.micHoldProgress) : 0.0
    ok := _RenderMicPillSurface(state.MicGui.Hwnd, x, y, w, h, cfg, state, alpha, overrideMuted, micHold)

    if (customX = "" && customW = "" && !IsSecondaryHudSuppressed(cfg) && state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui)) {
        secAlpha := (customAlpha != "") ? customAlpha : (state.HasOwnProp("secondaryCurrentAlpha") ? state.secondaryCurrentAlpha : alpha)
        ApplySecondaryMicAppearance(cfg, state, "", "", "", "", secAlpha, overrideMuted)
    }
    return ok
}

SyncChatState(cfg, state, newCount) {
    if (state.unreadChatCount != newCount) {
        state.unreadChatCount := newCount
        if (!IsHudSuppressed(cfg) && cfg.ShowExtraHuds)
            ApplyChatAppearance(cfg, state)
    }
}

ApplyChatAppearance(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("ChatGui") || !IsGuiValid(state.ChatGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    hasUnread := (state.unreadChatCount > 0)
    bg := hasUnread ? state.colors.chatAlert : state.colors.chatClear
    brd := hasUnread ? state.colors.chatBorderAlert : state.colors.chatBorderClear
    ic := cfg.MonoIcon ? (hasUnread ? state.colors.chatIconAlert : state.colors.chatIconClear) : (hasUnread ? "FFFFFF" : "D1D5DB")
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        cIconW := Round(UIConstants.CHAT_ICON_W * cfg.IndicatorScale)
        cIconX := Round(UIConstants.CHAT_ICON_X * cfg.IndicatorScale)
        cTextX := cIconX + cIconW + Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        cTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.chatW - cTextX - cIconX)
        lbl := hasUnread ? (state.unreadChatCount " NEW") : "CHAT"
        iconCfg := {text: Chr(0xE8BD), font: state.IconFont, size: state.subIconSize, color: contentArgb, x: cIconX, w: cIconW}
        labelCfg := {text: lbl, size: state.subTextSize, bold: true, color: contentArgb, x: cTextX, w: cTextW, align: 0}
    } else if (hasUnread) {
        iconCfg := ""
        labelCfg := {text: String(state.unreadChatCount), size: state.subTextSize, bold: true, color: contentArgb, x: 0, w: pos.chatW, align: 1}
    } else {
        iconCfg := {text: Chr(0xE8BD), font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.chatW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.ChatGui.Hwnd, pos.chatX, pos.chatY, pos.chatW, pos.chatH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.chatH), iconCfg, labelCfg)
}

SyncStudioState(cfg, state, isEnabled) {
    if (state.studioModeActive != isEnabled) {
        state.studioModeActive := isEnabled
        if (!IsHudSuppressed(cfg) && cfg.ShowExtraHuds)
            ApplyStudioAppearance(cfg, state)
    }
}

_LerpArgb(argbA, argbB, t) {
    k := Min(1.0, Max(0.0, Float(t)))
    a1 := (argbA >> 24) & 0xFF, r1 := (argbA >> 16) & 0xFF, g1 := (argbA >> 8) & 0xFF, b1 := argbA & 0xFF
    a2 := (argbB >> 24) & 0xFF, r2 := (argbB >> 16) & 0xFF, g2 := (argbB >> 8) & 0xFF, b2 := argbB & 0xFF
    a := Integer(Round(a1 + (a2 - a1) * k)) & 0xFF
    r := Integer(Round(r1 + (r2 - r1) * k)) & 0xFF
    g := Integer(Round(g1 + (g2 - g1) * k)) & 0xFF
    b := Integer(Round(b1 + (b2 - b1) * k)) & 0xFF
    return (a << 24) | (r << 16) | (g << 8) | b
}

ApplyStudioAppearance(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("StudioGui") || !IsGuiValid(state.StudioGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    bg := state.studioModeActive ? state.colors.studioOn : state.colors.studioOff
    brd := state.studioModeActive ? state.colors.studioBorderOn : state.colors.studioBorderOff
    ic := cfg.MonoIcon ? (state.studioModeActive ? state.colors.studioIconOn : state.colors.studioIconOff) : (state.studioModeActive ? "FFFFFF" : "D1D5DB")
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        stIconW := Round(UIConstants.STUDIO_ICON_W * cfg.IndicatorScale)
        stIconX := Round(UIConstants.STUDIO_ICON_X * cfg.IndicatorScale)
        stGap := Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        stTextX := stIconX + stIconW + stGap
        stTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.studioW - stTextX - stIconX)
        stIconSize := Max(1, Round(UIConstants.STUDIO_ICON_SIZE_TEXT * cfg.IndicatorScale))
        stTextSize := Max(1, Round(UIConstants.STUDIO_TEXT_SIZE * cfg.IndicatorScale))
        iconCfg := {text: Chr(0xE7F4), font: state.IconFont, size: stIconSize, color: contentArgb, x: stIconX, w: stIconW}
        labelCfg := {text: "STUDIO", size: stTextSize, bold: true, color: contentArgb, x: stTextX, w: stTextW, align: 0}
    } else {
        stIconSize := Max(1, Round(UIConstants.STUDIO_ICON_SIZE_ONLY * cfg.IndicatorScale))
        iconCfg := {text: Chr(0xE7F4), font: state.IconFont, size: stIconSize, color: contentArgb, x: 0, w: pos.studioW}
        labelCfg := ""
    }

    studioHold := state.HasOwnProp("studioHoldProgress") ? Float(state.studioHoldProgress) : 0.0
    return Gdip.RenderPill(state.StudioGui.Hwnd, pos.studioX, pos.studioY, pos.studioW, pos.studioH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.studioH), iconCfg, labelCfg, 0.0, 0, studioHold, 0xFFA78BFA)
}

ToggleStreamHud(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "ShowStreamHud")
    if (IsObject(state) && state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
        try state.refreshHudFn.Call()
}

_NotifyHostTelemetryChanged(cfg, state, includeRelayDirector := false) {
    if (IsSet(HostBridgeBroadcastMuteState))
        try HostBridgeBroadcastMuteState(cfg, state)
    if (includeRelayDirector && IsSet(BroadcastHostRelayDirectorState))
        try BroadcastHostRelayDirectorState(cfg, state)
}

_EmitWatchdogAlert(cfg, state, diagCat, diagEvt, diagDetail, timelineMsg, bannerMsg, accentHex := "F59E0B", durationMs := 5500, sender := "Safety Guard") {
    if (IsSet(DiagnosticLogger))
        try DiagnosticLogger.RecordBreadcrumb(diagCat, diagEvt, diagDetail)
    if (IsSet(SessionTimeline) && (cfg is Config))
        try SessionTimeline.Record("Alert", timelineMsg, state)
    if (IsSet(ShowStageNudgeBanner) && (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners))
        ShowStageNudgeBanner(bannerMsg, accentHex, durationMs, sender)
}

_GetHudGuiPropNames(includeSecondary := true) {
    return includeSecondary
        ? ["MicGui", "SecondaryMicGui", "RecGui", "ChatGui", "StudioGui", "SceneGui", "StreamGui", "VCamGui"]
        : ["MicGui", "RecGui", "ChatGui", "StudioGui", "SceneGui", "StreamGui", "VCamGui"]
}

SyncStreamState(cfg, state, newState, congestion := 0.0, skippedFrames := -1, reconnecting := false) {
    prevState := state.streamState
    if (newState == 0) {
        effectiveState := 0
        state.streamCongestion := 0.0
        state.streamSkippedFrames := 0
        state.streamPrevSkipped := 0
        state.streamReconnecting := false
    } else {
        state.streamCongestion := Max(0.0, Float(congestion))
        deltaSkip := (prevState != 0 && skippedFrames >= 0) ? Max(0, Integer(skippedFrames) - state.streamPrevSkipped) : 0
        if (skippedFrames >= 0) {
            state.streamSkippedFrames := Integer(skippedFrames)
            state.streamPrevSkipped := Integer(skippedFrames)
        }
        state.streamReconnecting := !!reconnecting
        isWarn := (newState == 2) || state.streamReconnecting || (state.streamCongestion >= UIConstants.STREAM_CONGESTION_WARN) || (deltaSkip > 0)
        effectiveState := isWarn ? 2 : 1
    }

    stateChanged := (prevState != effectiveState)
    state.streamState := effectiveState
    if (state.HasOwnProp("streamTimerFn") && state.streamTimerFn) {
        if (effectiveState != 0 && cfg.EnableWS && state.obsConnected)
            SetTimer(state.streamTimerFn, UIConstants.STREAM_POLL_INTERVAL_MS)
        else
            SetTimer(state.streamTimerFn, 0)
    }

    prevWarn := (prevState == 2)
    currWarn := (effectiveState == 2)
    state.streamDropWarn := currWarn
    if (prevWarn != currWarn)
        _NotifyHostTelemetryChanged(cfg, state, true)

    if (stateChanged) {
        oldW := state.streamW
        state.ComputeDimensions(cfg)
        if (!IsHudSuppressed(cfg) && cfg.ShowExtraHuds && cfg.EnableWS && (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud)) {
            if (state.streamW != oldW && !state.isDraggingHud) {
                UpdateHudLayout(state, state.savedX, state.savedY)
                ApplyVCamAppearance(cfg, state)
            }
            ApplyStreamAppearance(cfg, state)
        }
    }
}

ApplyStreamAppearance(cfg, state) {
    if (!IsGuiValid(state.StreamGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    if (state.streamState == 2) {
        bg := state.colors.streamWarn, brd := state.colors.streamBorderWarn, ic := cfg.MonoIcon ? state.colors.streamIconWarn : "FFFFFF"
        glyph := Chr(0xE7BA), lbl := "WARN"
    } else if (state.streamState == 1) {
        bg := state.colors.streamLive, brd := state.colors.streamBorderLive, ic := cfg.MonoIcon ? state.colors.streamIconLive : "FFFFFF"
        glyph := Chr(0xE93E), lbl := "LIVE"
    } else {
        bg := state.colors.streamOff, brd := state.colors.streamBorderOff, ic := cfg.MonoIcon ? state.colors.streamIconOff : "D1D5DB"
        glyph := Chr(0xE93E), lbl := "OFF"
    }
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        sIconW := Round(UIConstants.STREAM_ICON_W * cfg.IndicatorScale)
        sIconX := Round(UIConstants.STREAM_ICON_X * cfg.IndicatorScale)
        sGap := Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        sTextX := sIconX + sIconW + sGap
        sTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.streamW - sTextX - sIconX)
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: sIconX, w: sIconW}
        labelCfg := {text: lbl, size: state.subTextSize, bold: true, color: contentArgb, x: sTextX, w: sTextW, align: 0, autoFit: true}
    } else {
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.streamW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.StreamGui.Hwnd, pos.streamX, pos.streamY, pos.streamW, pos.streamH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.streamH), iconCfg, labelCfg)
}

SyncVCamState(cfg, state, isActive) {
    active := !!isActive
    if (state.vcamActive != active) {
        state.vcamActive := active
        if (!IsHudSuppressed(cfg) && cfg.ShowExtraHuds && cfg.EnableWS && (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud))
            ApplyVCamAppearance(cfg, state)
    }
}

ApplyVCamAppearance(cfg, state) {
    if (!IsGuiValid(state.VCamGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    if (state.vcamActive) {
        bg := state.colors.vcamOn, brd := state.colors.vcamBorderOn, ic := cfg.MonoIcon ? state.colors.vcamIconOn : "FFFFFF"
    } else {
        bg := state.colors.vcamOff, brd := state.colors.vcamBorderOff, ic := cfg.MonoIcon ? state.colors.vcamIconOff : "D1D5DB"
    }
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        vIconW := Round(UIConstants.VCAM_ICON_W * cfg.IndicatorScale)
        vIconX := Round(UIConstants.VCAM_ICON_X * cfg.IndicatorScale)
        vGap := Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        vTextX := vIconX + vIconW + vGap
        vTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.vcamW - vTextX - vIconX)
        iconCfg := {text: Chr(0xE714), font: state.IconFont, size: state.subIconSize, color: contentArgb, x: vIconX, w: vIconW}
        labelCfg := {text: "VCAM", size: state.subTextSize, bold: true, color: contentArgb, x: vTextX, w: vTextW, align: 0, autoFit: true}
    } else {
        iconCfg := {text: Chr(0xE714), font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.vcamW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.VCamGui.Hwnd, pos.vcamX, pos.vcamY, pos.vcamW, pos.vcamH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.vcamH), iconCfg, labelCfg)
}

RenderAllHudPills(cfg, state) {
    ApplyMicAppearance(cfg, state)
    ApplyRecAppearance(cfg, state)
    ApplyChatAppearance(cfg, state)
    ApplyStudioAppearance(cfg, state)
    ApplySceneAppearance(cfg, state)
    ApplyStreamAppearance(cfg, state)
    ApplyVCamAppearance(cfg, state)
}

SyncSceneState(cfg, state, sceneName) {
    if (sceneName != "" && state.currentSceneName != sceneName) {
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        if (state.HasOwnProp("currentSceneName") && state.currentSceneName != "")
            state.previousProgramScene := state.currentSceneName
        state.currentSceneName := sceneName
        state.sceneMarqueeOffset := 0
        state.sceneMarqueePhase := "pause_start"
        state.sceneMarqueeTicks := 0
        if (state.HasMethod("ComputeDimensions"))
            state.ComputeDimensions(cfg)
        if (!IsHudSuppressed(cfg) && cfg.ShowExtraHuds && (!state.HasOwnProp("isDraggingHud") || !state.isDraggingHud) && state.HasOwnProp("SceneGui") && IsGuiValid(state.SceneGui)) {
            UpdateHudLayout(state, state.savedX, state.savedY)
            ApplySceneAppearance(cfg, state)
        }
        _NotifyHostTelemetryChanged(cfg, state, true)
        if (IsSet(SessionTimeline) && (cfg is Config))
            SessionTimeline.Record("Scene", "Scene -> " sceneName, state, (state.HasOwnProp("obsConnected") && state.obsConnected) ? "OBS Program" : "", -1, "", true)
        if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
            try state.refreshHelpFn.Call()
    }
}

ApplySceneAppearance(cfg, state, fromMarqueeTick := false) {
    if (!IsObject(state) || !state.HasOwnProp("SceneGui") || !IsGuiValid(state.SceneGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    scPad := Round(UIConstants.SCENE_PAD_X * cfg.IndicatorScale)
    availW := Max(UIConstants.MIN_TEXT_WIDTH, pos.sceneW - 2 * scPad)

    fitFontPt := Float(state.miniTextSize)
    minFontPt := Max(6.5, Round(7.5 * cfg.IndicatorScale, 1))
    cacheKey := state.currentSceneName "|" cfg.IndicatorScale "|" availW "|" fitFontPt
    if (state.HasOwnProp("_sceneMeasureCache") && IsObject(state._sceneMeasureCache) && state._sceneMeasureCache.key == cacheKey) {
        cachedM := state._sceneMeasureCache
        fullW := cachedM.fullW
        fitFontPt := cachedM.fitFontPt
        marqueeFontPt := cachedM.marqueeFontPt
        nameW := cachedM.nameW
        dotChar := cachedM.dotChar
        dotW := cachedM.dotW
    } else {
        fullW := Gdip.MeasureTextWidthFloat(state.currentSceneName, "Segoe UI", fitFontPt, 1, false)
        while (fullW > Float(availW) && fitFontPt > minFontPt) {
            fitFontPt := Max(minFontPt, Round(fitFontPt - 0.5, 1))
            fullW := Gdip.MeasureTextWidthFloat(state.currentSceneName, "Segoe UI", fitFontPt, 1, false)
        }
        marqueeFontPt := Max(7.0, Round(8.0 * cfg.IndicatorScale, 1))
        nameW := (fullW > Float(availW)) ? Gdip.MeasureTextWidthFloat(state.currentSceneName, "Segoe UI", marqueeFontPt, 1, false) : fullW
        dotChar := Chr(0x2022)
        dotW := (fullW > Float(availW)) ? Gdip.MeasureTextWidthFloat(dotChar, "Segoe UI", marqueeFontPt, 1, false) : 0.0
        state._sceneMeasureCache := {
            key: cacheKey,
            fullW: fullW,
            fitFontPt: fitFontPt,
            marqueeFontPt: marqueeFontPt,
            nameW: nameW,
            dotChar: dotChar,
            dotW: dotW
        }
    }

    sceneTextArgb := Gdip.HexToArgb(state.colors.HasOwnProp("sceneText") ? state.colors.sceneText : "FFFFFF")
    if (fullW <= Float(availW)) {
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        state.sceneMarqueeMaxOffset := 0.0
        state.sceneMarqueeOffset := 0.0
        labelCfg := {
            text: state.currentSceneName,
            size: fitFontPt,
            bold: true,
            color: sceneTextArgb,
            x: scPad,
            w: availW,
            align: 1,
            autoFit: true
        }
    } else {
        sepGapPx := 28.0 * Float(cfg.IndicatorScale)
        singleSpan := nameW + sepGapPx
        state.sceneMarqueeFontPt := marqueeFontPt
        state.sceneMarqueeTextW := nameW
        state.sceneMarqueeSepGap := sepGapPx
        state.sceneMarqueeSpan := singleSpan
        state.sceneMarqueeMaxOffset := Max(0.0, nameW - Float(availW))
        if (!fromMarqueeTick) {
            state.sceneMarqueeOffset := 0.0
            state.sceneMarqueePhase := "pause_start"
            state.sceneMarqueeTicks := 0
            state.sceneMarqueeLastTick := 0
            if (!IsHudSuppressed(cfg) && cfg.ShowExtraHuds && cfg.EnableWS && state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
                SetTimer(state.sceneMarqueeTimerFn, 25)
        }
        x1 := Float(scPad) - Float(state.sceneMarqueeOffset)
        xDot := x1 + nameW + (sepGapPx - dotW) / 2.0
        x2 := x1 + singleSpan
        labelCfg := {
            size: marqueeFontPt,
            bold: true,
            color: sceneTextArgb,
            align: 0,
            autoFit: false,
            clipX: scPad,
            clipW: availW,
            draws: [
                { text: state.currentSceneName, x: x1, w: nameW + 8.0 },
                { text: dotChar, x: xDot, w: dotW + 8.0 },
                { text: state.currentSceneName, x: x2, w: nameW + 8.0 }
            ]
        }
    }
    return Gdip.RenderPill(state.SceneGui.Hwnd, pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH, Gdip.HexToArgb(state.colors.scene), Gdip.BgrToArgb(state.colors.sceneBorder), state.baseAlpha, GetCornerRadius(cfg, pos.sceneH), "", labelCfg)
}

SceneMarqueeTick(cfg, state) {
    if (!IsObject(state.SceneGui) || !cfg.ShowIndicator || !cfg.ShowExtraHuds || !cfg.EnableWS || state.sceneMarqueeMaxOffset <= 0) {
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        return
    }
    if (state.isDraggingHud)
        return

    ; Initial 1.5s pause (60 x 25ms) after a scene change, then calm 16*scale px/s loop.
    if (state.sceneMarqueePhase = "pause_start") {
        state.sceneMarqueeTicks += 1
        if (state.sceneMarqueeTicks < 60)
            return
        state.sceneMarqueeTicks := 0
        state.sceneMarqueePhase := "scroll_left"
        state.sceneMarqueeLastTick := A_TickCount
        return
    }
    nowTick := A_TickCount
    dtMs := (state.HasOwnProp("sceneMarqueeLastTick") && state.sceneMarqueeLastTick > 0) ? (nowTick - state.sceneMarqueeLastTick) : 0
    state.sceneMarqueeLastTick := nowTick
    dtSec := (dtMs > 0) ? Min(0.05, dtMs / 1000.0) : 0.025
    stepPx := 16.0 * Float(cfg.IndicatorScale) * dtSec
    singleSpan := (state.HasOwnProp("sceneMarqueeSpan") && state.sceneMarqueeSpan > 0) ? Float(state.sceneMarqueeSpan) : Max(1.0, Float(state.sceneMarqueeTextW) + 28.0 * Float(cfg.IndicatorScale))
    state.sceneMarqueeOffset := Mod(Float(state.sceneMarqueeOffset) + stepPx, singleSpan)
    ApplySceneAppearance(cfg, state, true)
}

FormatElapsedShort(sec) {
    s := Max(0, Integer(sec))
    hrs := s // 3600
    mins := Mod(s, 3600) // 60
    secs := Mod(s, 60)
    if (hrs > 0)
        return Format("{}:{:02}:{:02}", hrs, mins, secs)
    return Format("{:02}:{:02}", mins, secs)
}

RecTimerTick(cfg, state) {
    if (!IsObject(state) || state.recState != 1) {
        if (IsObject(state) && state.HasOwnProp("recTimerFn") && state.recTimerFn)
            SetTimer(state.recTimerFn, 0)
        return
    }
    if (state.HasOwnProp("obsRecState") && state.obsRecState == 1) {
        if (state.HasOwnProp("obsRecAnchorTick") && state.obsRecAnchorTick > 0)
            state.obsRecElapsedSec := Max(0, Integer((state.obsRecAnchorMs + (A_TickCount - state.obsRecAnchorTick)) // 1000))
        else
            state.obsRecElapsedSec += 1
    }
    if (state.HasOwnProp("confRecState") && state.confRecState == 1)
        state.confRecElapsedSec += 1

    activeMax := 0
    if (state.HasOwnProp("obsRecState") && state.obsRecState == state.recState)
        activeMax := Max(activeMax, state.obsRecElapsedSec)
    if (state.HasOwnProp("confRecState") && state.confRecState == state.recState)
        activeMax := Max(activeMax, state.confRecElapsedSec)
    state.recElapsedSec := activeMax

    state._recPollCounter := (state.HasOwnProp("_recPollCounter") ? state._recPollCounter : 0) + 1
    if (Mod(state._recPollCounter, 15) == 0 && state.HasOwnProp("obsRecState") && state.obsRecState == 1
        && state.HasOwnProp("obsConnected") && state.obsConnected && state.HasOwnProp("obsWs") && IsObject(state.obsWs)) {
        SendObsRequest(state.obsWs, "GetRecordStatus", "PollRecStatus")
    }

    if (Mod(state.recElapsedSec, 5) == 0)
        _NotifyHostTelemetryChanged(cfg, state, true)
    if (cfg.ShowIndicator && cfg.ShowExtraHuds && (!cfg.HasOwnProp("ShowRecTimer") || cfg.ShowRecTimer) && !state.isDraggingHud && IsGuiValid(state.RecGui)) {
        if (cfg.ShowText) {
            oldW := state.recW
            state.ComputeDimensions(cfg)
            if (state.recW != oldW) {
                UpdateHudLayout(state, state.savedX, state.savedY)
                ApplyChatAppearance(cfg, state)
            }
        }
        ApplyRecAppearance(cfg, state)
    }
}

ToggleRecTimer(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "ShowRecTimer")
    if (IsObject(state) && state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
        try state.refreshHudFn.Call()
}

GetRecLabelPrefix(cfg, state) {
    ; "OBS " / "ZM " / "BOTH " when OBS and conferencing tracking are both enabled and ShowText is on.
    if (!IsObject(cfg) || !IsObject(state) || !state.HasOwnProp("recSourceTag") || state.recSourceTag = "")
        return ""
    if (!cfg.HasOwnProp("ShowText") || !cfg.ShowText)
        return ""
    if (!(cfg.HasOwnProp("EnableWS") && cfg.EnableWS && cfg.HasOwnProp("EnableZoom") && cfg.EnableZoom))
        return ""
    return state.recSourceTag " "
}

GetRecBreakdownText(state) {
    static names := Map(0, "idle", 1, "REC", 2, "PAUSED")
    if (!IsObject(state) || !state.HasOwnProp("obsRecState"))
        return ""
    return Format("Recording: OBS {} {} | Conferencing {} {}"
        , names[state.obsRecState], FormatElapsedShort(state.obsRecElapsedSec)
        , names[state.confRecState], FormatElapsedShort(state.confRecElapsedSec))
}

SyncRecState(cfg, state, newState, initialDurationMs := -1, source := "obs") {
    ; source: "obs" (OBS WebSocket recording) or "conf" (Zoom/Teams UIA recording).
    ; state.recState is the unified state: Recording if any source records, else Paused if any paused.
    isConf := (source = "conf")
    prevState := state.recState
    prevTag := state.recSourceTag
    prevSrcState := isConf ? state.confRecState : state.obsRecState
    durProvided := (initialDurationMs >= 0)

    srcElapsed := isConf ? state.confRecElapsedSec : state.obsRecElapsedSec
    if (durProvided)
        srcElapsed := Max(0, Integer(initialDurationMs // 1000))
    else if (newState == 0)
        srcElapsed := 0
    else if (prevSrcState == 0 && newState == 1)
        srcElapsed := 0
    if (isConf) {
        state.confRecState := newState
        state.confRecElapsedSec := srcElapsed
    } else {
        if (durProvided) {
            state.obsRecAnchorMs := Integer(initialDurationMs)
            state.obsRecAnchorTick := A_TickCount
        } else if (newState == 0) {
            state.obsRecAnchorMs := 0
            state.obsRecAnchorTick := 0
        } else if (newState == 1 && prevSrcState != 1) {
            state.obsRecAnchorMs := srcElapsed * 1000
            state.obsRecAnchorTick := A_TickCount
        } else if (newState == 2 && prevSrcState == 1 && state.HasOwnProp("obsRecAnchorTick") && state.obsRecAnchorTick > 0) {
            state.obsRecAnchorMs := Max(0, state.obsRecAnchorMs + (A_TickCount - state.obsRecAnchorTick))
            state.obsRecAnchorTick := 0
            srcElapsed := Integer(state.obsRecAnchorMs // 1000)
        }
        state.obsRecState := newState
        state.obsRecElapsedSec := srcElapsed
    }

    obsSt := state.obsRecState, confSt := state.confRecState
    unified := (obsSt == 1 || confSt == 1) ? 1 : ((obsSt == 2 || confSt == 2) ? 2 : 0)
    state.recSourceTag := (obsSt > 0 && confSt > 0) ? "BOTH" : (obsSt > 0 ? "OBS" : (confSt > 0 ? "ZM" : ""))

    activeMax := 0
    if (obsSt == unified)
        activeMax := Max(activeMax, state.obsRecElapsedSec)
    if (confSt == unified)
        activeMax := Max(activeMax, state.confRecElapsedSec)
    otherSrcState := isConf ? obsSt : confSt
    stateChanged := (prevState != unified)
    tagChanged := (prevTag != state.recSourceTag)
    if (unified == 0) {
        state.recElapsedSec := 0
    } else if (durProvided) {
        state.recElapsedSec := activeMax
    } else if (prevState == 0 && unified == 1) {
        state.recElapsedSec := 0
    } else if (newState == 0 && otherSrcState > 0) {
        state.recElapsedSec := activeMax
    }
    newState := unified
    state.recState := newState
    if (state.HasOwnProp("recTimerFn") && state.recTimerFn) {
        if (newState == 1)
            SetTimer(state.recTimerFn, 1000)
        else
            SetTimer(state.recTimerFn, 0)
    }

    if (stateChanged || durProvided || tagChanged) {
        if (stateChanged && IsSet(SessionTimeline) && (cfg is Config)) {
            recEvt := (newState == 1) ? ((prevState == 2) ? "Recording Resumed" : "Recording Started")
                : ((newState == 2) ? "Recording Paused" : "Recording Stopped")
            SessionTimeline.Record("Recording", recEvt, state)
        }
        _NotifyHostTelemetryChanged(cfg, state, true)
        oldW := state.HasOwnProp("recW") ? state.recW : 0
        if (state.HasMethod("ComputeDimensions"))
            state.ComputeDimensions(cfg)
        if (!IsHudSuppressed(cfg) && cfg.ShowExtraHuds && state.HasOwnProp("RecGui") && IsGuiValid(state.RecGui)) {
            if (state.HasOwnProp("recW") && state.recW != oldW && (!state.HasOwnProp("isDraggingHud") || !state.isDraggingHud)) {
                UpdateHudLayout(state, state.savedX, state.savedY)
                ApplyChatAppearance(cfg, state)
            }
            ApplyRecAppearance(cfg, state)
        }
    }
}

ApplyRecAppearance(cfg, state) {
    if (!IsGuiValid(state.RecGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    showTimer := (!cfg.HasOwnProp("ShowRecTimer") || cfg.ShowRecTimer) && state.HasOwnProp("recElapsedSec")
    if (state.recState == 1) {
        bg := state.colors.recActive, brd := state.colors.recBorderActive, ic := cfg.MonoIcon ? state.colors.recIconActive : "FFFFFF"
        glyph := Chr(0xE7C8)
        recPfx := GetRecLabelPrefix(cfg, state)
        lbl := showTimer ? (recPfx "REC " FormatElapsedShort(state.recElapsedSec)) : (recPfx "REC")
    } else if (state.recState == 2) {
        bg := state.colors.recPaused, brd := state.colors.recBorderPaused, ic := cfg.MonoIcon ? state.colors.recIconPaused : "FFFFFF"
        glyph := Chr(0xE769)
        recPfx := GetRecLabelPrefix(cfg, state)
        lbl := showTimer ? (recPfx "PAUSED " FormatElapsedShort(state.recElapsedSec)) : (recPfx "PAUSED")
    } else {
        bg := state.colors.recOff, brd := state.colors.recBorderOff, ic := cfg.MonoIcon ? state.colors.recIconOff : "D1D5DB"
        glyph := Chr(0xE71A), lbl := "NOT REC"
    }
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        rIconW := Round(UIConstants.REC_ICON_W * cfg.IndicatorScale)
        rIconX := Round(UIConstants.REC_ICON_X * cfg.IndicatorScale)
        rTextX := rIconX + rIconW + Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        rTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.recW - rTextX - rIconX)
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: rIconX, w: rIconW}
        labelCfg := {text: lbl, size: state.subTextSize, bold: true, color: contentArgb, x: rTextX, w: rTextW, align: 0, autoFit: true}
    } else {
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.recW}
        labelCfg := ""
    }

    recHold := state.HasOwnProp("recHoldProgress") ? Float(state.recHoldProgress) : 0.0
    holdCol := (recHold > 0.001) ? _LerpArgb(0xFFF59E0B, 0xFFEF4444, recHold) : 0
    return Gdip.RenderPill(state.RecGui.Hwnd, pos.recX, pos.recY, pos.recW, pos.recH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.recH), iconCfg, labelCfg, 0.0, 0, recHold, holdCol)
}

GetMuteAudioCueTones(isMuted) {
    return isMuted
        ? { f1: 880, d1: 65, f2: 520, d2: 95 }
        : { f1: 520, d1: 65, f2: 880, d2: 95 }
}

_BuildDualToneWavBuffer(f1, d1Ms, f2, d2Ms, sampleRate := 22050, amp := 0.24) {
    n1 := Max(1, Round(sampleRate * d1Ms / 1000.0))
    nGap := Max(0, Round(sampleRate * 8 / 1000.0))
    n2 := Max(1, Round(sampleRate * d2Ms / 1000.0))
    totalSamples := n1 + nGap + n2
    dataBytes := totalSamples * 2
    buf := Buffer(44 + dataBytes, 0)

    ; Standard 44-byte RIFF/WAVE 16-bit mono PCM header
    NumPut("UInt", 0x46464952, buf, 0)         ; "RIFF"
    NumPut("UInt", 36 + dataBytes, buf, 4)
    NumPut("UInt", 0x45564157, buf, 8)         ; "WAVE"
    NumPut("UInt", 0x20746D66, buf, 12)        ; "fmt "
    NumPut("UInt", 16, buf, 16)
    NumPut("UShort", 1, buf, 20)               ; PCM
    NumPut("UShort", 1, buf, 22)               ; Mono
    NumPut("UInt", sampleRate, buf, 24)
    NumPut("UInt", sampleRate * 2, buf, 28)
    NumPut("UShort", 2, buf, 32)
    NumPut("UShort", 16, buf, 34)
    NumPut("UInt", 0x61746164, buf, 36)        ; "data"
    NumPut("UInt", dataBytes, buf, 40)

    rampSamples := Max(1, Round(sampleRate * 0.005))
    twoPi := 6.283185307179586
    maxVal := 32767.0 * amp

    Loop n1 {
        i := A_Index - 1
        env := Min(1.0, (i + 1) / rampSamples, (n1 - i) / rampSamples)
        smp := Max(-32767, Min(32767, Round(maxVal * env * Sin(twoPi * f1 * i / sampleRate))))
        NumPut("Short", smp, buf, 44 + (i * 2))
    }
    off2 := n1 + nGap
    Loop n2 {
        j := A_Index - 1
        env := Min(1.0, (j + 1) / rampSamples, (n2 - j) / rampSamples)
        smp := Max(-32767, Min(32767, Round(maxVal * env * Sin(twoPi * f2 * j / sampleRate))))
        NumPut("Short", smp, buf, 44 + ((off2 + j) * 2))
    }
    return buf
}

_ClearHudToolTip() {
    if (IsSet(HideCaptureSafeMicroToast))
        HideCaptureSafeMicroToast()
}

PlayMuteAudioCue(isMuted, async := true) {
    static wavMuted := ""
    static wavLive := ""
    if (isMuted) {
        if (!IsObject(wavMuted)) {
            tM := GetMuteAudioCueTones(true)
            wavMuted := _BuildDualToneWavBuffer(tM.f1, tM.d1, tM.f2, tM.d2)
        }
        wavBuf := wavMuted
    } else {
        if (!IsObject(wavLive)) {
            tL := GetMuteAudioCueTones(false)
            wavLive := _BuildDualToneWavBuffer(tL.f1, tL.d1, tL.f2, tL.d2)
        }
        wavBuf := wavLive
    }
    if (IsSet(g_IsTestMode) && g_IsTestMode)
        return true
    flags := async ? 0x00000007 : 0x00000006 ; SND_MEMORY | SND_NODEFAULT | (SND_ASYNC or SND_SYNC)
    try return !!DllCall("winmm\PlaySoundW", "Ptr", wavBuf.Ptr, "Ptr", 0, "UInt", flags, "Int")
    catch
        return false
}

ShowMuteToast(isMuted) {
    if (IsSet(ShowCaptureSafeMicroToast))
        ShowCaptureSafeMicroToast(isMuted ? "Mic: MUTED" : "Mic: LIVE", UIConstants.TOOLTIP_DURATION_MS)
}

ToggleBoolSetting(cfg, state, propName, remoteSection := "Appearance", primarySection := "Settings") {
    val := !cfg.%propName%
    cfg.%propName% := val
    section := (cfg is Config) ? primarySection : remoteSection
    cfg.WriteBool(section, propName, val)
    if (IsObject(state)) {
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
    }
}

ToggleAudioCue(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "EnableAudioCue")
}

ToggleMuteToast(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "EnableMuteToast")
}

TogglePushToMute(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "EnablePushToMute", "Pointer", "Pointer")
    if (cfg.EnablePushToMute && cfg.HasOwnProp("EnablePushToTalk") && cfg.EnablePushToTalk) {
        cfg.EnablePushToTalk := false
        cfg.WriteBool("Pointer", "EnablePushToTalk", false)
        if (IsObject(state)) {
            if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
                try state.rebuildTrayFn.Call()
            if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
                try state.refreshHelpFn.Call()
        }
    }
}

TogglePushToTalk(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "EnablePushToTalk", "Pointer", "Pointer")
    if (cfg.EnablePushToTalk && cfg.HasOwnProp("EnablePushToMute") && cfg.EnablePushToMute) {
        cfg.EnablePushToMute := false
        cfg.WriteBool("Pointer", "EnablePushToMute", false)
        if (IsObject(state)) {
            if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
                try state.rebuildTrayFn.Call()
            if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
                try state.refreshHelpFn.Call()
        }
    }
}

FormatCountdownClock(sec) {
    s := Integer(sec)
    neg := (s < 0)
    absS := Abs(s)
    hrs := absS // 3600
    mins := Mod(absS, 3600) // 60
    secs := Mod(absS, 60)
    core := (hrs > 0) ? Format("{}:{:02}:{:02}", hrs, mins, secs) : Format("{:02}:{:02}", mins, secs)
    return neg ? ("-" core) : core
}

global g_StageNudgeGui := ""
global g_StageNudgeHideFn := ""

global g_StageNudgeQueue := []
global g_StageNudgeHistory := []
global g_StageNudgeActivePriority := 0
global g_StageNudgeActiveMsg := ""

GetStageNudgeHistory() {
    global g_StageNudgeHistory
    out := []
    for _, item in g_StageNudgeHistory
        out.Push(item)
    return out
}

HideStageNudgeBanner(advanceQueue := true, *) {
    global g_StageNudgeGui, g_StageNudgeHideFn, g_StageNudgeActivePriority, g_StageNudgeActiveMsg, g_StageNudgeQueue
    if (IsObject(g_StageNudgeHideFn)) {
        try SetTimer(g_StageNudgeHideFn, 0)
        g_StageNudgeHideFn := ""
    }
    if (IsObject(g_StageNudgeGui)) {
        try g_StageNudgeGui.Destroy()
    }
    g_StageNudgeGui := ""
    g_StageNudgeActivePriority := 0
    g_StageNudgeActiveMsg := ""
    if (advanceQueue && g_StageNudgeQueue.Length > 0) {
        bestIdx := 1
        for idx, qItem in g_StageNudgeQueue {
            if (qItem.priority > g_StageNudgeQueue[bestIdx].priority) {
                bestIdx := idx
                break
            }
        }
        nxt := g_StageNudgeQueue.RemoveAt(bestIdx)
        _RenderStageNudgeBannerNow(nxt.message, nxt.accentHex, nxt.durationMs, nxt.sender, nxt.priority)
    }
}

ShowStageNudgeBanner(message, accentHex := "F59E0B", durationMs := 4500, sender := "", priority := -1) {
    global g_StageNudgeGui, g_StageNudgeQueue, g_StageNudgeHistory, g_StageNudgeActivePriority
    msgText := Trim(String(message))
    if (msgText = "")
        return false
    senderTxt := Trim(String(sender))
    accClean := NormalizeColorHex(accentHex, "F59E0B")
    prio := (priority >= 0) ? Integer(priority)
        : ((accClean = "EF4444" || accClean = "DC2626" || InStr(senderTxt, "Alert") || InStr(senderTxt, "Watchdog")) ? 1 : 0)

    g_StageNudgeHistory.Push({ message: msgText, sender: senderTxt, accentHex: accClean, priority: prio, tick: A_TickCount })
    if (g_StageNudgeHistory.Length > 10)
        g_StageNudgeHistory.RemoveAt(1)

    ; Never let a normal manual nudge clobber an active CRITICAL alert
    if (IsObject(g_StageNudgeGui) && g_StageNudgeActivePriority > prio) {
        if (g_StageNudgeQueue.Length < 16)
            g_StageNudgeQueue.Push({ message: msgText, accentHex: accClean, durationMs: durationMs, sender: senderTxt, priority: prio })
        return true
    }

    HideStageNudgeBanner(false)
    return _RenderStageNudgeBannerNow(msgText, accClean, durationMs, senderTxt, prio)
}

_RenderStageNudgeBannerNow(msgText, accentHex := "F59E0B", durationMs := 4500, senderTxt := "", prio := 0) {
    global g_StageNudgeGui, g_StageNudgeHideFn, g_StageNudgeActivePriority, g_StageNudgeActiveMsg
    fullText := (senderTxt != "") ? (senderTxt ": " msgText) : msgText
    g_StageNudgeActivePriority := prio
    g_StageNudgeActiveMsg := msgText

    nGui := ""
    try {
        nGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "PresenterSyncStageBanner")
        ApplyWindowCaptureAffinity(nGui.Hwnd, true)
        isDark := IsSet(Theme) ? Theme.IsDarkMode() : true
        bgHex := isDark ? "1E293B" : "FFFFFF"
        fgHex := isDark ? "F8FAFC" : "0F172A"
        accHex := NormalizeColorHex(accentHex, "F59E0B")
        nGui.BackColor := bgHex
        nGui.MarginX := 16
        nGui.MarginY := 10
        nGui.SetFont("s9 w700", Theme.UiFont)
        nGui.Add("Text", "xm y8 c" accHex, "STAGE NUDGE")
        nGui.SetFont("s11 w600", Theme.UiFont)
        nGui.Add("Text", "xm y+2 w440 c" fgHex, fullText)
        nGui.Show("AutoSize NoActivate Hide")
        nGui.GetPos(,, &gw, &gh)
        MonitorGetWorkArea(MonitorGetPrimary(), &mL, &mT, &mR, &mB)
        xPos := mL + Round(((mR - mL) - gw) / 2)
        yPos := mT + 22
        nGui.Show("x" xPos " y" yPos " NoActivate")
        WinSetAlwaysOnTop(1, "ahk_id " nGui.Hwnd)
        g_StageNudgeGui := nGui
        if (durationMs > 0) {
            g_StageNudgeHideFn := HideStageNudgeBanner
            SetTimer(g_StageNudgeHideFn, -Integer(durationMs))
        }
        return true
    } catch {
        if (IsObject(nGui))
            try nGui.Destroy()
        return false
    }
}

SetCustomHudColors(cfg, state, liveHex, mutedHex, activateCustom := true) {
    if (!IsObject(cfg))
        return false
    cfg.CustomLiveHex := NormalizeColorHex(liveHex, cfg.HasOwnProp("CustomLiveHex") ? cfg.CustomLiveHex : "107C10")
    cfg.CustomMutedHex := NormalizeColorHex(mutedHex, cfg.HasOwnProp("CustomMutedHex") ? cfg.CustomMutedHex : "C42B1C")
    section := (cfg is Config) ? "Settings" : "Appearance"
    cfg.Write(section, "CustomLiveHex", cfg.CustomLiveHex)
    cfg.Write(section, "CustomMutedHex", cfg.CustomMutedHex)
    if (activateCustom) {
        cfg.HudColorPreset := "Custom"
        cfg.Write(section, "HudColorPreset", "Custom")
    }
    if (IsObject(state)) {
        state.colors := UIConstants.GetColorPalette(cfg.HudColorPreset, cfg.CustomLiveHex, cfg.CustomMutedHex)
        if (state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
            try state.refreshHudFn.Call()
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
    }
    return true
}

ConfigureCustomHudColorsUI(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("PresenterSync - Custom HUD Colors")
    if IsObject(existing)
        return existing
    Theme.AcquireSuspend()
    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync - Custom HUD Colors")
    g._closed := false
    g.MarginX := 20
    g.MarginY := 16
    Theme.ApplyToWindow(g)
    Theme.NamedWindows["PresenterSync - Custom HUD Colors"] := g

    g.SetFont("s10 w700", Theme.UiFont)
    Theme.RegisterControl(g, g.Add("Text", "xm w340", "Custom HUD Hex Colors"), "Text")
    g.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(g, g.Add("Text", "xm y+6 w340", "Enter 6-digit hex colors (e.g. #107C10, #C42B1C). Icon and text contrast adapt automatically (WCAG)."), "Text", "muted")

    curLive := NormalizeColorHex(cfg.HasOwnProp("CustomLiveHex") ? cfg.CustomLiveHex : "107C10", "107C10")
    curMuted := NormalizeColorHex(cfg.HasOwnProp("CustomMutedHex") ? cfg.CustomMutedHex : "C42B1C", "C42B1C")
    g.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(g, g.Add("Text", "xm y+14 w150", "Live Mic Hex:"), "Text")
    g.SetFont("s9 w400", Theme.UiFont)
    edLive := g.Add("Edit", "xm y+4 w160", "#" curLive)
    Theme.RegisterControl(g, edLive, "Edit")
    swLive := g.Add("Progress", "x+12 yp w168 h24 Range0-100 Background" curLive, 0)

    g.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(g, g.Add("Text", "xm y+12 w150", "Muted Mic Hex:"), "Text")
    g.SetFont("s9 w400", Theme.UiFont)
    edMuted := g.Add("Edit", "xm y+4 w160", "#" curMuted)
    Theme.RegisterControl(g, edMuted, "Edit")
    swMuted := g.Add("Progress", "x+12 yp w168 h24 Range0-100 Background" curMuted, 0)

    UpdateSwatches(*) {
        try swLive.Opt("+Background" NormalizeColorHex(edLive.Value, curLive))
        try swMuted.Opt("+Background" NormalizeColorHex(edMuted.Value, curMuted))
    }
    edLive.OnEvent("Change", UpdateSwatches)
    edMuted.OnEvent("Change", UpdateSwatches)

    btnApply := g.Add("Button", "xm y+18 w164 h30 Default", "Apply Custom Theme")
    btnCancel := g.Add("Button", "x+12 yp w164 h30", "Close")
    Theme.RegisterControl(g, btnApply, "Button", "accent")
    Theme.RegisterControl(g, btnCancel, "Button")

    CloseDlg(*) {
        if (g._closed)
            return
        g._closed := true
        Theme.UnregisterWindow(g, "PresenterSync - Custom HUD Colors")
        Theme.ReleaseSuspend()
        g.Destroy()
    }
    btnApply.OnEvent("Click", (*) => (SetCustomHudColors(cfg, state, edLive.Value, edMuted.Value, true), CloseDlg()))
    btnCancel.OnEvent("Click", CloseDlg)
    g.OnEvent("Close", CloseDlg)
    g.OnEvent("Escape", CloseDlg)
    g.Show("AutoSize")
    return g
}

ParseDurationToSeconds(rawInput, defaultSec := 600) {
    s := Trim(String(rawInput))
    if (s = "")
        return defaultSec
    if RegExMatch(s, "^(\d+):(\d{1,2})$", &m)
        return Max(10, Min(14400, Integer(m[1]) * 60 + Integer(m[2])))
    if RegExMatch(s, "^(\d+(?:\.\d+)?)\s*m?$", &m)
        return Max(10, Min(14400, Round(Float(m[1]) * 60)))
    return defaultSec
}

PromptCustomPresenterTimerUI(onStartFn, defaultSec := 600) {
    existing := Theme.FocusExistingWindow("PresenterSync - Custom Timer")
    if IsObject(existing)
        return existing
    Theme.AcquireSuspend()
    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync - Custom Timer")
    g._closed := false
    g.MarginX := 20
    g.MarginY := 16
    Theme.ApplyToWindow(g)
    Theme.NamedWindows["PresenterSync - Custom Timer"] := g

    g.SetFont("s10 w700", Theme.UiFont)
    Theme.RegisterControl(g, g.Add("Text", "xm w300", "Presenter Countdown Duration"), "Text")
    g.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(g, g.Add("Text", "xm y+6 w300", "Enter minutes (e.g. 12) or MM:SS (e.g. 07:30):"), "Text", "muted")
    defMin := Max(1, Round(Integer(defaultSec) / 60))
    edDur := g.Add("Edit", "xm y+8 w300", String(defMin))
    Theme.RegisterControl(g, edDur, "Edit")
    btnGo := g.Add("Button", "xm y+14 w144 h30 Default", "Start Timer")
    btnCan := g.Add("Button", "x+12 yp w144 h30", "Close")
    Theme.RegisterControl(g, btnGo, "Button", "accent")
    Theme.RegisterControl(g, btnCan, "Button")

    CloseDlg(*) {
        if (g._closed)
            return
        g._closed := true
        Theme.UnregisterWindow(g, "PresenterSync - Custom Timer")
        Theme.ReleaseSuspend()
        g.Destroy()
    }
    btnGo.OnEvent("Click", (*) => (sec := ParseDurationToSeconds(edDur.Value, defaultSec), IsObject(onStartFn) ? onStartFn.Call(sec) : 0, CloseDlg()))
    btnCan.OnEvent("Click", CloseDlg)
    g.OnEvent("Close", CloseDlg)
    g.OnEvent("Escape", CloseDlg)
    g.Show("AutoSize")
    return g
}

PromptSendStageNudgeUI(onSendFn) {
    existing := Theme.FocusExistingWindow("PresenterSync - Send Stage Nudge")
    if IsObject(existing)
        return existing
    Theme.AcquireSuspend()
    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync - Send Stage Nudge")
    g._closed := false
    g.MarginX := 20
    g.MarginY := 16
    Theme.ApplyToWindow(g)
    Theme.NamedWindows["PresenterSync - Send Stage Nudge"] := g

    g.SetFont("s10 w700", Theme.UiFont)
    Theme.RegisterControl(g, g.Add("Text", "xm w360", "Send Silent Stage Nudge Toast"), "Text")
    g.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(g, g.Add("Text", "xm y+6 w360", "Displays a non-blocking banner on connected presenter displays (no steal focus):"), "Text", "muted")

    CloseDlg(*) {
        if (g._closed)
            return
        g._closed := true
        Theme.UnregisterWindow(g, "PresenterSync - Send Stage Nudge")
        Theme.ReleaseSuspend()
        g.Destroy()
    }
    DispatchAndClose(msgText) {
        clean := Trim(String(msgText))
        if (clean != "" && IsObject(onSendFn))
            onSendFn.Call(clean)
        CloseDlg()
    }

    b1 := g.Add("Button", "xm y+10 w84 h28", "Slow Down")
    b2 := g.Add("Button", "x+8 yp w84 h28", "Check Chat")
    b3 := g.Add("Button", "x+8 yp w84 h28", "Wrap Up")
    b4 := g.Add("Button", "x+8 yp w84 h28", "Cam Live")
    for btn in [b1, b2, b3, b4]
        Theme.RegisterControl(g, btn, "Button")
    b1.OnEvent("Click", (*) => DispatchAndClose("Please slow down a touch"))
    b2.OnEvent("Click", (*) => DispatchAndClose("Check meeting chat question"))
    b3.OnEvent("Click", (*) => DispatchAndClose("2 minutes left — wrap up"))
    b4.OnEvent("Click", (*) => DispatchAndClose("Camera is LIVE"))

    edMsg := g.Add("Edit", "xm y+12 w360")
    Theme.RegisterControl(g, edMsg, "Edit")
    DllCall("SendMessage", "Ptr", edMsg.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "Type custom stage message...")
    btnSend := g.Add("Button", "xm y+12 w174 h30 Default", "Send Nudge")
    btnCan := g.Add("Button", "x+12 yp w174 h30", "Close")
    Theme.RegisterControl(g, btnSend, "Button", "accent")
    Theme.RegisterControl(g, btnCan, "Button")
    btnSend.OnEvent("Click", (*) => DispatchAndClose(edMsg.Value))
    btnCan.OnEvent("Click", CloseDlg)
    g.OnEvent("Close", CloseDlg)
    g.OnEvent("Escape", CloseDlg)
    g.Show("AutoSize")
    return g
}

BuildSharedPresenterTimerSubmenu(state, startFn, pauseFn, resetFn) {
    TimerMenu := Menu()
    tState := (IsObject(state) && state.HasOwnProp("timerState")) ? state.timerState : "stopped"
    tRem := (IsObject(state) && state.HasOwnProp("timerRemainingSec")) ? Integer(state.timerRemainingSec) : 600
    tPreset := (IsObject(state) && state.HasOwnProp("timerPresetSec")) ? Integer(state.timerPresetSec) : 600
    statusLabel := "Timer: " FormatCountdownClock(tRem) " (" StrUpper(tState) ")"
    TimerMenu.Add(statusLabel, (*) => 0)
    TimerMenu.Disable(statusLabel)
    TimerMenu.Add()
    for mins in [5, 10, 15, 45] {
        secVal := mins * 60
        TimerMenu.Add("Start " mins " min (" FormatCountdownClock(secVal) ")", startFn.Bind(secVal))
    }
    TimerMenu.Add("Start Custom Duration...", (*) => PromptCustomPresenterTimerUI(startFn, tPreset))
    TimerMenu.Add()
    TimerMenu.Add((tState = "paused" || tState = "stopped") ? "Resume / Start Timer" : "Pause Timer", pauseFn)
    TimerMenu.Add("Reset Timer", (*) => resetFn.Call(tPreset))
    return TimerMenu
}

SetHudColorPreset(cfg, state, presetName, *) {
    normalized := NormalizeHudColorPreset(presetName)
    cfg.HudColorPreset := normalized
    section := (cfg is Config) ? "Settings" : "Appearance"
    cfg.Write(section, "HudColorPreset", normalized)
    if (IsObject(state)) {
        cLive := cfg.HasOwnProp("CustomLiveHex") ? cfg.CustomLiveHex : "107C10"
        cMuted := cfg.HasOwnProp("CustomMutedHex") ? cfg.CustomMutedHex : "C42B1C"
        state.colors := UIConstants.GetColorPalette(normalized, cLive, cMuted)
        if (state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
            try state.refreshHudFn.Call()
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
    }
}

IsGuiValid(guiObj) {
    if (!IsObject(guiObj))
        return false
    try return (guiObj.Hwnd != 0 && DllCall("IsWindow", "Ptr", guiObj.Hwnd) != 0)
    catch
        return false
}

UpdateVoiceMeterTimer(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("voiceMeterTimerFn") || !state.voiceMeterTimerFn)
        return
    primValid := !IsHudSuppressed(cfg) && IsGuiValid(state.MicGui)
    secValid := !IsSecondaryHudSuppressed(cfg) && state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui)
    shouldRun := (primValid || secValid) && (!cfg.HasOwnProp("ShowVoiceMeter") || cfg.ShowVoiceMeter) && !state.isMuted
    if (shouldRun) {
        SetTimer(state.voiceMeterTimerFn, UIConstants.VOICE_METER_INTERVAL_MS)
    } else {
        SetTimer(state.voiceMeterTimerFn, 0)
        state.voicePeak := 0.0
    }
}

VoiceMeterTick(cfg, state, readerFn := "") {
    primValid := !IsHudSuppressed(cfg) && IsGuiValid(state.MicGui)
    secValid := !IsSecondaryHudSuppressed(cfg) && state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui)
    if ((!primValid && !secValid) || (cfg.HasOwnProp("ShowVoiceMeter") && !cfg.ShowVoiceMeter) || state.isMuted) {
        state.voicePeak := 0.0
        if (state.HasOwnProp("voiceMeterTimerFn") && state.voiceMeterTimerFn)
            SetTimer(state.voiceMeterTimerFn, 0)
        return
    }
    if (state.isDraggingHud || (state.HasOwnProp("isDraggingSecondaryHud") && state.isDraggingSecondaryHud))
        return
    rawPeak := IsObject(readerFn) ? Float(readerFn.Call()) : AudioMeter.GetPeak()
    rawPeak := Min(1.0, Max(0.0, rawPeak))
    ; Asymmetric exponential ballistics: fast attack, slow release.
    alphaAttack := 0.55, alphaRelease := 0.18
    cur := state.voicePeak
    if (rawPeak > cur)
        newPeak := cur + alphaAttack * (rawPeak - cur)
    else if (rawPeak < cur)
        newPeak := cur + alphaRelease * (rawPeak - cur)
    else
        newPeak := cur
    if (newPeak < 0.008)
        newPeak := 0.0
    newPeak := Min(1.0, Max(0.0, newPeak))
    if (Abs(newPeak - state.voicePeak) >= 0.004 || (newPeak == 0.0 && state.voicePeak > 0.0)) {
        state.voicePeak := newPeak
        if (primValid)
            ApplyMicAppearance(cfg, state)
        if (secValid)
            ApplySecondaryMicAppearance(cfg, state)
    }
}

ToggleVoiceMeter(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "ShowVoiceMeter")
    if (IsObject(state)) {
        if (!cfg.ShowVoiceMeter)
            state.voicePeak := 0.0
        UpdateVoiceMeterTimer(cfg, state)
        if (state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
            try state.refreshHudFn.Call()
    }
}

EvaluateMutedVoiceAlert(cfg, state, rawPeak, nowTick := "") {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (nowTick = "")
        nowTick := A_TickCount
    alertEnabled := (!cfg.HasOwnProp("EnableVoiceWhileMutedAlert") || cfg.EnableVoiceWhileMutedAlert)
    inStandby := (state.HasOwnProp("isStandby") && state.isStandby)
    if (!state.isMuted || !alertEnabled || inStandby) {
        wasWarn := state.HasOwnProp("voiceWhileMuted") ? state.voiceWhileMuted : false
        state.voiceWhileMuted := false
        state.mutedVoiceAboveSince := 0
        state.mutedVoiceQuietSince := 0
        return wasWarn != state.voiceWhileMuted
    }
    if (!state.HasOwnProp("voiceWhileMuted"))
        state.voiceWhileMuted := false
    if (!state.HasOwnProp("mutedVoiceAboveSince"))
        state.mutedVoiceAboveSince := 0
    if (!state.HasOwnProp("mutedVoiceQuietSince"))
        state.mutedVoiceQuietSince := 0

    if (rawPeak >= UIConstants.MUTED_VOICE_THRESHOLD) {
        state.mutedVoiceQuietSince := 0
        if (state.mutedVoiceAboveSince = 0)
            state.mutedVoiceAboveSince := nowTick
        if (!state.voiceWhileMuted && (nowTick - state.mutedVoiceAboveSince) >= UIConstants.MUTED_VOICE_TRIGGER_MS) {
            state.voiceWhileMuted := true
            if (IsSet(SessionTimeline) && (cfg is Config))
                SessionTimeline.Record("Alert", "Speaking-While-Muted Alert", state)
            return true
        }
    } else {
        state.mutedVoiceAboveSince := 0
        if (state.voiceWhileMuted) {
            if (state.mutedVoiceQuietSince = 0)
                state.mutedVoiceQuietSince := nowTick
            if ((nowTick - state.mutedVoiceQuietSince) >= UIConstants.MUTED_VOICE_CLEAR_MS) {
                state.voiceWhileMuted := false
                state.mutedVoiceQuietSince := 0
                return true
            }
        }
    }
    return false
}

UpdateMutedVoiceMonitorTimer(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("mutedVoiceTimerFn") || !state.mutedVoiceTimerFn)
        return
    alertEnabled := (!IsObject(cfg) || !cfg.HasOwnProp("EnableVoiceWhileMutedAlert") || cfg.EnableVoiceWhileMutedAlert)
    if (state.isMuted && alertEnabled) {
        SetTimer(state.mutedVoiceTimerFn, UIConstants.MUTED_VOICE_POLL_MS)
    } else {
        SetTimer(state.mutedVoiceTimerFn, 0)
        if (state.HasOwnProp("voiceWhileMuted") && state.voiceWhileMuted) {
            state.voiceWhileMuted := false
            state.mutedVoiceAboveSince := 0
            state.mutedVoiceQuietSince := 0
            _NotifyHostTelemetryChanged(cfg, state, true)
        }
    }
}

MutedVoiceMonitorTick(cfg, state, readerFn := "") {
    alertEnabled := (!IsObject(cfg) || !cfg.HasOwnProp("EnableVoiceWhileMutedAlert") || cfg.EnableVoiceWhileMutedAlert)
    if (!IsObject(state) || !state.isMuted || !alertEnabled) {
        if (IsObject(state) && state.HasOwnProp("mutedVoiceTimerFn") && state.mutedVoiceTimerFn)
            SetTimer(state.mutedVoiceTimerFn, 0)
        if (EvaluateMutedVoiceAlert(cfg, state, 0.0))
            _NotifyHostTelemetryChanged(cfg, state, true)
        return
    }
    if (state.HasOwnProp("isStandby") && state.isStandby) {
        if (EvaluateMutedVoiceAlert(cfg, state, 0.0))
            _NotifyHostTelemetryChanged(cfg, state, true)
        return
    }
    wasWarn := state.HasOwnProp("voiceWhileMuted") ? !!state.voiceWhileMuted : false
    newPeak := IsObject(readerFn) ? Float(readerFn.Call()) : AudioMeter.GetPeak()
    newPeak := Min(1.0, Max(0.0, newPeak))
    if (EvaluateMutedVoiceAlert(cfg, state, newPeak)) {
        _NotifyHostTelemetryChanged(cfg, state, true)
        if (!wasWarn && state.voiceWhileMuted && (!IsSet(g_IsTestMode) || !g_IsTestMode)) {
            nowTick := A_TickCount
            lastWarn := state.HasOwnProp("_lastPrimaryVoiceWarnTick") ? state._lastPrimaryVoiceWarnTick : 0
            if (lastWarn = 0 || (nowTick - lastWarn) >= 5000) {
                state._lastPrimaryVoiceWarnTick := nowTick
                if (IsSet(ShowStageNudgeBanner) && (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners)) {
                    ShowStageNudgeBanner("You're on mute — mic signal detected!", "F59E0B", 3200, "Mic Alert")
                } else {
                    if (IsSet(ShowCaptureSafeMicroToast))
                        ShowCaptureSafeMicroToast("⚠ You're on mute — mic signal detected!", 2800)
                }
            }
        }
    }
}

EvaluateOsMicDrift(cfg, state, osMuted, nowTick := "") {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (nowTick = "")
        nowTick := A_TickCount
    if (!state.HasOwnProp("osMicMutedDrift"))
        state.osMicMutedDrift := false
    if (!state.HasOwnProp("lastOsDriftWarnTick"))
        state.lastOsDriftWarnTick := 0

    watchdogEnabled := (!cfg.HasOwnProp("EnableOsMuteDriftWatchdog") || cfg.EnableOsMuteDriftWatchdog)
    appMuted := (state.HasOwnProp("isMuted") && state.isMuted)
    wasDrift := !!state.osMicMutedDrift

    if (!watchdogEnabled || appMuted || osMuted != true) {
        state.osMicMutedDrift := false
        if (wasDrift)
            _NotifyHostTelemetryChanged(cfg, state)
        return false
    }

    state.osMicMutedDrift := true
    nudgeTriggered := false
    if (state.lastOsDriftWarnTick = 0 || (nowTick - state.lastOsDriftWarnTick) >= 60000) {
        state.lastOsDriftWarnTick := nowTick
        nudgeTriggered := true
        _EmitWatchdogAlert(cfg, state, "Audio", "OsMicDriftDetected", "Windows OS capture mic muted while LIVE",
            "OS Mic Hardware/Privacy Mute Drift",
            "OS Mic Muted — Windows hardware/privacy switch is muting your mic while LIVE", "F59E0B", 5500, "Mic Guard")
    }
    if (!wasDrift || nudgeTriggered)
        _NotifyHostTelemetryChanged(cfg, state)
    return true
}

CoreAudioWatchdogTick(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (cfg.HasOwnProp("EnableOsMuteDriftWatchdog") && !cfg.EnableOsMuteDriftWatchdog) {
        if (state.HasOwnProp("osMicMutedDrift") && state.osMicMutedDrift)
            EvaluateOsMicDrift(cfg, state, false)
        return false
    }
    osMuted := IsSet(AudioMeter) ? AudioMeter.GetOsMicMute() : -1
    return EvaluateOsMicDrift(cfg, state, osMuted)
}

UpdateCoreAudioWatchdogTimer(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("coreAudioWatchdogFn") || !state.coreAudioWatchdogFn)
        return false
    enabled := IsObject(cfg) && (!cfg.HasOwnProp("EnableOsMuteDriftWatchdog") || cfg.EnableOsMuteDriftWatchdog)
    if (enabled) {
        SetTimer(state.coreAudioWatchdogFn, 1000)
        return true
    }
    SetTimer(state.coreAudioWatchdogFn, 0)
    if (state.HasOwnProp("osMicMutedDrift") && state.osMicMutedDrift)
        EvaluateOsMicDrift(cfg, state, false)
    return false
}

EvaluateForgottenRecordWatchdog(cfg, state, isSlideshowActive, nowTick := "") {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (nowTick = "")
        nowTick := A_TickCount
    if (!state.HasOwnProp("_forgotRecSinceTick"))
        state._forgotRecSinceTick := 0
    if (!state.HasOwnProp("_lastForgotRecWarnTick"))
        state._lastForgotRecWarnTick := 0

    enabled := (!cfg.HasOwnProp("EnableForgottenRecordWatchdog") || cfg.EnableForgottenRecordWatchdog)
    mode := cfg.HasOwnProp("AudioRoutingMode") ? Integer(cfg.AudioRoutingMode) : 0
    modeOk := (mode == 1 || mode == 3)
    micLive := !(state.HasOwnProp("isMuted") && state.isMuted)
    obsStopped := ((state.HasOwnProp("obsRecState") ? Integer(state.obsRecState) : 0) == 0)

    if (!enabled || !modeOk || !isSlideshowActive || !micLive || !obsStopped) {
        state._forgotRecSinceTick := 0
        return false
    }

    if (state._forgotRecSinceTick = 0)
        state._forgotRecSinceTick := nowTick
    if ((nowTick - state._forgotRecSinceTick) < 15000)
        return false

    if (state._lastForgotRecWarnTick = 0 || (nowTick - state._lastForgotRecWarnTick) >= 120000) {
        state._lastForgotRecWarnTick := nowTick
        _EmitWatchdogAlert(cfg, state, "Safety", "ForgottenRecordWarn", "Slideshow LIVE >=15s without OBS recording",
            "Forgotten Recording Reminder",
            "Slideshow LIVE without OBS Recording — Press Record if you meant to capture", "F59E0B", 5500, "Safety Guard")
        return true
    }
    return false
}

EvaluateStreamDropWatchdog(cfg, state, nowTick := "") {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (nowTick = "")
        nowTick := A_TickCount
    if (!state.HasOwnProp("streamDropWarn"))
        state.streamDropWarn := false
    if (!state.HasOwnProp("_streamDropSinceTick"))
        state._streamDropSinceTick := 0
    if (!state.HasOwnProp("_streamDropBackupTriggered"))
        state._streamDropBackupTriggered := false

    enabled := (!cfg.HasOwnProp("AutoRecordOnStreamDrop") || cfg.AutoRecordOnStreamDrop)
    isDropping := (state.HasOwnProp("streamState") && state.streamState == 2)
    obsStopped := ((state.HasOwnProp("obsRecState") ? Integer(state.obsRecState) : 0) == 0)
    wasWarn := !!state.streamDropWarn
    wasWatchdogActive := !!state._streamDropBackupTriggered

    if (!enabled || !isDropping) {
        state._streamDropSinceTick := 0
        state._streamDropBackupTriggered := false
        if (wasWatchdogActive) {
            state.streamDropWarn := false
            if (wasWarn)
                _NotifyHostTelemetryChanged(cfg, state)
        }
        return false
    }

    if (!obsStopped || state._streamDropBackupTriggered) {
        if (!obsStopped)
            state._streamDropSinceTick := 0
        return false
    }

    if (state._streamDropSinceTick = 0)
        state._streamDropSinceTick := nowTick
    if ((nowTick - state._streamDropSinceTick) < 10000)
        return false

    sent := (state.HasOwnProp("obsWs") && IsObject(state.obsWs)) ? SendObsRequest(state.obsWs, "StartRecord", "AutoBackupRecord") : false
    state._streamDropBackupTriggered := true
    state.streamDropWarn := true
    _EmitWatchdogAlert(cfg, state, "Safety", "StreamDropAutoBackup", "sent=" (sent ? "1" : "0"),
        "Stream-Drop Auto-Backup Recording Triggered",
        "Stream unstable — Auto-started local OBS backup recording", "F59E0B", 5500, "Safety Guard")
    _NotifyHostTelemetryChanged(cfg, state)
    return true
}

EvaluateLowDiskWatchdog(cfg, state, freeMb, nowTick := "") {
    if (!IsObject(cfg) || !IsObject(state))
        return 0
    if (nowTick = "")
        nowTick := A_TickCount
    if (!state.HasOwnProp("lowDiskMb"))
        state.lowDiskMb := -1
    if (!state.HasOwnProp("lowDiskWarnLevel"))
        state.lowDiskWarnLevel := 0
    if (!state.HasOwnProp("_lastLowDiskWarnTick"))
        state._lastLowDiskWarnTick := 0

    enabled := (!cfg.HasOwnProp("EnableLowDiskWatchdog") || cfg.EnableLowDiskWatchdog)
    prevLevel := Integer(state.lowDiskWarnLevel)

    if (!enabled || !IsNumber(freeMb) || Float(freeMb) < 0) {
        state.lowDiskMb := -1
        state.lowDiskWarnLevel := 0
        if (prevLevel != 0)
            _NotifyHostTelemetryChanged(cfg, state)
        return 0
    }

    mb := Integer(Round(Float(freeMb)))
    state.lowDiskMb := mb
    newLevel := (mb < 512) ? 2 : ((mb < 2048) ? 1 : 0)
    state.lowDiskWarnLevel := newLevel

    if (newLevel == 0) {
        if (prevLevel != 0)
            _NotifyHostTelemetryChanged(cfg, state)
        return 0
    }

    escalated := (newLevel > prevLevel)
    cooldownOk := (state._lastLowDiskWarnTick = 0 || (nowTick - state._lastLowDiskWarnTick) >= 60000)
    if (escalated || cooldownOk) {
        state._lastLowDiskWarnTick := nowTick
        msg := (newLevel == 2)
            ? ("CRITICAL Low Disk Space (" mb " MB free) — Recording drive nearly full!")
            : ("Low Disk Space (" mb " MB free) — Recording drive below 2 GB")
        accent := (newLevel == 2) ? "EF4444" : "F59E0B"
        _EmitWatchdogAlert(cfg, state, "Safety", "LowDiskWarn", "level=" newLevel " freeMb=" mb, msg, msg, accent, 5500, "Disk Guard")
        _NotifyHostTelemetryChanged(cfg, state, true)
    } else if (newLevel != prevLevel) {
        _NotifyHostTelemetryChanged(cfg, state)
    }
    return newLevel
}

EvaluateDeadMicWatchdog(cfg, state, peak, isPresenting, nowTick := "") {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (nowTick = "")
        nowTick := A_TickCount
    if (!state.HasOwnProp("deadMicWarn"))
        state.deadMicWarn := false
    if (!state.HasOwnProp("_deadMicSinceTick"))
        state._deadMicSinceTick := 0
    if (!state.HasOwnProp("_lastDeadMicWarnTick"))
        state._lastDeadMicWarnTick := 0

    enabled := (!cfg.HasOwnProp("EnableDeadMicWatchdog") || cfg.EnableDeadMicWatchdog)
    appMuted := (state.HasOwnProp("isMuted") && state.isMuted)
    silent := (IsNumber(peak) && Float(peak) < 0.005)
    wasWarn := !!state.deadMicWarn

    if (!enabled || appMuted || !isPresenting || !silent) {
        state._deadMicSinceTick := 0
        state.deadMicWarn := false
        if (wasWarn)
            _NotifyHostTelemetryChanged(cfg, state)
        return false
    }

    if (state._deadMicSinceTick = 0)
        state._deadMicSinceTick := nowTick
    if ((nowTick - state._deadMicSinceTick) < 45000)
        return false

    state.deadMicWarn := true
    nudgeFired := false
    if (state._lastDeadMicWarnTick = 0 || (nowTick - state._lastDeadMicWarnTick) >= 180000) {
        state._lastDeadMicWarnTick := nowTick
        nudgeFired := true
        _EmitWatchdogAlert(cfg, state, "Audio", "DeadMicWatchdog", "LIVE mic 0% audio detected for >=45s",
            "Dead-Mic Watchdog Alert",
            "Mic is LIVE but 0% audio detected for 45s — check hardware switch or input", "EF4444", 6000, "Mic Guard")
    }
    if (!wasWarn || nudgeFired)
        _NotifyHostTelemetryChanged(cfg, state)
    return true
}

SafetyWatchdogTick(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    nowTick := A_TickCount
    isSlideshow := WinExist("ahk_class screenClass ahk_exe POWERPNT.EXE") ? true : false
    if (isSlideshow || (state.HasOwnProp("slideIndex") && state.slideIndex > 0)) {
        prevSlideIdx := state.HasOwnProp("slideIndex") ? state.slideIndex : 0
        prevSlideTot := state.HasOwnProp("slideTotal") ? state.slideTotal : 0
        try PollPowerPointSlideTelemetry(state)
        if (state.slideIndex != prevSlideIdx || state.slideTotal != prevSlideTot)
            _NotifyHostTelemetryChanged(cfg, state)
    }
    obsConn := (state.HasOwnProp("obsConnected") && state.obsConnected)

    if (obsConn)
        EvaluateForgottenRecordWatchdog(cfg, state, isSlideshow, nowTick)
    else
        state._forgotRecSinceTick := 0

    EvaluateStreamDropWatchdog(cfg, state, nowTick)

    if ((!cfg.HasOwnProp("EnableLowDiskWatchdog") || cfg.EnableLowDiskWatchdog)
        && state.HasOwnProp("obsRecState") && state.obsRecState == 1) {
        if (!state.HasOwnProp("_lastLowDiskPollTick"))
            state._lastLowDiskPollTick := 0
        if (state._lastLowDiskPollTick = 0 || (nowTick - state._lastLowDiskPollTick) >= 30000) {
            state._lastLowDiskPollTick := nowTick
            recDir := (state.HasOwnProp("recordDirectory") && state.recordDirectory != "") ? state.recordDirectory : ""
            if (recDir = "" && obsConn && state.HasOwnProp("obsWs") && IsObject(state.obsWs))
                SendObsRequest(state.obsWs, "GetRecordDirectory", "InitRecordDir")
            if (recDir != "") {
                freeMb := -1
                try freeMb := DriveGetSpaceFree(recDir)
                EvaluateLowDiskWatchdog(cfg, state, freeMb, nowTick)
            }
        }
    } else {
        state._lastLowDiskPollTick := 0
        if (state.HasOwnProp("lowDiskWarnLevel") && state.lowDiskWarnLevel != 0)
            EvaluateLowDiskWatchdog(cfg, state, -1, nowTick)
    }

    isPresenting := isSlideshow
        || (state.HasOwnProp("recState") && state.recState == 1)
        || (state.HasOwnProp("streamState") && (state.streamState == 1 || state.streamState == 2))
        || (state.HasOwnProp("zoomConnected") && state.zoomConnected)
    if ((!cfg.HasOwnProp("EnableDeadMicWatchdog") || cfg.EnableDeadMicWatchdog)
        && (!state.HasOwnProp("isMuted") || !state.isMuted) && isPresenting) {
        livePeak := IsSet(AudioMeter) ? AudioMeter.GetPeak() : 0.0
        curPeak := state.HasOwnProp("voicePeak") ? Float(state.voicePeak) : 0.0
        EvaluateDeadMicWatchdog(cfg, state, Max(livePeak, curPeak), true, nowTick)
    } else {
        EvaluateDeadMicWatchdog(cfg, state, 0.0, false, nowTick)
    }
    return true
}

UpdateSafetyWatchdogTimer(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("safetyWatchdogFn") || !state.safetyWatchdogFn)
        return false
    enabled := IsObject(cfg) && (
        (!cfg.HasOwnProp("EnableForgottenRecordWatchdog") || cfg.EnableForgottenRecordWatchdog)
        || (!cfg.HasOwnProp("AutoRecordOnStreamDrop") || cfg.AutoRecordOnStreamDrop)
        || (!cfg.HasOwnProp("EnableLowDiskWatchdog") || cfg.EnableLowDiskWatchdog)
        || (!cfg.HasOwnProp("EnableDeadMicWatchdog") || cfg.EnableDeadMicWatchdog)
    )
    if (enabled) {
        SetTimer(state.safetyWatchdogFn, 1000)
        return true
    }
    SetTimer(state.safetyWatchdogFn, 0)
    state._forgotRecSinceTick := 0
    state._streamDropSinceTick := 0
    state._deadMicSinceTick := 0
    state.deadMicWarn := false
    if (state.HasOwnProp("lowDiskWarnLevel") && state.lowDiskWarnLevel != 0)
        EvaluateLowDiskWatchdog(cfg, state, -1)
    return false
}

ArmHostOptimisticReconcile(cfg, state, delayMs := 300) {
    if (!IsObject(state))
        return
    if (!state.HasOwnProp("_optimisticTimerFn") || !IsObject(state._optimisticTimerFn))
        state._optimisticTimerFn := _ReconcileHostOptimisticMute.Bind(cfg, state)
    try SetTimer(state._optimisticTimerFn, -Max(50, Integer(delayMs)))
}

CancelHostOptimisticReconcile(state) {
    if (!IsObject(state))
        return
    state._optimisticMutePending := false
    if (state.HasOwnProp("_optimisticTimerFn") && IsObject(state._optimisticTimerFn))
        try SetTimer(state._optimisticTimerFn, 0)
}

_ReconcileHostOptimisticMute(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("_optimisticMutePending") || !state._optimisticMutePending)
        return
    if (IsObject(state.obsWs) && state.HasOwnProp("obsConnected") && state.obsConnected && IsSet(SendObsRequest) && IsObject(cfg)) {
        escMic := IsSet(EscapeJsonStr) ? EscapeJsonStr(cfg.HasOwnProp("targetMicName") ? cfg.targetMicName : "Mic/Aux") : "Mic/Aux"
        SendObsRequest(state.obsWs, "GetInputMute", "ReconcileObsMute", '{"inputName":"' escMic '"}')
    } else {
        state._optimisticMutePending := false
    }
}

SyncUIState(cfg, state, obsIsMuted, isOptimistic := false) {
    if (isOptimistic) {
        state._optimisticMutePending := true
        changedOpt := (state.isMuted != obsIsMuted)
        if (changedOpt) {
            state.isMuted := obsIsMuted
            cfg.IsMuted := obsIsMuted
            if (!obsIsMuted) {
                state.voiceWhileMuted := false
                state.mutedVoiceAboveSince := 0
                state.mutedVoiceQuietSince := 0
            } else {
                if (state.HasOwnProp("osMicMutedDrift") && state.osMicMutedDrift)
                    state.osMicMutedDrift := false
                if (state.HasOwnProp("deadMicWarn") && state.deadMicWarn)
                    state.deadMicWarn := false
                state._deadMicSinceTick := 0
            }
            PlayMuteAnimation(cfg, state)
            UpdateVoiceMeterTimer(cfg, state)
            UpdateMutedVoiceMonitorTimer(cfg, state)
        }
        ArmHostOptimisticReconcile(cfg, state, 300)
        return
    }

    wasOptimistic := (state.HasOwnProp("_optimisticMutePending") && state._optimisticMutePending)
    CancelHostOptimisticReconcile(state)
    stateChanged := (state.isMuted != obsIsMuted)
    if (stateChanged || wasOptimistic) {
        state.isMuted := obsIsMuted
        cfg.IsMuted := obsIsMuted
        if (cfg.HasMethod("WriteBoolDeferred"))
            cfg.WriteBoolDeferred("Settings", "IsMuted", state.isMuted, 250)
        else
            cfg.WriteBool("Settings", "IsMuted", state.isMuted)
        if (!obsIsMuted) {
            state.voiceWhileMuted := false
            state.mutedVoiceAboveSince := 0
            state.mutedVoiceQuietSince := 0
        } else {
            if (state.HasOwnProp("osMicMutedDrift") && state.osMicMutedDrift)
                state.osMicMutedDrift := false
            if (state.HasOwnProp("deadMicWarn") && state.deadMicWarn)
                state.deadMicWarn := false
            state._deadMicSinceTick := 0
        }
        BroadcastHostRelayMuteState(cfg, state)
        if (stateChanged) {
            PlayMuteAnimation(cfg, state)
            UpdateVoiceMeterTimer(cfg, state)
            UpdateMutedVoiceMonitorTimer(cfg, state)
        }
        if (cfg.HasOwnProp("EnableAudioCue") && cfg.EnableAudioCue)
            PlayMuteAudioCue(obsIsMuted)
        if (cfg.HasOwnProp("EnableMuteToast") && cfg.EnableMuteToast)
            ShowMuteToast(obsIsMuted)
        if (IsSet(SessionTimeline) && (cfg is Config))
            SessionTimeline.Record("Mic", obsIsMuted ? "Mic Muted" : "Mic Live", state, cfg.targetMicName, -1, "", true)
    }
}

; --- HUD APPEARANCE & CONFIG HELPERS ---
RefreshHudAppearance(cfg, state) {
    state.animSeq += 1
    state.baseAlpha := cfg.OpacityLevel
    state._breathStepAlpha := cfg.OpacityLevel
    state.currentAlpha := (state.HasOwnProp("isAutoDodged") && state.isAutoDodged) ? Min(cfg.OpacityLevel, UIConstants.DODGE_ALPHA) : cfg.OpacityLevel
    state.secondaryCurrentAlpha := (state.HasOwnProp("secondaryIsAutoDodged") && state.secondaryIsAutoDodged) ? Min(cfg.OpacityLevel, UIConstants.DODGE_ALPHA) : cfg.OpacityLevel
    state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
    state.ComputeDimensions(cfg)
    UpdateHudLayout(state, state.savedX, state.savedY)
    UpdateHudVisibility(cfg, state)
    ApplyHudCaptureExclusion(cfg, state)
    if (IsAnyMicHudVisible(cfg) && state.isMuted)
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    else
        SetTimer state.breathTimerFn, 0
}

SetThemeMode(cfg, themeMenu, mode, *) {
    cfg.ThemeMode := mode
    cfg.Write((cfg is Config) ? "Settings" : "Appearance", "ThemeMode", mode)
    if IsObject(themeMenu) {
        themeMenu.Uncheck("Follow System")
        themeMenu.Uncheck("Dark Mode")
        themeMenu.Uncheck("Light Mode")
        if (mode = "Dark")
            themeMenu.Check("Dark Mode")
        else if (mode = "Light")
            themeMenu.Check("Light Mode")
        else
            themeMenu.Check("Follow System")
    }
    Theme.SetMode(mode)
}

SetScale(cfg, state, val, *) {
    cfg.IndicatorScale := val
    cfg.Write("Settings", "IndicatorScale", val)
    if IsObject(state)
        RefreshHudAppearance(cfg, state)
}

ResetAppearance(cfg, state := "", *) {
    cfg.ResetAppearance()
    if IsObject(state)
        RefreshHudAppearance(cfg, state)
}

ResetSettings(cfg, *) {
    cfg.DeleteFile()
    Reload()
}

ResetTrayPosition(cfg, state := "", *) {
    cfg.ResetPosition()
    if IsObject(state)
        RefreshHudAppearance(cfg, state)
}

ToggleSecondaryMicHud(cfg, state := "", *) {
    cfg.ShowSecondaryMicHud := !cfg.ShowSecondaryMicHud
    cfg.WriteBool("Settings", "ShowSecondaryMicHud", cfg.ShowSecondaryMicHud)
    if (IsObject(state)) {
        UpdateHudVisibility(cfg, state)
        ApplyHudCaptureExclusion(cfg, state)
        if (state.HasOwnProp("breathTimerFn") && state.breathTimerFn) {
            if (IsAnyMicHudVisible(cfg) && state.isMuted)
                SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
            else
                SetTimer state.breathTimerFn, 0
        }
    }
}

ResetSecondaryTrayPosition(cfg, state := "", *) {
    cfg.ResetSecondaryPosition()
    if IsObject(state)
        RefreshHudAppearance(cfg, state)
}

; --- MAGNETIC SNAP, CLICK-THROUGH & AUTO-DODGE ---
GetHudGuiList(state, includeSecondary := true) {
    guis := []
    if (!IsObject(state))
        return guis
    for _, prop in _GetHudGuiPropNames(includeSecondary) {
        if (state.HasOwnProp(prop) && IsGuiValid(state.%prop%))
            guis.Push(state.%prop%)
    }
    return guis
}

GetHudTierFlags(cfg) {
    ; Which extra HUD tiers (Row2 REC/CHAT, Row3 STUDIO/SCENE, Row4 STREAM/VCAM) are enabled.
    ; Without a cfg object every tier is assumed enabled (legacy layout).
    if (!IsObject(cfg))
        return { row2: true, row3: true, row4: true }
    showExtra := cfg.HasOwnProp("ShowExtraHuds") ? !!cfg.ShowExtraHuds : true
    r2Flag := (!cfg.HasOwnProp("ShowRow2RecChatHud") || cfg.ShowRow2RecChatHud)
    r3Flag := (!cfg.HasOwnProp("ShowRow3StudioSceneHud") || cfg.ShowRow3StudioSceneHud)
    strmFlag := (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud)
    enableWS := cfg.HasOwnProp("EnableWS") ? !!cfg.EnableWS : true
    enableZoom := cfg.HasOwnProp("EnableZoom") ? !!cfg.EnableZoom : false
    return {
        row2: !!(showExtra && (enableWS || enableZoom) && r2Flag),
        row3: !!(showExtra && enableWS && r3Flag),
        row4: !!(showExtra && enableWS && strmFlag)
    }
}

GetHudStackBounds(cfg, state) {
    extraTopPad := 0
    if (IsObject(cfg) && (cfg is Config)) {
        t := GetHudTierFlags(cfg)
        extraTopPad := (t.row2 ? (state.recHeight + state.hudGap) : 0) + (t.row3 ? (state.row3Height + state.hudGap) : 0) + (t.row4 ? (state.row4Height + state.hudGap) : 0)
    }
    return {
        left: state.savedX,
        top: state.savedY - extraTopPad,
        right: state.savedX + state.baseWidth,
        bottom: state.savedY + state.baseHeight,
        extraTopPad: extraTopPad,
        stackW: state.baseWidth
    }
}

GetCandidateSnapWindowRects(state := "") {
    rects := []
    hudHwnds := Map()
    for g in GetHudGuiList(state)
        hudHwnds[g.Hwnd] := true
    static targetProcs := Map(
        "obs64.exe", true, "obs32.exe", true, "powerpnt.exe", true,
        "zoom.exe", true, "ms-teams.exe", true, "teams.exe", true,
        "chrome.exe", true, "msedge.exe", true, "firefox.exe", true, "brave.exe", true
    )
    for hwnd in WinGetList() {
        if (hudHwnds.Has(hwnd) || !DllCall("IsWindowVisible", "Ptr", hwnd))
            continue
        try {
            if (WinGetMinMax("ahk_id " hwnd) == -1)
                continue
            proc := StrLower(WinGetProcessName("ahk_id " hwnd))
            if (!targetProcs.Has(proc))
                continue
            buf := Buffer(16, 0)
            if (DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", buf.Ptr, "UInt", 16, "Int") == 0) {
                rl := NumGet(buf, 0, "Int"), rt := NumGet(buf, 4, "Int")
                rr := NumGet(buf, 8, "Int"), rb := NumGet(buf, 12, "Int")
            } else {
                WinGetPos(&rl, &rt, &rw, &rh, "ahk_id " hwnd)
                rr := rl + rw, rb := rt + rh
            }
            if ((rr - rl) >= 120 && (rb - rt) >= 80)
                rects.Push({ left: rl, top: rt, right: rr, bottom: rb })
        }
    }
    return rects
}

ComputeMagneticSnap(rawX, rawY, stackW, baseH, extraTopPad := 0, threshold := 14, candidateRects := "", workArea := "") {
    if (!IsObject(workArea)) {
        cx := rawX + (stackW // 2), cy := rawY + (baseH // 2)
        waIdx := 1
        monCount := MonitorGetCount()
        Loop monCount {
            MonitorGetWorkArea(A_Index, &mL, &mT, &mR, &mB)
            if (cx >= mL && cx <= mR && cy >= mT && cy <= mB) {
                waIdx := A_Index
                break
            }
        }
        MonitorGetWorkArea(waIdx, &waL, &waT, &waR, &waB)
        workArea := { left: waL, top: waT, right: waR, bottom: waB }
    }

    pad := UIConstants.SCREEN_MIN_PAD
    xTargets := [workArea.left + pad, workArea.right - pad - stackW]
    yTargets := [workArea.top + extraTopPad + pad, workArea.bottom - pad - baseH]

    if (IsObject(candidateRects)) {
        for r in candidateRects {
            xTargets.Push(r.left, r.left - stackW - 6, r.right - stackW - 6, r.right + 6)
            yTargets.Push(r.top + extraTopPad, r.bottom - baseH)
        }
    }

    bestX := rawX, bestDx := threshold + 1, didSnapX := false
    for tx in xTargets {
        dx := Abs(tx - rawX)
        if (dx <= threshold && dx < bestDx) {
            bestDx := dx
            bestX := tx
            didSnapX := true
        }
    }

    bestY := rawY, bestDy := threshold + 1, didSnapY := false
    for ty in yTargets {
        dy := Abs(ty - rawY)
        if (dy <= threshold && dy < bestDy) {
            bestDy := dy
            bestY := ty
            didSnapY := true
        }
    }

    bestX := Max(workArea.left, Min(bestX, workArea.right - stackW))
    bestY := Max(workArea.top + extraTopPad, Min(bestY, workArea.bottom - baseH))
    return { x: Round(bestX), y: Round(bestY), snappedX: didSnapX, snappedY: didSnapY }
}

ApplyHudClickThroughStyle(cfg, state, forceClickThrough := -1) {
    altHeld := GetKeyState("Alt", "P")
    clickThruCfg := (cfg.HasOwnProp("HudClickThrough") && cfg.HudClickThrough)
    wantPassThrough := (forceClickThrough != -1)
        ? !!forceClickThrough
        : ((clickThruCfg || (state.HasOwnProp("isAutoDodged") && state.isAutoDodged)) && !altHeld)
    styleFlag := wantPassThrough ? "+0x20" : "-0x20"
    secPassThrough := (forceClickThrough != -1)
        ? !!forceClickThrough
        : ((clickThruCfg || (state.HasOwnProp("secondaryIsAutoDodged") && state.secondaryIsAutoDodged)) && !altHeld)
    secFlag := secPassThrough ? "+0x20" : "-0x20"

    prevDhw := DetectHiddenWindows(true)
    try {
        for g in GetHudGuiList(state, false) {
            try WinSetExStyle(styleFlag, "ahk_id " g.Hwnd)
        }
        if (IsObject(state) && state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui)) {
            try WinSetExStyle(secFlag, "ahk_id " state.SecondaryMicGui.Hwnd)
        }
    } finally {
        DetectHiddenWindows(prevDhw)
    }
    return wantPassThrough
}

UpdateAutoDodgeTimer(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("autoDodgeTimerFn") || !state.autoDodgeTimerFn)
        return
    primActive := !IsHudSuppressed(cfg) && IsGuiValid(state.MicGui)
    secActive := !IsSecondaryHudSuppressed(cfg) && state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui)
    needPoll := (primActive || secActive)
        && ((cfg.HasOwnProp("HudAutoDodge") && cfg.HudAutoDodge) || (cfg.HasOwnProp("HudClickThrough") && cfg.HudClickThrough))
    SetTimer(state.autoDodgeTimerFn, needPoll ? UIConstants.DODGE_POLL_INTERVAL_MS : 0)
    if (!needPoll) {
        if (state.HasOwnProp("isAutoDodged") && state.isAutoDodged) {
            state.isAutoDodged := false
            state.currentAlpha := state.baseAlpha
            ApplyHudClickThroughStyle(cfg, state)
            for g in GetHudGuiList(state, false)
                Gdip.SetLayeredAlpha(g.Hwnd, state.currentAlpha)
        }
        if (state.HasOwnProp("secondaryIsAutoDodged") && state.secondaryIsAutoDodged) {
            state.secondaryIsAutoDodged := false
            state.secondaryCurrentAlpha := state.baseAlpha
            ApplyHudClickThroughStyle(cfg, state)
            if (state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui))
                Gdip.SetLayeredAlpha(state.SecondaryMicGui.Hwnd, state.secondaryCurrentAlpha)
        }
    }
}

AutoDodgeTick(cfg, state, cursorPos := "", altHeldOverride := -1) {
    if (!IsObject(state) || !IsAnyMicHudVisible(cfg))
        return
    altHeld := (altHeldOverride != -1) ? !!altHeldOverride : GetKeyState("Alt", "P")
    dodgeEnabled := (cfg.HasOwnProp("HudAutoDodge") && cfg.HudAutoDodge)
    clickThroughEnabled := (cfg.HasOwnProp("HudClickThrough") && cfg.HudClickThrough)

    mx := 0, my := 0, haveCursor := false
    if (dodgeEnabled) {
        if (IsObject(cursorPos)) {
            mx := cursorPos.x, my := cursorPos.y, haveCursor := true
        } else {
            pt := Buffer(8, 0)
            if DllCall("GetCursorPos", "Ptr", pt, "Int")
                mx := NumGet(pt, 0, "Int"), my := NumGet(pt, 4, "Int"), haveCursor := true
        }
    }

    primChanged := false
    if (dodgeEnabled && haveCursor && IsGuiValid(state.MicGui) && !IsHudSuppressed(cfg) && !state.isDraggingHud) {
        bounds := GetHudStackBounds(cfg, state)
        inside := (mx >= bounds.left && mx <= bounds.right && my >= bounds.top && my <= bounds.bottom)
        wantDodged := inside && !altHeld
        if (wantDodged != state.isAutoDodged) {
            state.isAutoDodged := wantDodged
            baseLvl := state.HasOwnProp("_breathStepAlpha") ? state._breathStepAlpha : state.baseAlpha
            state.currentAlpha := wantDodged ? Min(baseLvl, UIConstants.DODGE_ALPHA) : baseLvl
            for g in GetHudGuiList(state, false)
                Gdip.SetLayeredAlpha(g.Hwnd, state.currentAlpha)
            primChanged := true
        }
    }

    secChanged := false
    if (dodgeEnabled && haveCursor && state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui) && !IsSecondaryHudSuppressed(cfg) && !state.isDraggingSecondaryHud) {
        secPos := ComputeSecondaryMicLayout(cfg, state)
        secInside := (mx >= secPos.x && mx <= (secPos.x + secPos.w) && my >= secPos.y && my <= (secPos.y + secPos.h))
        wantSecDodged := secInside && !altHeld
        if (wantSecDodged != state.secondaryIsAutoDodged) {
            state.secondaryIsAutoDodged := wantSecDodged
            baseLvl := state.HasOwnProp("_breathStepAlpha") ? state._breathStepAlpha : state.baseAlpha
            state.secondaryCurrentAlpha := wantSecDodged ? Min(baseLvl, UIConstants.DODGE_ALPHA) : baseLvl
            Gdip.SetLayeredAlpha(state.SecondaryMicGui.Hwnd, state.secondaryCurrentAlpha)
            secChanged := true
        }
    }

    if (primChanged || secChanged || clickThroughEnabled)
        ApplyHudClickThroughStyle(cfg, state)
}

ToggleMagneticSnap(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "EnableMagneticSnap")
}

ToggleHudClickThrough(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "HudClickThrough")
    if (IsObject(state)) {
        ApplyHudClickThroughStyle(cfg, state)
        UpdateAutoDodgeTimer(cfg, state)
        if (state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
            try state.refreshHudFn.Call()
    }
    if (IsObject(cfg) && cfg.HasOwnProp("HudClickThrough") && cfg.HudClickThrough && IsSet(ShowCaptureSafeMicroToast) && (!IsSet(g_IsTestMode) || !g_IsTestMode)) {
        hwnd := (IsObject(state) && state.HasOwnProp("MicGui") && IsObject(state.MicGui)) ? state.MicGui.Hwnd : 0
        ShowCaptureSafeMicroToast("Click-Through Active — Hold Alt / Unlock via Tray", 4000, hwnd)
    }
}

ToggleHudAutoDodge(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "HudAutoDodge")
    if (IsObject(state)) {
        if (!cfg.HudAutoDodge && state.isAutoDodged) {
            state.isAutoDodged := false
            state.currentAlpha := state.baseAlpha
        }
        UpdateAutoDodgeTimer(cfg, state)
        ApplyHudClickThroughStyle(cfg, state)
        if (state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
            try state.refreshHudFn.Call()
    }
}

; --- HUD CREATION, LAYOUT & STYLING ---
ApplyWindowCaptureAffinity(hwnd, exclude := true) {
    if (!hwnd)
        return false
    if (IsSet(ProtectWindowFromCapture))
        return ProtectWindowFromCapture(hwnd, exclude)
    try return !!DllCall("user32\SetWindowDisplayAffinity", "Ptr", hwnd, "UInt", exclude ? 0x00000011 : 0x00000000, "Int")
    catch
        return false
}

ApplyHudCaptureExclusion(cfg, state) {
    if (!IsObject(state))
        return
    exclPrim := (IsObject(cfg) && cfg.HasOwnProp("ExcludeFromCapture")) ? !!cfg.ExcludeFromCapture : true
    exclSec := (IsObject(cfg) && cfg.HasOwnProp("ExcludeSecondaryFromCapture")) ? !!cfg.ExcludeSecondaryFromCapture : true
    for _, g in GetHudGuiList(state, false)
        ApplyWindowCaptureAffinity(g.Hwnd, exclPrim)
    if (state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui))
        ApplyWindowCaptureAffinity(state.SecondaryMicGui.Hwnd, exclSec)
}

InitHUD(cfg, state, showWindows := true) {
    Gdip.Startup()
    state.ComputeDimensions(cfg)

    ; Create 7 Primary GDI+ WS_EX_LAYERED (+E0x80000) HUD windows + 1 Independent Secondary Mic Pill
    for _, guiKey in _GetHudGuiPropNames(true)
        state.%guiKey% := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    ApplyHudCaptureExclusion(cfg, state)

    RenderAllHudPills(cfg, state)

    if (showWindows) {
        UpdateHudVisibility(cfg, state)
        if (IsAnyMicHudVisible(cfg) && state.isMuted)
            SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    }
    ApplyHudClickThroughStyle(cfg, state)
    UpdateAutoDodgeTimer(cfg, state)
    UpdateMutedVoiceMonitorTimer(cfg, state)

    OnMessage(0x0003, WM_HUD_MOVE.Bind(state))
    OnMessage(0x0201, WM_LBUTTONDOWN.Bind(cfg, state))
    OnMessage(0x0203, WM_LBUTTONDBLCLK.Bind(state))
    OnMessage(0x0205, WM_RBUTTONUP.Bind(state))
    OnMessage(0x02E0, WM_DPICHANGED.Bind(state))
    OnMessage(0x007E, WM_DISPLAYCHANGE.Bind(cfg, state))
}

ComputeHudLayout(state, anchorX, anchorY, cfg := "") {
    if (!IsObject(cfg) && state.HasProp("hudCfg") && IsObject(state.hudCfg))
        cfg := state.hudCfg
    tiers := GetHudTierFlags(cfg)
    recH := state.HasProp("recHeight") ? state.recHeight : 34
    gap := state.HasProp("hudGap") ? state.hudGap : 6
    r3H := state.HasProp("row3Height") ? state.row3Height : 30
    r4H := state.HasProp("row4Height") ? state.row4Height : 26
    recW := state.HasProp("recW") ? state.recW : 40
    chatW := state.HasProp("chatW") ? state.chatW : 34
    stuW := state.HasProp("studioW") ? state.studioW : 28
    scnW := state.HasProp("sceneW") ? state.sceneW : 46
    strmW := state.HasProp("streamW") ? state.streamW : 40
    vcW := state.HasProp("vcamW") ? state.vcamW : 34
    ; Gapless stacking: only enabled tiers consume vertical space above Tier 1 (MicGui).
    cursorY := anchorY
    recY := cursorY - recH - gap
    if (tiers.row2)
        cursorY := recY
    row3Y := cursorY - r3H - gap
    if (tiers.row3)
        cursorY := row3Y
    row4Y := cursorY - r4H - gap
    return {
        micX: anchorX,
        micY: anchorY,
        micW: state.baseWidth,
        micH: state.baseHeight,
        recX: anchorX,
        recY: recY,
        recW: recW,
        recH: recH,
        chatX: anchorX + recW + gap,
        chatY: recY,
        chatW: chatW,
        chatH: recH,
        studioX: anchorX,
        studioY: row3Y,
        studioW: stuW,
        studioH: r3H,
        sceneX: anchorX + stuW + gap,
        sceneY: row3Y,
        sceneW: scnW,
        sceneH: r3H,
        streamX: anchorX,
        streamY: row4Y,
        streamW: strmW,
        streamH: r4H,
        vcamX: anchorX + strmW + gap,
        vcamY: row4Y,
        vcamW: vcW,
        vcamH: r4H
    }
}

UpdateHudLayout(state, anchorX := "", anchorY := "", skipHwnd := 0) {
    if (anchorX = "" || anchorY = "") {
        if (IsObject(state.MicGui) && DllCall("IsWindowVisible", "Ptr", state.MicGui.Hwnd))
            try WinGetPos(&anchorX, &anchorY,,, state.MicGui.Hwnd)
        if (anchorX = "" || anchorY = "")
            anchorX := state.savedX, anchorY := state.savedY
    }
    state.savedX := anchorX, state.savedY := anchorY
    pos := ComputeHudLayout(state, anchorX, anchorY)
    if (IsObject(state.MicGui) && state.MicGui.Hwnd != skipHwnd)
        state.MicGui.Move(pos.micX, pos.micY, pos.micW, pos.micH)
    if (IsObject(state.RecGui) && state.RecGui.Hwnd != skipHwnd)
        state.RecGui.Move(pos.recX, pos.recY, pos.recW, pos.recH)
    if (IsObject(state.ChatGui) && state.ChatGui.Hwnd != skipHwnd)
        state.ChatGui.Move(pos.chatX, pos.chatY, pos.chatW, pos.chatH)
    if (IsObject(state.StudioGui) && state.StudioGui.Hwnd != skipHwnd)
        state.StudioGui.Move(pos.studioX, pos.studioY, pos.studioW, pos.studioH)
    if (IsObject(state.SceneGui) && state.SceneGui.Hwnd != skipHwnd)
        state.SceneGui.Move(pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH)
    if (IsObject(state.StreamGui) && state.StreamGui.Hwnd != skipHwnd)
        state.StreamGui.Move(pos.streamX, pos.streamY, pos.streamW, pos.streamH)
    if (IsObject(state.VCamGui) && state.VCamGui.Hwnd != skipHwnd)
        state.VCamGui.Move(pos.vcamX, pos.vcamY, pos.vcamW, pos.vcamH)
}

_SyncSecondaryHudVisibility(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("SecondaryMicGui") || !IsGuiValid(state.SecondaryMicGui))
        return
    if (IsSecondaryHudSuppressed(cfg)) {
        try state.SecondaryMicGui.Hide()
        return
    }
    state.secondaryCurrentAlpha := (state.HasOwnProp("secondaryIsAutoDodged") && state.secondaryIsAutoDodged)
        ? Min(state.baseAlpha, UIConstants.DODGE_ALPHA)
        : state.baseAlpha
    secPos := ComputeSecondaryMicLayout(cfg, state)
    ApplySecondaryMicAppearance(cfg, state)
    state.SecondaryMicGui.Show(Format("NoActivate x{} y{} w{} h{}", secPos.x, secPos.y, secPos.w, secPos.h))
}

UpdateHudVisibility(cfg, state) {
    state.animSeq += 1
    if (IsHudSuppressed(cfg) || ShouldHideForMutedOrAlertMode(cfg, state)) {
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        if IsObject(state.MicGui)
            state.MicGui.Hide()
        if IsObject(state.RecGui)
            state.RecGui.Hide()
        if IsObject(state.ChatGui)
            state.ChatGui.Hide()
        if IsObject(state.StudioGui)
            state.StudioGui.Hide()
        if IsObject(state.SceneGui)
            state.SceneGui.Hide()
        if IsObject(state.StreamGui)
            state.StreamGui.Hide()
        if IsObject(state.VCamGui)
            state.VCamGui.Hide()
        _SyncSecondaryHudVisibility(cfg, state)
        ApplyHudClickThroughStyle(cfg, state)
        UpdateVoiceMeterTimer(cfg, state)
        UpdateAutoDodgeTimer(cfg, state)
        UpdateMutedVoiceMonitorTimer(cfg, state)
        return
    }

    state.currentAlpha := (state.HasOwnProp("isAutoDodged") && state.isAutoDodged) ? Min(state.baseAlpha, UIConstants.DODGE_ALPHA) : state.baseAlpha
    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    if IsObject(state.MicGui) {
        ApplyMicAppearance(cfg, state)
        state.MicGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.micX, pos.micY, pos.micW, pos.micH))
    }
    _SyncSecondaryHudVisibility(cfg, state)
    UpdateVoiceMeterTimer(cfg, state)

    tiers := GetHudTierFlags(cfg)
    if (tiers.row2) {
        ApplyRecAppearance(cfg, state)
        state.RecGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.recX, pos.recY, pos.recW, pos.recH))
        ApplyChatAppearance(cfg, state)
        state.ChatGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.chatX, pos.chatY, pos.chatW, pos.chatH))
    } else {
        state.RecGui.Hide()
        state.ChatGui.Hide()
    }

    if (tiers.row3) {
        ApplyStudioAppearance(cfg, state)
        state.StudioGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.studioX, pos.studioY, pos.studioW, pos.studioH))
        ApplySceneAppearance(cfg, state)
        state.SceneGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH))
    } else {
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        state.StudioGui.Hide()
        state.SceneGui.Hide()
    }

    if (tiers.row4) {
        ApplyStreamAppearance(cfg, state)
        if IsObject(state.StreamGui)
            state.StreamGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.streamX, pos.streamY, pos.streamW, pos.streamH))
        ApplyVCamAppearance(cfg, state)
        if IsObject(state.VCamGui)
            state.VCamGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.vcamX, pos.vcamY, pos.vcamW, pos.vcamH))
    } else {
        if IsObject(state.StreamGui)
            state.StreamGui.Hide()
        if IsObject(state.VCamGui)
            state.VCamGui.Hide()
    }    ApplyHudClickThroughStyle(cfg, state)
    UpdateAutoDodgeTimer(cfg, state)
    UpdateMutedVoiceMonitorTimer(cfg, state)
}

; --- HUD ANIMATIONS ---
_StepMuteAnimation(state) {
    if (!IsObject(state) || !state.HasOwnProp("_muteAnimCfg") || !IsObject(state._muteAnimCfg)) {
        if (IsObject(state) && state.HasOwnProp("_muteAnimTimerFn") && IsObject(state._muteAnimTimerFn))
            try SetTimer(state._muteAnimTimerFn, 0)
        return
    }
    cfg := state._muteAnimCfg
    mySeq := state.HasOwnProp("_muteAnimSeq") ? state._muteAnimSeq : -1
    if (state.animSeq != mySeq || state.isDraggingHud || (state.HasOwnProp("isDraggingSecondaryHud") && state.isDraggingSecondaryHud) || !IsAnyMicHudVisible(cfg)) {
        if (state.HasOwnProp("_muteAnimTimerFn") && IsObject(state._muteAnimTimerFn))
            try SetTimer(state._muteAnimTimerFn, 0)
        return
    }

    hasPrimGui := state.HasOwnProp("MicGui") && IsGuiValid(state.MicGui)
    hasSecGui := state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui)
    primVis := hasPrimGui && !IsHudSuppressed(cfg)
    secVis := hasSecGui && !IsSecondaryHudSuppressed(cfg)
    if (!primVis && !secVis) {
        if (state.HasOwnProp("_muteAnimTimerFn") && IsObject(state._muteAnimTimerFn))
            try SetTimer(state._muteAnimTimerFn, 0)
        return
    }

    dur := Max(1, state.HasOwnProp("_muteAnimDurationMs") ? Integer(state._muteAnimDurationMs) : 120)
    elapsed := Max(0, A_TickCount - state._muteAnimStartTick)
    t := Min(1.0, Float(elapsed) / Float(dur))

    targetPrimAlpha := (state.HasOwnProp("isAutoDodged") && state.isAutoDodged) ? Min(state.baseAlpha, UIConstants.DODGE_ALPHA) : state.baseAlpha
    targetSecAlpha := (state.HasOwnProp("secondaryIsAutoDodged") && state.secondaryIsAutoDodged) ? Min(state.baseAlpha, UIConstants.DODGE_ALPHA) : state.baseAlpha

    if (t >= 1.0) {
        if (state.HasOwnProp("_muteAnimTimerFn") && IsObject(state._muteAnimTimerFn))
            try SetTimer(state._muteAnimTimerFn, 0)
        state._breathStepAlpha := state.baseAlpha
        state.currentAlpha := targetPrimAlpha
        state.secondaryCurrentAlpha := targetSecAlpha
        if (primVis)
            ApplyMicAppearance(cfg, state, state.savedX, state.savedY, state.baseWidth, state.baseHeight, state.currentAlpha)
        if (secVis) {
            secPos := ComputeSecondaryMicLayout(cfg, state)
            ApplySecondaryMicAppearance(cfg, state, secPos.x, secPos.y, state.baseWidth, state.baseHeight, state.secondaryCurrentAlpha)
        }
        if (state.isMuted && IsAnyMicHudVisible(cfg) && (!state.HasOwnProp("activeHost") || state.obsConnected)) {
            state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
            SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
        } else if (state.HasOwnProp("breathTimerFn") && IsObject(state.breathTimerFn)) {
            SetTimer state.breathTimerFn, 0
        }
        return
    }

    scaleFrac := (1.0 - t) * (1.0 - t)
    widthInc := (cfg.ShowText ? UIConstants.POP_WIDTH_INC_TEXT : UIConstants.POP_WIDTH_INC_ICON) * cfg.IndicatorScale
    heightInc := UIConstants.POP_HEIGHT_INC * cfg.IndicatorScale
    popWidth := Round(state.baseWidth + (widthInc * 2.0 * scaleFrac))
    popHeight := Round(state.baseHeight + (heightInc * 2.0 * scaleFrac))
    offsetX := Round((popWidth - state.baseWidth) / 2)
    offsetY := Round((popHeight - state.baseHeight) / 2)

    state._breathStepAlpha := state.baseAlpha
    state.currentAlpha := targetPrimAlpha
    state.secondaryCurrentAlpha := targetSecAlpha

    if (primVis)
        ApplyMicAppearance(cfg, state, state.savedX - offsetX, state.savedY - offsetY, popWidth, popHeight, targetPrimAlpha, state.isMuted)
    if (secVis) {
        secPos := ComputeSecondaryMicLayout(cfg, state)
        ApplySecondaryMicAppearance(cfg, state, secPos.x - offsetX, secPos.y - offsetY, popWidth, popHeight, targetSecAlpha, state.isMuted)
    }
}

PlayMuteAnimation(cfg, state) {
    if (!IsObject(state))
        return
    hasPrimGui := state.HasOwnProp("MicGui") && IsGuiValid(state.MicGui)
    hasSecGui := state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui)
    if (!hasPrimGui && !hasSecGui)
        return

    primVis := hasPrimGui && !IsHudSuppressed(cfg)
    secVis := hasSecGui && !IsSecondaryHudSuppressed(cfg)
    if (!primVis && !secVis) {
        if (state.HasOwnProp("_muteAnimTimerFn") && IsObject(state._muteAnimTimerFn))
            try SetTimer(state._muteAnimTimerFn, 0)
        if (state.HasOwnProp("breathTimerFn") && state.breathTimerFn)
            SetTimer state.breathTimerFn, 0
        state._breathStepAlpha := state.baseAlpha
        state.currentAlpha := (state.HasOwnProp("isAutoDodged") && state.isAutoDodged) ? Min(state.baseAlpha, UIConstants.DODGE_ALPHA) : state.baseAlpha
        state.secondaryCurrentAlpha := (state.HasOwnProp("secondaryIsAutoDodged") && state.secondaryIsAutoDodged) ? Min(state.baseAlpha, UIConstants.DODGE_ALPHA) : state.baseAlpha
        if (hasPrimGui)
            ApplyMicAppearance(cfg, state)
        if (hasSecGui)
            ApplySecondaryMicAppearance(cfg, state)
        return
    }

    state.animSeq += 1
    if (state.HasOwnProp("breathTimerFn") && state.breathTimerFn)
        SetTimer state.breathTimerFn, 0

    state._muteAnimSeq := state.animSeq
    state._muteAnimStartTick := A_TickCount
    state._muteAnimDurationMs := 120
    state._muteAnimCfg := cfg
    if (!state.HasOwnProp("_muteAnimTimerFn") || !IsObject(state._muteAnimTimerFn))
        state._muteAnimTimerFn := _StepMuteAnimation.Bind(state)

    _StepMuteAnimation(state)
    if (state.animSeq == state._muteAnimSeq && !state.isDraggingHud && !(state.HasOwnProp("isDraggingSecondaryHud") && state.isDraggingSecondaryHud) && IsAnyMicHudVisible(cfg)) {
        if ((A_TickCount - state._muteAnimStartTick) < state._muteAnimDurationMs)
            SetTimer(state._muteAnimTimerFn, 16)
    }
}

BreathingAnimation(cfg, state) {
    if (!IsAnyMicHudVisible(cfg)) {
        if (IsObject(state) && state.HasOwnProp("breathTimerFn") && state.breathTimerFn)
            SetTimer state.breathTimerFn, 0
        return
    }
    primOk := IsObject(state.MicGui) && !IsHudSuppressed(cfg) && !state.isDraggingHud
    secOk := state.HasOwnProp("SecondaryMicGui") && IsObject(state.SecondaryMicGui) && !IsSecondaryHudSuppressed(cfg) && (!state.HasOwnProp("isDraggingSecondaryHud") || !state.isDraggingSecondaryHud)
    if (!primOk && !secOk)
        return

    minRatio := cfg.AggressivePulse ? UIConstants.PULSE_MIN_RATIO_AGGRESSIVE : UIConstants.PULSE_MIN_RATIO_NORMAL
    lowerBound := Round(state.baseAlpha * minRatio)
    stepAmount := cfg.AggressivePulse ? UIConstants.PULSE_STEP_AGGRESSIVE : UIConstants.PULSE_STEP_NORMAL

    stepAlpha := state.HasOwnProp("_breathStepAlpha") ? state._breathStepAlpha : state.currentAlpha
    stepAlpha += state.breathDir
    if (stepAlpha <= lowerBound) {
        stepAlpha := lowerBound
        state.breathDir := stepAmount
    } else if (stepAlpha >= state.baseAlpha) {
        stepAlpha := state.baseAlpha
        state.breathDir := -stepAmount
    }
    state._breathStepAlpha := stepAlpha
    state.currentAlpha := (state.HasOwnProp("isAutoDodged") && state.isAutoDodged) ? Min(stepAlpha, UIConstants.DODGE_ALPHA) : stepAlpha
    state.secondaryCurrentAlpha := (state.HasOwnProp("secondaryIsAutoDodged") && state.secondaryIsAutoDodged) ? Min(stepAlpha, UIConstants.DODGE_ALPHA) : stepAlpha

    if (primOk) {
        if (!Gdip.SetLayeredAlpha(state.MicGui.Hwnd, state.currentAlpha))
            ApplyMicAppearance(cfg, state)
    }
    if (secOk) {
        if (!Gdip.SetLayeredAlpha(state.SecondaryMicGui.Hwnd, state.secondaryCurrentAlpha))
            ApplySecondaryMicAppearance(cfg, state)
    }
}

; --- HUD DRAG & DPI HANDLERS ---
IsHudHwnd(state, hwnd) {
    if (!IsObject(state) || !hwnd)
        return false
    return (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd)
        || (state.HasOwnProp("SecondaryMicGui") && IsObject(state.SecondaryMicGui) && hwnd == state.SecondaryMicGui.Hwnd)
        || (IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd)
        || (IsObject(state.ChatGui) && hwnd == state.ChatGui.Hwnd)
        || (IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd)
        || (IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd)
        || (IsObject(state.StreamGui) && hwnd == state.StreamGui.Hwnd)
        || (IsObject(state.VCamGui) && hwnd == state.VCamGui.Hwnd)
}

AnchorFromHwnd(state, hwnd, X, Y) {
    if (IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd) {
        Y := Y + state.recHeight + state.hudGap
    } else if (IsObject(state.ChatGui) && hwnd == state.ChatGui.Hwnd) {
        X := X - state.recW - state.hudGap
        Y := Y + state.recHeight + state.hudGap
    } else if (IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd) {
        Y := Y + state.row3Height + state.hudGap + state.recHeight + state.hudGap
    } else if (IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd) {
        X := X - state.studioW - state.hudGap
        Y := Y + state.row3Height + state.hudGap + state.recHeight + state.hudGap
    } else if (IsObject(state.StreamGui) && hwnd == state.StreamGui.Hwnd) {
        Y := Y + state.row4Height + state.hudGap + state.row3Height + state.hudGap + state.recHeight + state.hudGap
    } else if (IsObject(state.VCamGui) && hwnd == state.VCamGui.Hwnd) {
        X := X - state.streamW - state.hudGap
        Y := Y + state.row4Height + state.hudGap + state.row3Height + state.hudGap + state.recHeight + state.hudGap
    }
    return {x: X, y: Y}
}

DragSyncTick(state) {
    if (!state.isDraggingHud || !state.activeDragHwnd)
        return
    try {
        WinGetPos(&curX, &curY,,, "ahk_id " state.activeDragHwnd)
        anchor := AnchorFromHwnd(state, state.activeDragHwnd, curX, curY)
        UpdateHudLayout(state, anchor.x, anchor.y, state.activeDragHwnd)
    }
}

WM_HUD_MOVE(state, wParam, lParam, msg, hwnd) {
    if (state.isDraggingHud && hwnd == state.activeDragHwnd)
        DragSyncTick(state)
}

SwitchObsScene(cfg, state, sceneName, *) {
    if (sceneName = "")
        return false
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) {
        esc := EscapeJsonStr(sceneName)
        return SendObsRequest(state.obsWs, "SetCurrentProgramScene", "ClickSetScene", '{"sceneName":"' esc '"}')
    }
    SyncSceneState(cfg, state, sceneName)
    return true
}

BuildSceneSwitcherMenu(cfg, state, onSelectFn := "") {
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs))
        SendObsRequest(state.obsWs, "GetSceneList", "InitSceneList")
    Theme.ApplyMenuTheme()
    sceneMenu := Menu()
    scenes := []
    if (state.HasOwnProp("sceneList") && IsObject(state.sceneList) && state.sceneList.Length > 0) {
        for sc in state.sceneList
            scenes.Push(sc)
    } else if (state.currentSceneName != "") {
        scenes.Push(state.currentSceneName)
    }
    handler := IsObject(onSelectFn) ? onSelectFn : SwitchObsScene
    for sc in scenes {
        disp := StrReplace(sc, "&", "&&")
        sceneMenu.Add(disp, handler.Bind(cfg, state, sc))
        if (sc = state.currentSceneName)
            sceneMenu.Check(disp)
    }
    return { menu: sceneMenu, scenes: scenes }
}

SelectObsSceneFromPopup(cfg, state, sceneName, *) {
    if (sceneName = "")
        return false
    return SwitchObsScene(cfg, state, sceneName)
}

ShowSceneSwitcherPopup(cfg, state) {
    built := BuildSceneSwitcherMenu(cfg, state, SelectObsSceneFromPopup)
    built.menu.Show()
    return built.scenes
}

TryConfirmStopRecording(cfg, state, nowTick := "") {
    if (!IsObject(cfg) || !IsObject(state))
        return true
    if (nowTick = "")
        nowTick := A_TickCount
    if (!state.HasOwnProp("stopRecConfirmUntil"))
        state.stopRecConfirmUntil := 0
    confirmEnabled := !cfg.HasOwnProp("ConfirmBeforeStopRecording") || cfg.ConfirmBeforeStopRecording
    isRecording := (state.HasOwnProp("obsRecState") && state.obsRecState != 0) || (state.HasOwnProp("recState") && state.recState != 0)
    if (!confirmEnabled || !isRecording) {
        state.stopRecConfirmUntil := 0
        return true
    }
    if (nowTick >= state.stopRecConfirmUntil) {
        state.stopRecConfirmUntil := nowTick + UIConstants.STOP_RECORD_CONFIRM_WINDOW_MS
        if (!IsSet(g_IsTestMode) || !g_IsTestMode) {
            if (IsSet(ShowCaptureSafeMicroToast))
                try ShowCaptureSafeMicroToast("Click REC again within 3s to STOP recording", UIConstants.STOP_RECORD_CONFIRM_WINDOW_MS)
        }
        return false
    }
    state.stopRecConfirmUntil := 0
    return true
}

HandleHudPillClick(cfg, state, hwnd) {
    if (!IsObject(cfg) || !IsObject(state) || !hwnd)
        return false
    if (cfg.HasOwnProp("EnableHudClickActions") && !cfg.EnableHudClickActions)
        return false

    isPrimMic := (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd)
    isSecMic := (state.HasOwnProp("SecondaryMicGui") && IsObject(state.SecondaryMicGui) && hwnd == state.SecondaryMicGui.Hwnd)
    if (isPrimMic || isSecMic) {
        if (state.HasOwnProp("triggerMuteFn") && IsObject(state.triggerMuteFn)) {
            state.triggerMuteFn.Call()
        } else {
            DispatchHostMuteToggle(cfg, state)
            if (!cfg.EnableWS || !state.obsConnected)
                SyncUIState(cfg, state, !state.isMuted)
        }
        return isSecMic ? "secondary_mic" : "mic"
    }
    if (IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd) {
        wasRecState := state.recState
        if (wasRecState == 1 || wasRecState == 2) {
            ExecuteHostPauseRecord(cfg, state)
            retTag := (wasRecState == 1) ? "rec_pause" : "rec_resume"
        } else {
            ExecuteHostStartRecord(cfg, state)
            retTag := "rec"
        }
        if ((!IsSet(g_IsTestMode) || !g_IsTestMode) && cfg.HasOwnProp("EnableWS") && cfg.EnableWS && cfg.HasOwnProp("EnableZoom") && cfg.EnableZoom) {
            if (IsSet(ShowCaptureSafeMicroToast))
                ShowCaptureSafeMicroToast(GetRecBreakdownText(state), UIConstants.TOOLTIP_DURATION_MS)
        }
        return retTag
    }
    if (IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd) {
        nextStudio := !state.studioModeActive
        if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs))
            SendObsRequest(state.obsWs, "SetStudioModeEnabled", "ClickToggleStudio", '{"studioModeEnabled":' (nextStudio ? "true" : "false") '}')
        else
            SyncStudioState(cfg, state, nextStudio)
        return "studio"
    }
    if (IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd) {
        ; Left-click: native Preview<->Program transition. Scene list lives on right-click.
        if (IsSet(TriggerObsSceneTransition))
            TriggerObsSceneTransition(cfg, state, true)
        return "scene"
    }
    if (IsObject(state.VCamGui) && hwnd == state.VCamGui.Hwnd) {
        if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs))
            SendObsRequest(state.obsWs, "ToggleVirtualCam", "ClickToggleVCam")
        else
            SyncVCamState(cfg, state, !state.vcamActive)
        return "vcam"
    }
    if (IsObject(state.StreamGui) && hwnd == state.StreamGui.Hwnd) {
        if (!IsSet(g_IsTestMode) || !g_IsTestMode) {
            statusLbl := (state.streamState == 2) ? "WARN" : ((state.streamState == 1) ? "LIVE" : "OFF")
            congPct := Round((state.HasOwnProp("streamCongestion") ? state.streamCongestion : 0.0) * 100, 1)
            skp := state.HasOwnProp("streamSkippedFrames") ? state.streamSkippedFrames : 0
            reconnStr := (state.HasOwnProp("streamReconnecting") && state.streamReconnecting) ? " (Reconnecting)" : ""
            tip := Format("Stream: {}{} | Congestion: {}% | Skipped Frames: {}", statusLbl, reconnStr, congPct, skp)
            if (IsSet(ShowCaptureSafeMicroToast))
                ShowCaptureSafeMicroToast(tip, UIConstants.TOOLTIP_DURATION_MS)
        }
        return "stream_readonly"
    }
    if (IsObject(state.ChatGui) && hwnd == state.ChatGui.Hwnd) {
        SyncChatState(cfg, state, 0)
        confSpec := GetConferencingWindowSpec(cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom")
        if WinExist(confSpec)
            try WinActivate(confSpec)
        return "chat"
    }
    return false
}

ApplyDraggedSecondaryPosition(cfg, state, rawX, rawY) {
    secX := Integer(rawX)
    secY := Integer(rawY)
    if (!cfg.HasOwnProp("EnableMagneticSnap") || cfg.EnableMagneticSnap) {
        snap := ComputeMagneticSnap(secX, secY, state.baseWidth, state.baseHeight, 0, UIConstants.SNAP_THRESHOLD_PX, GetCandidateSnapWindowRects(state))
        secX := snap.x, secY := snap.y
    }
    cfg.savedSecondaryX := secX
    cfg.savedSecondaryY := secY
    pos := ComputeSecondaryMicLayout(cfg, state)
    cfg.savedSecondaryX := pos.x
    cfg.savedSecondaryY := pos.y
    cfg.Write("SecondaryPosition", "X", pos.x)
    cfg.Write("SecondaryPosition", "Y", pos.y)
    return pos
}

WaitPillLongPressWithProgress(startMX, startMY, downTick, holdMs, visualDelayMs, tapMaxMs, onProgressFn := "", onHoldCompleteFn := "") {
    ; Shared 16ms long-press tracker with drag break (>4px) and guaranteed 0.0 reset in finally.
    lastProg := -1.0
    try {
        while (GetKeyState("LButton", "P")) {
            MouseGetPos(&mx, &my)
            if (Abs(mx - startMX) > 4 || Abs(my - startMY) > 4)
                return { verdict: "drag", elapsedMs: A_TickCount - downTick }
            elapsed := A_TickCount - downTick
            if (elapsed >= holdMs) {
                if (IsObject(onHoldCompleteFn)) {
                    if (IsObject(onProgressFn))
                        onProgressFn.Call(0.0)
                    onHoldCompleteFn.Call()
                    KeyWait "LButton"
                    return { verdict: "hold_handled", elapsedMs: elapsed }
                }
                if (IsObject(onProgressFn))
                    onProgressFn.Call(1.0)
                KeyWait "LButton"
                return { verdict: "hold", elapsedMs: elapsed }
            }
            if (elapsed >= visualDelayMs && IsObject(onProgressFn)) {
                prog := Min(0.99, Max(0.0, (elapsed - visualDelayMs) / Float(Max(1, holdMs - visualDelayMs))))
                if (Abs(prog - lastProg) >= 0.015) {
                    lastProg := prog
                    onProgressFn.Call(prog)
                }
            }
            Sleep(16)
        }
        elapsed := A_TickCount - downTick
        return { verdict: (elapsed < tapMaxMs ? "tap" : "cancel"), elapsedMs: elapsed }
    } finally {
        if (IsObject(onProgressFn))
            onProgressFn.Call(0.0)
    }
}

WaitStudioLongPress(startMX, startMY, downTick, onProgressFn := "") {
    res := WaitPillLongPressWithProgress(startMX, startMY, downTick, UIConstants.STUDIO_LONG_PRESS_MS, 80, 350, onProgressFn)
    if (res.verdict = "hold")
        return "toggle"
    if (res.verdict = "drag")
        return "drag"
    return "tap"
}

WM_LBUTTONDBLCLK(state, wParam, lParam, msg, hwnd) {
    if (IsObject(state) && state.HasOwnProp("StreamGui") && IsObject(state.StreamGui) && hwnd == state.StreamGui.Hwnd)
        return 0
}

WM_LBUTTONDOWN(cfg, state, wParam, lParam, msg, hwnd) {
    if (!IsHudHwnd(state, hwnd))
        return

    isSecondary := (state.HasOwnProp("SecondaryMicGui") && IsObject(state.SecondaryMicGui) && hwnd == state.SecondaryMicGui.Hwnd)
    clickActionsEnabled := !cfg.HasOwnProp("EnableHudClickActions") || cfg.EnableHudClickActions
    prevMouseMode := A_CoordModeMouse
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startMX, &startMY)
    downTick := A_TickCount

    if (isSecondary) {
        secDragInitiated := false
        if (clickActionsEnabled) {
            UpdateSecondaryMicHold(p) {
                if (p != state.secondaryMicHoldProgress) {
                    state.secondaryMicHoldProgress := p
                    ApplySecondaryMicAppearance(cfg, state)
                }
            }
            secRes := WaitPillLongPressWithProgress(startMX, startMY, downTick, UIConstants.MIC_LONG_PRESS_MS, 90, UIConstants.MIC_LONG_PRESS_MS, UpdateSecondaryMicHold, (*) => HandleHudPillClick(cfg, state, hwnd))
            if (secRes.verdict = "hold_handled") {
                CoordMode("Mouse", prevMouseMode)
                return
            }
            if (secRes.verdict = "tap" || secRes.verdict = "hold") {
                CoordMode("Mouse", prevMouseMode)
                HandleHudPillClick(cfg, state, hwnd)
                return
            }
            if (secRes.verdict = "cancel") {
                CoordMode("Mouse", prevMouseMode)
                return
            }
            secDragInitiated := true
        }
        secPos := ComputeSecondaryMicLayout(cfg, state)
        prevSX := secPos.x
        prevSY := secPos.y
        state.animSeq += 1
        SetTimer state.breathTimerFn, 0
        state.isDraggingSecondaryHud := true
        PostMessage(0xA1, 2,,, "ahk_id " hwnd)
        KeyWait "LButton"
        state.isDraggingSecondaryHud := false

        MouseGetPos(&endMX, &endMY)
        CoordMode("Mouse", prevMouseMode)
        isShortClick := (Abs(endMX - startMX) <= 3 && Abs(endMY - startMY) <= 3 && (A_TickCount - downTick) < 400)

        if (isShortClick) {
            state.savedSecondaryX := prevSX
            state.savedSecondaryY := prevSY
            state.SecondaryMicGui.Move(prevSX, prevSY, state.baseWidth, state.baseHeight)
        } else {
            WinGetPos(&X, &Y,,, "ahk_id " hwnd)
            pos := ApplyDraggedSecondaryPosition(cfg, state, X, Y)
            state.SecondaryMicGui.Move(pos.x, pos.y, pos.w, pos.h)
        }
        baseLvl := state.HasOwnProp("_breathStepAlpha") ? state._breathStepAlpha : state.baseAlpha
        state.secondaryCurrentAlpha := (state.HasOwnProp("secondaryIsAutoDodged") && state.secondaryIsAutoDodged) ? Min(baseLvl, UIConstants.DODGE_ALPHA) : baseLvl
        ApplySecondaryMicAppearance(cfg, state)
        ApplyHudClickThroughStyle(cfg, state)
        if (IsAnyMicHudVisible(cfg) && state.isMuted)
            SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
        if (isShortClick && !secDragInitiated)
            HandleHudPillClick(cfg, state, hwnd)
        return
    }

    dragInitiated := false

    if (clickActionsEnabled && IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd) {
        UpdateMicHold(p) {
            if (p != state.micHoldProgress) {
                state.micHoldProgress := p
                ApplyMicAppearance(cfg, state)
            }
        }
        micRes := WaitPillLongPressWithProgress(startMX, startMY, downTick, UIConstants.MIC_LONG_PRESS_MS, 90, UIConstants.MIC_LONG_PRESS_MS, UpdateMicHold, (*) => HandleHudPillClick(cfg, state, hwnd))
        if (micRes.verdict = "hold_handled") {
            CoordMode("Mouse", prevMouseMode)
            return
        }
        if (micRes.verdict = "tap" || micRes.verdict = "hold") {
            CoordMode("Mouse", prevMouseMode)
            HandleHudPillClick(cfg, state, hwnd)
            return
        }
        if (micRes.verdict = "cancel") {
            CoordMode("Mouse", prevMouseMode)
            return
        }
        dragInitiated := true
    }

    if (clickActionsEnabled && IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd) {
        UpdateStudioHold(p) {
            if (p != state.studioHoldProgress) {
                state.studioHoldProgress := p
                ApplyStudioAppearance(cfg, state)
            }
        }
        verdict := WaitStudioLongPress(startMX, startMY, downTick, UpdateStudioHold)
        if (verdict != "drag") {
            CoordMode("Mouse", prevMouseMode)
            if (verdict = "toggle") {
                nextStudio := !state.studioModeActive
                if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs))
                    SendObsRequest(state.obsWs, "SetStudioModeEnabled", "ClickToggleStudio", '{"studioModeEnabled":' (nextStudio ? "true" : "false") '}')
                else
                    SyncStudioState(cfg, state, nextStudio)
            } else {
                if (IsSet(ShowCaptureSafeMicroToast))
                    ShowCaptureSafeMicroToast("Hold Studio pill (0.6s) to toggle Studio Mode", UIConstants.TOOLTIP_DURATION_MS)
            }
            return
        }
        dragInitiated := true
    }

    if (clickActionsEnabled && IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd && (state.recState == 1 || state.recState == 2)) {
        UpdateRecHold(p) {
            if (p != state.recHoldProgress) {
                state.recHoldProgress := p
                ApplyRecAppearance(cfg, state)
            }
        }
        recRes := WaitPillLongPressWithProgress(startMX, startMY, downTick, UIConstants.REC_STOP_LONG_PRESS_MS, 120, 350, UpdateRecHold)
        if (recRes.verdict != "drag") {
            CoordMode("Mouse", prevMouseMode)
            if (recRes.verdict = "hold") {
                ExecuteHostStopRecord(cfg, state)
            } else if (recRes.verdict = "tap") {
                ExecuteHostPauseRecord(cfg, state)
            } else {
                if (IsSet(ShowCaptureSafeMicroToast))
                    ShowCaptureSafeMicroToast("Hold longer to stop recording", UIConstants.TOOLTIP_DURATION_MS)
            }
            return
        }
        dragInitiated := true
    }

    if (clickActionsEnabled && IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd) {
        sceneMoved := false
        while (GetKeyState("LButton", "P")) {
            MouseGetPos(&mx, &my)
            if (Abs(mx - startMX) > 4 || Abs(my - startMY) > 4) {
                sceneMoved := true
                break
            }
            Sleep(8)
        }
        if (!sceneMoved) {
            CoordMode("Mouse", prevMouseMode)
            HandleHudPillClick(cfg, state, hwnd)
            return
        }
        dragInitiated := true
    }

    prevX := state.savedX
    prevY := state.savedY
    state.animSeq += 1
    SetTimer state.breathTimerFn, 0
    state.activeDragHwnd := hwnd
    state.isDraggingHud := true
    SetTimer state.dragTimerFn, UIConstants.DRAG_SYNC_INTERVAL_MS
    PostMessage(0xA1, 2,,, "ahk_id " hwnd)
    KeyWait "LButton"
    state.isDraggingHud := false
    state.activeDragHwnd := 0
    SetTimer state.dragTimerFn, 0

    MouseGetPos(&endMX, &endMY)
    CoordMode("Mouse", prevMouseMode)
    isShortClick := (Abs(endMX - startMX) <= 3 && Abs(endMY - startMY) <= 3 && (A_TickCount - downTick) < 400)

    if (isShortClick) {
        anchor := {x: prevX, y: prevY}
    } else {
        WinGetPos(&X, &Y,,, "ahk_id " hwnd)
        anchor := AnchorFromHwnd(state, hwnd, X, Y)
        if (!cfg.HasOwnProp("EnableMagneticSnap") || cfg.EnableMagneticSnap) {
            b := GetHudStackBounds(cfg, state)
            snap := ComputeMagneticSnap(anchor.x, anchor.y, b.stackW, state.baseHeight, b.extraTopPad, UIConstants.SNAP_THRESHOLD_PX, GetCandidateSnapWindowRects(state))
            anchor.x := snap.x, anchor.y := snap.y
        }
        if (anchor.x != prevX || anchor.y != prevY) {
            cfg.savedX := anchor.x
            cfg.savedY := anchor.y
            cfg.Write("Position", "X", anchor.x)
            cfg.Write("Position", "Y", anchor.y)
        }
    }
    UpdateHudLayout(state, anchor.x, anchor.y)
    state.currentAlpha := (state.HasOwnProp("isAutoDodged") && state.isAutoDodged) ? Min(state.baseAlpha, UIConstants.DODGE_ALPHA) : state.baseAlpha
    ApplyMicAppearance(cfg, state)
    if (!IsHudSuppressed(cfg) && cfg.ShowExtraHuds && cfg.EnableWS) {
        ApplySceneAppearance(cfg, state)
        if (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud)
            ApplyStreamAppearance(cfg, state)
    }
    ApplyHudClickThroughStyle(cfg, state)
    if (IsAnyMicHudVisible(cfg) && state.isMuted)
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)

    if (isShortClick && !dragInitiated)
        HandleHudPillClick(cfg, state, hwnd)
}

WM_RBUTTONUP(state, wParam, lParam, msg, hwnd) {
    if (!IsHudHwnd(state, hwnd))
        return
    if (state.HasOwnProp("SceneGui") && IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd
        && state.HasOwnProp("hudCfg") && IsObject(state.hudCfg)) {
        ShowSceneSwitcherPopup(state.hudCfg, state)
        return
    }
    A_TrayMenu.Show()
}

WM_DPICHANGED(state, wParam, lParam, msg, hwnd) {
    if (!IsObject(state))
        return
    newLeft := NumGet(lParam, 0, "Int")
    newTop := NumGet(lParam, 4, "Int")
    if (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd) {
        state.savedX := newLeft
        state.savedY := newTop
        UpdateHudLayout(state, newLeft, newTop)
        if (state.HasOwnProp("hudCfg") && IsObject(state.hudCfg)) {
            RenderAllHudPills(state.hudCfg, state)
            ApplyHudCaptureExclusion(state.hudCfg, state)
        }
        return
    }
    if (state.HasOwnProp("SecondaryMicGui") && IsGuiValid(state.SecondaryMicGui) && hwnd == state.SecondaryMicGui.Hwnd) {
        state.savedSecondaryX := newLeft
        state.savedSecondaryY := newTop
        if (state.HasOwnProp("hudCfg") && IsObject(state.hudCfg)) {
            ApplySecondaryMicAppearance(state.hudCfg, state)
            ApplyHudCaptureExclusion(state.hudCfg, state)
        }
    }
}

WM_DISPLAYCHANGE(cfg, state, *) {
    if (!IsObject(state) || !IsObject(cfg))
        return
    if (IsSet(CaptureSafety) && state.HasOwnProp("savedX") && state.HasOwnProp("savedY")) {
        cPrim := CaptureSafety.ClampRectToMonitors(state.savedX, state.savedY, state.baseWidth, state.baseHeight)
        if (cPrim.clamped) {
            state.savedX := cPrim.x
            state.savedY := cPrim.y
        }
        if (state.HasOwnProp("savedSecondaryX") && state.HasOwnProp("savedSecondaryY")) {
            secW := (state.HasOwnProp("secWidth") && state.secWidth > 0) ? state.secWidth : state.baseWidth
            cSec := CaptureSafety.ClampRectToMonitors(state.savedSecondaryX, state.savedSecondaryY, secW, state.baseHeight)
            if (cSec.clamped) {
                state.savedSecondaryX := cSec.x
                state.savedSecondaryY := cSec.y
            }
        }
    }
    RefreshHudAppearance(cfg, state)
}

ToggleHudOptionAndRebuild(cfg, state, propName, cfgSection, refreshFn, rebuildTrayFn, afterFn := "") {
    cfg.%propName% := !cfg.%propName%
    cfg.WriteBool(cfgSection, propName, cfg.%propName%)
    refreshFn.Call(cfg, state)
    rebuildTrayFn.Call(cfg, state)
    if IsObject(afterFn)
        afterFn.Call(state)
}

SetHudOpacityAndRebuild(cfg, state, val, cfgSection, refreshFn, rebuildTrayFn, effectiveAlphaFn := "", afterFn := "") {
    cfg.OpacityLevel := val
    cfg.Write(cfgSection, "OpacityLevel", val)
    if IsObject(state) {
        state.baseAlpha := val
        state.currentAlpha := IsObject(effectiveAlphaFn) ? effectiveAlphaFn.Call(state) : val
    }
    refreshFn.Call(cfg, state)
    rebuildTrayFn.Call(cfg, state)
    if IsObject(afterFn)
        afterFn.Call(state)
}

BuildSharedAppearanceSubmenus(parentMenu, cfg, state, onOpacityFn, onScaleFn, onThemeFn) {
    OpacityMenu := Menu()
    for opt in [
        { label: "Solid (100%)", val: UIConstants.OPACITY_SOLID },
        { label: "Frosted (85%)", val: UIConstants.OPACITY_FROSTED },
        { label: "Ghost (50%)", val: UIConstants.OPACITY_GHOST }
    ] {
        OpacityMenu.Add(opt.label, onOpacityFn.Bind(opt.val))
        if (cfg.OpacityLevel == opt.val)
            OpacityMenu.Check(opt.label)
    }
    parentMenu.Add("Transparency Level", OpacityMenu)

    ScaleMenu := Menu()
    for opt in [
        { label: "Tiny (x0.25)", val: 0.25 },
        { label: "Small (x0.5)", val: 0.5 },
        { label: "Normal (x1.0)", val: 1.0 },
        { label: "Medium (x1.25)", val: 1.25 },
        { label: "Large (x1.5)", val: 1.5 },
        { label: "Huge (x2.0)", val: 2.0 },
        { label: "Massive (x2.5)", val: 2.5 },
        { label: "Colossal (x3.0)", val: 3.0 },
        { label: "Gigantic (x5.0)", val: 5.0 }
    ] {
        ScaleMenu.Add(opt.label, onScaleFn.Bind(opt.val))
        if (Abs(cfg.IndicatorScale - opt.val) < 0.001)
            ScaleMenu.Check(opt.label)
    }
    parentMenu.Add("Indicator Scale", ScaleMenu)

    ThemeMenu := Menu()
    for item in [
        { label: "Follow System", mode: "System" },
        { label: "Dark Mode", mode: "Dark" },
        { label: "Light Mode", mode: "Light" }
    ] {
        ThemeMenu.Add(item.label, onThemeFn.Bind(0, item.mode))
        if (cfg.ThemeMode = item.mode)
            ThemeMenu.Check(item.label)
    }
    parentMenu.Add("App Theme", ThemeMenu)

    PresetMenu := Menu()
    for pName in GetHudColorPresetNames() {
        PresetMenu.Add(pName, SetHudColorPreset.Bind(cfg, state, pName))
        if (cfg.HudColorPreset = pName)
            PresetMenu.Check(pName)
    }
    PresetMenu.Add()
    PresetMenu.Add("Configure Custom Colors...", ConfigureCustomHudColorsUI.Bind(cfg, state))
    parentMenu.Add("HUD Color Preset", PresetMenu)
}

