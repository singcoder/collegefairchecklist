@echo off
REM Run emulator WITHOUT hardware acceleration (arm64 image - slower but works everywhere).
REM Use this if x86_64 fails with "hypervisor driver is not installed".
set ANDROID_HOME=C:\Users\garye\androidStudio
set ANDROID_SDK_ROOT=C:\Users\garye\androidStudio
set ANDROID_AVD_HOME=%USERPROFILE%\.android\avd

if not exist "%ANDROID_AVD_HOME%" mkdir "%ANDROID_AVD_HOME%"

REM Install arm64 system image if missing (no hypervisor needed)
if not exist "%ANDROID_HOME%\system-images\android-34\google_apis\arm64-v8a" (
    echo Installing arm64 system image (one-time, may take a few minutes)...
    call "%ANDROID_HOME%\cmdline-tools\bin\sdkmanager.bat" --sdk_root=%ANDROID_HOME% "system-images;android-34;google_apis;arm64-v8a"
)

echo.
echo Creating AVD Pixel_6_API34_arm64...
echo no | call "%ANDROID_HOME%\cmdline-tools\bin\avdmanager.bat" create avd -n "Pixel_6_API34_arm64" -k "system-images;android-34;google_apis;arm64-v8a" -d "pixel_5" --force

echo.
echo Starting emulator (arm64 - no acceleration required)...
"%ANDROID_HOME%\emulator\emulator.exe" -avd "Pixel_6_API34_arm64" -no-snapshot-load
