# PresenterSync v3.0.0 🎙️📊

PresenterSync is a lightweight, standalone Windows utility designed for live streamers, educators, and corporate professionals. It bridges OBS Studio, Zoom / Microsoft Teams / Google Meet, and Microsoft PowerPoint, allowing you to control your slides, track recording/stream/vcam/studio/scene/chat telemetry, and manage your microphone without ever losing window focus or broadcasting a hot mic.

## 🚀 Features

*   **Unified Fluent Control Center Dashboard (`v3.0.0`):** Configure every subsystem in one Windows 11 Fluent 6-tab dashboard (**Audio & Conf**, **OBS & Stream**, **Pointer**, **HUD & Theme**, **Remote**, **Profiles & Sys**) and click **Apply & Save** to validate hotkeys, update settings, rebind hotkeys, tear down or switch telemetry backends, and refresh the HUD and tray menu live without restarting.
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
*   **Smart Board Companion Client (`PresenterSync_Remote.ahk` / `.exe`):** Standalone, dedicated **1-tier Mic HUD** companion for Windows-based smart boards (OPS modules) and secondary laptops. Works with OBS Studio over **Same Router (LAN)** or **Different Networks (Internet)** AND in **Conferencing-Only Mode (Zoom/Teams/Meet without OBS)** via the Host Companion Relay Bridge.
    *   **Same Router (LAN) & Different Networks (Internet) Modes:** Use the default multi-candidate LAN failover engine (`STUDIO-PC.local, 192.168.1.50, 192.168.1.125`) when on the same router, or switch to **Different Networks (Internet)** using your host's auto-generated **Internet Pairing Code** (`PS-XXXX-XXXX`) when devices are on separate networks or mobile hotspots.
    *   **Remote Clicker Mute & Customizable Shortcuts:** Intercepts pointer keystrokes (default `b`) with a 150ms debounce shield. Toggle Pointer Mute Control ON/OFF anytime on the secondary device using `Ctrl + F12` (when OFF, clicking the pointer will not mute OBS while the HUD continues displaying live mic status from the primary device) and exit using `Alt + Shift + F12` (both customizable via **Change App Shortcuts...**).
    *   **Safe Manual Remote Shutdown:** Use **Close Remote Companion...** in the Primary system tray (or **Remote Companion Info...**) to send a confirmed shutdown signal to turn off the secondary companion without ever closing it accidentally when restarting the primary app.
    *   **Touchscreen Drag & Scale:** Fully touch-friendly drag-and-drop repositioning with scales up to `5.0x` for large 65"–86" 4K interactive displays.

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
3. Ensure the `Lib` folder contains `WebSocket.ahk`, `UIA.ahk`, `Crypto.ahk`, `Gdip.ahk`, `OBS_Network.ahk`, and `GUI_Config.ahk`.
4. Run `PresenterSync.ahk` on the primary streaming laptop.
5. Run `PresenterSync_Remote.ahk` on the smart board / secondary laptop.

### Option C: 1-Click Portable Executable Build
You can build standalone, zero-dependency `.exe` binaries for both the primary and remote apps:
1. Ensure AutoHotkey v2 with compiler tools is installed.
2. Double-click **`build.bat`**.
3. It compiles:
   * **`PresenterSync.exe`** (Primary Streaming Host)
   * **`PresenterSync_Remote.exe`** (Smart Board Companion)
4. Copy `PresenterSync_Remote.exe` to a USB drive or smart board OPS module and run it portably without any installation!

## 📡 Smart Board Remote Companion Setup
1. **Host Firewall & OBS WebSocket:** Enable OBS Studio WebSocket v5 (`Tools` > `WebSocket Server Settings`, port `4455`), and allow **TCP port `4455`** in Windows Firewall on the host laptop.
2. **Copy Host Endpoints:** On the primary laptop, right-click the PresenterSync tray icon > **Settings** > **Remote Companion Info...** (or open the **Remote Setup** tab in **Help & Shortcuts**) and click **Copy Universal String to Clipboard** (contains your computer name `.local` and all active Ethernet/Wi-Fi IPs).
3. **Connect Smart Board:** On the smart board, launch `PresenterSync_Remote` (script or `.exe`). Paste the connection string into **Host Address**, verify **Port** (`4455`), enter your OBS WebSocket password, match the exact **Audio Source Name** (default `Mic/Aux`), and click **Test Connection** before clicking **Connect & Start**.
4. **In-App Help on Smart Board:** Right-click the Remote pill (or tray icon) and choose **Help & Setup Guide...**, or click **Setup Guide** directly in the connection dialog.
5. **Present:** Plug your clicker into the smart board—pressing the mute button (default `b`) immediately toggles OBS mute on the host laptop, while the HUD dims automatically when disconnected.

## 🎮 How It Works

1. **Initial Setup:** On your first launch, choose your Audio Routing Mode (`1`, `2`, or `3`) and configure your OBS / Zoom fallback shortcuts.
2. **Choose Monitoring Engine:** Right-click the PresenterSync tray icon (or right-click directly on any HUD pill) to enable **OBS WebSocket Sync** or **Conferencing Monitoring** (`Zoom`, `Microsoft Teams`, or `Google Meet`, mutually exclusive).
3. **Interactive Help & Remote Guide:** Open **Help & Shortcuts** in the tray menu for step-by-step setup instructions across **Shortcuts**, **Pointer & PPT**, **Audio & Sync**, **Remote Setup**, **HUD & Theme**, and **Live Status**.
4. **Customize Live:** Left-drag any HUD pill to reposition the whole stack (coordinates save automatically), or use **Indicator Appearance** to change scale, labels, opacity, corner style, and **App Theme** (**Follow System**, **Dark Mode**, or **Light Mode**) live without interrupting your active session.

**Default System Shortcuts (Primary Host):**
*   `Ctrl + F12` : Cycle Pointer Modes (Full PPT + Mute / Mute Only / OFF)
*   `Alt + F12` : Toggle OBS WebSocket Sync ON/OFF
*   `Ctrl + Alt + F12` : Toggle Conferencing Monitoring ON/OFF (`Zoom` / `Teams` / `Meet`)
*   `Ctrl + Shift + F12` : Hide/Unhide the HUD Indicator
*   `Ctrl + Alt + Shift + F12` : Suspend All Hotkeys
*   `Alt + Shift + F12` : Exit Application

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
