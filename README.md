# PresenterSync v5.4.0 🎙️📊

PresenterSync is a lightweight, standalone Windows utility designed for live streamers, educators, and corporate professionals. It bridges OBS Studio, Zoom / Microsoft Teams / Google Meet, and Microsoft PowerPoint, allowing you to control your slides, track recording/stream/vcam/studio/scene/chat telemetry, and manage your microphone without ever losing window focus or broadcasting a hot mic.

## 🚀 Features

*   **Interactive Help Center, Live Visual HUD Guide & Instant Search:** Explore an annotated **Live HUD Diagram** with numbered arrow callouts explaining every pill, color state, click/drag/hold/Alt gesture, and the CoreAudio Voice Activity bar; browse every **System Tray menu and submenu**; read the categorized **Features A-Z** guide; and search any feature, menu item, or shortcut instantly in both PresenterSync and PresenterSync Remote (with Remote's **About** & **Setup & Help Guide** strictly curated to its streamlined 1-tier companion capabilities).
*   **Undocumented Desktop Surprise (`Alt + Ctrl + Shift + S`):** Curious explorers who press **`Alt + Ctrl + Shift + S`** while PresenterSync is active will find their floating HUD transforming into something unexpected right on the desktop (intentionally absent from the System Tray and Control Center—*try at your own risk!*).
*   **Unified Fluent Control Center Dashboard:** Configure every subsystem in one Windows 11 Fluent 6-tab dashboard (**Audio & Conf**, **OBS & Stream**, **Pointer**, **HUD & Theme**, **Remote**, **Profiles & Sys**) and click **Apply & Save** to validate hotkeys, update settings, rebind hotkeys, tear down or switch telemetry backends, and refresh the HUD and tray menu live without restarting.
*   **3 Audio Routing Profiles & Multi-Platform Conferencing (`Zoom`, `Microsoft Teams`, `Google Meet`):**
    1. **Pro OBS Setup (VB-Cable):** Controls OBS mic directly.
    2. **Standard Direct Mic (Conferencing-Only):** Controls Zoom, Microsoft Teams, or Google Meet mic directly without OBS.
    3. **Dual App Sync (OBS + Conferencing Direct):** Keeps OBS and your active conferencing platform (`Zoom`, `Teams`, or `Meet`) mic states synchronized 2-way.
*   **OBS WebSocket v5 Integration & 4th-Tier Live Stream / VCam HUD:** Real-time 2-way synchronization with OBS for Mic Mute, 3-state Recording (`NOT REC` / `REC` / `PAUSED`) with **Live Elapsed Recording Timer**, Studio Mode indicator, Active Program Scene pill, plus a **4th HUD Layer** for **OBS Live Stream Status** (`OFFLINE` / `LIVE` / `RECONNECT` / `DROP WARN` dropped-frames alert) and **OBS Virtual Camera (`VCAM`)**.
*   **Native Windows UIA Conferencing Monitoring (`Lib\UIA.ahk`):** Real-time background inspection of **Zoom**, **Microsoft Teams**, and **Google Meet** controls for 2-way Mic sync, Recording telemetry, and a universal **Unread Chat Counter** (`CHAT` / `X NEW`).
*   **Adaptive 4-Tier Interactive HUD Overlay:**
    *   **Basic Mode:** 1-tier live/muted Mic pill with a real-time **CoreAudio Voice Activity / Peak VU Meter Bar** along the bottom edge of the `LIVE` pill.
    *   **Conferencing Mode:** 2-tier stack adding Recording Status (with elapsed timer) + Unread Chat badge.
    *   **Pro OBS Mode:** 3-tier & 4-tier stack adding OBS Studio Mode + Active Program Scene (with **smooth horizontal marquee scrolling**) and optional Row 4 **Live Stream + Virtual Camera** pills.
    *   **Interactive Clickable HUD Pills:** Short-clicking (`<= 3px` movement, `< 400ms`) any HUD pill triggers quick actions: toggle Mic Mute, toggle OBS/Conferencing Recording, focus the Conferencing Chat window, toggle OBS Studio Mode, open a live **Popup OBS Scene Switcher Menu**, toggle Virtual Camera, or inspect live stream health—while dragging any pill moves the entire stack smoothly.
    *   **Magnetic Edge/Window Snapping, Auto-Dodge & Click-Through Mode:** Automatically snaps the HUD stack within `14px` of monitor work-area edges/centers and active `OBS` / `PowerPoint` / `Zoom` / `Teams` window borders. Optional **Auto-Dodge on Hover** fades the HUD to `15%` click-through ghost opacity when the mouse approaches, and **Click-Through Mode** lets clicks pass straight through (hold `Alt` to drag).
*   **5 Curated HUD Color Palettes & Tally Presets:** Choose between **Standard**, **Colorblind Safe** (Okabe-Ito Blue/Orange), **OLED Stealth**, **Broadcast Tally**, and **Cyber Ocean**, plus optional **Two-Tone Acoustic Audio Chime** and **Mute Status Toast** feedback.
*   **Smart PowerPoint Controls & Cough Hold-to-Mute Gesture:** Safely route arrow/page/slide keys directly to PowerPoint in the background, and optionally enable **Cough / Push-to-Mute** so holding your clicker mute button (`>= 350ms`) mutes while held and automatically unmutes back to `LIVE` on release.
*   **Persistent Named Configuration Profiles & System Utilities:** Save, load, switch, and delete named configuration profiles (`[Profile:<Name>]`) from the Tray Menu or Control Center, toggle **Start with Windows** (strictly `OFF` by default), and check for new releases via the built-in **GitHub Update Checker**.
*   **Smart Board & Mobile Remote Companions (`PresenterSync_Remote.apk` for Android 12–15+ & `PresenterSync_Remote.exe` for Windows):** Standalone **1-tier Mic HUD** companions for 65"+ classroom Smart Boards, Android phones (Galaxy A07, Redmi Note 12, Poco M3 class), and Windows OPS/presenter laptops.
    *   **Simultaneous Multi-Remote Host Bridge (`:4456`):** Pair and run **multiple Android and Windows remotes at the same time** (e.g., Smart Board + Presenter Phone + Secondary Laptop via `-Instance <name>`) connected to one Primary PC Host, with bidirectional sync across Mode 1 OBS, Mode 2 Conferencing-Only, Mode 3 Dual, and WAN Relay, monitored live inside **Remote Companion Info...**.
    *   **Adaptive Smart Board & Phone Layouts:** Automatic form-factor detection (`Auto`, `Smart Board`, `Mobile Phone`) keeps controls crisp from compact 360dp portrait phones (`Android 12+`) up to 65"+ 4K landscape Smart Boards (`Android 14+`) with floating pill scales from `0.25x` up to `5.0x`.
    *   **Triple-Method Pairing (QR, Session Code, WAN Relay):** Scan the host's live QR code (`presentersync://connect?...`) in Android, enter the 6-character LAN **Session Code (`XXX-XXX`)** on camera-less Smart Boards or Windows Remote via Host Bridge port `4456`, use **WAN Relay (`PS-XXXX-XXXX`)** across separate networks/hotspots, or enter manual Host/Port directly.
    *   **Customizable Floating Bubble Multi-Gestures & Position Lock:** Configure **Single Tap**, **Double Tap**, **Long Press** (`600ms`), and **Very Long Press** (`1400ms`) independently—defaulting to Single Tap disabled (`None`) to prevent accidental Smart Board touches, `Long Press` to Toggle Mute (with animated progress arc), and `Double Tap` for Quick Menu—plus optional split Hold Mute / Very Long Unmute and **Lock Pill Position**.
    *   **Play Protect-Safe Touch + PC Clicker Architecture:** Android keeps a minimal permission footprint (no `BIND_ACCESSIBILITY_SERVICE`), avoiding Play Protect sideload blocks cleanly. Keep your presenter clicker plugged into the Primary Windows PC (which syncs live mute status to Android) or control mute straight from the Android floating bubble gestures (`Long Press` / `Double Tap`).
    *   **Safe Manual Remote Shutdown:** Use **Close Remote Companion...** in the Primary system tray (or **Remote Companion Info...**) to shut down all connected Windows or Android companions safely.
    *   **Touchscreen Drag, Scale & Safety:** Magnetic screen-edge/center snapping, hover Auto-Dodge, Click-Through Mode (with persistent notification & Quick Tile unlock), two-tone acoustic chime, and 5 color presets.

## ⚙️ Prerequisites: OBS WebSocket & Zoom Setup

### OBS Studio (WebSocket v5)
Before connecting PresenterSync to OBS, enable the WebSocket server inside OBS Studio (OBS Studio v28.0+):

1. Open OBS Studio.
2. Navigate to the top menu bar and click **Tools** > **WebSocket Server Settings**.
3. Check the box for **Enable WebSocket server**.
4. Ensure the **Server Port** is set to `4455` (the default).
5. Check the box for **Enable Authentication**.
6. Click **Generate Password** (or type a custom password). Click **Apply** and **OK**. 
*Keep this password handy - PresenterSync will ask for it the first time you enable OBS WebSocket Sync.*

### Zoom (UIA Background Monitoring)
To let PresenterSync read Zoom's Mute, Recording, and Unread Chat controls reliably in the background:

1. Open Zoom Settings > **Accessibility** (or **General**).
2. Enable **Always show meeting controls**.

## 🛠️ Installation & Usage

You can run PresenterSync in two ways:

### Option A: Ready-to-Run Portable Executables (Recommended)
Zero-dependency portable executables (`PresenterSync.exe` and `PresenterSync_Remote.exe` for x64 Windows) can be built directly from the repository or obtained via releases:
👉 **[PresenterSync on Gumroad](https://saabithjiffry.gumroad.com/l/presentersync)**

### Option B: Run from Source
If you prefer to run the raw script or compile it yourself:
1. Download and install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone or download this repository.
3. Ensure the `Lib` folder contains the supporting modules (`WebSocket.ahk`, `UIA.ahk`, `Crypto.ahk`, `Gdip.ahk`, `OBS_Network.ahk`, `GUI_Config.ahk`, `HelpCenter.ahk`, etc.).
4. Run `PresenterSync.ahk` on the primary streaming laptop.
5. Run `PresenterSync_Remote.ahk` on the smart board / secondary laptop.

### Option C: 1-Click Portable Executable & APK Build
You can build standalone, zero-dependency `.exe` binaries for both Windows apps (or `build_android.bat` for the signed Android APK):
1. Ensure AutoHotkey v2 with compiler tools is installed.
2. Double-click **`build.bat`** (outputs to `dist\`).
3. It compiles:
   * **`dist\PresenterSync.exe`** (Primary Streaming Host)
   * **`dist\PresenterSync_Remote.exe`** (Smart Board Companion)
4. Copy `dist\PresenterSync_Remote.exe` to a USB drive or smart board OPS module and run it portably without any installation! (Or install `dist\PresenterSync_Remote.apk` on Android Smart Boards & phones.)

## 📁 Repository Layout
* `PresenterSync.ahk`, `PresenterSync_Remote.ahk` — Primary Host & Remote Companion AutoHotkey v2 entrypoints (`Lib\` holds shared modules)
* `android/` — Native Kotlin/Compose Android Smart Board & Phone Remote project (`build_android.bat`)
* `assets/` — Application icon files (`PresenterSync.ico`, `PresenterSyncRemote.ico`)
* `dist/` — Built release binaries (`PresenterSync.exe`, `PresenterSync_Remote.exe`, `PresenterSync_Remote.apk`)
* `tests/` — Automated AutoHotkey & Python regression/E2E suites

## 📡 Multi-Remote Smart Board & Phone Setup
1. **Host Firewall & Companion Bridge:** Enable OBS Studio WebSocket v5 (`Tools` > `WebSocket Server Settings`, port `4455`) if using OBS (Mode 1/3)—Mode 2 Zoom/Teams/Meet works without OBS via Host Bridge—and allow TCP ports `4455` & `4456` plus UDP `4456` on Private Firewall.
2. **Instant Pair Multiple Remotes:** Open **Settings** > **Remote Companion Info...** on the Primary host PC:
   * **Android (Phone / Smart Board):** Tap **Scan QR** in `PresenterSync_Remote.apk` or type the 6-character **Session Code (`XXX-XXX`)** -> **Pair Code** (works simultaneously on both your presenter phone and 65" Smart Board).
   * **Windows Remote (`PresenterSync_Remote.exe`):** Enter the **Session Code** in **Host Bridge Session Code** -> **Pair by Code**, or paste the **Universal Connection String**. Launch additional isolated Windows companions anytime using `-Instance <name>` (or `-Config <path.ini>`).
   * **Separate Networks (WAN Relay):** Enable **Different Networks (Internet)** and enter your `PS-XXXX-XXXX` code on any remote.
3. **Customize Controls Per Device:** On Android Smart Boards, leave **Single Tap = None** and use **Long Press** / **Very Long Press** gestures (or split Mute / Unmute holds) plus **Lock Pill Position** so interactive board taps don't accidentally toggle mute. Connect your presenter clicker to the Primary Windows PC to sync mute state across all screens cleanly.
4. **Live Connected Roster:** Watch all paired/live Windows & Android remotes update live inside **Remote Companion Info...**, or safely shut them down together with **Close Remote Companion...**.

## 🎮 How It Works

1. **Initial Setup:** On your first launch, choose your Audio Routing Mode (`1`, `2`, or `3`) and configure your OBS / Zoom fallback shortcuts.
2. **Choose Monitoring Engine:** Right-click the PresenterSync tray icon (or right-click directly on any HUD pill) to enable **OBS WebSocket Sync** or **Conferencing Monitoring** (`Zoom`, `Microsoft Teams`, or `Google Meet`, mutually exclusive).
3. **Interactive Help & Remote Guide:** Open **Help & Shortcuts** in the tray menu for an interactive **Visual HUD** diagram, **Tray Menus**, **Features A-Z**, instant **Search Help**, **Shortcuts**, **Remote Setup**, and **Live Status**.
4. **Customize Live:** Left-drag any HUD pill to reposition the whole stack (coordinates save automatically), or use **Indicator Appearance** to change scale, labels, opacity, corner style, and **App Theme** (**Follow System**, **Dark Mode**, or **Light Mode**) live without interrupting your active session.

**Default System Shortcuts (Primary Host):**
*   `Ctrl + F12` : Cycle Pointer Modes (Full PPT + Mute / Mute Only / OFF)
*   `Alt + F12` : Toggle OBS WebSocket Sync ON/OFF
*   `Ctrl + Alt + F12` : Toggle Conferencing Monitoring ON/OFF (`Zoom` / `Teams` / `Meet`)
*   `Ctrl + Shift + F12` : Hide/Unhide the HUD Indicator
*   `Ctrl + Alt + Shift + F12` : Suspend All Hotkeys
*   `Alt + Shift + F12` : Exit Application
*   `Alt + Ctrl + Shift + S` : Try at your own risk...

**Default System Shortcuts (Remote Companion):**
*   `Ctrl + F12` : Toggle Pointer Mute Control ON/OFF (HUD continues displaying live mic status when OFF)
*   `Alt + Shift + F12` : Exit PresenterSync Remote

## 📄 License
This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Acknowledgments
* WebSocket communication is powered by the [AutoHotkey-WebSocket](https://github.com/thqby/ahk2_lib) library by [thqby](https://github.com/thqby).


## ⚠️️ Known Limitations & Background Animation Declaration

**Background PowerPoint Animations (Windows DWM / DirectX GPU Throttling)**
PresenterSync uses a **Hybrid COM (`ComObjActive`) + `ControlSend` fallback architecture** paired with a **150ms hardware debounce shield** to dispatch native slide transitions (`View.Next()` / `View.Previous()`) without stealing window focus, triggering synthetic key-hold fast-forwarding, or breaking `{Tab}` + `{Enter}` hyperlink navigation.

However, when PowerPoint's fullscreen slideshow (`ahk_class screenClass`) is running in the background (e.g., while OBS Studio or Zoom is your active foreground window), **Windows OS aggressively throttles PowerPoint's DirectX GPU rendering loop** to conserve system resources. Because of this hardcoded OS behavior, duration-based slide animations (like Fades, Wipes, or Morphs) may still freeze or snap to their final frame unless Windows is prevented from throttling the unfocused presentation window.

* **Instantaneous Animations:** Standard "Appear" effects (for bullet points, code, or equations) are completely unaffected and render seamlessly.
* **Input & UAC Stability:** Slide progression and clicker inputs remain 100% functionally stable. If PresenterSync and PowerPoint run under different privilege levels (e.g., Administrator vs. Standard User), PresenterSync automatically falls back from COM to `ControlSend`.
* **Recommended Setup for Smooth Background Animations:**
  1. In OBS Studio, capture the PowerPoint Slide Show using **Window Capture** with **Capture Method** set to **`Windows 10 (1903 and up)`** (uses the Windows Graphics Capture API to signal active frame consumption).
  2. In **Windows Settings > System > Display > Graphics**, set `POWERPNT.EXE` to **High performance**.

For full technical details, historical test logs, and advanced multi-monitor/GPU workarounds, please refer to [Issue #16](https://github.com/SaabithJiffry/PresenterSync/issues/16).
