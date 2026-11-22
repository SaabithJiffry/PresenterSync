; ==============================================================================
; Module: HelpCenter.ahk
; Description: Comprehensive searchable Help knowledge base, System Tray menu
;              encyclopedia, Feature A-Z reference, and live GDI+ Annotated HUD
;              visual diagram renderer for PresenterSync & PresenterSync Remote.
; ==============================================================================

/**
 * Returns the 8 numbered HUD anatomy items shown in the interactive visual diagram
 * for the Primary 4-Tier HUD.
 */
GetPrimaryHudAnatomyItems() {
    return [
        {
            id: 1,
            tag: "[1] STREAM",
            pillTitle: "STREAM Status & Drop Alert (Row 4 Left)",
            tier: "Tier 4 (OBS WebSocket v5 Only — Top Row Left)",
            summary: "Shows live OBS streaming output status plus automatic dropped-frame and bitrate congestion alerts.",
            states: "• Slate OFF: Not streaming.`r`n• Rose/Red LIVE: Broadcast active cleanly.`r`n• Orange WARN: Reconnecting, skipped frames detected, or congestion >= 35%.",
            actions: "• Short-Click: Pops a tooltip showing exact stream state, congestion %, and skipped frame count.`r`n• Left-Drag: Moves the entire HUD stack.`r`n• Right-Click: Opens the full tray menu.",
            configWhere: "• Tray -> Show Extra HUDs (must be ON)`r`n• Tray -> Indicator Appearance -> Show Stream & VCam HUD`r`n• Tray -> Enable OBS WebSocket Sync (Alt+F12)`r`n• Control Center -> OBS & Stream tab"
        },
        {
            id: 2,
            tag: "[2] VCAM",
            pillTitle: "Virtual Camera Indicator (Row 4 Right)",
            tier: "Tier 4 (OBS WebSocket v5 Only — Top Row Right)",
            summary: "Displays whether OBS Virtual Camera is actively feeding Zoom, Teams, or Meet and toggles it with one click.",
            states: "• Slate VCAM: Virtual Camera is stopped.`r`n• Teal VCAM: Virtual Camera output is active.",
            actions: "• Short-Click: Immediately starts or stops OBS Virtual Camera (ToggleVirtualCam).`r`n• Left-Drag: Moves the entire HUD stack.`r`n• Right-Click: Opens the full tray menu.",
            configWhere: "• Tray -> Show Extra HUDs`r`n• Tray -> Indicator Appearance -> Show Stream & VCam HUD`r`n• Tray -> Enable OBS WebSocket Sync`r`n• Control Center -> OBS & Stream tab"
        },
        {
            id: 3,
            tag: "[3] STUDIO",
            pillTitle: "OBS Studio Mode Badge (Row 3 Left)",
            tier: "Tier 3 (OBS WebSocket v5 — Upper-Middle Row Left)",
            summary: "Shows whether OBS Studio Mode (dual Preview / Program editing view) is active and lets you toggle it live.",
            states: "• Slate STUDIO: Single-scene standard OBS view.`r`n• Purple STUDIO: Studio Mode active (safe Preview edits before transitioning).",
            actions: "• Short-Click: Enables or disables OBS Studio Mode live.`r`n• Left-Drag: Moves the entire HUD stack.`r`n• Right-Click: Opens the full tray menu.",
            configWhere: "• Tray -> Show Extra HUDs`r`n• Tray -> Enable OBS WebSocket Sync`r`n• Control Center -> OBS & Stream tab"
        },
        {
            id: 4,
            tag: "[4] SCENE",
            pillTitle: "Active Program Scene & Switcher (Row 3 Right)",
            tier: "Tier 3 (OBS WebSocket v5 — Upper-Middle Row Right)",
            summary: "Displays the currently live OBS Program scene name with smooth horizontal marquee scrolling for long names.",
            states: "• Dark Slate Pill: Shows active OBS Program Scene name; automatically scrolls left/right when wider than the pill.",
            actions: "• Short-Click: Opens a floating Popup Scene Switcher menu so you can switch OBS scenes without leaving PowerPoint.`r`n• Left-Drag: Moves the entire HUD stack.`r`n• Right-Click: Opens the full tray menu.",
            configWhere: "• Tray -> Show Extra HUDs`r`n• Tray -> Enable OBS WebSocket Sync`r`n• Control Center -> HUD & Theme tab"
        },
        {
            id: 5,
            tag: "[5] REC + Timer",
            pillTitle: "Recording Status & Elapsed Timer (Row 2 Left)",
            tier: "Tier 2 (OBS WebSocket OR Conferencing UIA — Middle Row Left)",
            summary: "Tracks 3-state recording progress in OBS Studio or Zoom/Teams/Meet and counts elapsed recording duration live.",
            states: "• Slate NOT REC: Idle / not recording.`r`n• Red REC 04:18: Recording active with live MM:SS (or H:MM:SS) timer.`r`n• Amber PAUSED 04:18: Recording paused (resumes timing when unpaused).",
            actions: "• Short-Click: Starts or stops Recording in OBS (or sends your Conferencing Rec shortcut).`r`n• Left-Drag: Moves the entire HUD stack.`r`n• Right-Click: Opens the full tray menu.",
            configWhere: "• Tray -> Show Extra HUDs`r`n• Tray -> Indicator Appearance -> Show Recording Elapsed Timer`r`n• Control Center -> OBS & Stream / Audio & Conf tabs"
        },
        {
            id: 6,
            tag: "[6] CHAT",
            pillTitle: "Unread Chat Alert Badge (Row 2 Right)",
            tier: "Tier 2 (Conferencing UIA — Middle Row Right)",
            summary: "Monitors your selected conferencing app (Zoom, Microsoft Teams, or Google Meet) in the background for unread chat messages.",
            states: "• Slate CHAT: No unread chat notifications.`r`n• Bright Blue '2 NEW': Shows live unread message count detected from the meeting controls.",
            actions: "• Short-Click: Clears the unread badge highlight and brings the active Conferencing meeting window to the front.`r`n• Left-Drag: Moves the entire HUD stack.`r`n• Right-Click: Opens the full tray menu.",
            configWhere: "• Tray -> Show Extra HUDs`r`n• Tray -> Settings -> Conferencing Platform (Zoom / Teams / Meet)`r`n• Tray -> Enable Zoom Monitoring (Ctrl+Alt+F12)"
        },
        {
            id: 7,
            tag: "[7] LIVE/MUTE",
            pillTitle: "Primary Mic Status Pill (Row 1 Bottom)",
            tier: "Tier 1 (Always Available Base Pill — Bottom Row)",
            summary: "Your unmistakable always-on-top microphone status indicator with fade-pop transition animation and muted breathing pulse.",
            states: "• Bright Green LIVE: Microphone is unmuted / live on air.`r`n• Red MUTED (Pulses): Microphone is muted and pulses gently (or aggressively) so you never speak into a muted mic.",
            actions: "• Short-Click: Immediately toggles mic Mute/Unmute (via OBS WebSocket, fallback shortcut, or Conferencing key).`r`n• Hardware Clicker: Press pointer button (default b), or HOLD >= 350ms for Cough Push-to-Mute.`r`n• Left-Drag / Right-Click: Reposition entire stack or open Tray menu.",
            configWhere: "• Tray -> Show Mute Indicator (Ctrl+Shift+F12)`r`n• Tray -> Indicator Appearance -> Show Text Label / Aggressive Mute Pulse / HUD Color Preset`r`n• Control Center -> Audio & Conf / HUD & Theme"
        },
        {
            id: 8,
            tag: "[8] VU / Grab",
            pillTitle: "Live CoreAudio Voice Meter Bar & Smart Gestures",
            tier: "Overlay Mechanics (Applies Across All HUD Tiers)",
            summary: "Real-time white peak bar inside the LIVE pill driven locally by Windows CoreAudio, plus Magnetic Snapping, Auto-Dodge, and Click-Through.",
            states: "• Glowing White Bottom Bar: Rises/falls with actual mic audio using zero OBS WebSocket bandwidth.`r`n• Auto-Dodge: Fades stack to 15% ghost pass-through on mouse hover.`r`n• Click-Through: Mouse clicks pass underneath (hold Alt to drag/click).",
            actions: "• Drag near screen edges/centers or OBS/PPT/Zoom/Teams windows for 14px Magnetic Snapping.`r`n• Hold Alt while Click-Through or Auto-Dodge is ON to grab or click any pill anytime.",
            configWhere: "• Tray -> Indicator Appearance -> Show Live Voice Activity Bar`r`n• Tray -> Indicator Appearance -> Magnetic Edge/Window Snap / Auto-Dodge / Click-Through`r`n• Tray -> Indicator Appearance -> Interactive HUD Click Actions"
        }
    ]
}

/**
 * Returns the 4 numbered anatomy items for the Remote Companion's 1-tier Mic HUD.
 */
