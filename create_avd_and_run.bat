@echo off
REM Create Android AVD and run emulator - run from "Source code" folder
set ANDROID_HOME=C:\Users\garye\androidStudio
set ANDROID_SDK_ROOT=C:\Users\garye\androidStudio
set ANDROID_AVD_HOME=%USERPROFILE%\.android\avd

if not exist "%ANDROID_AVD_HOME%" mkdir "%ANDROID_AVD_HOME%"

REM Install system image if missing
if not exist "%ANDROID_HOME%\system-images\android-34\google_apis\x86_64" (
    echo Installing system image...
    call "%ANDROID_HOME%\cmdline-tools\bin\sdkmanager.bat" --sdk_root=%ANDROID_HOME% "system-images;android-34;google_apis;x86_64"
)

echo.
echo Creating AVD Pixel_6_API34...
echo no | call "%ANDROID_HOME%\cmdline-tools\bin\avdmanager.bat" create avd -n "Pixel_6_API34" -k "system-images;android-34;google_apis;x86_64" -d "pixel_5" --force

echo.
echo AVDs:
call "%ANDROID_HOME%\emulator\emulator.exe" -list-avds

echo.
echo Starting emulator...
"%ANDROID_HOME%\emulator\emulator.exe" -avd "Pixel_6_API34" -no-snapshot-load
