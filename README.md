# PresenterSync 🎙️📊

PresenterSync is a lightweight, standalone Windows utility designed for live streamers, educators, and corporate professionals. It seamlessly bridges OBS Studio and Microsoft PowerPoint, allowing you to control your slides and manage your microphone without ever losing window focus or broadcasting a hot mic.

## 🚀 Features

*   **OBS WebSocket v5 Integration:** Real-time two-way synchronization with OBS. If you mute in OBS, the on-screen indicator updates instantly.
*   **Smart PowerPoint Controls:** Safely route your arrow keys and presentation shortcuts directly to PowerPoint while keeping OBS in the background.
*   **Dynamic Visual Mute Indicator:** A customizable, floating UI overlay that sits on your screen so you always know your live audio status.
*   **Appearance Customization:** Toggle text labels, switch to monochromatic icons, adjust transparency (Ghost/Frosted/Solid), and enable an aggressive pulsing animation when muted.
*   **Self-Healing Setup:** Automatically detects network failures or changed OBS passwords and prompts you with a clean, user-friendly UI to fix it.

## 🛠️ Installation & Usage

You can run PresenterSync in two ways:

### Option A: The Ready-to-Run Executable (Recommended for Non-Technical Users)
If you don't want to install AutoHotkey or deal with code compilation, you can download the standalone, signed `.exe` version of PresenterSync.
👉 **[Get the Compiled `.exe` on Gumroad]** *(Link will be added later)*

### Option B: Run from Source
If you prefer to run the raw script or compile it yourself:
1. Download and install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone or download this repository.
3. Ensure `WebSocket.ahk` is located inside the `lib` folder.
4. Run `PresenterSync.ahk`.

## ⚙️ How It Works

On your first launch, the app will ask for a fallback OBS Mute shortcut. Once running, right-click the PresenterSync icon in your system tray to access the **Module Controls**. Enable **OBS WebSocket Sync** and enter your OBS WebSocket password to establish a direct network link.

**Default Shortcuts:**
*   `Ctrl + F12` : Toggle PowerPoint Controls ON/OFF
*   `Alt + F12` : Toggle OBS WebSocket Sync ON/OFF
*   `Ctrl + Shift + F12` : Hide/Unhide the Visual Indicator
*   `Alt + Shift + F12` : Exit Application

## 📄 License
This project is licensed under the MIT License - see the LICENSE file for details.