GetRemoteHudAnatomyItems() {
    return [
        {
            id: 1,
            tag: "[1] Mic State",
            pillTitle: "Remote 1-Tier Mic Pill (LIVE / MUTED / Offline)",
            tier: "PresenterSync Remote (Dedicated Single-Pill Companion)",
            summary: "Displays real-time microphone mute state synchronized from your Primary streaming PC over LAN or the Internet Relay.",
            states: "• Bright Green LIVE: Mic is open on host PC.`r`n• Red MUTED (Pulses): Mic is muted on host PC and pulses steadily.`r`n• Slate OFFLINE: Searching for host or LAN disconnected (uses your full chosen Transparency Level).`r`n• Amber PW REQ (Lock Icon): Host OBS WebSocket or Bridge requires a password (none configured yet).`r`n• Crimson AUTH ERR (Error Icon): Supplied password or pairing code was rejected (4009 / Bridge auth error).",
            actions: "• Press Pointer Mute Button (default b) or short-click the pill to toggle mic Mute/Unmute.`r`n• Toggle Pointer Mute Control ON/OFF with Ctrl+F12 (HUD still stays live when OFF).",
            configWhere: "• Tray -> Show Mute Indicator`r`n• Tray -> Pointer Controls -> Enable Pointer Mute`r`n• Tray -> Indicator Appearance -> Show Text Label / HUD Color Preset"
        },
        {
            id: 2,
            tag: "[2] Short-Click",
            pillTitle: "Interactive Pill Click & Cough Hold Gesture",
            tier: "PresenterSync Remote Quick Interaction",
            summary: "Lets you tap the floating pill directly on a Smart Board touchscreen or mouse, or hold your clicker for a temporary cough mute.",
            states: "• Short Tap (<= 3px move, < 400ms): Toggles host mute.`r`n• Disabled notice: If Pointer Mute Control is OFF, shows tooltip without changing OBS.",
            actions: "• Enable/disable clicking via Tray -> Indicator Appearance -> Interactive HUD Click Actions.`r`n• Hold Mute Button >= 350ms when Cough / Push-to-Mute is enabled to mute temporarily until release.",
            configWhere: "• Tray -> Pointer Controls -> Enable Cough / Push-to-Mute (Hold)`r`n• Tray -> Indicator Appearance -> Interactive HUD Click Actions"
        },
        {
            id: 3,
            tag: "[3] Drag & Snap",
            pillTitle: "Touchscreen Drag, Magnetic Snap & 0.25x-5.0x Scale",
            tier: "Smart Board Positioning & Sizing",
            summary: "Drag smoothly with a finger or mouse anywhere on the pill; position saves automatically across restarts.",
            states: "• Magnetic Snap: Aligns within 14px to monitor work-area edges/centers or open windows.`r`n• Large-Display Scales: Supports Gigantic (x5.0) for 65`"-86`" 4K interactive boards.",
            actions: "• Left-Drag anywhere to move.`r`n• Reset via Tray -> Indicator Appearance -> Reset Indicator Position.",
            configWhere: "• Tray -> Indicator Appearance -> Indicator Scale`r`n• Tray -> Indicator Appearance -> Magnetic Edge/Window Snap`r`n• Tray -> Indicator Appearance -> Transparency Level / Sleek Corners"
        },
        {
            id: 4,
            tag: "[4] Menu & Dodge",
            pillTitle: "Right-Click Menu, Auto-Dodge & Click-Through (Alt)",
            tier: "Window Interaction & Safety",
            summary: "Full configuration menu on right-click plus pass-through / hover-dodge options so the pill never blocks whiteboard ink.",
            states: "• Auto-Dodge: Ghosts to 15% click-through under your cursor.`r`n• Click-Through: Passes clicks straight through to Smart Board apps underneath.",
            actions: "• Right-Click pill (or long-press on touch) for full Tray Menu.`r`n• Hold Alt to temporarily drag/click while Auto-Dodge or Click-Through is active.",
            configWhere: "• Tray -> Indicator Appearance -> Click-Through HUD (Hold Alt)`r`n• Tray -> Indicator Appearance -> Auto-Dodge HUD on Hover"
        }
    ]
}

/**
 * Returns the complete curated Help Knowledge Base covering:
 *  - Category "HUD": every HUD indicator & interaction gesture
 *  - Category "Tray": every single Primary & Remote Tray Menu item and submenu
 *  - Category "Features": complete plain-English feature encyclopedia A-Z
 *  - Category "Shortcuts": global hotkeys, clicker mapping, fallback shortcuts
 *  - Category "Remote": Smart Board / secondary device setup & networking
 */
GetHelpKnowledgeBase() {
    static cache := ""
    if IsObject(cache)
        return cache

    entries := []

    ; Helper to append normalized entries concisely
    Add(id, cat, group, title, menuPath, shortcut, defVal, summary, body, keywords := "", hudId := 0) {
        entries.Push({
            id: id,
            cat: cat,
            group: group,
            title: title,
            menuPath: menuPath,
            shortcut: shortcut,
            defVal: defVal,
            summary: summary,
            body: body,
            keywords: keywords,
            hudId: hudId,
            searchBlob: StrLower(title " " menuPath " " group " " cat " " shortcut " " defVal " " summary " " body " " keywords)
        })
    }

    ; ==========================================================================
    ; 1. HUD INDICATORS & GESTURES (Visual Anatomy [1]-[8] & Remote [1]-[4])
    ; ==========================================================================
    for item in GetPrimaryHudAnatomyItems() {
        fullBody := item.summary "`r`n`r`nCOLOR & VISUAL STATES`r`n" item.states "`r`n`r`nHOW TO USE`r`n" item.actions "`r`n`r`nWHERE TO CONFIGURE`r`n" item.configWhere
        Add("hud-" item.id, "HUD", "HUD Indicators & Gestures", item.tag " - " item.pillTitle, item.tier, "Short-click / Drag / Right-click", "Shown automatically per active mode", item.summary, fullBody, "hud pill indicator bar meter row " item.tag " " item.pillTitle, item.id)
    }
    for rItem in GetRemoteHudAnatomyItems() {
        rBody := rItem.summary "`r`n`r`nCOLOR & VISUAL STATES`r`n" rItem.states "`r`n`r`nHOW TO USE`r`n" rItem.actions "`r`n`r`nWHERE TO CONFIGURE`r`n" rItem.configWhere
        Add("rhud-" rItem.id, "HUD", "Remote 1-Tier Mic HUD", rItem.tag " - " rItem.pillTitle, rItem.tier, "Tap / Hold / Drag / Right-click", "1-Tier Mic Pill Always Shown", rItem.summary, rBody, "remote hud mic pill 1 tier " rItem.tag " " rItem.pillTitle, rItem.id)
    }

    ; ==========================================================================
    ; 2. COMPLETE SYSTEM TRAY MENU & SUBMENU REFERENCE (PRIMARY HOST)
    ; ==========================================================================
    Add("tray-ppt", "Tray", "Top-Level Quick Toggles", "Enable Full Pointer Controls (PPT + Mute)",
        "Tray > Enable Full Pointer Controls (PPT + Mute)", "Cycle with PptHotkey (default Ctrl+F12)", "OFF on fresh install (toggle ON to present)",
        "Arms PowerPoint slide key interception AND your clicker mic mute button.",
        "MENU ITEM: Enable Full Pointer Controls (PPT + Mute)`r`nLOCATION: Primary System Tray (Top section)`r`n`r`nWHAT IT DOES:`r`n• Intercepts slide navigation keys (PgUp/PgDn, Arrows, Space, Enter, Tab, Esc, Shift+F5) and forwards them in the background directly to PowerPoint using hybrid COM + ControlSend—even when OBS Studio or Zoom is focused.`r`n• Arms your Hardware Clicker Mute Button (default 'b') to toggle microphone mute.`r`n• Mutually exclusive with 'Enable Pointer Mute Only'.`r`n`r`nNOTE:`r`n• Automatically pauses while any PresenterSync settings window is active so typing doesn't flip your slides or mic.`r`n• Customize which slide keys are intercepted under Settings > Configure Pointer Intercepts.",
        "ppt powerpoint clicker full pointer controls slide route com controlsend")

    Add("tray-miconly", "Tray", "Top-Level Quick Toggles", "Enable Pointer Mute Only",
        "Tray > Enable Pointer Mute Only", "Cycle with PptHotkey (default Ctrl+F12)", "OFF",
        "Arms ONLY your clicker mute button while leaving all keyboard/arrow keys completely normal.",
        "MENU ITEM: Enable Pointer Mute Only`r`nLOCATION: Primary System Tray (Top section)`r`n`r`nWHAT IT DOES:`r`n• Leaves Arrow keys, PageUp/PageDown, Space, Enter, Tab, and Esc untouched for normal laptop typing or browser work.`r`n• Keeps ONLY your Hardware Clicker Mute Button (default 'b') active to mute/unmute your microphone cleanly from anywhere.`r`n• Automatically turns off 'Enable Full Pointer Controls (PPT + Mute)'.",
        "pointer mute only mic only clicker normal typing")

    Add("tray-ws", "Tray", "Top-Level Quick Toggles", "Enable OBS WebSocket Sync",
        "Tray > Enable OBS WebSocket Sync", "WsHotkey (default Alt+F12)", "OFF until enabled",
        "Connects PresenterSync directly to OBS Studio WebSocket v5 (port 4455) for 4-tier live telemetry.",
        "MENU ITEM: Enable OBS WebSocket Sync`r`nLOCATION: Primary System Tray (Live Sync section)`r`n`r`nWHAT IT DOES:`r`n• Connects over local TCP WebSocket (ws://127.0.0.1:4455) using SHA-256 OBS WebSocket v5 authentication.`r`n• Enables 2-way instant synchronization for Mic Mute, 3-state Recording (NOT REC / REC MM:SS / PAUSED), Studio Mode, Active Program Scene + switcher, Live Stream status + dropped frame alerts, and Virtual Camera (VCAM).`r`n• In Audio Routing Mode 3 (Dual App Sync), automatically pushes OBS mute changes to your active conferencing app (Zoom / Teams / Meet).`r`n• Prompts for your OBS password if auth fails (code 4009) instead of silently failing.",
        "obs websocket ws sync port 4455 v5 4009 live scene record stream vcam")

    Add("tray-zoom", "Tray", "Top-Level Quick Toggles", "Enable Zoom Monitoring",
        "Tray > Enable Zoom Monitoring", "ZoomHotkey (default Ctrl+Alt+F12)", "OFF until enabled",
        "Enables background Windows UI Automation monitoring for Zoom, Microsoft Teams, or Google Meet without OBS.",
        "MENU ITEM: Enable Zoom Monitoring`r`nLOCATION: Primary System Tray (Live Sync section)`r`n`r`nWHAT IT DOES:`r`n• Polls your chosen conferencing platform (Zoom, Microsoft Teams, or Google Meet) via native Windows UI Automation (Lib\UIA.ahk).`r`n• Syncs your LIVE/MUTED mic pill, detects meeting Recording (Row 2), and reads Unread Chat message counts into the Row 2 CHAT badge—without needing OBS open.`r`n• Also switches between Zoom, Teams, or Meet under Settings > Conferencing Platform.`r`n• Mutually exclusive with OBS WebSocket Sync when toggled in the tray.",
        "zoom teams meet conferencing monitoring uia chat badge background")

    Add("tray-ind", "Tray", "Top-Level Quick Toggles", "Show Mute Indicator",
        "Tray > Show Mute Indicator", "IndHotkey (default Ctrl+Shift+F12)", "ON",
        "Shows or hides the entire floating GDI+ HUD stack cleanly.",
        "MENU ITEM: Show Mute Indicator`r`nLOCATION: Primary System Tray (HUD section)`r`n`r`nWHAT IT DOES:`r`n• Completely shows or hides all floating HUD overlay pills (Row 1 Mic and Rows 2-4 if enabled).`r`n• Automatically pauses the breathing mute pulse, Voice Activity meter timer, and Auto-Dodge timer when hidden to consume zero CPU.`r`n• Quick shortcut: press Ctrl+Shift+F12 anytime (or right-click the tray icon to bring it back).",
        "show mute indicator hide unhide visibility toggle hud")

    Add("tray-extra", "Tray", "Top-Level Quick Toggles", "Show Extra HUDs",
        "Tray > Show Extra HUDs", "None (also inside Help > Live Status & Control Center)", "ON",
        "Toggles the upper telemetry tiers (REC, CHAT, STUDIO, Scene, STREAM, VCAM) above the Mic pill.",
        "MENU ITEM: Show Extra HUDs`r`nLOCATION: Primary System Tray (HUD section)`r`n`r`nWHAT IT DOES:`r`n• When ON: Displays Row 2 (REC + CHAT) in Conferencing/OBS modes, Row 3 (STUDIO + Active Scene) in OBS WebSocket mode, and Row 4 (STREAM + VCAM) when enabled.`r`n• When OFF: Keeps your HUD ultra-minimal—just the single Row 1 LIVE/MUTED Mic pill.",
        "show extra huds tiers stack compact rec chat studio scene")

    Add("tray-app-text", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Show Text Label",
        "Tray > Indicator Appearance > Show Text Label", "Also inside Help > Live Status & Control Center", "OFF (Compact Icon Mode)",
        "Switches HUD pills between compact Icon-Only width (80px base) and Icon + Label mode (168px base).",
        "MENU ITEM: Indicator Appearance > Show Text Label`r`n`r`nWHAT IT DOES:`r`n• When OFF (Default): Compact minimal icon pills (80px base width) ideal for corners and small screens.`r`n• When ON: Widens the stack (168px base) to show crisp readable labels: LIVE / MUTED, REC 04:18 / NOT REC / PAUSED, X NEW / CHAT, STUDIO, Scene Name, STREAM LIVE/WARN/OFF, and VCAM.",
        "show text label compact icon mode live muted words")

    Add("tray-app-mono", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Use Monochromatic Icon",
        "Tray > Indicator Appearance > Use Monochromatic Icon", "None", "OFF (Crisp White Icons)",
        "Switches HUD glyph icons from white to palette-matched high-contrast dark/tinted glyphs.",
        "MENU ITEM: Indicator Appearance > Use Monochromatic Icon`r`n`r`nWHAT IT DOES:`r`n• Off: Crisp white icons on colored pill backgrounds.`r`n• On: Tints each icon to a deep palette-matched tone (e.g. dark forest green on LIVE green pill, dark crimson on MUTED red pill) for a subtle low-glare studio aesthetic.",
        "monochromatic icon mono color white glyph style")

    Add("tray-app-corners", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Use Sleek Corners",
        "Tray > Indicator Appearance > Use Sleek Corners", "None", "OFF (8px Rounded Rectangle)",
        "Changes pill corners from modern rounded-square (8px) to full capsule/stadium shape.",
        "MENU ITEM: Indicator Appearance > Use Sleek Corners`r`n`r`nWHAT IT DOES:`r`n• Off: Balanced Windows 11 rounded corners (8px scaled radius).`r`n• On: Full stadium capsule pills (corner radius = half pill height).",
        "sleek corners capsule pill rounded square border radius")

    Add("tray-app-pulse", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Aggressive Mute Pulse",
        "Tray > Indicator Appearance > Aggressive Mute Pulse", "None", "OFF (Gentle 60% floor)",
        "Increases breathing pulse speed and depth (down to 20% opacity) while your mic is muted.",
        "MENU ITEM: Indicator Appearance > Aggressive Mute Pulse`r`n`r`nWHAT IT DOES:`r`n• Off: Smooth gentle breathing fade down to 60% opacity when MUTED.`r`n• On: Urgent, deeper pulsing animation (15ms step, 20% minimum opacity) so an accidental mute during a presentation is impossible to miss.",
        "aggressive mute pulse breathing flash warn opacity")

    Add("tray-app-cue", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Mute Audio Cue (Beep)",
        "Tray > Indicator Appearance > Mute Audio Cue (Beep)", "None", "OFF (Non-destructive default)",
        "Plays a crisp 2-tone acoustic chime whenever mic state transitions between LIVE and MUTED.",
        "MENU ITEM: Indicator Appearance > Mute Audio Cue (Beep)`r`n`r`nWHAT IT DOES:`r`n• Off by default so speakers/streams aren't disturbed unless wanted.`r`n• On: Plays an asynchronous two-tone ascending chime when going LIVE and a descending confirmation tone when MUTED—great when eyes are on your class or slides instead of the monitor.",
        "audio cue beep sound chime tone mute unmute acoustic feedback")

    Add("tray-app-toast", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Mute Status Toast",
        "Tray > Indicator Appearance > Mute Status Toast", "None", "OFF (Non-destructive default)",
        "Displays a brief floating cursor tooltip ('MIC MUTED' / 'MIC LIVE') for 1.5s when mute changes.",
        "MENU ITEM: Indicator Appearance > Mute Status Toast`r`n`r`nWHAT IT DOES:`r`n• Off by default.`r`n• On: Shows a lightweight 1.5-second status banner next to your pointer whenever mute flips—handy if the main HUD is dragged onto another monitor or hidden.",
        "mute status toast tooltip popup cursor banner feedback")

    Add("tray-app-vu", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Show Live Voice Activity Bar",
        "Tray > Indicator Appearance > Show Live Voice Activity Bar", "None", "ON",
        "Displays a live local CoreAudio peak VU bar along the bottom edge of the LIVE pill.",
        "MENU ITEM: Indicator Appearance > Show Live Voice Activity Bar`r`n`r`nWHAT IT DOES:`r`n• Samples your Windows default capture microphone via CoreAudio (IAudioMeterInformation::GetPeakValue) locally every 65ms—zero OBS WebSocket bandwidth overhead!`r`n• Draws a sleek luminous white bar along the bottom edge of the green LIVE pill as you speak so you have proof your mic is picking up audio.`r`n• Automatically flattens when MUTED.",
        "voice activity bar vu meter peak coreaudio mic level live bar")

    Add("tray-app-rectimer", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Show Recording Elapsed Timer",
        "Tray > Indicator Appearance > Show Recording Elapsed Timer", "None", "ON",
        "Shows live elapsed recording time ('REC MM:SS' or 'PAUSED MM:SS') inside Row 2 REC pill.",
        "MENU ITEM: Indicator Appearance > Show Recording Elapsed Timer`r`n`r`nWHAT IT DOES:`r`n• Reads active recording duration from OBS WebSocket on connect and ticks forward live every second while recording.`r`n• Freezes accurately when PAUSED and resets on stop.`r`n• Note: Requires 'Show Text Label' ON to display numerals inside the pill.",
        "recording elapsed timer stopwatch duration rec mm:ss paused")

    Add("tray-app-stream", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Show Stream & VCam HUD",
        "Tray > Indicator Appearance > Show Stream & VCam HUD", "None", "ON",
        "Toggles the 4th HUD layer (Row 4: Live Stream health/dropped frames pill + Virtual Camera pill).",
        "MENU ITEM: Indicator Appearance > Show Stream & VCam HUD`r`n`r`nWHAT IT DOES:`r`n• Shown whenever 'Show Extra HUDs' and 'OBS WebSocket Sync' are both enabled.`r`n• Left Pill (STREAM): Red/Rose LIVE while broadcasting, switches to orange WARN automatically on reconnect, congestion >= 35%, or newly skipped/dropped frames.`r`n• Right Pill (VCAM): Teal when OBS Virtual Camera is active; short-click toggles Virtual Camera cleanly.",
        "stream vcam 4th row tier hud dropped frames congestion virtual camera")

    Add("tray-app-clicks", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Interactive HUD Click Actions",
        "Tray > Indicator Appearance > Interactive HUD Click Actions", "None", "ON",
        "Enables or disables short-click actions on HUD pills without affecting drag or right-click.",
        "MENU ITEM: Indicator Appearance > Interactive HUD Click Actions`r`n`r`nWHAT IT DOES:`r`n• When ON: A quick short click (<= 3px mouse movement, < 400ms hold) on ANY pill triggers its quick-action (toggle Mute, toggle Rec, focus Chat, toggle Studio Mode, open Scene menu, toggle VCam, or inspect Stream stats).`r`n• Dragging (> 3px or longer hold) ALWAYS moves the stack cleanly without misfiring a click action.`r`n• Turn OFF if you want the HUD purely visual with no accidental clicks.",
        "interactive hud click actions short click drag toggle pills")

    Add("tray-app-snap", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Magnetic Edge/Window Snap",
        "Tray > Indicator Appearance > Magnetic Edge/Window Snap", "None", "ON",
        "Snaps the HUD stack cleanly within 14px to monitor work-area edges/centers and key app windows.",
        "MENU ITEM: Indicator Appearance > Magnetic Edge/Window Snap`r`n`r`nWHAT IT DOES:`r`n• On drag release, checks within 14px against all monitor work-area outer edges and centers, plus visible OBS Studio, PowerPoint, Zoom, and Teams window borders.`r`n• Snaps flush so your overlay sits neatly aligned with corners, sidebars, or presentation edges.",
        "magnetic snap edge window align 14px drag dock monitor")

    Add("tray-app-clickthru", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Click-Through HUD (Hold Alt)",
        "Tray > Indicator Appearance > Click-Through HUD (Hold Alt)", "Hold Alt to grab/click", "OFF",
        "Applies WS_EX_TRANSPARENT so clicks pass straight through the HUD to underlying apps; hold Alt to drag.",
        "MENU ITEM: Indicator Appearance > Click-Through HUD (Hold Alt)`r`n`r`nWHAT IT DOES:`r`n• Lets you interact with buttons, menus, or slide tools directly beneath the HUD without ever hitting the HUD by mistake.`r`n• Need to move or right-click the HUD? Hold down Alt—within 80ms the HUD temporarily becomes solid/clickable so you can drag, click, or right-click, then resumes click-through when Alt is released!",
        "click through transparent ws_ex_transparent alt hold pass through")

    Add("tray-app-dodge", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Auto-Dodge HUD on Hover",
        "Tray > Indicator Appearance > Auto-Dodge HUD on Hover", "Hold Alt to interact", "OFF",
        "Fades the HUD to 15% ghost click-through opacity whenever your cursor moves over it.",
        "MENU ITEM: Indicator Appearance > Auto-Dodge HUD on Hover`r`n`r`nWHAT IT DOES:`r`n• Keeps the HUD fully visible at your chosen opacity while you speak—until your mouse cursor approaches it.`r`n• When the cursor enters the HUD stack bounds (unless holding Alt), the stack ghosts to ~15% opacity and allows clicks right through to anything hidden underneath, then restores automatically when your cursor leaves!",
        "auto dodge hover ghost fade pass through alt hold")

    Add("tray-app-opacity", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Transparency Level",
        "Tray > Indicator Appearance > Transparency Level > Solid (100%) / Frosted (85%) / Ghost (50%)", "None", "Frosted (85%)",
        "Sets the baseline opacity of all HUD overlay pills: Solid (100%), Frosted (85%), or Ghost (50%).",
        "MENU ITEM: Indicator Appearance > Transparency Level`r`nOPTIONS:`r`n• Solid (100% / Alpha 255): Completely opaque maximum legibility.`r`n• Frosted (85% / Alpha 220 - Default): Sleek translucent finish that stays readable over slides.`r`n• Ghost (50% / Alpha 127): Subtle low-profile presence for busy workspaces.",
        "transparency opacity solid 100 frosted 85 ghost 50 alpha")

    Add("tray-app-scale", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Indicator Scale",
        "Tray > Indicator Appearance > Indicator Scale > Tiny (x0.25) ... Gigantic (x5.0)", "None", "Normal (x1.0)",
        "Resizes the entire GDI+ HUD stack crisply across 8 preset scales from 0.25x up to 5.0x for 4K walls.",
        "MENU ITEM: Indicator Appearance > Indicator Scale`r`nOPTIONS:`r`n• Tiny (x0.25), Small (x0.5), Normal (x1.0), Large (x1.5), Huge (x2.0), Massive (x2.5), Colossal (x3.0), Gigantic (x5.0).`r`n• Every GDI+ vector rounded pill, icon, label width, marquee speed, and row gap recalculates pixel-perfectly on every monitor DPI—ideal for both compact 1080p laptops and 86`" 4K Smart Boards.",
        "indicator scale resize size tiny small normal large huge massive colossal gigantic 0.25 0.5 1.0 1.5 2.0 2.5 3.0 5.0")

    Add("tray-app-theme", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > App Theme",
        "Tray > Indicator Appearance > App Theme > Follow System / Dark Mode / Light Mode", "Also in Help > Live Status", "Follow System",
        "Themes all PresenterSync dialogs, Control Center, Help, and Tray Menus across Dark, Light, or Windows System mode.",
        "MENU ITEM: Indicator Appearance > App Theme`r`nOPTIONS:`r`n• Follow System (Default): Matches Windows 11/10 dark/light personalization live.`r`n• Dark Mode: Forces Windows 11 Explorer dark surfaces (#202020 / #2C2C2C) across windows & menus.`r`n• Light Mode: Forces crisp Fluent light surfaces (#F3F3F3 / #FFFFFF).",
        "app theme follow system dark mode light mode fluent win11")

    Add("tray-app-preset", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > HUD Color Preset",
        "Tray > Indicator Appearance > HUD Color Preset > Standard / Colorblind Safe / OLED Stealth / Broadcast Tally / Cyber Ocean", "None", "Standard",
        "Applies one of 5 curated color palettes across all HUD tiers immediately.",
        "MENU ITEM: Indicator Appearance > HUD Color Preset`r`nPRESETS:`r`n1. Standard (Default): Classic Green LIVE / Red MUTED + vivid status hues.`r`n2. Colorblind Safe: Scientifically tuned Okabe-Ito Blue LIVE / Burnt-Orange MUTED palette so red-green colorblind presenters distinguish states effortlessly.`r`n3. OLED Stealth: Ultra-low-glare deep charcoal fills with high-contrast glowing icons.`r`n4. Broadcast Tally: Classic TV studio emerald/crimson/purple/sky tally colors.`r`n5. Cyber Ocean: Vivid cyan LIVE / magenta MUTED / midnight slate finish.",
        "hud color preset palette standard colorblind safe oled stealth broadcast tally cyber ocean theme")

    Add("tray-app-resetpos", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Reset Indicator Position",
        "Tray > Indicator Appearance > Reset Indicator Position", "None", "Bottom-Right Corner",
        "Snaps the floating HUD stack immediately back to the default bottom-right primary monitor corner.",
        "MENU ITEM: Indicator Appearance > Reset Indicator Position`r`n`r`nWHAT IT DOES:`r`n• Resets Position X/Y back to 'Default' and centers the HUD cleanly in the bottom-right corner above the taskbar—helpful if a secondary monitor was unplugged.",
        "reset indicator position lost monitor corner default coordinates")

    Add("tray-app-resetapp", "Tray", "Indicator Appearance Submenu", "Indicator Appearance > Restore Default Appearance",
        "Tray > Indicator Appearance > Restore Default Appearance", "None", "N/A (Action)",
        "Resets HUD scale, opacity, labels, corners, pulse, theme, palette, and smart hover flags back to clean defaults.",
        "MENU ITEM: Indicator Appearance > Restore Default Appearance`r`n`r`nWHAT IT DOES:`r`n• Restores Scale=1.0x, Opacity=85%, Theme=System, Preset=Standard, Text=OFF, Mono=OFF, Sleek=OFF, Pulse=OFF, AudioCue=OFF, Toast=OFF, VoiceMeter=ON, RecTimer=ON, StreamHUD=ON, ClickActions=ON, MagneticSnap=ON, ClickThrough=OFF, AutoDodge=OFF.`r`n• Note: Does not erase your shortcuts, OBS password, or saved coordinates.",
        "restore default appearance factory reset hud look")

    Add("tray-cc", "Tray", "Settings Submenu", "Control Center... / Settings > Control Center (All Settings)...",
        "Tray > Control Center...  (and Settings > Control Center (All Settings)...)", "None", "Opens Unified 6-Tab Dashboard",
        "Opens the unified Fluent Control Center window containing all settings organized across 6 tabs.",
        "MENU ITEM: Control Center...`r`nLOCATION: Primary System Tray AND Settings Submenu`r`n`r`nWHAT IT DOES:`r`n• Opens one sleek Windows 11 Fluent 6-tab dashboard covering: Audio & Conf, OBS & Stream, Pointer, HUD & Theme, Remote, and Profiles & Sys.`r`n• Clicking 'Apply & Save' validates hotkeys, updates MicOverlay_Config.ini, rebinds hotkeys, switches telemetry backends, and refreshes HUD + Tray live—zero restart required!",
        "control center dashboard all settings apply save live")

    Add("tray-set-routing", "Tray", "Settings Submenu", "Settings > Audio Routing Mode",
        "Tray > Settings > Audio Routing Mode > 1: Pro OBS Setup / 2: Standard Direct Mic / 3: Dual App Sync", "Re-apply restarts app cleanly", "Chosen on First Launch",
        "Selects how microphone mute triggers are routed between OBS Studio and your conferencing app.",
        "MENU ITEM: Settings > Audio Routing Mode`r`nMODES:`r`n• 1: Pro OBS Setup (VB-Cable): Best when OBS processes your mic and feeds Zoom/Teams/Meet via VB-Cable. Mute commands target OBS directly.`r`n• 2: Standard Direct Mic (Zoom-Only): No OBS needed. Mute dispatches directly to Zoom/Teams/Meet and automatically enables the Companion Relay Bridge for PresenterSync Remote!`r`n• 3: Dual App Sync (OBS + Zoom): Keeps OBS AND your Conferencing app synchronized two-way so muting either app updates both.",
        "audio routing mode vb-cable mode 1 mode 2 mode 3 dual app sync")

    Add("tray-set-wizard", "Tray", "Settings Submenu", "Settings > Run Audio Setup Wizard...",
        "Tray > Settings > Run Audio Setup Wizard...", "None", "Runs automatically on first launch",
        "Re-launches the quick initial setup dialog to pick your Audio Routing Mode and main mute shortcuts.",
        "MENU ITEM: Settings > Run Audio Setup Wizard...`r`n`r`nWHAT IT DOES:`r`n• Walks you step-by-step through choosing Routing Mode (1, 2, or 3) and configuring OBS Mute / Conferencing Mute fallback hotkeys.",
        "run audio setup wizard initial configuration")

    Add("tray-set-conf", "Tray", "Settings Submenu", "Settings > Conferencing Platform",
        "Tray > Settings > Conferencing Platform > Zoom / Microsoft Teams / Google Meet", "None", "Zoom",
        "Selects which conferencing app PresenterSync monitors via UIA and targets with mute hotkeys.",
        "MENU ITEM: Settings > Conferencing Platform`r`nOPTIONS:`r`n• Zoom (Default shortcut Alt+A, window ahk_exe Zoom.exe)`r`n• Microsoft Teams (Default shortcut Ctrl+Shift+M, window ms-teams.exe / Teams.exe)`r`n• Google Meet (Default shortcut Ctrl+D, browser tab 'Meet' in Chrome/Edge/Firefox/Brave)`r`n• Determines which UIA control signatures are read for Mic mute, Recording, and Unread Chat count.",
        "conferencing platform zoom microsoft teams google meet uia select")

    Add("tray-set-profiles", "Tray", "Settings Submenu", "Settings > Configuration Profiles",
        "Tray > Settings > Configuration Profiles > [Saved Profiles] / Save Current as New Profile... / Manage Profiles...", "None", "Default",
        "Create, save, switch between, and delete named configuration snapshots stored right inside your .ini.",
        "MENU ITEM: Settings > Configuration Profiles`r`n`r`nWHAT IT DOES:`r`n• Switch between named setups (e.g., 'Lecture Hall OBS', 'Morning Zoom Call', 'Smart Board 4K') in 1 click without losing settings.`r`n• Each snapshot stores Routing Mode, Platform, Hotkeys, Telemetry flags, HUD Theme/Palette/Scale, Position, and Pointer settings under [Profile:<Name>] in MicOverlay_Config.ini.`r`n• Clicking 'Save Current as New Profile...' or 'Manage Profiles...' opens the Profile Manager dialog ('Default' is protected against accidental deletion).",
        "configuration profiles save load switch delete manage presets ini")

    Add("tray-set-obs", "Tray", "Settings Submenu", "Settings > Change OBS Settings",
        "Tray > Settings > Change OBS Settings", "Save & Restart", "Port 4455, Target: Mic/Aux",
        "Configures OBS fallback Mute/Rec/Pause shortcuts, exact Audio Source Name, and WebSocket password.",
        "MENU ITEM: Settings > Change OBS Settings`r`n`r`nFIELDS:`r`n• OBS Mute Shortcut: Optional when WebSocket Sync is ON; required in Mode 1/3 when WebSocket is OFF.`r`n• Start/Stop Recording Shortcut (Default Ctrl+F9) & Pause/Resume (Default Ctrl+F10).`r`n• Exact OBS Audio Source Name (Default 'Mic/Aux'): Must match the exact capitalization in OBS Audio Mixer.`r`n• OBS WebSocket Password: Password configured under OBS Tools -> WebSocket Server Settings.",
        "change obs settings password mic aux hotkey target source")

    Add("tray-set-zoom", "Tray", "Settings Submenu", "Settings > Change Zoom Shortcuts",
        "Tray > Settings > Change Zoom Shortcuts", "Save & Restart", "Zoom !a, Teams ^+m, Meet ^d, Rec !r, Pause !p",
        "Customizes keyboard mute shortcuts for Zoom, Microsoft Teams, Google Meet, plus Zoom Rec/Pause keys.",
        "MENU ITEM: Settings > Change Zoom Shortcuts`r`n`r`nWHAT IT DOES:`r`n• Lets you customize the hotkeys PresenterSync sends (or observes) for Zoom Mute, Microsoft Teams Mute, Google Meet Mute, Zoom Start/Stop Rec, and Zoom Pause/Resume Rec.",
        "change zoom shortcuts conferencing teams meet rec pause hotkey")

    Add("tray-set-remmode", "Tray", "Settings Submenu", "Settings > Remote Network Mode",
        "Tray > Settings > Remote Network Mode > Same Router (LAN) / Different Networks (Internet)", "Applied live", "Same Router (LAN)",
        "Chooses how PresenterSync Remote connects: direct LAN WebSocket or encrypted Internet Relay bridge.",
        "MENU ITEM: Settings > Remote Network Mode`r`nMODES:`r`n• Same Router (LAN - Default): Lowest latency (< 2ms). Uses mDNS (.local) + all local Ethernet/Wi-Fi IPs.`r`n• Different Networks (Internet): Enables the Host Internet Pairing Relay (PS-XXXX-XXXX) so your Smart Board/secondary PC works even across university VLANs, separate routers, or mobile hotspots (and automatically activates whenever Mode 2 Conferencing-Only is used!).",
        "remote network mode lan internet wan relay router bridge pairing")

    Add("tray-set-reminfo", "Tray", "Settings Submenu", "Settings > Remote Companion Info...",
        "Tray > Settings > Remote Companion Info...", "Live auto-refresh + Pair Code", "N/A",
        "Shows live QR code, 6-char Session Code, Host Bridge :4456 status, live paired remotes, and WAN Relay code.",
        "MENU ITEM: Settings > Remote Companion Info...`r`n`r`nWHAT IT DOES:`r`n• Displays your offline QR Code (presentersync://connect?...), 6-character LAN Session Code (XXX-XXX) with New rotate button, Host Bridge port 4456 status, and live auto-refreshing paired/connected Windows & Android remote roster.`r`n• Also shows your computer's .local mDNS hostname, detected LAN IPv4 addresses, 'Copy Universal String to Clipboard', your WAN Relay Code (PS-XXXX-XXXX), and 'Close Remote Companion...'.",
        "remote companion info universal connection string ip mdns copy pairing code qr session 4456 live devices")

    Add("tray-set-closerem", "Tray", "Settings & Top-Level", "Close Remote Companion...",
        "Tray > Close Remote Companion...  (and Settings > Close Remote Companion...)", "Confirmed prompt", "Safe manual shutdown",
        "Sends an explicit confirmed shutdown signal to turn off PresenterSync_Remote on your secondary device.",
        "MENU ITEM: Close Remote Companion...`r`nLOCATION: Top-level Tray AND Settings Submenu`r`n`r`nWHAT IT DOES:`r`n• Opens a confirmation prompt and broadcasts an explicit 'CloseRemote' signal over OBS WebSocket (and/or Internet Relay) to close PresenterSync Remote on the Smart Board.`r`n• Designed safely so closing/restarting your Primary PC app NEVER shuts down your Remote PC by accident unless you explicitly confirm here.",
        "close remote companion shutdown secondary turn off smart board")

    Add("tray-set-ptrkey", "Tray", "Settings Submenu", "Settings > Change Pointer Mute Button",
        "Tray > Settings > Change Pointer Mute Button", "Capture OR type AHK key", "b",
        "Captures any wireless presenter button press (or typed AutoHotkey key name) to assign as your mic mute trigger.",
        "MENU ITEM: Settings > Change Pointer Mute Button`r`n`r`nWHAT IT DOES:`r`n• Opens the live Capture Dialog—simply press the mute/blank-screen/laser button on your clicker to capture its exact hardware key name.`r`n• Or click inside the box to type any AHK key (e.g. b, Tab, PgDn, Esc, Media_Play_Pause, F12) or 'None' to unbind.",
        "change pointer mute button hardware clicker key capture hwmutekey")

    Add("tray-set-cough", "Tray", "Settings Submenu", "Settings > Enable Cough / Push-to-Mute (Hold)",
        "Tray > Settings > Enable Cough / Push-to-Mute (Hold)", "Hold >= 350ms", "OFF (Standard Toggle)",
        "Turns a long press (>= 350ms) of your mute button into a temporary hold-to-mute that unmutes on release.",
        "MENU ITEM: Enable Cough / Push-to-Mute (Hold)`r`n`r`nWHAT IT DOES:`r`n• Short Tap (< 350ms): Behaves like a normal mute toggle (stays muted or live).`r`n• Hold (>= 350ms): Immediately mutes when pressed so you can cough, sip water, or whisper off-mic, then automatically flips back to LIVE the instant you release the button!`r`n• Supported identically on BOTH Primary Host and Remote Companion.",
        "cough push to mute hold gesture 350ms release temporary mute")

    Add("tray-set-intercept", "Tray", "Settings Submenu", "Settings > Configure Pointer Intercepts",
        "Tray > Settings > Configure Pointer Intercepts", "Save & Restart", "All 6 key groups ON",
        "Selects which slide navigation key groups are caught and sent to PowerPoint in Full PPT mode.",
        "MENU ITEM: Configure Pointer Intercepts`r`nCHECKBOXES:`r`n• Arrow Keys (Up, Down, Left, Right)`r`n• Page Keys (PgUp, PgDn — most clickers)`r`n• Spacebar, Enter Key, Tab Key, Escape Key`r`n• Note: Shift+F5 is always routed in Full PPT mode unless assigned as your Clicker Mute button.",
        "configure pointer intercepts arrows pgup pgdn space enter tab esc powerpoint")

    Add("tray-set-tester", "Tray", "Settings Submenu", "Settings > Launch Clicker Tester",
        "Tray > Settings > Launch Clicker Tester", "Close / Esc", "Live diagnostic tool",
        "Opens a live key-inspector window that displays the exact AutoHotkey key name sent by your clicker.",
        "MENU ITEM: Launch Clicker Tester`r`n`r`nWHAT IT DOES:`r`n• Press any button on your wireless presenter clicker to see its true AutoHotkey key name (for instance, 'b', 'Period', 'PgDn', 'Volume_Down', or 'F5').`r`n• Use this before setting 'Change Pointer Mute Button' if you aren't sure what key a button emits.",
        "launch clicker tester pointer tester diagnose key name")

    Add("tray-set-apphk", "Tray", "Settings Submenu", "Settings > Change App Shortcuts",
        "Tray > Settings > Change App Shortcuts", "Ctrl+F12 / Alt+F12 / etc.", "Save & Restart",
        "Rebinds all 6 global PresenterSync keyboard shortcuts (Pointer, WS, Conf, HUD, Suspend, Exit).",
        "MENU ITEM: Change App Shortcuts`r`nCONTROLS:`r`n• Cycle Pointer Mode (Default: Ctrl+F12)`r`n• Toggle OBS WebSocket (Default: Alt+F12)`r`n• Toggle Conf Monitor (Default: Ctrl+Alt+F12)`r`n• Toggle Indicator (Default: Ctrl+Shift+F12)`r`n• Suspend Hotkeys (Default: Ctrl+Alt+Shift+F12)`r`n• Exit PresenterSync (Default: Alt+Shift+F12)`r`n(Also editable live without restart in Control Center > Profiles & Sys!)",
        "change app shortcuts global hotkeys rebind cycle pointer suspend exit")

    Add("tray-set-startup", "Tray", "Settings Submenu", "Settings > Start with Windows",
        "Tray > Settings > Start with Windows", "None", "OFF (Explicit opt-in only)",
        "Adds or removes PresenterSync from your current Windows user Run startup registry key.",
        "MENU ITEM: Start with Windows`r`n`r`nWHAT IT DOES:`r`n• Strictly OFF by default so PresenterSync never alters your Windows startup silently.`r`n• When checked ON, registers PresenterSync (or PresenterSync Remote) under HKCU\Software\Microsoft\Windows\CurrentVersion\Run so your presenter overlay boots automatically when you sign in.",
        "start with windows autostart boot login registry run hkcu")

    Add("tray-set-updates", "Tray", "Bottom Utilities & Exit", "Check for Updates...",
        "Tray > Check for Updates...  (and Settings > Check for Updates...)", "None", "Online GitHub check",
        "Checks GitHub Releases/Tags and tells you cleanly if a newer PresenterSync version is available.",
        "MENU ITEM: Check for Updates...`r`n`r`nWHAT IT DOES:`r`n• Queries https://api.github.com/repos/SaabithJiffry/PresenterSync/releases/latest (with /tags fallback) and compares semantic versions (SemVer).`r`n• If a newer release exists, offers a 1-click prompt to open the GitHub Releases download page in your browser.",
        "check for updates github releases version upgrade semver")

    Add("tray-help", "Tray", "Bottom Utilities & Exit", "Help & Shortcuts",
        "Tray > Help & Shortcuts", "None (Auto-opens on First Run)", "Help Center",
        "Opens this interactive Help Center featuring Visual HUD Diagrams, Tray Guide, Feature A-Z, and Search.",
        "MENU ITEM: Help & Shortcuts`r`n`r`nWHAT IT DOES:`r`n• Opens this tabbed interactive Help window with live GDI+ HUD Anatomy diagrams, full Tray Menu & Submenu reference, Searchable Knowledge Base, active Shortcuts list, Remote Companion guide, and Live Status toggles.",
        "help shortcuts manual guide documentation")

    Add("tray-about", "Tray", "Bottom Utilities & Exit", "About PresenterSync",
        "Tray > About PresenterSync", "None", "Version & Credits",
        "Displays app version, description, author credits, GitHub repository link, Update checker, and Help link.",
        "MENU ITEM: About PresenterSync`r`n`r`nWHAT IT DOES:`r`n• Shows PresenterSync v" UIConstants.APP_VERSION ", creator credit (Saabith Jiffry), quick button to open the GitHub Repository, Check for Updates button, and Help & Guide launcher.",
        "about presentersync version credits github")

    Add("tray-suspend", "Tray", "Bottom Utilities & Exit", "Suspend All Hotkeys",
        "Tray > Suspend All Hotkeys", "SuspendHotkey (default Ctrl+Alt+Shift+F12)", "Active (Not Suspended)",
        "Temporarily pauses all clicker and system hotkeys while keeping the HUD and app open.",
        "MENU ITEM: Suspend All Hotkeys`r`n`r`nWHAT IT DOES:`r`n• Suspends PowerPoint routing keys, hardware mute triggers, and global hotkeys except the Suspend toggle itself.`r`n• Useful if another presentation app needs unintercepted keys temporarily without exiting PresenterSync.",
        "suspend all hotkeys pause keys temporary disable")

    Add("tray-exit", "Tray", "Bottom Utilities & Exit", "Exit PresenterSync",
        "Tray > Exit PresenterSync", "ExitHotkey (default Alt+Shift+F12)", "Closes Primary Host",
        "Cleanly shuts down OBS WebSocket, Relay, UIA handles, GDI+ resources, and exits PresenterSync.",
        "MENU ITEM: Exit PresenterSync`r`n`r`nWHAT IT DOES:`r`n• Cleanly saves state, shuts down UIA/WebSocket/Theme/GDI+ resources, and exits without leaving orphan HUD windows behind.`r`n• Note: Does NOT force-close any connected PresenterSync Remote companion (use 'Close Remote Companion...' for that).",
        "exit presentersync quit close stop")

    ; Remote Tray-specific items so Tray explorer covers Remote completely too!
    Add("rtray-status", "Tray", "Remote Companion Tray Menu", "Remote Status Header Banner",
        "Remote Tray > ● Connected / ⚠ Mic Not Found / ✕ Auth Failed / ○ Searching", "Read-only status row", "Live status indicator",
        "Top disabled status line inside PresenterSync Remote's tray menu showing live link & mic health.",
        "REMOTE TRAY ITEM: Top Connection Banner`r`nSTATES:`r`n• ● Connected: <host> — Linked cleanly and synced.`r`n• ⚠ Connected (Mic Not Found) — OBS link is open, but Target Audio Source casing doesn't match OBS Mixer.`r`n• ✕ Auth Failed — OBS WebSocket password mismatch (code 4009).`r`n• ○ Searching for OBS Host... — Cycling LAN candidates or awaiting Relay bridge.",
        "remote tray status connected auth failed mic not found searching")

    Add("rtray-ptrmenu", "Tray", "Remote Companion Tray Menu", "Pointer Controls > Enable Pointer Mute & Sub-Items",
        "Remote Tray > Pointer Controls > Enable Pointer Mute / Cough Push-to-Mute / Change Mute Key / Clicker Tester", "Ctrl+F12 (Toggle Mute Control)", "Enable Pointer Mute ON",
        "Controls whether the secondary device's clicker can toggle host mute while keeping the Remote HUD synced.",
        "REMOTE TRAY SUBMENU: Pointer Controls`r`nITEMS:`r`n• Enable Pointer Mute (Default ON, hotkey Ctrl+F12): Turn OFF if an audience member or presenter is holding a secondary clicker and you only want passive live mic status visibility.`r`n• Enable Cough / Push-to-Mute (Hold): Hold >= 350ms to temporarily mute until release.`r`n• Change Pointer Mute Button...: Capture clicker button on the secondary PC.`r`n• Launch Clicker Tester...: Inspect clicker key names locally.",
        "remote pointer controls enable pointer mute ctrl f12 passive")

    Add("rtray-conn", "Tray", "Remote Companion Tray Menu", "Change OBS Connection... & Change App Shortcuts...",
        "Remote Tray > Change OBS Connection... / Change App Shortcuts...", "Alt+Shift+F12 (Exit)", "Wizard on first boot",
        "Edits LAN vs Internet Relay mode, Pairing Code, Host Address, Port 4455, Password, Target Mic, and Remote hotkeys.",
        "REMOTE TRAY ITEMS: Connection & App Shortcuts`r`n• Change OBS Connection...: Switch Same Router (LAN) vs Different Networks (Internet Relay), enter Pairing Code or Universal LAN String, set OBS Port (4455), Password, exact Mic Name, and run Test Connection before Save & Reconnect.`r`n• Change App Shortcuts...: Rebind 'Toggle Pointer Mute' (default Ctrl+F12) and 'Exit PresenterSync Remote' (default Alt+Shift+F12).",
        "remote change obs connection shortcuts pairing host address port")

    Add("rtray-ind", "Tray", "Remote Companion Tray Menu", "Show Mute Indicator & Indicator Appearance",
        "Remote Tray > Show Mute Indicator / Indicator Appearance", "None", "Show=ON, Frosted 85%, Scale 1.0x",
        "Shows/hides the Remote Mic pill and customizes text label, monochrome icon, corners, pulse, theme, palette, snap, click-through, and auto-dodge.",
        "REMOTE TRAY ITEMS: HUD Visibility & Appearance`r`n• Show Mute Indicator: Shows or hides the 1-tier LIVE/MUTED Mic HUD on the secondary display.`r`n• Indicator Appearance submenu: Includes Show Text Label, Monochromatic Icon, Sleek Corners, Aggressive Mute Pulse, Mute Audio Cue, Mute Status Toast, Interactive Click Actions, Magnetic Snap, Click-Through (Hold Alt), Auto-Dodge, Transparency (100/85/50%), Scale (0.25x-5.0x), App Theme, Color Preset, Reset Position, and Restore Defaults.",
        "remote show mute indicator appearance scale preset theme snap click through dodge")

    Add("rtray-about", "Tray", "Remote Companion Tray Menu", "About PresenterSync Remote (Curated Scope)",
        "Remote Tray > About PresenterSync Remote...", "None", "Remote Companion Edition",
        "Shows PresenterSync Remote's version, stripped-down 1-tier capabilities, omitted host modules, GitHub link, updates, and Help launcher.",
        "REMOTE TRAY ITEM: About PresenterSync Remote...`r`n`r`nWHAT IT SHOWS:`r`n• Curated strictly to PresenterSync Remote v" UIConstants.APP_VERSION " (Remote Companion Edition):`r`n  - Dedicated 1-Tier LIVE / MUTED Mic HUD (OBS WebSocket v5 or Mode 2 Conferencing Relay Bridge).`r`n  - Dual Network Transport: Same Router (LAN failover) and Different Networks (Internet Pairing Code).`r`n  - Secondary Clicker Mute Button, Cough Hold (>= 350ms), local Clicker Tester, and Ctrl+F12 arming toggle.`r`n  - Visual customization up to 5.0x scale, 5 color presets, snapping, Auto-Dodge, Click-Through (hold Alt), Start with Windows, and GitHub Updates.`r`n• Clearly notes that multi-tier overlay panels, live CoreAudio voice meter, Windows UIA meeting tracking, Control Center, Setup Wizard, and PowerPoint slide navigation live on the Primary Host PC.",
        "remote tray about capabilities scope omitted host stripped down credits")

    Add("rtray-util", "Tray", "Remote Companion Tray Menu", "Start with Windows, Updates, Help & Setup Guide, Suspend & Exit",
        "Remote Tray > Start with Windows / Check for Updates... / Help & Setup Guide... / Suspend / Exit", "Alt+Shift+F12 (Exit)", "Startup OFF",
        "System utilities inside PresenterSync Remote's tray menu for auto-start, GitHub updates, help, hotkey suspension, and clean exit.",
        "REMOTE TRAY UTILITIES`r`n• Start with Windows: Opt-in HKCU Run registry auto-start for PresenterSync Remote (default OFF).`r`n• Check for Updates...: Checks GitHub Releases against the running version.`r`n• Help & Setup Guide...: Opens Remote's 3-tab Mic HUD diagram, setup guide, and searchable Tray explorer.`r`n• About PresenterSync Remote...: Curated Remote capabilities, version & credits.`r`n• Suspend All Hotkeys / Exit PresenterSync Remote: Pauses Remote hotkeys or closes Remote cleanly without affecting the Primary Host.",
        "remote tray start with windows updates help about suspend exit")

    ; Remote-isolated overrides for entries whose Primary wording references multi-tier pills or Control Center
    Add("rtray-text", "Tray", "Remote Companion Tray Menu", "Indicator Appearance > Show Text Label",
        "Remote Tray > Indicator Appearance > Show Text Label", "None", "OFF (Compact Icon Mode)",
        "Switches Remote's 1-tier Mic pill between compact Icon-Only width (80px base) and Icon + Label mode (168px base).",
        "REMOTE TRAY ITEM: Indicator Appearance > Show Text Label`r`n`r`nWHAT IT DOES:`r`n• When OFF (Default): Compact 80px base microphone icon pill ideal for corners and whiteboards.`r`n• When ON: Widens the Remote pill (168px base) to show a bold readable label beside the mic icon: LIVE or MUTED.",
        "remote show text label compact icon mode live muted words appearance")

    Add("rtray-clicks", "Tray", "Remote Companion Tray Menu", "Indicator Appearance > Interactive HUD Click Actions",
        "Remote Tray > Indicator Appearance > Interactive HUD Click Actions", "Short-Tap Pill", "ON",
        "Lets a quick tap (<= 3px move, < 400ms) on Remote's Mic pill toggle host mute while longer drags move the pill.",
        "REMOTE TRAY ITEM: Indicator Appearance > Interactive HUD Click Actions`r`n`r`nWHAT IT DOES:`r`n• When ON: Tapping the Remote Mic pill briefly (<= 3px movement, < 400ms hold) toggles mic Mute/Unmute on the Primary Host (requires Pointer Mute ON via Ctrl+F12).`r`n• Dragging (> 3px or longer hold) repositions the Remote pill cleanly across displays or touchscreens without misfiring a mute toggle.`r`n• Turn OFF for view-only wall display mode.",
        "remote interactive hud click actions tap drag touch toggle mute appearance")

    Add("rtray-theme", "Tray", "Remote Companion Tray Menu", "Indicator Appearance > App Theme",
        "Remote Tray > Indicator Appearance > App Theme > Follow System / Dark Mode / Light Mode", "None", "Follow System",
        "Themes PresenterSync Remote's Help, Connection, Shortcuts, About, and Tray dialogs across Dark, Light, or Windows System mode.",
        "REMOTE TRAY ITEM: Indicator Appearance > App Theme`r`nOPTIONS:`r`n• Follow System (Default): Matches Windows 11/10 dark or light personalization live.`r`n• Dark Mode: Forces Windows 11 dark surfaces across Remote dialogs and popup menus.`r`n• Light Mode: Forces crisp Fluent light surfaces across Remote dialogs and menus.",
        "remote app theme follow system dark mode light mode fluent win11 appearance")

    Add("rtray-resetapp", "Tray", "Remote Companion Tray Menu", "Indicator Appearance > Restore Default Appearance",
        "Remote Tray > Indicator Appearance > Restore Default Appearance", "None", "N/A (Action)",
        "Resets Remote HUD scale, opacity, labels, corners, pulse, theme, palette, and smart hover flags back to clean defaults.",
        "REMOTE TRAY ITEM: Indicator Appearance > Restore Default Appearance`r`n`r`nWHAT IT DOES:`r`n• Restores Scale=1.0x, Opacity=85%, Theme=System, Preset=Standard, Text=OFF, Mono=OFF, Sleek=OFF, Pulse=OFF, AudioCue=OFF, Toast=OFF, ClickActions=ON, MagneticSnap=ON, ClickThrough=OFF, AutoDodge=OFF.`r`n• Note: Preserves your OBS/Pairing connection settings, hotkeys, and saved screen position.",
        "remote restore default appearance factory reset hud look")

    Add("rtray-startup", "Tray", "Remote Companion Tray Menu", "Start with Windows",
        "Remote Tray > Start with Windows", "None", "OFF (Explicit opt-in only)",
        "Adds or removes PresenterSync Remote from your current Windows user Run startup registry key.",
        "REMOTE TRAY ITEM: Start with Windows`r`n`r`nWHAT IT DOES:`r`n• Strictly OFF by default so Smart Boards or secondary PCs never add startup entries silently.`r`n• When checked ON, registers PresenterSync Remote under HKCU\Software\Microsoft\Windows\CurrentVersion\Run to launch automatically on sign-in.",
        "remote start with windows autostart boot login registry run hkcu")

    Add("rtray-shortcut", "Tray", "Remote Companion Tray Menu", "Create Desktop Shortcut for Instance...",
        "Remote Tray > Create Desktop Shortcut for Instance...", "None", "Action Dialog",
        "Generates a Windows Desktop .lnk shortcut pinned to -Instance <name> (and optional -Config path).",
        "REMOTE TRAY ITEM: Create Desktop Shortcut for Instance...`r`n`r`nWHAT IT DOES:`r`n• Creates a 1-click Desktop .lnk launching PresenterSync_Remote.exe -Instance `"<name>`" so separate rooms, podiums, or Smart Boards maintain isolated INIs, HUD positions, and host targets.",
        "remote desktop shortcut lnk instance multi instance room podium smart board")

    Add("rfeat-auth-states", "Features", "Remote Clicker & Ergonomics", "Distinct OBS Password Required (PW REQ) vs Auth Failed (AUTH ERR)",
        "Remote Mic HUD / Remote Tray / Change OBS Connection", "None", "Automatic status badge",
        "Immediately distinguishes a missing blank OBS password (amber PW REQ) from a wrong/rejected password or pairing code (crimson AUTH ERR).",
        "REMOTE AUTHENTICATION BADGES:`r`n• PW REQ (Amber Lock Badge): OBS WebSocket requires authentication and your password field is blank.`r`n• AUTH ERR (Crimson Error Badge): Supplied OBS password, Bridge code/token, or Internet Relay secret was rejected.`r`n• Both pause reconnect loops safely until you update credentials under Change OBS Connection...",
        "remote pw req auth err 4009 password required failed lock badge status")

    Add("rtray-updates", "Tray", "Remote Companion Tray Menu", "Check for Updates...",
        "Remote Tray > Check for Updates...", "None", "Online GitHub check",
        "Checks GitHub Releases/Tags and reports if a newer PresenterSync / Remote version is available.",
        "REMOTE TRAY ITEM: Check for Updates...`r`n`r`nWHAT IT DOES:`r`n• Queries https://api.github.com/repos/SaabithJiffry/PresenterSync/releases/latest (with /tags fallback) and compares semantic versions (SemVer).`r`n• Offers a 1-click prompt to open the GitHub Releases download page if an update exists.",
        "remote check for updates github releases version upgrade semver")

    Add("rfeat-cough", "Features", "Remote Clicker & Ergonomics", "Cough / Push-to-Mute Hold Gesture",
        "Remote Tray > Pointer Controls > Enable Cough / Push-to-Mute (Hold)", "Hold Mute Button >= 350ms", "OFF (Standard Toggle)",
        "Temporarily mute just by holding your Remote clicker mute button down—and automatically return to LIVE upon release.",
        "COUGH / PUSH-TO-MUTE GESTURE (REMOTE)`r`n`r`n• Standard Mode (OFF): Every mute button tap flips Mute <-> Live.`r`n• Cough Mode (ON):`r`n  - Tap briefly (< 350ms): Toggles normally (stays Muted or Live).`r`n  - Hold down (>= 350ms): Mutes immediately while held, then transmits a second toggle automatically when released so you return straight to LIVE!`r`n• Configured in Remote Tray -> Pointer Controls -> Enable Cough / Push-to-Mute (Hold).",
        "remote cough push to mute hold gesture 350ms tap release pointer")

    Add("rfeat-snapping", "Features", "Remote Clicker & Ergonomics", "Magnetic Screen/Window Snapping, Click-Through & Auto-Dodge",
        "Remote Tray > Indicator Appearance", "Hold Alt to grab", "Snap=ON, Dodge=OFF, Click-Through=OFF",
        "Alignment and visibility tools so the Remote Mic pill stays clear of whiteboard buttons and lesson content.",
        "MAGNETIC SNAPPING, DODGE & CLICK-THROUGH (REMOTE)`r`n`r`n• Magnetic Snap (Default ON): On drag drop, edges within 14px align cleanly with monitor work-area edges, screen centers, and visible windows.`r`n• Auto-Dodge on Hover (Default OFF): Stays visible while speaking—then ghosts to 15% opacity and click-through when your pointer hovers over it.`r`n• Click-Through Mode (Default OFF): Lets whiteboard taps and mouse clicks pass straight underneath the pill.`r`n• Alt Override: Whenever Click-Through or Auto-Dodge is ON, hold Alt to grab, tap, or right-click the Remote pill.",
        "remote magnetic snap 14px auto dodge click through alt hold grab")

    Add("rfeat-themes", "Features", "Remote Clicker & Ergonomics", "5 HUD Color Palettes, Dark/Light Themes, Opacity & 8 Scales",
        "Remote Tray > Indicator Appearance", "Tray > App Theme / Color Preset", "System / Standard / 85% / 1.0x",
        "Customize Remote's Mic pill palette (including Colorblind Safe), corner shape, transparency, and 0.25x-5.0x Smart Board scale.",
        "REMOTE VISUAL CUSTOMIZATION SUITE`r`n`r`n• 5 HUD Color Palettes: Standard, Colorblind Safe (Okabe-Ito Blue/Orange), OLED Stealth, Broadcast Tally, and Cyber Ocean.`r`n• 3 App Window Themes: Follow System (live OS sync), Dark Mode, and Light Mode.`r`n• 3 Transparency Levels: Solid (100%), Frosted (85%), Ghost (50%).`r`n• 8 Pixel-Sharp Scales: 0.25x (Tiny) up to 5.0x (Gigantic) for massive 65`"-86`" 4K Smart Boards.`r`n• Breathing Mute Pulse, Monochromatic Icons, and Sleek Capsule Corners.",
        "remote themes colorblind okabe ito oled stealth broadcast cyber ocean opacity scale 5.0x")

    Add("rfeat-audio-toast", "Features", "Remote Clicker & Ergonomics", "Mute Audio Cue (2-Tone Beep) & Cursor Status Toast",
        "Remote Tray > Indicator Appearance", "None", "Both OFF by default",
        "Optional eyes-free 2-tone acoustic confirmation chime and brief cursor tooltip notifications when muting/unmuting.",
        "EYES-FREE MUTE CONFIRMATION (REMOTE)`r`n`r`n• Mute Audio Cue (Beep): Plays a distinct 2-tone rising chime when LIVE and a soft falling chime when MUTED—non-blocking on the Remote device.`r`n• Mute Status Toast: Displays a crisp 1.5-second cursor tooltip ('MIC MUTED' / 'MIC LIVE') whenever state flips.`r`n• Both default to OFF and live under Remote Tray -> Indicator Appearance.",
        "remote audio cue beep toast eyes free chime tooltip confirmation")

    Add("rfeat-easter-snake", "Features", "Remote Clicker & Ergonomics", "Sector Z Subsystem — Locked [0 Credits]",
        "Sector Z Clearance Required (About > Diagnostic Standby)", "Clearance Required", "Locked [0 Credits]",
        "Confidential studio diagnostic layer. Summon via Sector Z clearance and enter the two classic arcade words.",
        "SECTOR Z DIAGNOSTIC SUBSYSTEM (LOCKED)`r`n`r`n• CLEARANCE: Remains strictly locked in RAM on every launch [0 Credits].`r`n• WINDOWS REMOTE: Summon Sector Z clearance (Ctrl + Alt + Shift + Z) or inspect the About footer, then enter the two classic 1980s arcade words.`r`n• ANDROID REMOTE: Open About -> explore the diagnostic footer (7x version badge or 3s logo hold) -> enter clearance passphrase.",
        "remote sector z diagnostic locked credits clearance standby cabinet about")

    Add("rsc-remote", "Shortcuts", "Remote Companion Shortcuts", "PresenterSync Remote Hotkeys & Clicker Mute Key",
        "Remote Tray > Change App Shortcuts... / Pointer Controls", "Ctrl+F12 / Alt+Shift+F12", "Editable to custom key or 'None'",
        "Reference for all hotkeys inside PresenterSync Remote plus Secondary Clicker Mute & Cough Hold bindings.",
        "DEFAULT PRESENTER SYNC REMOTE HOTKEYS:`r`n• Ctrl + F12 : Toggle Pointer Mute Control ON/OFF (when OFF, clicker presses won't toggle host mute while the Mic HUD stays live)`r`n• Alt + Shift + F12 : Exit PresenterSync Remote cleanly`r`n`r`nHARDWARE CLICKER & COUGH HOLD:`r`n• Clicker Mute Button (default 'b'): Customize anytime under Remote Tray -> Pointer Controls -> Change Pointer Mute Button... (test unknown keys via Launch Clicker Tester...).`r`n• Clear a hotkey box or enter 'None' inside Change App Shortcuts... to unbind it completely.",
        "remote shortcuts hotkeys ctrl alt shift f12 pointer mute exit none clicker b")

    ; ==========================================================================
    ; 3. ALL FEATURES ENCYCLOPEDIA A-Z
    ; ==========================================================================
    Add("feat-quickstart", "Features", "Getting Started & Overview", "First-Time Walkthrough & Architecture Overview",
        "First Run / Overview", "Ctrl+Shift+F12 / Ctrl+F12", "Starts guided setup on first run",
        "How PresenterSync works from first launch: Pick Audio Mode -> Enable Telemetry -> Arm Clicker -> Customize HUD.",
        "WELCOME TO PRESENTER SYNC v" UIConstants.APP_VERSION "`r`n`r`nSTEP 1 — PICK YOUR AUDIO ROUTING MODE`r`n• Using OBS + VB-Cable into a call? Choose Mode 1 (Pro OBS Setup).`r`n• Only running Zoom, Teams, or Meet (no OBS)? Choose Mode 2 (Conferencing-Only).`r`n• Running BOTH OBS and Zoom/Teams/Meet and want mute synced between them? Choose Mode 3 (Dual App Sync).`r`n`r`nSTEP 2 — ENABLE LIVE TELEMETRY`r`n• With OBS open (Tools -> WebSocket Server Settings -> Enable Port 4455 + Password): Check 'Enable OBS WebSocket Sync' (Alt+F12).`r`n• Without OBS (or Conferencing-only): Check 'Enable Zoom Monitoring' (Ctrl+Alt+F12) and pick Zoom, Teams, or Meet under Settings -> Conferencing Platform.`r`n`r`nSTEP 3 — TEST & ARM YOUR CLICKER`r`n• Open Settings -> Launch Clicker Tester to see what key your pointer sends (e.g., b, PgDn).`r`n• Assign your mute button in Settings -> Change Pointer Mute Button, then toggle 'Enable Full Pointer Controls (PPT + Mute)' (Ctrl+F12).`r`n`r`nSTEP 4 — POSITION YOUR HUD & SAVE PROFILES`r`n• Drag any pill into place (snaps magnetically to corners/windows). Configure everything anytime inside Control Center...",
        "getting started quick start guide beginner overview walkthrough steps first run")

    Add("feat-routing", "Features", "Audio Routing & OBS Telemetry", "Audio Routing Modes 1, 2 & 3 Explained",
        "Settings > Audio Routing Mode / Control Center > Audio & Conf", "Wizard / Mode Switch", "Selected on setup",
        "Deep dive on Pro OBS (Mode 1), Conferencing-Only Direct Mic (Mode 2), and Dual App Two-Way Sync (Mode 3).",
        "AUDIO ROUTING MODES EXPLAINED`r`n`r`n• MODE 1 — Pro OBS Setup (VB-Cable)`r`n  Audio routes OBS -> VB-Cable -> Conferencing app, so muting your OBS mic source ('Mic/Aux') silences everything cleanly. Clicker/HUD mute calls OBS WebSocket ToggleInputMute (or falls back to OBS Mute shortcut if WS is OFF).`r`n`r`n• MODE 2 — Standard Direct Mic (Conferencing-Only)`r`n  No OBS required! Dispatches your active platform's mute key (Zoom Alt+A, Teams Ctrl+Shift+M, Meet Ctrl+D) directly to the meeting window. Also automatically enables the Host Companion Relay Bridge so PresenterSync Remote on a Smart Board still works cleanly without OBS!`r`n`r`n• MODE 3 — Dual App Sync (OBS + Conferencing)`r`n  Controls OBS directly AND runs a directional sync lock: muting in OBS mirrors your mic mute into Zoom/Teams/Meet cleanly without infinite mute ping-pong loops (even during rapid <1000ms Cough Push-to-Mute releases).",
        "routing mode 1 2 3 vb cable direct mic dual sync directional lock")

    Add("feat-obs", "Features", "Audio Routing & OBS Telemetry", "OBS Studio WebSocket v5 & 4-Tier Stream Telemetry",
        "Control Center > OBS & Stream / Tray > Enable OBS WebSocket Sync", "Alt+F12", "Port 4455 (Password optional)",
        "Complete OBS Studio WebSocket v5 setup, Scene switching, Rec timer, Stream congestion alerts, and VCam control.",
        "OBS STUDIO WEBSOCKET v5 SETUP & FEATURES`r`n`r`n1. In OBS Studio (v28+): Tools -> WebSocket Server Settings -> Enable WebSocket server (Port 4455) -> optionally Enable Authentication -> Copy Password.`r`n2. In PresenterSync: Tray -> Enable OBS WebSocket Sync (Alt+F12), or open Control Center -> OBS & Stream.`r`n3. Live features unlocked:`r`n   • Exact source mute control (case-sensitive match to OBS Mixer, default 'Mic/Aux').`r`n   • 3-State Recording status (NOT REC / REC MM:SS / PAUSED MM:SS) + Click-to-Record.`r`n   • Studio Mode pill (Click to toggle Preview/Program).`r`n   • Active Program Scene pill with auto-scrolling marquee + Click-to-Switch scene menu.`r`n   • 4th HUD Tier: STREAM health pill (monitors skipped frames + congestion >= 35% -> orange WARN + click tooltip) and VCAM pill (click to toggle Virtual Camera).`r`n   • Lightweight by design: Uses EventSubscription 2047 (excludes heavy 20Hz OBS audio meters!).",
        "obs studio websocket v5 setup stream skipped frames congestion vcam studio mode scene")

    Add("feat-conf", "Features", "Conferencing (Zoom / Teams / Meet)", "Zoom, Microsoft Teams & Google Meet Background Monitoring",
        "Control Center > Audio & Conf / Tray > Settings > Conferencing Platform", "Ctrl+Alt+F12", "Zoom (supports Teams & Meet)",
        "How native Windows UI Automation (UIA) tracks mute, recording, and unread chat across Zoom, Teams, and Meet.",
        "CONFERENCING PLATFORMS SUPPORTED`r`n`r`nSwitch cleanly anytime via Tray -> Settings -> Conferencing Platform (or Control Center -> Audio & Conf):`r`n1. ZOOM (ahk_exe Zoom.exe, default mute Alt+A)`r`n   • Tip: Enable Zoom Settings -> Accessibility -> 'Always show meeting controls' so mute, record, and chat buttons remain readable while minimized or covered.`r`n2. MICROSOFT TEAMS (ms-teams.exe / Teams.exe, default mute Ctrl+Shift+M)`r`n   • Reads Teams mute & unread chat notifications automatically.`r`n3. GOOGLE MEET (Meet in Chrome, Edge, Firefox, or Brave, default mute Ctrl+D)`r`n   • Reads Google Meet browser tab mic/chat state seamlessly.`r`n`r`nINTERACTION:`r`n• Clicking the blue/slate Row 2 CHAT badge clears the unread alert highlight and focuses your active Conferencing window.",
        "zoom microsoft teams google meet uia always show meeting controls chat badge")

    Add("feat-ppt", "Features", "PowerPoint & Hardware Clicker", "Background PowerPoint Slide Control & DWM Smooth Animation Tip",
        "Control Center > Pointer / Tray > Enable Full Pointer Controls", "Ctrl+F12", "Hybrid COM + ControlSend",
        "Controls PowerPoint slides behind OBS/Zoom without stealing focus, plus Windows Graphics settings for smooth Fade/Morph animations.",
        "POWERPOINT BACKGROUND ROUTING ARCHITECTURE`r`n`r`n• In 'Full PPT + Mute' mode, PresenterSync catches selected navigation keys (Arrows, PgUp/PgDn, Space, Enter, Tab, Esc, Shift+F5) and dispatches them to PowerPoint even when PowerPoint does NOT have focus:`r`n  1. COM First: Calls PowerPoint.Application SlideShowWindows(1).View.Next()/Previous() for rock-solid advance/previous (shielded by 150ms debounce).`r`n  2. ControlSend Fallback: Automatically handles Presenter View, {Tab}/{Enter} hyperlinks, or mixed Admin/User privilege windows.`r`n`r`nSMOOTH BACKGROUND FADE / MORPH ANIMATIONS TIP:`r`n• Windows throttles GPU rendering on unfocused fullscreen PowerPoint windows by default.`r`n• To keep fades & morphs silky-smooth behind OBS/Zoom: In OBS capture PowerPoint via Window Capture -> Capture Method 'Windows 10 (1903 and up)', and in Windows Display -> Graphics set POWERPNT.EXE to 'High performance'.",
        "powerpoint ppt background com controlsend fade morph animation gpu high performance")

    Add("feat-cough", "Features", "PowerPoint & Hardware Clicker", "Cough / Push-to-Mute Hold Gesture",
        "Settings > Enable Cough / Push-to-Mute (Hold)  |  Control Center > Pointer", "Hold Mute Button >= 350ms", "OFF (Standard Toggle)",
        "Temporarily mute just by holding your clicker mute button down—and automatically return to LIVE upon release.",
        "COUGH / PUSH-TO-MUTE GESTURE`r`n`r`n• Standard Mode (OFF): Every button tap flips Mute <-> Live.`r`n• Cough Mode (ON):`r`n  - Tap briefly (< 350ms): Toggles normally (stays Muted or Live).`r`n  - Hold down (>= 350ms): Mutes immediately when held, waits cleanly while you clear your throat or speak off-camera, then sends a second toggle automatically the moment you lift your finger so you return straight to LIVE!`r`n• Works on BOTH Primary Host and PresenterSync Remote.",
        "cough push to mute hold gesture 350ms tap release")

    Add("feat-hud-actions", "Features", "HUD Customization & Visuals", "Interactive Clickable HUD Pills & Drag Separation",
        "Indicator Appearance > Interactive HUD Click Actions", "Short-Click vs Drag", "ON",
        "Short-clicking any pill triggers instant quick-actions while moving >= 4px cleanly drags the whole stack.",
        "CLICK VS DRAG PROTECTION`r`n`r`nPresenterSync measures exact mouse travel and hold time between Left-Button-Down and Release:`r`n• Short Click (travel <= 3px AND duration < 400ms): Snaps coordinates cleanly to prevent tiny jitter and triggers the pill's quick-action:`r`n  - Mic Pill -> Toggle Mute`r`n  - REC Pill -> Start/Stop Recording`r`n  - CHAT Pill -> Acknowledge & Focus Meeting`r`n  - STUDIO Pill -> Toggle OBS Studio Mode`r`n  - SCENE Pill -> Open Live Popup OBS Scene Switcher`r`n  - STREAM Pill -> Tooltip with live Congestion % & Skipped Frames`r`n  - VCAM Pill -> Toggle OBS Virtual Camera`r`n• Drag (> 3px OR >= 400ms): Smoothly drags all 4 HUD tiers together as one unified stack without firing any pill clicks.",
        "clickable pills quick actions drag vs click scene switcher popup tooltip")

    Add("feat-snapping", "Features", "HUD Customization & Visuals", "Magnetic Screen/Window Snapping, Click-Through & Auto-Dodge",
        "Indicator Appearance / Control Center > HUD & Theme", "Hold Alt to grab", "Snap=ON, Dodge=OFF, Click-Through=OFF",
        "Alignment and visibility tools so your HUD always sits neatly out of the way of buttons beneath it.",
        "MAGNETIC SNAPPING, DODGE & CLICK-THROUGH`r`n`r`n• Magnetic Snap (Default ON): On drag drop, edges within 14px align flush with monitor work-area edges, screen midpoints, and open OBS, PowerPoint, Zoom, or Teams windows.`r`n• Auto-Dodge on Hover (Default OFF): Full opacity until your mouse approaches—then fades to 15% opacity and turns click-through until your mouse moves away.`r`n• Click-Through Mode (Default OFF): Permanently lets mouse clicks pass straight through the HUD to buttons beneath it.`r`n• Alt Override: Whenever Click-Through or Auto-Dodge is ON, simply hold down Alt to temporarily grab, click, or right-click any pill!",
        "magnetic snap 14px auto dodge click through alt hold grab")

    Add("feat-themes", "Features", "HUD Customization & Visuals", "5 HUD Color Palettes, Dark/Light Themes, Opacity & 8 Scales",
        "Indicator Appearance / Control Center > HUD & Theme", "Cycle Theme in Help > Live Status", "System / Standard / 85% / 1.0x",
        "Customize pill color schemes (including Colorblind Safe), corner styles, transparency, and 0.25x-5.0x scale.",
        "VISUAL CUSTOMIZATION SUITE`r`n`r`n• 5 HUD Color Palettes: Standard, Colorblind Safe (Okabe-Ito blue/orange), OLED Stealth, Broadcast Tally, and Cyber Ocean.`r`n• 3 App Window Themes: Follow System (live OS sync), Dark Mode, and Light Mode.`r`n• 3 Transparency Levels: Solid (100%), Frosted (85%), Ghost (50%).`r`n• 8 Pixel-Sharp Scales: 0.25x (Tiny) up to 5.0x (Gigantic) for massive Smart Boards.`r`n• Voice Activity Bar + Breathing Pulse + Monochromatic Icons + Sleek Capsule Corners.",
        "themes colorblind okabe ito oled stealth broadcast cyber ocean opacity scale 5.0x")

    Add("feat-audio-toast", "Features", "HUD Customization & Visuals", "Mute Audio Cue (2-Tone Beep) & Cursor Status Toast",
        "Indicator Appearance / Control Center > Audio & Conf", "None", "Both OFF by default",
        "Optional eyes-free acoustic confirmation tones and brief cursor tooltip notifications when muting/unmuting.",
        "EYES-FREE MUTE CONFIRMATION`r`n`r`n• Mute Audio Cue (Beep): Plays a distinct 2-tone rising chime when LIVE and a soft falling chime when MUTED—never blocking hotkey execution.`r`n• Mute Status Toast: Displays a crisp 1.5-second tooltip right near your cursor ('MIC MUTED' / 'MIC LIVE').`r`n• Both default to OFF so nothing changes unexpectedly until you turn them ON.",
        "audio cue beep toast eyes free chime tooltip confirmation")

    Add("feat-profiles", "Features", "Profiles, Updates & Startup", "Persistent Named Configuration Profiles & App-Trigger Auto-Switch",
        "Settings > Configuration Profiles / Manage Profiles & Auto Rules...", "1-click switch / Active App", "Default / Auto-Switch OFF",
        "Save distinct profiles for different rooms or apps and optionally auto-switch whenever OBS, Zoom, or Teams becomes active.",
        "CONFIGURATION PROFILES & APP-TRIGGER AUTO-SWITCH`r`n`r`n• Create named snapshots stored cleanly under [Profile:<Name>] in MicOverlay_Config.ini.`r`n• Optional App-Trigger Rules (e.g. obs64.exe=OBS|Zoom.exe=Zoom|ms-teams.exe=Teams): When enabled in Profile Manager or Tray -> Configuration Profiles -> Auto-Switch by Active App, PresenterSync switches automatically when a matching app focuses and restores your prior manual profile when focus leaves.",
        "profiles save load switch delete manager snapshot presets classroom auto trigger obs64 zoom teams")

    Add("feat-diagnostics", "Features", "Profiles, Updates & Startup", "One-Click Sanitized Diagnostics Export (Zero Secret Leakage)",
        "Tray > Export Sanitized Diagnostics... / Help Status / Control Center", "None", "Redacts all passwords & tokens",
        "Exports a troubleshooting report masking ObsPassword, PairingCodes, SessionToken, and Paired Device tokens.",
        "SANITIZED DIAGNOSTICS EXPORT`r`n`r`n• Captures App/OS versions, Live Status summary, Host Bridge listener metrics, network endpoints, Auto-Profile state, and sanitized INI settings into a plain-text .txt file.`r`n• Automatically replaces all passwords, Internet/Session pairing codes, and device auth tokens with [REDACTED] before writing.",
        "diagnostics export support bundle redact sanitize password token troubleshooting")

    Add("feat-system", "Features", "Profiles, Updates & Startup", "Control Center Dashboard, Start with Windows & Update Checker",
        "Tray > Control Center... / Settings > Start with Windows / Check for Updates...", "Auto-check manual only", "Startup OFF",
        "All-in-one 6-tab settings dashboard, opt-in Windows Run startup toggle, and SemVer GitHub update checker.",
        "SYSTEM UTILITIES`r`n`r`n• Unified Control Center: Edit every setting across 6 tabs with live validation—invalid hotkeys are flagged cleanly in the status bar without corrupting saved configuration.`r`n• Start with Windows: Strictly OFF by default; adds/removes HKCU Run startup entry when toggled.`r`n• GitHub Update Checker: Safely checks https://api.github.com/repos/SaabithJiffry/PresenterSync/releases/latest when clicked and compares SemVer.",
        "control center apply save start with windows update checker github semver")

    Add("feat-secondary-mic", "Features", "HUD Customization & Visuals", "Secondary Independent Mic Pill (Primary Host Only)",
        "Tray > Show Secondary Mic Pill (Mic-Only) / Control Center > HUD & Theme", "Independent Drag & [SecondaryPosition]", "OFF (Primary-Only)",
        "Toggles a second standalone Mic-only pill with independent drag/snap coordinates while staying synced live to Primary mic state.",
        "SECONDARY INDEPENDENT MIC PILL (PRIMARY APP ONLY)`r`n`r`n• Dedicated Mic-Only Tier: Displays strictly the LIVE / MUTED Mic pill without duplicating extra telemetry tiers—ideal for placing on a second monitor, teleprompter, or speaker notes corner.`r`n• Independent Drag & Reset: Dragging moves only the secondary pill and saves cleanly under [SecondaryPosition] X/Y; Primary Indicator Position stays untouched.`r`n• Synchronized State: Shares mute state, click-to-mute, breathing pulse, custom hex theme colors, voice meter activity, and independent hover Auto-Dodge.",
        "secondary mic pill independent primary monitor second display duplicate indicator appearance")

    Add("feat-director", "Features", "Audio Routing & OBS Telemetry", "Director Deck, Standby BRB Curtain, Countdown Timer & Stage Nudge",
        "Tray > OBS Director & Standby / Remote Companion Deck", "Scene / Split / BRB / Timer / Nudge", "Synced across Host & Remotes",
        "Switch OBS scenes, split recording chapters, trigger Standby BRB curtain macros, run synced countdown timers, and send silent nudges.",
        "WIRELESS DIRECTOR DECK, TIMER & STAGE NUDGE`r`n`r`n• OBS Scene Switcher & Recording Controls: Switch Program scenes, Pause/Resume recording, or Split chapters from Primary or any paired Remote.`r`n• Standby / BRB Curtain Macro: Snapshots mic mute + scene, switches cleanly to Standby scene & mutes mic, then restores prior scene & mute state on return.`r`n• Synchronized Presenter Countdown Timer: 5/10/15/45m presets or custom durations with 2:00 checkpoint warning & overtime clock.`r`n• Silent Stage Nudge: Pushes unobtrusive floating cues onto Primary and Android screens without entering OBS display captures.",
        "director deck standby brb curtain timer countdown stage nudge scene switch split chapter")

    Add("feat-ptt", "Features", "PowerPoint & Hardware Clicker", "Push-to-Talk Mode & Custom Hex HUD Theme Colors",
        "Tray > Settings > Enable Push-to-Talk / Indicator Appearance > HUD Color Preset > Custom", "Hold-to-Unmute (>= 300ms)", "PTT OFF / Custom Hex Optional",
        "Keep mic muted by default until clicker or floating pill is held down, and personalize #RRGGBB live/muted colors with WCAG contrast.",
        "PUSH-TO-TALK & CUSTOM HEX THEME COLORS`r`n`r`n• Push-to-Talk Mode: Mutes mic by default and unmutes strictly while holding down your clicker mute key (Windows) or floating pill (Android), automatically returning to MUTED on release.`r`n• Custom Hex HUD Colors: Configure Custom Live Hex and Custom Muted Hex in Appearance or Control Center -> HUD & Theme with automatic WCAG contrast icon coloring.",
        "push to talk ptt hold unmute custom hex colors wcag contrast palette")

    Add("feat-timeline", "Features", "Profiles, Updates & Startup", "Session Activity Timeline & Chapter CSV / Markdown / YouTube Export",
        "Tray > OBS Director & Standby > View & Export Session Timeline...", "Up to 2,000 events", "Auto-recorded in memory",
        "Records session mic, scene, slide, recording split, Standby, alert, and remote events and exports Video Editor CSV chapters, Markdown, or YouTube timestamps.",
        "SESSION TIMELINE & VIDEO EDITOR CHAPTER EXPORTER`r`n`r`n• Bounded 2,000-Entry Timeline: Tracks Mic transitions, OBS recording start/pause/split, scene switches, Standby macros, slides, timers, and remote clients cleanly in memory.`r`n• Multi-Format Exports: Save CSV Chapter Markers (Timecode, Seconds, Color, Category, Marker Name, Notes), full Markdown Session Summary (.md), or copy 00:00 YouTube Chapters straight to clipboard.",
        "session timeline chapter csv markdown youtube export markers recording log")

    Add("feat-setup-wizard", "Features", "Getting Started & Overview", "Guided 4-Step Setup Wizard & Zero-Config Classroom UDP Discovery",
        "Tray > Settings > Guided Setup Wizard... (First-Run Auto)", "UDP Discovery :4457", "4 Live Hardware/Network Checks",
        "Interactive setup checklist probing OBS (:4455), CoreAudio routing, floating pill display, and Classroom LAN UDP beacon readiness.",
        "GUIDED SETUP WIZARD & CLASSROOM UDP DISCOVERY`r`n`r`n• 4-Step Windows Setup Probe: Checks OBS WebSocket :4455 reachability, Audio Routing & CoreAudio meter, active HUD window, and Host Bridge :4456 + Classroom UDP Discovery (:4457).`r`n• One-Click Tools: Flash HUD Pill to locate it, open Pairing QR directly, or jump straight into Control Center.",
        "guided setup wizard onboarding checklist udp discovery 4457 classroom lan auto find")

    Add("feat-easter-snake", "Features", "Profiles, Updates & Startup", "Sector Z Subsystem — Locked [0 Credits]",
        "Sector Z Clearance Required (About > Diagnostic Standby)", "Clearance Required", "Locked [0 Credits]",
        "Confidential studio diagnostic layer. Summon via Sector Z clearance and enter the two classic arcade words.",
        "SECTOR Z DIAGNOSTIC SUBSYSTEM (LOCKED)`r`n`r`n• STATUS: Cabinet Standby [0 Credits] — never persisted across restarts.`r`n• ACCESS PROTOCOL: Summon the Sector Z Terminal via Ctrl + Alt + Shift + Z or About PresenterSync, then enter what every 1980s arcade cabinet asks before Player 1 starts.`r`n• AUDIO SAFETY: Hardware presenter mute remains LIVE even while Sector Z diagnostics run.",
        "sector z diagnostic locked credits clearance standby cabinet about secret")

    Add("feat-obs-transition", "Features", "Audio Routing & OBS Telemetry", "Native OBS Scene Transition Keystroke & Bounce Filter",
        "Settings > Change Pointer OBS Transition Button / Control Center > OBS & Stream", "HwTransitionHotkey / ObsTransitionHotkey", "25ms bounce shield",
        "Bind a dedicated clicker button or OBS fallback hotkey to trigger Preview <-> Program transitions with zero-lag SetKeyDelay -1, -1.",
        "NATIVE OBS SCENE TRANSITION (TriggerObsSceneTransition)`r`n`r`n• Dedicated Clicker Binding (HwTransitionHotkey): Enable 'Enable Pointer OBS Scene Transition' and assign a clicker button; bound with the '$' hook prefix so PowerPoint intercepts never collide.`r`n• Studio Mode & Fallback: Calls OBS WebSocket TriggerStudioModeTransition when Studio Mode is active, SetCurrentProgramScene when a preview/previous scene is known, or ControlSend (ObsTransitionHotkey) with zero-lag SetKeyDelay -1, -1 when OBS WS cannot determine a target scene.`r`n• 25ms Micro-Bounce Filter: Prevents noisy wireless clicker switches from double-triggering transitions.",
        "obs scene transition studio mode hwtransitionhotkey obstransitionhotkey triggerobsscenetransition bounce")

    Add("feat-preflight-bundle", "Features", "Profiles, Updates & Startup", "Go Live 10s Rehearsal, Portable Settings Bundle & Quick-Nudge Presets",
        "Tray > Go Live 10-Second Rehearsal... / Control Center > Profiles & Sys", "Pre-Flight / .json / .ini", "5 Live Gates",
        "Run a 10-second 5-gate rehearsal check before going live, export/import portable settings bundles, and customize Quick-Nudge presets.",
        "PRE-FLIGHT REHEARSAL, PORTABLE BUNDLES & QUICK-NUDGE PRESETS`r`n`r`n• Go Live 10-Second Rehearsal (RunPreFlightRehearsalChecks): Checks 5 live gates—(1) OBS :4455 + transition + mic input, (2) live mic peak > 5%, (3) Conferencing window, (4) Host Bridge + paired remotes, (5) Recording disk space (<512 MB FAIL, <2048 MB WARN).`r`n• Portable Settings Bundle (ExportPortableSettingsBundle / ImportPortableSettingsBundle): Export or import non-secret settings as .json (PresenterSyncBundle_v1) or .ini with automatic .ini.bak crash-recovery backup.`r`n• Quick-Nudge Presets (QuickNudgePresets): Customize up to 6 '|' or ',' separated stage nudges (default: '2 min left|Wrap up|Check Mic|Q&A') synced across Host, Windows Remote, Android Remote, and Web Remote.",
        "go live 10s rehearsal preflight bundle export import json ini quick nudge presets")

    Add("feat-watchdogs-cli", "Features", "Safety Watchdogs & CLI", "CoreAudio Fallback, Safety Watchdogs, Auto-Mute Triggers & 64-bit CLI Flags",
        "Control Center > Audio & Conf / OBS & Stream / CLI", "--mute --transition --scene --nudge", "Active Watchdogs",
        "Protects live sessions with CoreAudio OS mic drift monitoring, Forgotten-Record/Low-Disk/Dead-Mic watchdogs, Auto-Mute triggers, and WM_COPYDATA CLI control.",
        "WATCHDOGS, AUTO-MUTE & CLI FLAGS`r`n`r`n• CoreAudio IAudioEndpointVolume Fallback & Drift Watchdog + Multi-Mic Lockstep (SecondaryAudioSources).`r`n• Watchdogs: Forgotten-Record (15s), Stream-Drop auto-backup record (10s), Low-Disk (30s), Dead-Mic (45s), and 3s Stop-Record 2nd-tap confirm guard.`r`n• Auto-Mute Triggers: Auto-mute on Windows lock screen, meeting end, or first OBS connect.`r`n• 64-bit WM_COPYDATA CLI Flags: --mute, --unmute, --toggle, --transition, --scene <name>, --brb, --nudge <msg>, --timer <sec|pause|reset>, --status.",
        "watchdogs coreaudio drift forgotten record low disk dead mic auto mute cli wm_copydata")

    Add("feat-diagnostics-privacy", "Features", "Diagnostics & Privacy", "Persistent Error Log, Secret Redaction & Screen-Share Capture Exclusion",
        "Tray > View Error & Diagnostic Log... / Export Sanitized Diagnostics...", "logs\\PresenterSync_ErrorLog.log", "5 MB Rotation + Capture Exclusion",
        "50-event rolling breadcrumbs, 5-section context snapshots with secret redaction, PERF_LAG checks, and WDA_EXCLUDEFROMCAPTURE privacy.",
        "DIAGNOSTICS & SCREEN-SHARE PRIVACY`r`n`r`n• DiagnosticLogger (logs\\PresenterSync_ErrorLog.log): Captures 50-event rolling breadcrumbs, 5-section context snapshots, PERF_LAG (>120ms) warnings, and 5 MB log rotation—automatically scrubbing passwords, tokens, and pairing codes.`r`n• Screen-Share Capture Exclusion (ExcludeFromCapture / ExcludeSecondaryFromCapture): Applies Windows WDA_EXCLUDEFROMCAPTURE so floating HUD pills and Stage Nudges stay hidden from OBS Display/Window Capture and screen shares.",
        "diagnostic logger error log breadcrumbs redaction perf lag capture exclusion wda_excludefromcapture")

    ; ==========================================================================
    ; 4. KEYBOARD & CLICKER SHORTCUTS
    ; ==========================================================================
    Add("sc-global", "Shortcuts", "Keyboard & Clicker Shortcuts", "Global App Hotkeys (Default Bindings & Conflict Rules)",
        "Settings > Change App Shortcuts / Control Center > Profiles & Sys", "Ctrl+F12 / Alt+F12 / etc.", "Editable live or to 'None'",
        "Reference for all global hotkeys (plus one curious chord), Suspend behavior, and leaving keys unbound.",
        "DEFAULT HOST HOTKEYS:`r`n• Ctrl + F12 : Cycle Pointer Modes (Full PPT + Mute -> Mute Only -> OFF)`r`n• Alt + F12  : Toggle OBS WebSocket Sync ON/OFF`r`n• Ctrl + Alt + F12 : Toggle Conferencing Monitoring ON/OFF`r`n• Ctrl + Shift + F12 : Show / Hide HUD Overlay Stack`r`n• Ctrl + Alt + Shift + F12 : Suspend All Hotkeys`r`n• Alt + Shift + F12 : Exit PresenterSync`r`n• Ctrl + Alt + Shift + Z : Sector Z Diagnostic Terminal (0 Credits)`r`n`r`nDEFAULT REMOTE COMPANION HOTKEYS:`r`n• Ctrl + F12 : Toggle Pointer Mute Control ON/OFF`r`n• Alt + Shift + F12 : Exit PresenterSync Remote`r`n`r`n• Clear a hotkey box or enter 'None' to disable that shortcut completely.",
        "shortcuts hotkeys ctrl alt shift f12 suspend exit none disable sector z")

    Add("sc-clicker", "Shortcuts", "Keyboard & Clicker Shortcuts", "Hardware Clicker Mute Button & Collision Prevention",
        "Settings > Change Pointer Mute Button / Configure Pointer Intercepts", "Default: b", "Supports any AHK key",
        "Explains how PresenterSync prevents key collisions between slide navigation and your clicker mute key.",
        "HARDWARE CLICKER RULES`r`n`r`n• Smart Mutual Exclusion (IsPptKeyNotMute): If you bind your Hardware Mute Button to PgDn, Esc, Tab, or F5, PresenterSync automatically exempts that key from PowerPoint forwarding so one button never triggers both slide change AND mute!`r`n• Safe Typing Guard: Clicker mute and PPT intercepts pause automatically whenever any PresenterSync settings window is active.`r`n• 150ms Hardware Debounce Shield prevents noisy wireless USB receivers from double-toggling mute on one press.",
        "clicker mute key collision escape pgdn debounce safe typing shield")

    Add("sc-fallback", "Shortcuts", "Keyboard & Clicker Shortcuts", "OBS & Conferencing Fallback Shortcuts",
        "Settings > Change OBS Settings / Change Zoom Shortcuts", "OBS ^F9/^F10, Conf !a/^+m/^d", "Customizable",
        "When fallback keyboard hooks fire and how optimistic laptop keyboard detection works.",
        "FALLBACK & PASSTHROUGH SHORTCUTS`r`n`r`n• When OBS WebSocket Sync is OFF (in Mode 1 or Mode 3), pressing your clicker sends OBS Mute Shortcut directly to obs64.exe via ControlSend.`r`n• Pressing your configured OBS or Zoom Mute/Rec/Pause shortcuts directly on the laptop keyboard is also observed passively (`~` passthrough hook) so the HUD updates even when you use OBS/Zoom's own shortcuts!`r`n• In Conferencing Mode (Mode 2 / Mode 3), Mute dispatches Zoom (Alt+A), Teams (Ctrl+Shift+M), or Meet (Ctrl+D).",
        "fallback shortcut obs rec pause zoom teams meet passthrough keyboard")

    ; ==========================================================================
    ; 5. REMOTE COMPANION GUIDES
    ; ==========================================================================
    Add("rem-overview", "Remote", "PresenterSync Remote Companion", "How PresenterSync Remote Works (Dedicated 1-Tier Mic HUD)",
        "Help > Remote Setup / PresenterSync_Remote.exe", "Ctrl+F12 (Toggle Pointer Mute)", "Strictly 1-Tier Mic Pill",
        "Standalone portable companion for classroom Smart Boards (OPS modules) or secondary presenter laptops.",
        "PRESENTER SYNC REMOTE COMPANION`r`n`r`n• Built specifically to run portably (zero installation—just copy PresenterSync_Remote.exe!) on a Smart Board PC or secondary presentation laptop.`r`n• Deliberately stays a super-clean, focused 1-tier LIVE / MUTED Mic HUD so it never clutters the whiteboard.`r`n• Supports touch-friendly dragging, Magnetic Snapping, Auto-Dodge, Click-Through (hold Alt), 5 Color Presets, and scales up to 5.0x for 86`" 4K displays.`r`n• Clicking 'Toggle Pointer Mute' (Ctrl+F12) lets you temporarily stop the Smart Board clicker from muting the host while keeping live mic status visible!",
        "remote companion smart board ops 1 tier single pill touch portable")

    Add("rem-lan", "Remote", "PresenterSync Remote Companion", "Same Router (LAN) Multi-Candidate Failover & Setup",
        "Settings > Remote Companion Info...  |  Remote > Change OBS Connection...", "Port 4455 (TCP)", "Same Router (LAN)",
        "Connects across 2.4 GHz, 5 GHz, and wired adapters using .local mDNS and multi-IP auto-failover.",
        "SAME ROUTER (LAN) SETUP`r`n`r`n1. On Primary Host PC: Enable OBS WebSocket Server (Tools -> WebSocket Server Settings, Port 4455 + Password) and allow Private Firewall TCP port 4455.`r`n2. Open Tray -> Settings -> Remote Companion Info... -> click 'Copy Universal String to Clipboard' (contains HOSTNAME.local plus every Ethernet & Wi-Fi IP).`r`n3. On Secondary PC / Smart Board: Launch PresenterSync_Remote.exe, keep Mode '1: Same Router (LAN)', paste the Universal String, enter OBS Password, match Target Mic Name ('Mic/Aux'), click Test Connection, then Connect & Start!`r`n4. Failover: Remote cycles through every candidate address cleanly until the active route connects.",
        "remote lan same router universal string mdns local ip failover port 4455 firewall")

    Add("rem-web-relay", "Remote", "Web Remote & AES-256-GCM Relay", "Zero-Install Browser Web Remote (:4456) & AES-256-GCM WAN Relay",
        "http://<host-ip>:4456/  |  Control Center > Remote Companion", "TCP :4456 / Custom Relay URL", "AES-256-GCM",
        "Control PresenterSync from any iOS, iPadOS, macOS, Linux, or Chromebook browser, or over encrypted AES-256-GCM WAN Relay.",
        "ZERO-INSTALL BROWSER WEB REMOTE & AES-256-GCM WAN RELAY`r`n`r`n• Browser Web Remote (Lib\\WebRemoteUI.ahk): Open http://<host-ip>:4456/ (shown in Remote Companion Info) on any browser, enter the 6-char Session Code, and control Mic Mute, OBS Transition, Slides + Speaker Notes, Scenes, Timer, BRB, and Stage Nudges over WebSocket.`r`n• Authenticated AES-256-GCM WAN Relay: Uses Windows bcrypt.dll (Lib\\Crypto.ahk) <-> Android AES/GCM/NoPadding (RelayCrypto.kt) with 96-bit IV, 128-bit auth tag, replay protection, and optional self-hosted Relay Base URL (RelayBaseUrl).",
        "web remote browser ios ipad mac linux chromebook 4456 aes gcm wan relay custom url")

    Add("rem-ergonomics", "Remote", "Remote Ergonomics & Android", "Windows & Android Remote v8.0.0 Ergonomics, Podium Deck, Widget & Haptics",
        "PresenterSync_Remote.exe  |  PresenterSync_Remote.apk", "Quick Deck / Podium / Widget / BT", "v8.0.0 Parity",
        "Overview of Windows Remote Quick Deck, Saved Profiles, Lock/Auto-Dim, Screen-Ratio persistence, plus Android Podium Deck, 2x1 Widget, Haptics & BT Media Clicker.",
        "WINDOWS & ANDROID REMOTE v8.0.0 ERGONOMICS`r`n`r`n• Windows Remote: Double-click pill for Touch Quick Deck (ShowRemoteTouchDeckGUI), Saved Host Profiles, Paste Pairing URI, Slide & OBS Transition hotkeys, Lock Pill Position (LockHudPosition), 10s Idle Auto-Dim (EnableIdleAutoDim), Screen-Ratio persistence (savedXRatio/savedYRatio), Pill Mini-Badges, and Sanitized Diagnostics Export.`r`n• Android Remote: High-DPI Smart Board Canvas (0.5x-5.0x), expanded Quick Menu (TRANSITION_SCENE), Full-Screen OLED Podium Deck (PodiumDeckScreen), 2x1 Home Screen App Widget, silent HapticAlertPlayer (API 26-34), Background BT Media Clicker, Battery Optimization check, and Share Pairing QR.",
        "windows remote android quick deck podium widget haptics bt media clicker lock auto dim ratio mini badges")

    Add("rem-internet", "Remote", "PresenterSync Remote Companion", "Different Networks (Internet Pairing Code) & Mode 2 Bridge",
        "Settings > Remote Network Mode > Different Networks (Internet)", "PS-XXXX-XXXX Code", "Auto-enabled in Mode 2",
        "Connects PresenterSync Remote across separate Wi-Fi networks, hotspots, OR in Mode 2 Conferencing-Only without OBS.",
        "INTERNET PAIRING & MODE 2 CONFERENCING BRIDGE`r`n`r`n• SEPARATE NETWORKS (WAN RELAY):`r`n  If your Primary PC is on campus Ethernet and your Smart Board is on a hotspot or isolated VLAN, choose 'Different Networks (Internet)' on both devices and enter your Primary Host's Pairing Code (e.g. PS-A4K9-2XM7).`r`n`r`n• CONFERENCING-ONLY MODE (WITHOUT OBS):`r`n  When Primary is in Audio Routing Mode 2 (Zoom/Teams/Meet-Only without OBS), PresenterSync automatically starts the Companion Relay Bridge! Entering the Pairing Code on PresenterSync Remote mirrors live Zoom/Teams/Meet mute status AND lets your Smart Board clicker mute/unmute the meeting on the Primary laptop—even with OBS closed!",
        "internet pairing code wan relay hotspot vlan mode 2 conferencing bridge without obs")

    Add("rem-tray", "Remote", "PresenterSync Remote Companion", "Safe Manual Close & Remote Companion Troubleshooting",
        "Tray > Close Remote Companion...  |  OBS Code 4009 / Mic Not Found", "Confirmed Prompt", "Safe isolation",
        "How to safely shut down Remote from the Primary PC and fix authentication or mic name errors.",
        "SAFE REMOTE SHUTDOWN & TROUBLESHOOTING`r`n`r`n• Safe Manual Shutdown: Closing or restarting Primary PresenterSync NEVER closes PresenterSync Remote unexpectedly. To shut down PresenterSync Remote on the secondary PC remotely, use Primary Tray -> 'Close Remote Companion...' and confirm.`r`n• Error 'Auth Failed (Code 4009)': Re-enter your OBS WebSocket password in Remote Tray -> Change OBS Connection...`r`n• Error 'Mic Not Found': Open OBS Audio Mixer on Primary Host and match exact capitalization (e.g., 'Mic/Aux' vs 'USB Mic') inside Change OBS Connection...",
        "close remote companion safe shutdown auth failed 4009 mic not found troubleshooting")

    Add("rem-android", "Remote", "Android Smart Board & Phone Client (APK)", "Android Companion (PresenterSync_Remote.apk)",
        "Settings > Remote Companion Info...  |  Android 12+ Phones & 65`" Smart Boards", "QR / XXX-XXX / Manual", "Zero Google Play Services",
        "Always-on-top 1-tier floating Mic pill with Multi-Gestures, Phone/Smart Board layouts, and Play Protect-clean permissions.",
        "ANDROID SMART BOARD & PHONE COMPANION (dist\\PresenterSync_Remote.apk)`r`n`r`n• Adaptive Layouts (Android 12–15+): Automatically adapts between 65`"+ landscape Smart Boards and portrait mobile phones (Auto / Smart Board / Mobile Phone).`r`n• Floating Bubble Multi-Gestures & Position Lock: Customize Single Tap (default None to prevent accidental touches), Double Tap (Quick Menu), Long Press (600ms Toggle Mute with animated progress arc), and Very Long Press (1400ms, optional split Mute Only / Unmute Only), plus Lock Pill Position.`r`n• 3-Method Instant Pairing: Camera QR Scan, 6-char Session Code (XXX-XXX) over Host Bridge :4456, or WAN Relay (PS-XXXX-XXXX) / Manual OBS (:4455).`r`n• Play Protect-Safe Architecture: No background Accessibility service is declared, keeping sideloaded GitHub APK installs clean. Plug hardware presenter clickers into the Primary Windows PC (which syncs mute state instantaneously to Android) or use Bubble Multi-Gestures on Android.",
        "android apk smart board phone 12 14 qr session code 4456 gestures long press position lock play protect safe non-gms")

    Add("rem-multi", "Remote", "Multi-Remote Host Bridge", "Simultaneous Multi-Remote Sync (Smart Board + Phone + Windows)",
        "Host Bridge Port 4456  |  PresenterSync_Remote.exe -Instance <name>", "Unlimited paired remotes", "Live sync across all clients",
        "Connect multiple Android Smart Boards, presenters' phones, and Windows companions to one Primary Host simultaneously.",
        "SIMULTANEOUS MULTI-REMOTE ARCHITECTURE`r`n`r`n• Mix Any Devices Together: Pair your classroom Smart Board (Android or Windows), presenter's Android phone, and secondary laptop at the same time against one Primary PresenterSync PC Host.`r`n• Shared Real-Time Mute State: Toggling mute from Primary Host, Mode 2 Zoom/Teams/Meet, OBS Studio, or ANY paired remote broadcasts updated LIVE/MUTED status to every connected remote in real time.`r`n• Windows Session Code & Multi-Instance CLI: Inside PresenterSync Remote's OBS Connection UI, enter the Host Bridge Session Code (XXX-XXX) and click 'Pair by Code'. To run 2+ Windows companions on the same machine, launch with '-Instance board' or '-Config C:\\path\\remote2.ini' (or pass '-Uri presentersync://connect?...').`r`n• Live Roster & Safe Shutdown: View all connected devices live inside Primary -> Remote Companion Info..., and cleanly close all connected remotes with 'Close Remote Companion...'.",
        "multi remote simultaneous bridge 4456 multiple android phone smart board windows instance config uri")

    cache := entries
    return cache
}

/**
 * Formats a Knowledge Base entry consistently for detail panes across Primary & Remote Help UIs.
 */
BuildHelpEntryDetailText(entry) {
    if (!IsObject(entry))
        return ""
    return "TITLE: " entry.title "`r`n"
        . "MENU PATH: " entry.menuPath "`r`n"
        . "SHORTCUT: " entry.shortcut "   |   DEFAULT: " entry.defVal "`r`n"
        . "------------------------------------------------`r`n"
        . entry.body
}

/**
 * Filters and ranks Help Knowledge Base entries by search query and category.
 * Supports multi-word matching (every space-separated token must match).
 */
SearchHelpEntries(query := "", category := "All", forRemote := false) {
    kb := GetHelpKnowledgeBase()
    q := StrLower(Trim(String(query)))
    tokens := []
    if (q != "") {
        for tok in StrSplit(RegExReplace(q, "\s+", " "), " ") {
            if (tok != "")
                tokens.Push(tok)
        }
    }

    matches := []
    for idx, entry in kb {
        isRemoteHud := (SubStr(entry.id, 1, 5) = "rhud-")
        isRemoteAlt := (SubStr(entry.id, 1, 6) = "rfeat-") || (entry.id = "rsc-remote")
            || (entry.id = "rtray-about" || entry.id = "rtray-text" || entry.id = "rtray-clicks"
            || entry.id = "rtray-theme" || entry.id = "rtray-resetapp" || entry.id = "rtray-startup" || entry.id = "rtray-updates")
        if (!forRemote && (isRemoteHud || isRemoteAlt))
            continue

        if (forRemote) {
            isPrimaryHud := (SubStr(entry.id, 1, 4) = "hud-")
            isPrimaryAppOverride := (entry.id = "tray-app-vu" || entry.id = "tray-app-rectimer" || entry.id = "tray-app-stream"
                || entry.id = "tray-app-text" || entry.id = "tray-app-clicks" || entry.id = "tray-app-theme" || entry.id = "tray-app-resetapp")
            if (isPrimaryHud || isPrimaryAppOverride)
                continue
            allowRemote := isRemoteHud
                || isRemoteAlt
                || (entry.cat = "Remote")
                || (entry.group = "Remote Companion Tray Menu")
                || (SubStr(entry.id, 1, 9) = "tray-app-")
            if (!allowRemote)
                continue
        }

        if (category != "" && category != "All" && StrLower(entry.cat) != StrLower(category))
            continue

        score := 1000 - idx
        if (tokens.Length > 0) {
            allMatch := true
            titleLow := StrLower(entry.title)
            pathLow := StrLower(entry.menuPath)
            kwLow := StrLower(entry.keywords)
            score := 0
            if (InStr(titleLow, q) || InStr(pathLow, q))
                score += 120
            for tok in tokens {
                if (!InStr(entry.searchBlob, tok)) {
                    allMatch := false
                    break
                }
                if (InStr(titleLow, tok) || InStr(pathLow, tok))
                    score += 35
                else if (InStr(kwLow, tok))
                    score += 20
                else
                    score += 10
            }
            if (!allMatch)
                continue
        }

        matches.Push({ score: score, entry: entry })
    }

    ; Simple insertion sort descending by score when a search query is active
    if (tokens.Length > 0 && matches.Length > 1) {
        i := 2
        while (i <= matches.Length) {
            cur := matches[i]
            j := i - 1
            while (j >= 1 && matches[j].score < cur.score) {
                matches[j + 1] := matches[j]
                j -= 1
            }
            matches[j + 1] := cur
            i += 1
        }
    }

    out := []
    for m in matches
        out.Push(m.entry)
    return out
}

; ==============================================================================
; GDI+ ANNOTATED VISUAL HUD DIAGRAM RENDERER & HIT TESTER
; ==============================================================================

_GdipDrawLine(pGraphics, x1, y1, x2, y2, argbColor, width := 1.6, dash := false) {
    pPen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", argbColor, "Float", Float(width), "Int", 2, "Ptr*", &pPen)
    if (!pPen)
        return
    if (dash)
        DllCall("gdiplus\GdipSetPenDashStyle", "Ptr", pPen, "Int", 1)
    DllCall("gdiplus\GdipDrawLine", "Ptr", pGraphics, "Ptr", pPen, "Float", Float(x1), "Float", Float(y1), "Float", Float(x2), "Float", Float(y2))
    DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
}

_GdipDrawArrow(pGraphics, x1, y1, x2, y2, argbColor, width := 1.7) {
    dx := Float(x2 - x1)
    dy := Float(y2 - y1)
    len := Sqrt(dx * dx + dy * dy)
    if (len < 1.0)
        return
    ux := dx / len
    uy := dy / len
    headLen := 7.0
    headW := 3.6
    lineEndX := x2 - ux * (headLen - 1.5)
    lineEndY := y2 - uy * (headLen - 1.5)
    _GdipDrawLine(pGraphics, x1, y1, lineEndX, lineEndY, argbColor, width)

    ; Anchor dot at callout edge
    pBrush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argbColor, "Ptr*", &pBrush)
    if (pBrush) {
        DllCall("gdiplus\GdipFillEllipse", "Ptr", pGraphics, "Ptr", pBrush, "Float", Float(x1) - 2.6, "Float", Float(y1) - 2.6, "Float", 5.2, "Float", 5.2)

        pts := Buffer(24, 0) ; 3 PointF (x, y)
        px := -uy
        py := ux
        baseX := x2 - ux * headLen
        baseY := y2 - uy * headLen
        NumPut("Float", Float(x2), "Float", Float(y2), pts, 0)
        NumPut("Float", Float(baseX + px * headW), "Float", Float(baseY + py * headW), pts, 8)
        NumPut("Float", Float(baseX - px * headW), "Float", Float(baseY - py * headW), pts, 16)
        DllCall("gdiplus\GdipFillPolygon", "Ptr", pGraphics, "Ptr", pBrush, "Ptr", pts, "Int", 3, "Int", 0)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
    }
}

