# PresenterSync 🎙️📊

PresenterSync is a lightweight, standalone Windows utility designed for live streamers, educators, and corporate professionals. It seamlessly bridges OBS Studio and Microsoft PowerPoint, allowing you to control your slides and manage your microphone without ever losing window focus or broadcasting a hot mic.

## 🚀 Features

*   **OBS WebSocket v5 Integration:** Real-time two-way synchronization with OBS. If you mute in OBS, the on-screen indicator updates instantly.
*   **Smart PowerPoint Controls:** Safely route your arrow keys and presentation shortcuts directly to PowerPoint while keeping OBS or other apps in the background.
*   **Dynamic Visual Mute Indicator:** A customizable, floating UI overlay that sits on your screen so you always know your live audio status.
*   **Extensive Appearance Customization:** Toggle text labels, switch to monochromatic icons, adjust transparency (Ghost/Frosted/Solid), enable aggressive pulsing animations, and choose between standard, sleek, or circular/pill-shaped indicator styles.
*   **Self-Healing Setup:** Automatically detects network failures or changed OBS passwords and prompts you with a clean, user-friendly UI to fix it.
*   **One-Click Reset:** Instantly restore the factory default appearance from the system tray without losing your custom screen position.

## ⚙️ Prerequisites: OBS WebSocket Setup

Before connecting PresenterSync, you must enable the WebSocket server inside OBS Studio (Requires OBS Studio v28.0 or newer):

1. Open OBS Studio.
2. Navigate to the top menu bar and click **Tools** > **WebSocket Server Settings**.
3. Check the box for **Enable WebSocket server**.
4. Ensure the **Server Port** is set to `4455` (the default).
5. Check the box for **Enable Authentication**.
6. Click **Generate Password** (or type a custom password). Click **Apply** and **OK**. 
*Keep this password handy—PresenterSync will ask for it the first time you enable Sync.*

## 🛠️ Installation & Usage

You can run PresenterSync in two ways:

### Option A: The Ready-to-Run Executable (Recommended)
The ready-to-run `.exe` version (no AutoHotkey installation required) is currently being finalized. 
👉 **[It will be available on Gumroad here shortly!](https://saabithjiffry.gumroad.com/l/presentersync)**

### Option B: Run from Source
If you prefer to run the raw script or compile it yourself:
1. Download and install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone or download this repository.
3. Ensure `WebSocket.ahk` is located inside the `lib` folder.
4. Run `PresenterSync.ahk`.

## 🎮 How It Works

1. **Initial Setup:** On your first launch, the app will prompt you for a fallback OBS Mute keyboard shortcut (e.g., the hotkey you normally press to mute your mic in OBS).
2. **Connect to OBS:** Right-click the PresenterSync icon in your Windows system tray to access the **Module Controls**. Click **Enable OBS WebSocket Sync**.
3. **Enter Password:** Paste the OBS WebSocket password you generated earlier. The app will securely hash and store this for future sessions.
4. **Customize:** Use the system tray menu to drag the indicator to your preferred spot on the screen, tweak the visual settings, or manage your hotkeys.

**Default System Shortcuts:**
*   `Ctrl + F12` : Toggle PowerPoint Controls ON/OFF
*   `Alt + F12` : Toggle OBS WebSocket Sync ON/OFF
*   `Ctrl + Shift + F12` : Hide/Unhide the Visual Indicator
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
