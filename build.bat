@echo off
setlocal
cd /d "%~dp0"

set "AHK2EXE=C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
set "BASE=C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
set "ICON=assets\PresenterSync.ico"
set "REMOTE_ICON=assets\PresenterSyncRemote.ico"
set "DIST_DIR=%~dp0dist"

if not exist "%AHK2EXE%" (
    echo [ERROR] Ahk2Exe compiler not found at: %AHK2EXE%
    echo Please install AutoHotkey v2 with compiler components.
    if /i not "%~1"=="--nopause" pause
    exit /b 1
)

if not exist "%BASE%" (
    echo [ERROR] AutoHotkey64 base binary not found at: %BASE%
    if /i not "%~1"=="--nopause" pause
    exit /b 1
)

echo =======================================================
echo Building PresenterSync Portable Executables...
echo =======================================================

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

echo [1/2] Compiling dist\PresenterSync.exe (Primary Streaming Host)...
taskkill /F /IM PresenterSync.exe >nul 2>&1
if exist "%DIST_DIR%\PresenterSync.exe" del /f /q "%DIST_DIR%\PresenterSync.exe"
"%AHK2EXE%" /in "%~dp0PresenterSync.ahk" /out "%DIST_DIR%\PresenterSync.exe" /icon "%~dp0%ICON%" /base "%BASE%" /silent verbose
if %errorlevel% neq 0 (
    echo [FAILED] Compilation of dist\PresenterSync.exe failed with exit code %errorlevel%.
    if /i not "%~1"=="--nopause" pause
    exit /b %errorlevel%
)
echo [OK] dist\PresenterSync.exe built successfully.

echo.
echo [2/2] Compiling dist\PresenterSync_Remote.exe (Smart Board Companion)...
taskkill /F /IM PresenterSync_Remote.exe >nul 2>&1
if exist "%DIST_DIR%\PresenterSync_Remote.exe" del /f /q "%DIST_DIR%\PresenterSync_Remote.exe"
"%AHK2EXE%" /in "%~dp0PresenterSync_Remote.ahk" /out "%DIST_DIR%\PresenterSync_Remote.exe" /icon "%~dp0%REMOTE_ICON%" /base "%BASE%" /silent verbose
if %errorlevel% neq 0 (
    echo [FAILED] Compilation of dist\PresenterSync_Remote.exe failed with exit code %errorlevel%.
    if /i not "%~1"=="--nopause" pause
    exit /b %errorlevel%
)
echo [OK] dist\PresenterSync_Remote.exe built successfully.

echo.
echo Refreshing Windows Shell icon cache...
set "REPO_DIR=%~dp0dist"
set "HOST_EXE=%DIST_DIR%\PresenterSync.exe"
set "REMOTE_EXE=%DIST_DIR%\PresenterSync_Remote.exe"
powershell -NoProfile -Command "Add-Type -Namespace Win32 -Name Shell -MemberDefinition ('[DllImport(' + [char]34 + 'shell32.dll' + [char]34 + ')] public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);'); foreach ($p in @($env:HOST_EXE, $env:REMOTE_EXE)) { $ptr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($p); try { [Win32.Shell]::SHChangeNotify(0x00002000, 0x1005, $ptr, [IntPtr]::Zero) } finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) } }; $dirPtr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($env:REPO_DIR.TrimEnd('\')); try { [Win32.Shell]::SHChangeNotify(0x00001000, 0x1005, $dirPtr, [IntPtr]::Zero) } finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($dirPtr) }; [Win32.Shell]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero); $sh = New-Object -ComObject Shell.Application; foreach ($w in $sh.Windows()) { try { if ($w.Document.Folder.Self.Path -eq $env:REPO_DIR.TrimEnd('\')) { $w.Refresh() } } catch {} }" >nul 2>&1
if exist "%SystemRoot%\System32\ie4uinit.exe" "%SystemRoot%\System32\ie4uinit.exe" -show >nul 2>&1

echo.
echo =======================================================
echo Build complete!
echo Portable binaries ready:
echo  - dist\PresenterSync.exe
echo  - dist\PresenterSync_Remote.exe
echo =======================================================
if /i not "%~1"=="--nopause" pause