_GdipDrawRoundedBox(pGraphics, x, y, w, h, radius, fillArgb, strokeArgb := 0, strokeW := 1.2, dash := false) {
    pPath := Gdip.CreateRoundedRectPath(x, y, w, h, radius)
    if (!pPath)
        return
    if ((fillArgb >>> 24) > 0) {
        pBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", fillArgb, "Ptr*", &pBrush)
        if (pBrush) {
            DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pBrush, "Ptr", pPath)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
        }
    }
    if ((strokeArgb >>> 24) > 0 && strokeW > 0) {
        pPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", strokeArgb, "Float", Float(strokeW), "Int", 2, "Ptr*", &pPen)
        if (pPen) {
            if (dash)
                DllCall("gdiplus\GdipSetPenDashStyle", "Ptr", pPen, "Int", 1)
            DllCall("gdiplus\GdipDrawPath", "Ptr", pGraphics, "Ptr", pPen, "Ptr", pPath)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
        }
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
}

_GdipDrawMiniPill(pGraphics, x, y, w, h, bgHex, borderHex, iconFont, glyph, iconHex, labelStr, labelSize, isDark, vuRatio := 0.0, selected := false, accentArgb := 0) {
    radius := Min(6.5, h / 2.0)
    bgArgb := Gdip.HexToArgb(bgHex, 245)
    brdArgb := Gdip.HexToArgb(borderHex, 255)
    pPath := Gdip.CreateRoundedRectPath(x, y, w, h, radius)
    if (pPath) {
        pBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", bgArgb, "Ptr*", &pBrush)
        if (pBrush) {
            DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pBrush, "Ptr", pPath)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
        }
        if (vuRatio > 0.0) {
            DllCall("gdiplus\GdipSetClipPath", "Ptr", pGraphics, "Ptr", pPath, "Int", 0)
            pVu := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xEBFFFFFF, "Ptr*", &pVu)
            if (pVu) {
                barH := 4.5
                DllCall("gdiplus\GdipFillRectangle", "Ptr", pGraphics, "Ptr", pVu, "Float", Float(x + 1), "Float", Float(y + h - barH - 0.5), "Float", Float(w - 2) * Min(1.0, vuRatio), "Float", Float(barH))
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pVu)
            }
            DllCall("gdiplus\GdipResetClip", "Ptr", pGraphics)
        }
        pPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", brdArgb, "Float", 1.3, "Int", 2, "Ptr*", &pPen)
        if (pPen) {
            DllCall("gdiplus\GdipDrawPath", "Ptr", pGraphics, "Ptr", pPen, "Ptr", pPath)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
        }
        DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
    }
    if (selected && accentArgb)
        _GdipDrawRoundedBox(pGraphics, x - 2.5, y - 2.5, w + 5.0, h + 5.0, radius + 2.0, 0x00000000, accentArgb, 2.2)

    icArgb := Gdip.HexToArgb(iconHex, 255)
    if (glyph != "" && labelStr != "") {
        icW := Min(24, Round(h * 0.62))
        icX := x + 7
        txtX := icX + icW + 3
        txtW := Max(8, (x + w) - txtX - 6)
        Gdip.DrawText(pGraphics, glyph, iconFont, Max(8.5, Round(h * 0.36)), 0, icArgb, icX, y, icW, h, 1, 1)
        Gdip.DrawText(pGraphics, labelStr, "Segoe UI", labelSize, 1, icArgb, txtX, y, txtW, h, 0, 1, 0, true)
    } else if (labelStr != "") {
        Gdip.DrawText(pGraphics, labelStr, "Segoe UI", labelSize, 1, icArgb, x + 6, y, Max(8, w - 12), h, 1, 1, 0, true)
    } else if (glyph != "") {
        Gdip.DrawText(pGraphics, glyph, iconFont, Max(10, Round(h * 0.42)), 0, icArgb, x, y, w, h, 1, 1)
    }
}

