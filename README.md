# PresenterSync — Smart Streaming, Conferencing & Classroom Presenter Suite

**PresenterSync** is a cross-platform presenter control suite bridging **OBS Studio**, **Zoom / Microsoft Teams / Google Meet**, **Microsoft PowerPoint**, **65"+ Android Smart Boards**, **Android Phones**, and **Zero-Install Browser Web Remotes** (iOS, iPadOS, macOS, Linux, Chromebook). Manage mic mute/unmute, switch or transition OBS scenes cleanly, trigger timed presenter alerts, export video editor chapter timelines, and keep presenters in sync across the podium laptop, Smart Board, phone, and browser without losing focus or broadcasting a hot mic.

[![Download Portal](https://img.shields.io/badge/Portal-SaabithJiffry.github.io-10B981?style=for-the-badge)](https://saabithjiffry.github.io)
[![GitHub Release](https://img.shields.io/github/v/release/SaabithJiffry/PresenterSync?style=for-the-badge&color=0EA5E9)](https://github.com/SaabithJiffry/PresenterSync/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

---

## Core Capabilities (v8.0.0)

### 1. Adaptive Floating Mic, 4-Tier HUD & Privacy Capture Exclusion
* **Adaptive 4-Tier Host Stack (`PresenterSync.exe`):**
  * **Tier 1:** High-contrast `LIVE` / `MUTED` Mic pill with live **CoreAudio Voice Activity VU Meter**, **Speaking-While-Muted Alert**, and optional **Timer / `BRB` / `REC` Pill Mini-Badges** (`ShowPillMiniBadges`).
  * **Tier 2:** Recording status (`REC` / `PAUSED` / `NOT REC`) with live elapsed timer + universal UIA **Unread Chat Counter** (`CHAT` / `X NEW`) for Zoom, Microsoft Teams, and Google Meet (with Meet background-tab alert).
  * **Tier 3:** OBS **Studio Mode** toggle + scrolling **Active Program Scene** pill (short-click opens live Scene Switcher menu).
  * **Tier 4:** Optional **OBS Live Stream Health** (`OFFLINE` / `LIVE` / `RECONNECT` / `DROP WARN`) + **Virtual Camera (`VCAM`)** controls.
* **Toggleable Secondary Independent Mic Pill (Primary App Only):** Toggle **Show Secondary Mic Pill (Mic-Only)** from the System Tray or Control Center Tab 4 (`HUD & Theme`). Renders **only** the Mic pill layer (`LIVE`/`MUTED`, voice meter, custom colors, breathing pulse), drags and snaps independently into `[SecondaryPosition]`, syncs live mute state with the Primary stack, and stays strictly off Remote companion builds.
* **Screen-Share Capture Exclusion:** Toggleable `WDA_EXCLUDEFROMCAPTURE` on Windows (`ExcludeFromCapture` / `ExcludeSecondaryFromCapture`) and `FLAG_SECURE` on Android (`hideFromScreenCapture`) keeps floating HUDs and Stage Nudges invisible to OBS Display/Window Capture and screen shares.
* **Interactive & Non-Intrusive:** Short-click any pill for instant action; left-drag for `14px` magnetic edge/window snapping; optional **Auto-Dodge on Hover**, **Click-Through Mode** (hold `Alt` to drag), and **Custom `#RRGGBB` Hex Theme Colors** with automatic WCAG contrast.

### 2. Native OBS Scene Transition, Director Deck, Timer, Quick-Nudge & Push-to-Talk
* **Native OBS Scene Transition Keystroke:** Bind a dedicated clicker button (`HwTransitionHotkey`) or OBS fallback (`ObsTransitionHotkey`) via `TriggerObsSceneTransition` — zero-lag `SetKeyDelay -1, -1` + `25ms` micro-bounce filter + `$` hook non-interception. Works across Studio Mode (`TriggerStudioModeTransition`), Program scene switching, and `ControlSend` fallback.
* **Wireless OBS Director Deck & Standby (`BRB`):** Switch OBS Program scenes, **Pause/Resume** or **Split Recording Chapter** (`3s` 2nd-tap stop-record confirm guard prevents accidental stops), and toggle **Standby (`BRB`)** across Windows Primary, Windows Remote, Android Remote, and Browser Web Remote.
* **Synchronized Presenter Countdown Timer & Quick-Nudge Presets:** Presets (`5:00`, `10:00`, `15:00`, `45:00`) with `2:00` remaining alert and live overtime (`-00:15`). Customize up to 6 **Quick-Nudge Presets** (`QuickNudgePresets`, default `"2 min left|Wrap up|Check Mic|Q&A"`) synced across Host, Windows Remote, Android Remote, and Web Remote.
* **Push-to-Talk & Cough Hold-to-Mute Modes:** Classic toggle, **Cough / Push-to-Mute** (`>= 350ms` hold), or **Push-to-Talk** (`>= 300ms` hold while muted to unmute, release to auto-mute; mutually exclusive with Cough mode and guarded against accidental unmuted clicks and `< 300ms` double-taps).

### 3. Safety Watchdogs, Pre-Flight Rehearsal, Timeline & Portable Bundles
* **Safety Watchdogs & Auto-Mute Triggers:**
  * **CoreAudio OS `IAudioEndpointVolume` Fallback & Drift Watchdog:** Monitors OS mic mute drift and supports multi-mic lockstep (`SecondaryAudioSources`).
  * **Live Alert Watchdogs:** Forgotten-Record (`15s`), Stream-Drop auto-backup record (`10s`), Low-Disk space (`30s`), and Dead-Mic (`45s`).
  * **Auto-Mute Safety Triggers:** Automatically mutes on Windows lock screen (`AutoMuteOnLock`), meeting end (`AutoMuteOnMeetingEnd`), or first OBS connect (`AutoMuteOnFirstObsConnect`).
* **"Go Live 10-Second Rehearsal" Pre-Flight Check (`RunPreFlightRehearsalChecks`):** 1-click 5-gate verification of OBS `:4455` + transition + audio input, live mic peak (`> 5%`), conferencing window, Host Bridge + paired remotes, and recording disk space.
* **Portable Settings Bundle Export/Import:** Export and import non-secret settings cleanly as `.json` (`PresenterSyncBundle_v1`) or `.ini` via `ExportPortableSettingsBundle` / `ImportPortableSettingsBundle`, with automatic `.ini.bak` backup.
* **Bounded Activity Timeline & Crash Recovery (`Lib\SessionTimeline.ahk`):** `2,000`-entry rolling buffer with `.jsonl` autosave, **Video Editor Chapter CSV** (RFC-4180 + formula-injection guard), **Markdown Summary (`.md`)**, and **YouTube Chapters**.
* **Persistent Error & Context Diagnostic Log (`Lib\DiagnosticLogger.ahk` & `DiagnosticLogger.kt`):** Writes `logs\PresenterSync_ErrorLog.log` (5 MB rotation, 50-event rolling breadcrumbs, 5-section context snapshots, secret redaction, `PERF_LAG` warnings) with an in-app Log Viewer and Sanitized Diagnostics Export.
* **64-bit `WM_COPYDATA` CLI Flags:** Control a running Host instance from Stream Deck, Task Scheduler, or scripts via `--mute`, `--unmute`, `--toggle`, `--transition`, `--scene <name>`, `--brb`, `--nudge <msg>`, `--timer <sec|pause|reset>`, and `--status`.

### 4. Multi-Remote Companions (`Windows`, `Android`, `Zero-Install Browser Web Remote`) & AES-256-GCM WAN Relay
* **Simultaneous Multi-Remote Host Bridge (`TCP :4456`, fallback `4458..4465`) & Classroom UDP Discovery (`:4457`):** Pair multiple Android devices, Windows Remotes (`-Instance <name>`), and Web Remotes simultaneously, with Standalone Cutoff mode (`EnableRemoteConnections=false` closes listening ports cleanly) and Firewall/UIPI probes.
* **Zero-Install Browser Web Remote (`http://<host-ip>:4456/`):** Self-contained dark-themed HTML5/CSS3/ES6 companion (`Lib\WebRemoteUI.ahk`) for iOS, iPadOS, macOS, Linux, and Chromebooks with Session Code auth, `localStorage` token persistence, and full live WebSocket control.
* **Direct OBS `:4455` Failover & Automatic `:4456` Bridge Re-Promotion:** If Host Bridge drops (`1,800ms` timeout), Remotes fail over automatically to Direct OBS `:4455` (with local `BRB` & Timer fallback) and probe `:4456` every `8,000ms` to re-promote seamlessly when the Host returns.
* **Authenticated AES-256-GCM WAN Relay:** Cross-platform `bcrypt.dll` (`Lib\Crypto.ahk`) <-> Kotlin `RelayCrypto.kt` (`AES/GCM/NoPadding`) with 96-bit IV, 128-bit auth tag, replay protection, custom self-hosted Relay Base URL (`RelayBaseUrl`), and full WAN telemetry parity.
* **Windows Remote Ergonomics (`PresenterSync_Remote.exe`):** `WM_POWERBROADCAST` wake & `WM_DISPLAYCHANGE` hotplug recovery, dual `:4456/health` + `:4455` probe, Touch-Friendly Quick Deck (`ShowRemoteTouchDeckGUI`), Saved Host Profiles, `"Paste Pairing URI"`, Slide & OBS Transition hotkeys, `LockHudPosition`, 10s idle auto-dim, `savedXRatio`/`savedYRatio` screen-ratio persistence, Error Log viewer, and pill mini-badges.
* **Android Remote Ergonomics (`PresenterSync_Remote.apk`, API 26–34+):**
  * **Smart Board High-DPI Canvas (`MicPillCanvasView` / `MicPillRenderMetrics`):** `0.5x–5.0x` sub-linear optical border scaling, tonal gradient sheen, knockout mute slash, auto-fit label, and timer/`BRB`/`REC`/amber alert mini-badges.
  * **Full-Screen OLED Podium Deck (`PodiumDeckScreen`):** Pure `#000000` lectern mode with `FLAG_KEEP_SCREEN_ON`, oversized Mute/Unmute surface, OBS Transition, Slides (`Prev`/`Next`/`F5` + Speaker Notes), Timer, `BRB`, and Stage Nudge chips.
  * **2x1 Home Screen App Widget (`PresenterSyncWidgetProvider`), Silent Waveform Haptics (`HapticAlertPlayer`), & Background BT Media Clicker (`BackgroundMediaClickerController`):** Native `MediaSession` + `VolumeProvider` clicker capture, Battery Optimization check, Share Pairing QR dialog, Error Log viewer, and dual `:4456`/`:4455` probe.
* **1-Tap In-App Self-Updaters & HUD Snake Easter Egg:** GitHub Releases + `SHA256SUMS.txt` verification on Windows & Android; `Alt + Ctrl + Shift + S` (or 5s Quick Menu hold on Android) launches translucent HUD Snake.

---

## Prerequisites & Setup

### OBS Studio (WebSocket v5 — Modes 1 & 3)
1. In **OBS Studio v28+**, open **Tools > WebSocket Server Settings**.
2. Enable **Enable WebSocket server** on port `4455` (recommended: enable authentication & copy password).
3. In PresenterSync, enable **OBS WebSocket Sync** (`Alt + F12` or Tray / Control Center). Mode 2 (**Conferencing-Only**) works without OBS via Host Bridge (`:4456`).

### Conferencing Apps (`Zoom`, `Microsoft Teams`, `Google Meet`)
* **Zoom:** Enable **Settings > Accessibility > Always show meeting controls** so UIA monitoring reads Mute, Record, and Chat status reliably in the background. Select `Auto` or a specific platform in Control Center.

### Firewall (Classroom Multi-Remote LAN)
Allow Private Network inbound **TCP `4455`** (if direct OBS), **TCP `4456`** (Host Bridge, Web Remote, & HTTP pairing), and **UDP `4456` / `4457`** (Host Bridge & Classroom discovery) on the Primary Host PC.

---

## Installation & Building from Source

* **Portal & Prebuilt Releases:** [saabithjiffry.github.io](https://saabithjiffry.github.io) or [GitHub Releases](https://github.com/SaabithJiffry/PresenterSync/releases/latest) (`PresenterSync.exe`, `PresenterSync_Remote.exe`, signed `PresenterSync_Remote.apk`, `SHA256SUMS.txt`).
* **Build Windows Executables:** Install [AutoHotkey v2](https://www.autohotkey.com/) (`v2.0+` with compiler) and run:
  ```bat
  build.bat
  ```
  Outputs portable binaries `dist\PresenterSync.exe` and `dist\PresenterSync_Remote.exe`.
* **Build Signed Android APK & Run JVM Tests:** Requires JDK 17 + Android SDK (`local.properties` or `signing.properties` / keystore configured):
  ```bat
  build_android.bat
  ```
  Runs JVM unit tests and builds signed `dist\PresenterSync_Remote.apk`.

---

## Default Shortcuts

| App | Shortcut | Action |
| :--- | :--- | :--- |
| **Primary Host** | `Ctrl + F12` | Cycle Pointer Mode (PPT + Mute / Mute Only / OFF) |
| **Primary Host** | `Alt + F12` | Toggle OBS WebSocket Sync ON/OFF |
| **Primary Host** | `Ctrl + Alt + F12` | Toggle Conferencing Monitor (`Zoom` / `Teams` / `Meet`) |
| **Primary Host** | `Ctrl + Shift + F12` | Show / Hide Primary HUD Stack |
| **Primary Host** | `Ctrl + Alt + Shift + F12` | Suspend / Resume All Hotkeys |
| **Primary Host** | `Alt + Shift + F12` | Exit PresenterSync |
| **Primary + Remote** | `Alt + Ctrl + Shift + S` | Toggle HUD Snake Easter Egg |
| **Windows Remote** | `Ctrl + F12` | Toggle Pointer Mute Control ON/OFF (HUD stays synced) |
| **Windows Remote** | `Alt + Shift + F12` | Exit PresenterSync Remote |

---

## Repository Architecture

```text
PresenterSync/
├── PresenterSync.ahk               # Primary Host entrypoint, hotkeys, PowerPoint COM/ControlSend, Tray
├── PresenterSync_Remote.ahk        # Windows Remote Companion (1-tier Mic HUD, Quick Deck, Bridge/Relay client)
├── Lib/
│   ├── GUI_Config.ahk              # Config/profile/theme/state classes, Portable Bundle Export/Import, facade
│   ├── DiagnosticLogger.ahk        # Persistent Error Log (5 MB rotation, 50 breadcrumbs, secret redaction)
│   ├── HudRenderer.ahk             # GDI+ layered pills, Secondary Mic Pill, mini-badges, snap & dodge
│   ├── ControlCenter.ahk           # Fluent 6-tab Control Center, Profile UIs, sanitized diagnostics
│   ├── SetupWizard.ahk             # Guided Setup Wizard, 10s Pre-Flight Rehearsal, LAN/WAN pairing QR & probes
│   ├── SelfUpdater.ahk             # GitHub Releases API, WinINet streamer, SHA-256 verifier & .exe/.old swapper
│   ├── SessionTimeline.ahk         # Bounded 2,000-entry timeline ring buffer, .jsonl autosave, CSV/MD/YouTube export
│   ├── HelpCenter.ahk              # Searchable A-Z Help entries & visual anatomy catalog
│   ├── HostBridge.ahk              # Multi-remote HTTP/WS/UDP bridge server (:4456) & Classroom beacon (:4457)
│   ├── WebRemoteUI.ahk             # Zero-install self-contained HTML5/CSS3/ES6 Web Remote served on :4456
│   ├── RemoteBridgeClient.ahk      # Windows Remote LAN UDP discovery, DHCP IP-shift follower, ratio & failover
│   ├── OBS_Network.ahk             # OBS WebSocket v5, Transition, Watchdogs, Director Deck, AES-256-GCM WAN Relay
│   ├── HudSnakeGame.ahk            # Playable translucent desktop Snake engine (keyboard + XInput/D-Pad)
│   ├── UIA.ahk / WebSocket.ahk / Crypto.ahk / Gdip.ahk / QrCode.ahk
├── android/                        # Kotlin + Jetpack Compose Remote Companion (API 26..34+)
│   └── app/src/main/.../remote/
│       ├── ui/screens/             # MainActivity, MainShellChrome, StatusAndHudScreen, PodiumDeckScreen,
│       │                           # HudAppearanceScreen, PointerSettingsScreen, HelpCenterScreen, ConnectionDialogScreen
│       ├── ui/overlay/             # MicPillCanvasView, MicPillRenderMetrics, FloatingMicOverlayManager,
│       │                           # FloatingToastBannerManager, HudSnakeOverlayView, HudSnakeEngine
│       ├── network/                # ConnectionManager, HostBridgeClient, ObsWebSocketClient, RelayClient,
│       │                           # RelayCrypto, UdpHostDiscoveryClient, DualEndpointProbe, AppUpdater
│       ├── config/                 # RemoteConfig, PairingUriBuilder, QuickNudgePresetHelper, DiagnosticLogger
│       ├── input/                  # ClickerMuteController, BubbleGestureRecognizer, KeyCapture
│       ├── service/                # FloatingHudForegroundService, HapticAlertPlayer, BackgroundMediaClickerController,
│       │                           # QuickToggleTileService
│       └── widget/                 # PresenterSyncWidgetProvider (2x1 Home Screen App Widget)
├── tests/                          # 32 AutoHotkey v2 suites (incl. 353-check master suite) +
│                                   # 9 Python live multi-process E2E & cross-language AES-GCM suites
└── dist/                           # Portable PresenterSync.exe, PresenterSync_Remote.exe, PresenterSync_Remote.apk
```

---

## Automated Verification Coverage

* **Windows (AutoHotkey v2):** `32` automated suites including `tests\test_master_suite.ahk` (`353` checks covering HUD rendering, OBS WS v5, UIA, Bridge, Watchdogs, Timeline, and Diagnostics) plus dedicated `v7.0.1`–`v7.8.1` feature & static audit suites.
* **Cross-Process & Cross-Language E2E (Python):** `9` live multi-process suites (`test_host_bridge.py`, `test_multi_remote_e2e.py`, `test_v762_cross_lang_crypto.py`, and `test_e2e_01`..`06`) verifying Web Remote, Crash Failover & Re-Promotion, Sleep/Wake & Rapid Transition Stress, Standalone Cutoff, PTT Mutual Exclusion, CLI `WM_COPYDATA`, Watchdogs, and AES-256-GCM parity.
* **Android (JVM & Lint):** `35` JUnit test suites (`112` tests) + `lintDebug` (`0` errors).

---

## License & Acknowledgments

* Licensed under the [MIT License](LICENSE).
* WebSocket communication built with [AutoHotkey-WebSocket](https://github.com/thqby/ahk2_lib) by [thqby](https://github.com/thqby).
