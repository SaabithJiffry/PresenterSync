# PresenterSync — Smart Streaming, Conferencing & Classroom Presenter Suite

**PresenterSync** is a lightweight cross-platform presenter control suite bridging **OBS Studio**, **Zoom / Microsoft Teams / Google Meet**, **Microsoft PowerPoint**, **65"+ Android Smart Boards**, and **Android Phones**. Manage mic mute/unmute, switch OBS scenes cleanly, trigger timed presenter alerts, export video editor chapter timelines, and keep presenters in sync across the podium laptop, Smart Board, and handheld phone without losing focus or broadcasting a hot mic.

[![Download Portal](https://img.shields.io/badge/Portal-SaabithJiffry.github.io-10B981?style=for-the-badge)](https://saabithjiffry.github.io)
[![GitHub Release](https://img.shields.io/github/v/release/SaabithJiffry/PresenterSync?style=for-the-badge&color=0EA5E9)](https://github.com/SaabithJiffry/PresenterSync/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

---

## Core Capabilities

### 1. Adaptive Floating Mic & 4-Tier HUD (Windows Host + Primary Secondary Mic Pill)
* **Adaptive 4-Tier Host Stack (`PresenterSync.exe`):**
  * **Tier 1:** High-contrast `LIVE` / `MUTED` Mic pill with live **CoreAudio Voice Activity VU Meter** and **Speaking-While-Muted Alert** (triggers if audio peaks while muted).
  * **Tier 2:** Recording status (`REC` / `PAUSED` / `NOT REC`) with live elapsed timer + universal UIA **Unread Chat Counter** (`CHAT` / `X NEW`) for Zoom, Microsoft Teams, and Google Meet.
  * **Tier 3:** OBS **Studio Mode** toggle + scrolling **Active Program Scene** pill (short-click opens live Scene Switcher menu).
  * **Tier 4:** Optional **OBS Live Stream Health** (`OFFLINE` / `LIVE` / `RECONNECT` / `DROP WARN`) + **Virtual Camera (`VCAM`)** controls.
* **Toggleable Secondary Independent Mic Pill (Primary App Only):** Need a second pure mic-status indicator on your teleprompter, second monitor, or presenter notes corner? Toggle **Show Secondary Mic Pill (Mic-Only)** from the System Tray or Control Center Tab 4 (`HUD & Theme`). It renders **only** the Mic pill layer (`LIVE`/`MUTED`, voice meter, custom colors, breathing pulse), drags and snaps **independently** into `[SecondaryPosition]`, syncs live mute state and click-to-mute with the Primary stack, and stays strictly off Remote companion builds.
* **Interactive & Non-Intrusive:** Short-click any pill for instant action; left-drag for `14px` magnetic edge/window snapping; optional **Auto-Dodge on Hover** (`15%` ghost opacity) and **Click-Through Mode** (hold `Alt` to drag).
* **Custom Hex Theme Colors & Tallies:** Pick **Standard**, **Colorblind Safe** (Okabe-Ito Blue/Orange), **OLED Stealth**, **Broadcast Tally**, **Cyber Ocean**, or **Custom** `#RRGGBB` live/muted hex colors with automatic WCAG icon contrast — synced across QR/deep-link to Android Remotes and HUD Snake.

### 2. Director Deck, Presenter Countdown Timer, Silent Stage Nudge & Push-to-Talk
* **Wireless OBS Director Deck:** Switch OBS Program scenes, **Pause/Resume** or **Split Recording Chapter** cleanly across Windows Primary, Windows Remote, and Android Remote (`Status & HUD` Director Deck card & Quick Menu).
* **Standby / `"BRB"` Curtain Macro:** 1-tap macro snapshots your active mic mute state & scene, switches cleanly to your configured `BRB` standby scene and mutes mic, then restores your exact previous scene & mute state on return.
* **Synchronized Presenter Countdown Timer:** Presets (`5:00`, `10:00`, `15:00`, `45:00`) or custom durations synchronized via Host Bridge & WAN Relay, with `2:00` remaining alert, live overtime counting (`-00:15`), and floating pill badge display on Windows & Android.
* **Silent Stage Nudge Toasts:** Send unobtrusive on-screen cues (e.g., `"2 mins left"`, `"Switch to Q&A"`) from Producer/Control laptop or Android to floating banner overlays on Windows (`ShowStageNudgeBanner`) and Android (`FloatingToastBannerManager`) — never captured by OBS Display/Game scenes.
* **Push-to-Talk & Cough Hold-to-Mute Modes:** Choose classic toggle, **Cough / Push-to-Mute** (hold clicker >= 350ms to mute, release to restore `LIVE`), or **Push-to-Talk** (stay muted by default; hold clicker or Android floating pill >= 300ms to unmute while speaking, release to auto-mute).

### 3. Session Activity Timeline, Chapter CSV/Markdown Export & Guided Setup Wizards
* **Bounded Activity Timeline & Video Editor Exports (`Lib\SessionTimeline.ahk`):** Automatically logs mic transitions, OBS recording start/pause/chapter-splits, scene switches, Standby toggles, slide clicks, countdown checkpoints, muted-voice alerts, and remote join/leave events in a bounded `2,000`-entry rolling buffer. Export with 1 click to **Video Editor Chapter CSV** (RFC-4180 escaped with spreadsheet formula injection guard), **Markdown Session Summary (`.md`)**, or **YouTube Chapters (`00:00` block)** copied to clipboard.
* **Guided First-Run Setup Wizards:** Both Windows (`ShowGuidedSetupWizard`) and Android (`OnboardingWizardCard`) include 4-step live hardware/permission/LAN checklists with 1-tap **Scan Classroom (`:4457`)**, **Grant Overlay**, **Allow Notifications (`API 33+`)**, **Test Floating HUD**, and **Flash Pill** probes.

### 4. Zero-Config Multi-Remote Companions & Classroom Failover (`Android` + `Windows Remote`)
* **Simultaneous Multi-Remote Host Bridge (`TCP :4456`):** Pair and run **multiple Android phones, Android Smart Boards, and Windows Remotes simultaneously** (launch extra isolated Windows remotes with `-Instance <name>`). Monitor connected devices or cleanly **Close Remote Companion...** from the host tray.
* **Zero-Config Classroom UDP Discovery (`:4457`) & Smart Failover:** Remotes discover nearby classroom hosts broadcast on UDP `:4457` (`PS_DISCOVER_V1`) without manual IP typing, track `hostUuid` to auto-follow DHCP IP shifts across reconnects, auto-failover between LAN <-> WAN Relay (`PS-XXXX-XXXX`), and recover automatically after Windows sleep/wake (`WM_POWERBROADCAST`) or Wi-Fi/hotspot swaps.
* **3 Audio Routing Profiles + Multi-App UIA:**
  1. **Mode 1 — Pro OBS Setup (VB-Cable):** Controls OBS mic directly over WebSocket v5 (`:4455`).
  2. **Mode 2 — Standard Direct Mic (Conferencing-Only):** Controls Zoom, Microsoft Teams, or Google Meet directly without OBS.
  3. **Mode 3 — Dual App Sync:** Keeps OBS and your active conferencing platform synchronized 2-way.
* **Smart Board & Phone Form-Factor Ergonomics:** Responsive layouts (`Auto`, `Smart Board`, `Mobile Phone`) from `360dp` compact phones up to `65"+` 4K Smart Boards; configurable Single Tap (off by default on Smart Boards to prevent accidental touches), Double Tap, Long Press, and Very Long Press gestures; `keepScreenOn`, idle dimming, saved host profiles, and **Lock Pill Position**.
* **1-Tap In-App Self-Updaters:** Both Windows (`Lib\SelfUpdater.ahk` WinINet streaming + `bcrypt` SHA-256 verification + atomic `.exe`/`.old` swap) and Android (`ApkSelfInstaller` + `FileProvider` + `REQUEST_INSTALL_PACKAGES` + HUD auto-restore) check GitHub Releases and verify `SHA256SUMS.txt` signatures before installing.
* **Undocumented HUD Snake Easter Egg:** Press `Alt + Ctrl + Shift + S` on Windows (or double-tap the Android pill to open Quick Menu -> hold `"Try at your own risk"` for 5 seconds) to morph the floating HUD into playable translucent desktop/overlay Snake with keyboard arrows, `WASD`, swipe/touch, and hardware controller/D-Pad support (`auto-hiding` live HUDs cleanly until exit).

---

## Prerequisites & Setup

### OBS Studio (WebSocket v5 — Modes 1 & 3)
1. In **OBS Studio v28+**, open **Tools > WebSocket Server Settings**.
2. Enable **Enable WebSocket server** on port `4455` (recommended: enable authentication & copy password).
3. In PresenterSync, enable **OBS WebSocket Sync** (`Alt + F12` or Tray / Control Center). Mode 2 (**Conferencing-Only**) works without OBS via Host Bridge (`:4456`).

### Conferencing Apps (`Zoom`, `Microsoft Teams`, `Google Meet`)
* **Zoom:** Enable **Settings > Accessibility > Always show meeting controls** so UIA monitoring reads Mute, Record, and Chat status reliably in the background.

### Firewall (Classroom Multi-Remote LAN)
Allow Private Network inbound **TCP `4455`** (if direct OBS), **TCP `4456`** (Host Bridge & HTTP pairing), and **UDP `4456` / `4457`** (Host Bridge & Classroom discovery) on the Primary Host PC.

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
├── PresenterSync_Remote.ahk        # Windows Remote Companion (strictly 1-tier Mic HUD + Bridge/Relay client)
├── Lib/
│   ├── GUI_Config.ahk              # Core config/profile/theme/state classes & facade #Include entrypoint
│   ├── HudRenderer.ahk             # GDI+ layered pills, Secondary Independent Mic Pill, animations, snap & dodge
│   ├── ControlCenter.ahk           # Fluent 6-tab Control Center, Help/About/Profile UIs, sanitized diagnostics
│   ├── SetupWizard.ahk             # Guided 4-step Setup Wizard, LAN/WAN pairing QR & probe helpers
│   ├── SelfUpdater.ahk             # GitHub Releases API, WinINet streamer, SHA-256 verifier & .exe/.old swapper
│   ├── SessionTimeline.ahk         # Bounded 2,000-entry timeline ring buffer, Chapter CSV / MD / YouTube export
│   ├── HelpCenter.ahk              # Searchable A-Z Help entries & visual anatomy catalog
│   ├── HostBridge.ahk              # Multi-remote HTTP/WS/UDP bridge server (:4456) & Classroom beacon (:4457)
│   ├── RemoteBridgeClient.ahk      # Windows Remote LAN UDP discovery, DHCP IP-shift follower & failover
│   ├── OBS_Network.ahk             # OBS WebSocket v5, Director Deck macros, Timer, Stage Nudge & WAN Relay
│   ├── HudSnakeGame.ahk            # Playable translucent desktop Snake engine (keyboard + XInput/D-Pad)
│   ├── UIA.ahk / WebSocket.ahk / Crypto.ahk / Gdip.ahk / QrCode.ahk
├── android/                        # Kotlin + Jetpack Compose Remote Companion (API 26..34+)
│   └── app/src/main/.../remote/
│       ├── ui/screens/             # MainActivity, MainShellChrome, StatusAndHudScreen, DirectorControlsSheet,
│       │                           # OnboardingWizardCard, UpdateBannerCard, ConnectionDialogScreen, QrScannerScreen, ...
│       ├── ui/overlay/             # FloatingMicOverlayManager (pill + Quick Menu + 5s Snake), FloatingToastBannerManager,
│       │                           # HudSnakeOverlayView, HudSnakeEngine
│       ├── network/                # ConnectionManager (LAN <-> WAN failover), UdpHostDiscoveryClient, HostBridgeClient,
│       │                           # ObsWebSocketClient, RelayClient, AppUpdater, ApkSelfInstaller
│       ├── input/                  # ClickerMuteController, BubbleGestureRecognizer, KeyCapture
│       └── service/                # FloatingHudForegroundService & Quick Settings Tile
├── tests/                          # 6 AutoHotkey suites + 5 Python live process/network E2E suites
└── dist/                           # Portable PresenterSync.exe, PresenterSync_Remote.exe, PresenterSync_Remote.apk
```

---

## Known Limitations: Background PowerPoint Animations

PresenterSync dispatches native background PowerPoint slide transitions via Hybrid **COM (`ComObjActive`) + `ControlSend`** with a `150ms` hardware debounce shield so slide navigation never steals focus. When PowerPoint's fullscreen slideshow (`ahk_class screenClass`) runs unfocused, Windows OS aggressively throttles unfocused DirectX DWM animations:
* **Appear** transitions render instantaneously and cleanly.
* For timed **Fade / Wipe / Morph** animations under OBS Studio, use **Window Capture** with **Capture Method = `Windows 10 (1903 and up)`** and set `POWERPNT.EXE` to **High performance** under **Windows Settings > Display > Graphics**.

See [Issue #16](https://github.com/SaabithJiffry/PresenterSync/issues/16) for detailed test matrices and GPU workarounds.

---

## License & Acknowledgments

* Licensed under the [MIT License](LICENSE).
* WebSocket communication built with [AutoHotkey-WebSocket](https://github.com/thqby/ahk2_lib) by [thqby](https://github.com/thqby).