_GdipDrawCalloutCard(pGraphics, card, numIdx, selected, isDark, accentArgb) {
    cardBg := selected
        ? (isDark ? 0xFF223648 : 0xFFE6F2FC)
        : (isDark ? 0xFF25262B : 0xFFFFFFFF)
    cardBrd := selected
        ? accentArgb
        : (isDark ? 0xFF3E4049 : 0xFFD2D6DF)
    txtArgb := isDark ? 0xFFF3F4F6 : 0xFF18191E
    subArgb := isDark ? 0xFFB5BAC6 : 0xFF555B68

    _GdipDrawRoundedBox(pGraphics, card.x, card.y, card.w, card.h, 6.0, cardBg, cardBrd, selected ? 1.8 : 1.1)

    badgeBg := selected ? accentArgb : (isDark ? 0xFF373A44 : 0xFFE3E7F0)
    badgeTxt := selected ? (isDark ? 0xFF111827 : 0xFFFFFFFF) : txtArgb
    _GdipDrawRoundedBox(pGraphics, card.x + 6, card.y + 6, 20, 18, 4.5, badgeBg)
    Gdip.DrawText(pGraphics, String(numIdx), "Segoe UI", 8.5, 1, badgeTxt, card.x + 6, card.y + 6, 20, 18, 1, 1)

    Gdip.DrawText(pGraphics, card.title, "Segoe UI", 8.8, 1, txtArgb, card.x + 30, card.y + 4, card.w - 36, 16, 0, 1, 0, true)
    Gdip.DrawText(pGraphics, card.sub, "Segoe UI", 7.8, 0, subArgb, card.x + 30, card.y + 20, card.w - 36, 15, 0, 1, 0, true)
}

