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
"%AHK2EXE%" /in "%~dp0PresenterSync.ahk" /out "%~dp0PresenterSync.exe" /icon "%~dp0%ICON%" /base "%BASE%"
if %errorlevel% neq 0 (
    echo [FAILED] Compilation of PresenterSync.exe failed with exit code %errorlevel%.
    pause
    exit /b %errorlevel%
)
echo [OK] PresenterSync.exe built successfully.

echo.
echo [2/2] Compiling PresenterSync_Remote.exe (Smart Board Companion)...
"%AHK2EXE%" /in "%~dp0PresenterSync_Remote.ahk" /out "%~dp0PresenterSync_Remote.exe" /icon "%~dp0%REMOTE_ICON%" /base "%BASE%"
if %errorlevel% neq 0 (
    echo [FAILED] Compilation of PresenterSync_Remote.exe failed with exit code %errorlevel%.
    pause
    exit /b %errorlevel%
)
echo [OK] PresenterSync_Remote.exe built successfully.

echo.
echo =======================================================
echo Build complete!
echo Portable binaries ready:
echo  - PresenterSync.exe
echo  - PresenterSync_Remote.exe
echo =======================================================
pause

