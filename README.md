# PresenterSync 🎙️📊

PresenterSync is a lightweight, standalone Windows utility designed for live streamers, educators, and corporate professionals. It bridges OBS Studio, Zoom, and Microsoft PowerPoint, allowing you to control your slides, track recording/studio/scene/chat telemetry, and manage your microphone without ever losing window focus or broadcasting a hot mic.

## 🚀 Features

*   **3 Audio Routing Profiles:**
    1. **Pro OBS Setup (VB-Cable):** Controls OBS mic directly.
    2. **Standard Direct Mic (Zoom-Only):** Controls Zoom mic directly without OBS.
    3. **Dual App Sync (OBS + Zoom Direct):** Keeps OBS and Zoom mic states synchronized 2-way (`ObsMuteHotkey` + `ZoomMuteHotkey`).
*   **OBS WebSocket v5 Integration:** Real-time 2-way synchronization with OBS for Mic Mute, 3-state Recording (`NOT REC` / `REC` / `PAUSED`), Studio Mode indicator, and Active Program Scene pill.
*   **Native Windows UIA Zoom Monitoring (`Lib\UIA.ahk`):** Real-time background inspection of Zoom meeting controls for 2-way Mic sync, 3-state Zoom Recording, and a universal **Unread Chat Counter** (`CHAT` / `X NEW`) active in both OBS and Zoom modes.
*   **Adaptive Multi-Tier HUD Overlay:**
    *   **Basic Mode:** 1-tier live/muted Mic pill.
    *   **Zoom Mode:** 2-tier stack adding Recording Status + Zoom Chat Unread badge.
    *   **Pro OBS Mode:** 3-tier stack adding OBS Studio Mode + dynamically expanding Active Program Scene display.
    *   **Toggleable Extra HUDs:** Use **Show Extra HUDs** in the tray menu to collapse Row 2 and Row 3 down to just the Mic pill at any time while keeping OBS WebSocket Sync or Zoom Monitoring active in the background.
*   **Smart PowerPoint Controls:** Safely route your arrow keys and presentation shortcuts directly to PowerPoint while keeping OBS or Zoom in the background.
*   **Extensive Appearance & Scale Customization:** Toggle text labels, switch to monochromatic icons, adjust transparency (`Ghost 50%` / `Frosted 85%` / `Solid 100%`), enable aggressive pulsing animations, choose corner styles, and scale the HUD across 8 presets (`0.25x`, `0.5x`, `1.0x`, `1.5x`, `2.0x`, `2.5x`, `3.0x`, `5.0x`).
*   **Dynamic System Dark & Light Mode:** Automatically adapts the system tray menu, submenus, and all settings/help/about/tester windows to match your Windows Dark or Light theme in real time.
*   **Self-Healing Setup & Reset:** Automatically prompts for missing routing profiles/shortcuts or changed OBS passwords, and supports one-click factory appearance reset without losing custom screen position.

## ⚙️ Prerequisites: OBS WebSocket & Zoom Setup

### OBS Studio (WebSocket v5)
Before connecting PresenterSync to OBS, enable the WebSocket server inside OBS Studio (OBS Studio v28.0+):

1. Open OBS Studio.
2. Navigate to the top menu bar and click **Tools** > **WebSocket Server Settings**.
3. Check the box for **Enable WebSocket server**.
4. Ensure the **Server Port** is set to `4455` (the default).
5. Check the box for **Enable Authentication**.
6. Click **Generate Password** (or type a custom password). Click **Apply** and **OK**. 
*Keep this password handy—PresenterSync will ask for it the first time you enable OBS WebSocket Sync.*

### Zoom (UIA Background Monitoring)
To let PresenterSync read Zoom's Mute, Recording, and Unread Chat controls reliably in the background:

1. Open Zoom Settings > **Accessibility** (or **General**).
2. Enable **Always show meeting controls**.

## 🛠️ Installation & Usage

You can run PresenterSync in two ways:

### Option A: The Ready-to-Run Executable (Recommended)
The ready-to-run `.exe` version (no AutoHotkey installation required) is currently being finalized. 
👉 **[It will be available on Gumroad here shortly!](https://saabithjiffry.gumroad.com/l/presentersync)**

### Option B: Run from Source
If you prefer to run the raw script or compile it yourself:
1. Download and install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone or download this repository.
3. Ensure the `Lib` folder contains `WebSocket.ahk`, `UIA.ahk`, `Crypto.ahk`, `Gdip.ahk`, `OBS_Network.ahk`, and `GUI_Config.ahk`.
4. Run `PresenterSync.ahk`.

## 🎮 How It Works

1. **Initial Setup:** On your first launch, choose your Audio Routing Mode (`1`, `2`, or `3`) and configure your OBS / Zoom fallback shortcuts.
2. **Choose Monitoring Engine:** Right-click the PresenterSync tray icon to enable **OBS WebSocket Sync** or **Zoom Monitoring** (mutually exclusive).
3. **Customize:** Left-drag any HUD pill to reposition the whole stack (coordinates save automatically), or use **Indicator Appearance** in the tray menu to change scale, labels, opacity, and corner style.

**Default System Shortcuts:**
*   `Ctrl + F12` : Cycle Pointer Modes (Full PPT + Mute / Mute Only / OFF)
*   `Alt + F12` : Toggle OBS WebSocket Sync ON/OFF
*   `Ctrl + Alt + F12` : Toggle Zoom Monitoring ON/OFF
*   `Ctrl + Shift + F12` : Hide/Unhide the HUD Indicator
*   `Ctrl + Alt + Shift + F12` : Suspend All Hotkeys
*   `Alt + Shift + F12` : Exit Application

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