/**
 * Returns deterministic DIP coordinates & hit regions for the Primary HUD Diagram (776 x 240)
 * so both rendering and Picture click hit-testing use identical geometry.
 */
GetPrimaryHudDiagramSpec(W := 776, H := 240) {
    ; Center 4-tier HUD mockup: x=254..522 (width 268, pills inside 280..496 width 216)
    pills := [
        { id: 1, x: 280, y: 12,  w: 118, h: 30, arrowFrom: "L" }, ; STREAM LIVE
        { id: 2, x: 404, y: 12,  w: 92,  h: 30, arrowFrom: "R" }, ; VCAM
        { id: 3, x: 280, y: 48,  w: 88,  h: 32, arrowFrom: "L" }, ; STUDIO
        { id: 4, x: 374, y: 48,  w: 122, h: 32, arrowFrom: "R" }, ; SCENE
        { id: 5, x: 280, y: 86,  w: 120, h: 36, arrowFrom: "L" }, ; REC 04:18
        { id: 6, x: 406, y: 86,  w: 90,  h: 36, arrowFrom: "R" }, ; 2 NEW CHAT
        { id: 7, x: 280, y: 128, w: 216, h: 42, arrowFrom: "L" }, ; LIVE + Mic
        { id: 8, x: 280, y: 162, w: 216, h: 12, arrowFrom: "R" }  ; VU Bar / Bottom Gestures
    ]

    cards := [
        { id: 1, x: 10,  y: 8,   w: 222, h: 39, title: "STREAM Status Pill", sub: "Click: stats  •  Orange: drops",   ax: 232, ay: 27,  tx: 279, ty: 27 },
        { id: 2, x: 544, y: 8,   w: 222, h: 39, title: "VCAM Toggle Pill",   sub: "Click: OBS Virtual Cam ON/OFF",  ax: 544, ay: 27,  tx: 497, ty: 27 },
        { id: 3, x: 10,  y: 54,  w: 222, h: 39, title: "STUDIO Mode Badge",  sub: "Click: Preview/Program view",    ax: 232, ay: 73,  tx: 279, ty: 64 },
        { id: 4, x: 544, y: 54,  w: 222, h: 39, title: "Active Scene Pill",  sub: "Click: Scene menu  •  Marquee",  ax: 544, ay: 73,  tx: 497, ty: 64 },
        { id: 5, x: 10,  y: 100, w: 222, h: 39, title: "REC + Live Timer",   sub: "Click: Rec  •  Red/Amber MM:SS", ax: 232, ay: 119, tx: 279, ty: 104 },
        { id: 6, x: 544, y: 100, w: 222, h: 39, title: "Unread CHAT Badge",  sub: "Click: Clear & focus meeting",   ax: 544, ay: 119, tx: 497, ty: 104 },
        { id: 7, x: 10,  y: 146, w: 222, h: 39, title: "LIVE / MUTED Mic",   sub: "Click: Mute  •  Red pulses",     ax: 232, ay: 165, tx: 279, ty: 146 },
        { id: 8, x: 544, y: 146, w: 222, h: 39, title: "Voice Bar & Gestures", sub: "Bottom VU • Drag • Alt=Grab",  ax: 544, ay: 168, tx: 497, ty: 167 }
    ]

    return { W: W, H: H, frame: { x: 254, y: 4, w: 268, h: 186 }, pills: pills, cards: cards }
}

