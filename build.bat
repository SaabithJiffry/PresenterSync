@echo off
setlocal
cd /d "%~dp0"

set "AHK2EXE=C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
set "BASE=C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
set "ICON=PresenterSync.ico"
set "REMOTE_ICON=PresenterSyncRemote.ico"

if not exist "%AHK2EXE%" (
    echo [ERROR] Ahk2Exe compiler not found at: %AHK2EXE%
    echo Please install AutoHotkey v2 with compiler components.
    pause
    exit /b 1
)

if not exist "%BASE%" (
    echo [ERROR] AutoHotkey64 base binary not found at: %BASE%
    pause
    exit /b 1
)

echo =======================================================
echo Building PresenterSync Portable Executables...
echo =======================================================

echo [1/2] Compiling PresenterSync.exe (Primary Streaming Host)...
if exist "%~dp0PresenterSync.exe" del /f /q "%~dp0PresenterSync.exe"
"%AHK2EXE%" /in "%~dp0PresenterSync.ahk" /out "%~dp0PresenterSync.exe" /icon "%~dp0%ICON%" /base "%BASE%"
if %errorlevel% neq 0 (
    echo [FAILED] Compilation of PresenterSync.exe failed with exit code %errorlevel%.
    pause
    exit /b %errorlevel%
)
echo [OK] PresenterSync.exe built successfully.

echo.
echo [2/2] Compiling PresenterSync_Remote.exe (Smart Board Companion)...
if exist "%~dp0PresenterSync_Remote.exe" del /f /q "%~dp0PresenterSync_Remote.exe"
"%AHK2EXE%" /in "%~dp0PresenterSync_Remote.ahk" /out "%~dp0PresenterSync_Remote.exe" /icon "%~dp0%REMOTE_ICON%" /base "%BASE%"
if %errorlevel% neq 0 (
    echo [FAILED] Compilation of PresenterSync_Remote.exe failed with exit code %errorlevel%.
    pause
    exit /b %errorlevel%
)
echo [OK] PresenterSync_Remote.exe built successfully.

echo.
echo Refreshing Windows Shell icon cache...
set "REPO_DIR=%~dp0"
set "HOST_EXE=%~dp0PresenterSync.exe"
set "REMOTE_EXE=%~dp0PresenterSync_Remote.exe"
powershell -NoProfile -Command "Add-Type -Namespace Win32 -Name Shell -MemberDefinition ('[DllImport(' + [char]34 + 'shell32.dll' + [char]34 + ')] public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);'); foreach ($p in @($env:HOST_EXE, $env:REMOTE_EXE)) { $ptr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($p); try { [Win32.Shell]::SHChangeNotify(0x00002000, 0x1005, $ptr, [IntPtr]::Zero) } finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) } }; $dirPtr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($env:REPO_DIR.TrimEnd('\')); try { [Win32.Shell]::SHChangeNotify(0x00001000, 0x1005, $dirPtr, [IntPtr]::Zero) } finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($dirPtr) }; [Win32.Shell]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero); $sh = New-Object -ComObject Shell.Application; foreach ($w in $sh.Windows()) { try { if ($w.Document.Folder.Self.Path -eq $env:REPO_DIR.TrimEnd('\')) { $w.Refresh() } } catch {} }" >nul 2>&1
if exist "%SystemRoot%\System32\ie4uinit.exe" "%SystemRoot%\System32\ie4uinit.exe" -show >nul 2>&1

echo.
echo =======================================================
echo Build complete!
echo Portable binaries ready:
echo  - PresenterSync.exe
echo  - PresenterSync_Remote.exe
echo =======================================================
pause

