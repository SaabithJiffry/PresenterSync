@echo off
setlocal enabledelayedexpansion

set "NO_PAUSE=0"
if /i "%~1"=="--nopause" set "NO_PAUSE=1"

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ANDROID_DIR=%SCRIPT_DIR%\android"

if not defined JAVA_HOME (
    if exist "C:\Program Files\Eclipse Adoptium\jdk-17.0.21.9-hotspot\bin\java.exe" (
        set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.21.9-hotspot"
    ) else (
        for /d %%D in ("C:\Program Files\Eclipse Adoptium\jdk-17*") do (
            if exist "%%~fD\bin\java.exe" set "JAVA_HOME=%%~fD"
        )
    )
)

if defined JAVA_HOME (
    set "PATH=%JAVA_HOME%\bin;%PATH%"
)

echo ===========================================================================
echo  PresenterSync Android Remote Build Script
echo ===========================================================================
echo JAVA_HOME=%JAVA_HOME%

pushd "%ANDROID_DIR%" || exit /b 1

echo.
echo [1/2] Running JVM Unit Tests + Release APK Build...
call gradlew.bat testDebugUnitTest assembleRelease --no-daemon --stacktrace -PrequireReleaseSigning=true
if %errorlevel% neq 0 (
    echo [ERROR] Android Gradle build/test failed with exit code %errorlevel%.
    popd
    goto :done
)

set "RELEASE_APK=%ANDROID_DIR%\app\build\outputs\apk\release\app-release.apk"
if not exist "%RELEASE_APK%" (
    echo [ERROR] Expected release APK not found: %RELEASE_APK%
    popd
    exit /b 1
)

echo.
echo [2/2] Copying signed release APK to dist\PresenterSync_Remote.apk...
if not exist "%SCRIPT_DIR%\dist" mkdir "%SCRIPT_DIR%\dist"
copy /y "%RELEASE_APK%" "%SCRIPT_DIR%\dist\PresenterSync_Remote.apk" >nul
if %errorlevel% neq 0 (
    echo [ERROR] Failed to copy dist\PresenterSync_Remote.apk.
    popd
    exit /b 1
)

for %%F in ("%SCRIPT_DIR%\dist\PresenterSync_Remote.apk") do (
    echo [OK] dist\PresenterSync_Remote.apk built ^(%%~zF bytes^)
)

popd
set "BUILD_EXIT=0"

:done
if not defined BUILD_EXIT set "BUILD_EXIT=%errorlevel%"
if "%NO_PAUSE%"=="0" pause
exit /b %BUILD_EXIT%