/**
 * Hit-tests a DIP click coordinate (relX, relY) inside the Primary HUD Visual Diagram.
 * Returns callout ID 1..8, or 0 if background clicked.
 */
HitTestPrimaryHudDiagram(relX, relY) {
    spec := GetPrimaryHudDiagramSpec()
    for card in spec.cards {
        if (relX >= card.x && relX <= card.x + card.w && relY >= card.y && relY <= card.y + card.h)
            return card.id
    }
    ; Check pill 8 (VU bottom bar) before pill 7 so clicking the white bar selects #8 accurately
    p8 := spec.pills[8]
    if (relX >= p8.x && relX <= p8.x + p8.w && relY >= p8.y && relY <= p8.y + p8.h)
        return 8
    for pill in spec.pills {
        if (relX >= pill.x && relX <= pill.x + pill.w && relY >= pill.y && relY <= pill.y + pill.h)
            return pill.id
    }
    return 0
}

/**
 * Renders the Primary 4-Tier Live Annotated HUD Diagram using GDI+ into an HBITMAP.
 * Automatically honors active Light/Dark Theme AND active HUD Color Preset!
 */
BuildPrimaryHudDiagramBitmap(cfg, selectedIdx := 1, targetW := 776, targetH := 240) {
    Gdip.Startup()
    dpiScale := A_ScreenDPI / 96.0
    pixW := Max(1, Round(targetW * dpiScale))
    pixH := Max(1, Round(targetH * dpiScale))

    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", pixW, "Int", pixH, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBitmap)
    if (!pBitmap)
        return 0

    pGraphics := 0
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBitmap, "Ptr*", &pGraphics)
    if (!pGraphics) {
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
        return 0
    }

    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", pGraphics, "Int", 4)
    if (Abs(dpiScale - 1.0) > 0.001)
        DllCall("gdiplus\GdipScaleWorldTransform", "Ptr", pGraphics, "Float", Float(dpiScale), "Float", Float(dpiScale), "Int", 0)

    isDark := Theme.IsDarkMode()
    outerBg := isDark ? UIConstants.DARK_SURFACE_BGR : UIConstants.LIGHT_SURFACE_BGR
    canvasBgArgb := isDark ? 0xFF1B1C20 : 0xFFF7F8FA
    canvasBrdArgb := isDark ? 0xFF353740 : 0xFFD5D8E0
    frameBgArgb := isDark ? 0xFF141519 : 0xFFE9ECF2
    frameBrdArgb := isDark ? 0xFF4B4F5C : 0xFFB0B7C5
    accentArgb := isDark ? 0xFF60CDFF : 0xFF0067C0
    lineMutedArgb := isDark ? 0xFF7D8596 : 0xFF687082
    subMutedArgb := isDark ? 0xFFB2B8C4 : 0xFF525866
    iconFont := (Integer(StrSplit(A_OSVersion, ".")[3]) >= 22000) ? "Segoe Fluent Icons" : "Segoe MDL2 Assets"

    palName := (IsObject(cfg) && cfg.HasOwnProp("HudColorPreset")) ? cfg.HudColorPreset : "Standard"
    cLive := (IsObject(cfg) && cfg.HasOwnProp("CustomLiveHex")) ? cfg.CustomLiveHex : "107C10"
    cMuted := (IsObject(cfg) && cfg.HasOwnProp("CustomMutedHex")) ? cfg.CustomMutedHex : "C42B1C"
    pal := UIConstants.GetColorPalette(palName, cLive, cMuted)
    mono := IsObject(cfg) && cfg.HasOwnProp("MonoIcon") ? cfg.MonoIcon : false

    spec := GetPrimaryHudDiagramSpec(targetW, targetH)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", pGraphics, "UInt", isDark ? 0xFF2C2C2C : 0xFFFFFFFF)
    _GdipDrawRoundedBox(pGraphics, 0.5, 0.5, targetW - 1.0, targetH - 1.0, 8.0, canvasBgArgb, canvasBrdArgb, 1.1)

    ; Center desktop preview backdrop for the 4-tier HUD stack
    _GdipDrawRoundedBox(pGraphics, spec.frame.x, spec.frame.y, spec.frame.w, spec.frame.h, 8.0, frameBgArgb, frameBrdArgb, 1.1, true)
    Gdip.DrawText(pGraphics, "Live 4-Tier Overlay (" palName " Palette)", "Segoe UI", 7.6, 0, subMutedArgb, spec.frame.x + 6, spec.frame.y + spec.frame.h - 16, spec.frame.w - 12, 14, 1, 1)

    ; Draw leader arrows first so pills and cards sit crisply on top
    for cardItem in spec.cards {
        isSel := (cardItem.id == selectedIdx)
        _GdipDrawArrow(pGraphics, cardItem.ax, cardItem.ay, cardItem.tx, cardItem.ty, isSel ? accentArgb : lineMutedArgb, isSel ? 2.2 : 1.5)
    }

    ; Render Row 4 -> Row 1 live HUD pills inside the center frame
    p := spec.pills[1]
    _GdipDrawMiniPill(pGraphics, p.x, p.y, p.w, p.h, pal.streamLive, pal.streamLive, iconFont, Chr(0xE93E), mono ? pal.streamIconLive : "FFFFFF", "LIVE", 8.5, isDark, 0.0, selectedIdx == 1, accentArgb)
    p := spec.pills[2]
    _GdipDrawMiniPill(pGraphics, p.x, p.y, p.w, p.h, pal.vcamOn, pal.vcamOn, iconFont, Chr(0xE714), mono ? pal.vcamIconOn : "FFFFFF", "VCAM", 8.5, isDark, 0.0, selectedIdx == 2, accentArgb)
    p := spec.pills[3]
    _GdipDrawMiniPill(pGraphics, p.x, p.y, p.w, p.h, pal.studioOn, pal.studioOn, iconFont, Chr(0xE7F4), mono ? pal.studioIconOn : "FFFFFF", "STUDIO", 8.0, isDark, 0.0, selectedIdx == 3, accentArgb)
    p := spec.pills[4]
    _GdipDrawMiniPill(pGraphics, p.x, p.y, p.w, p.h, pal.scene, pal.scene, iconFont, "", mono ? pal.sceneText : "FFFFFF", "Main Cam", 8.5, isDark, 0.0, selectedIdx == 4, accentArgb)
    p := spec.pills[5]
    _GdipDrawMiniPill(pGraphics, p.x, p.y, p.w, p.h, pal.recActive, pal.recActive, iconFont, Chr(0xE7C8), mono ? pal.recIconActive : "FFFFFF", "REC 04:18", 8.5, isDark, 0.0, selectedIdx == 5, accentArgb)
    p := spec.pills[6]
    _GdipDrawMiniPill(pGraphics, p.x, p.y, p.w, p.h, pal.chatAlert, pal.chatAlert, iconFont, Chr(0xE8BD), mono ? pal.chatIconAlert : "FFFFFF", "2 NEW", 8.5, isDark, 0.0, selectedIdx == 6, accentArgb)
    p := spec.pills[7]
    _GdipDrawMiniPill(pGraphics, p.x, p.y, p.w, p.h, pal.live, pal.live, iconFont, Chr(0xE720), mono ? pal.iconLive : "FFFFFF", "LIVE", 11.5, isDark, 0.68, selectedIdx == 7, accentArgb)

    if (selectedIdx == 8) {
        pVu := spec.pills[8]
        _GdipDrawRoundedBox(pGraphics, pVu.x - 2.0, pVu.y - 1.0, pVu.w + 4.0, pVu.h, 3.0, 0x00000000, accentArgb, 2.0)
    }

    ; Left & Right annotated callout cards
    for cardItem in spec.cards
        _GdipDrawCalloutCard(pGraphics, cardItem, cardItem.id, cardItem.id == selectedIdx, isDark, accentArgb)

    ; Bottom alternate-state legend strip (y=198..234, inside height 240)
    _GdipDrawLine(pGraphics, 12, 194, targetW - 12, 194, canvasBrdArgb, 1.0)
    Gdip.DrawText(pGraphics, "Other States:", "Segoe UI", 8.0, 1, subMutedArgb, 12, 200, 86, 28, 0, 1)

    _GdipDrawMiniPill(pGraphics, 100, 201, 78, 26, pal.muted, pal.muted, iconFont, Chr(0xF781), mono ? pal.iconMuted : "FFFFFF", "MUTED", 8.0, isDark)
    Gdip.DrawText(pGraphics, "Red pulses", "Segoe UI", 7.8, 0, subMutedArgb, 182, 200, 74, 28, 0, 1)

    _GdipDrawMiniPill(pGraphics, 260, 201, 82, 26, pal.recPaused, pal.recPaused, iconFont, Chr(0xE769), mono ? pal.recIconPaused : "FFFFFF", "PAUSED", 8.0, isDark)
    Gdip.DrawText(pGraphics, "Rec paused", "Segoe UI", 7.8, 0, subMutedArgb, 346, 200, 76, 28, 0, 1)

    _GdipDrawMiniPill(pGraphics, 426, 201, 74, 26, pal.streamWarn, pal.streamWarn, iconFont, Chr(0xE7BA), mono ? pal.streamIconWarn : "FFFFFF", "WARN", 8.0, isDark)
    Gdip.DrawText(pGraphics, "Drop/Reconn", "Segoe UI", 7.8, 0, subMutedArgb, 504, 200, 84, 28, 0, 1)

    _GdipDrawMiniPill(pGraphics, 592, 201, 84, 26, pal.recOff, pal.recOff, iconFont, Chr(0xE71A), mono ? pal.recIconOff : "D1D5DB", "NOT REC", 8.0, isDark)
    Gdip.DrawText(pGraphics, "Idle/Standby", "Segoe UI", 7.8, 0, subMutedArgb, 680, 200, 86, 28, 0, 1)

    hBmp := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBitmap, "Ptr*", &hBmp, "UInt", 0xFF000000 | ((outerBg & 0xFF) << 16) | (outerBg & 0xFF00) | ((outerBg >> 16) & 0xFF))
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    return hBmp
}

/**
 * Returns layout & hit regions for the Remote 1-Tier Mic HUD Diagram (680 x 194).
 */
GetRemoteHudDiagramSpec(W := 680, H := 194) {
    pills := [
        { id: 1, x: 252, y: 18,  w: 176, h: 42 }, ; LIVE green pill
        { id: 2, x: 252, y: 74,  w: 176, h: 42 }, ; MUTED red pulsing pill
        { id: 3, x: 252, y: 130, w: 176, h: 38 }  ; Dimmed searching/disconnected pill
    ]
    cards := [
        { id: 1, x: 10,  y: 16,  w: 204, h: 44, title: "Live / Muted State",  sub: "Green LIVE • Red pulses",        ax: 214, ay: 38,  tx: 251, ty: 38 },
        { id: 2, x: 466, y: 16,  w: 204, h: 44, title: "Click & Cough Hold",  sub: "Tap: Mute • Hold 350ms: Cough",  ax: 466, ay: 38,  tx: 429, ty: 38 },
        { id: 3, x: 10,  y: 124, w: 204, h: 44, title: "Drag, Snap & Scale",  sub: "Touch drag • 0.25x to 5.0x",     ax: 214, ay: 146, tx: 251, ty: 146 },
        { id: 4, x: 466, y: 124, w: 204, h: 44, title: "Menu, Dodge & Alt",   sub: "Right-click menu • Hold Alt",    ax: 466, ay: 146, tx: 429, ty: 146 }
    ]
    return { W: W, H: H, frame: { x: 236, y: 8, w: 208, h: 178 }, pills: pills, cards: cards }
}

HitTestRemoteHudDiagram(relX, relY) {
    spec := GetRemoteHudDiagramSpec()
    for card in spec.cards {
        if (relX >= card.x && relX <= card.x + card.w && relY >= card.y && relY <= card.y + card.h)
            return card.id
    }
    for pill in spec.pills {
        if (relX >= pill.x && relX <= pill.x + pill.w && relY >= pill.y && relY <= pill.y + pill.h)
            return Min(pill.id, 4)
    }
    return 0
}

/**
 * Renders the Remote Companion 1-Tier Mic HUD Diagram using GDI+ into an HBITMAP.
 */
BuildRemoteHudDiagramBitmap(cfg, selectedIdx := 1, targetW := 680, targetH := 194) {
    Gdip.Startup()
    dpiScale := A_ScreenDPI / 96.0
    pixW := Max(1, Round(targetW * dpiScale))
    pixH := Max(1, Round(targetH * dpiScale))

    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", pixW, "Int", pixH, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBitmap)
    if (!pBitmap)
        return 0

    pGraphics := 0
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBitmap, "Ptr*", &pGraphics)
    if (!pGraphics) {
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
        return 0
    }

    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", pGraphics, "Int", 4)
    if (Abs(dpiScale - 1.0) > 0.001)
        DllCall("gdiplus\GdipScaleWorldTransform", "Ptr", pGraphics, "Float", Float(dpiScale), "Float", Float(dpiScale), "Int", 0)

    isDark := Theme.IsDarkMode()
    outerBg := isDark ? UIConstants.DARK_SURFACE_BGR : UIConstants.LIGHT_SURFACE_BGR
    canvasBgArgb := isDark ? 0xFF1B1C20 : 0xFFF7F8FA
    canvasBrdArgb := isDark ? 0xFF353740 : 0xFFD5D8E0
    frameBgArgb := isDark ? 0xFF141519 : 0xFFE9ECF2
    frameBrdArgb := isDark ? 0xFF4B4F5C : 0xFFB0B7C5
    accentArgb := isDark ? 0xFF60CDFF : 0xFF0067C0
    lineMutedArgb := isDark ? 0xFF7D8596 : 0xFF687082
    subMutedArgb := isDark ? 0xFFB2B8C4 : 0xFF525866
    iconFont := (Integer(StrSplit(A_OSVersion, ".")[3]) >= 22000) ? "Segoe Fluent Icons" : "Segoe MDL2 Assets"

    cLive := (IsObject(cfg) && cfg.HasOwnProp("CustomLiveHex")) ? cfg.CustomLiveHex : "107C10"
    cMuted := (IsObject(cfg) && cfg.HasOwnProp("CustomMutedHex")) ? cfg.CustomMutedHex : "C42B1C"
    pal := UIConstants.GetColorPalette((IsObject(cfg) && cfg.HasOwnProp("HudColorPreset")) ? cfg.HudColorPreset : "Standard", cLive, cMuted)
    mono := IsObject(cfg) && cfg.HasOwnProp("MonoIcon") ? cfg.MonoIcon : false
    spec := GetRemoteHudDiagramSpec(targetW, targetH)

    DllCall("gdiplus\GdipGraphicsClear", "Ptr", pGraphics, "UInt", isDark ? 0xFF2C2C2C : 0xFFFFFFFF)
    _GdipDrawRoundedBox(pGraphics, 0.5, 0.5, targetW - 1.0, targetH - 1.0, 8.0, canvasBgArgb, canvasBrdArgb, 1.1)
    _GdipDrawRoundedBox(pGraphics, spec.frame.x, spec.frame.y, spec.frame.w, spec.frame.h, 8.0, frameBgArgb, frameBrdArgb, 1.1, true)
    Gdip.DrawText(pGraphics, "Strict 1-Tier Remote HUD States", "Segoe UI", 7.6, 0, subMutedArgb, spec.frame.x + 6, spec.frame.y + spec.frame.h - 15, spec.frame.w - 12, 13, 1, 1)

    for cardItem in spec.cards {
        isSel := (cardItem.id == selectedIdx)
        _GdipDrawArrow(pGraphics, cardItem.ax, cardItem.ay, cardItem.tx, cardItem.ty, isSel ? accentArgb : lineMutedArgb, isSel ? 2.2 : 1.5)
    }

    p := spec.pills[1]
    _GdipDrawMiniPill(pGraphics, p.x, p.y, p.w, p.h, pal.live, pal.live, iconFont, Chr(0xE720), mono ? pal.iconLive : "FFFFFF", "LIVE", 11.0, isDark, 0.0, selectedIdx == 1 || selectedIdx == 2, accentArgb)
    p := spec.pills[2]
    _GdipDrawMiniPill(pGraphics, p.x, p.y, p.w, p.h, pal.muted, pal.muted, iconFont, Chr(0xF781), mono ? pal.iconMuted : "FFFFFF", "MUTED (Pulse)", 10.0, isDark, 0.0, selectedIdx == 1, accentArgb)
    p := spec.pills[3]
    _GdipDrawMiniPill(pGraphics, p.x, p.y, p.w, p.h, pal.recOff, pal.recOff, iconFont, Chr(0xF781), "E5E7EB", "Slate (Offline)", 8.5, isDark, 0.0, selectedIdx == 3 || selectedIdx == 4, accentArgb)

    for cardItem in spec.cards
        _GdipDrawCalloutCard(pGraphics, cardItem, cardItem.id, cardItem.id == selectedIdx, isDark, accentArgb)

    hBmp := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBitmap, "Ptr*", &hBmp, "UInt", 0xFF000000 | ((outerBg & 0xFF) << 16) | (outerBg & 0xFF00) | ((outerBg >> 16) & 0xFF))
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    return hBmp
}

/**
 * Safely assigns a newly created HBITMAP to a GUI Picture control.
 */
ApplyDiagramBitmap(picCtrl, hBmp) {
    if (!IsObject(picCtrl) || !hBmp)
        return
    try picCtrl.Value := "HBITMAP:" hBmp
}

/**
 * Populates a ListBox with formatted titles from Help entries.
 */
PopulateHelpListBox(lbCtrl, entries, showCategoryTag := true) {
    if (!IsObject(lbCtrl))
        return
    lbCtrl.Delete()
    items := []
    for entry in entries
        items.Push(showCategoryTag ? ("[" entry.cat "] " entry.title) : entry.title)
    if (items.Length > 0) {
        lbCtrl.Add(items)
        lbCtrl.Choose(1)
    }
}
