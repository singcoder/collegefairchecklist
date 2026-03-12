# Create Android AVD and run emulator - run from "Source code" folder
# Requires: system image already installed (system-images;android-34;google_apis;x86_64)

$env:ANDROID_HOME = "C:\Users\garye\androidStudio"
$sdkRoot = $env:ANDROID_HOME
$avdHome = "$env:USERPROFILE\.android\avd"
$env:ANDROID_AVD_HOME = $avdHome

New-Item -ItemType Directory -Force -Path $avdHome | Out-Null

# 1) Install system image if missing
$sysImgPath = "$sdkRoot\system-images\android-34\google_apis\x86_64"
if (-not (Test-Path $sysImgPath)) {
    Write-Host "Installing system image..."
    & "$sdkRoot\cmdline-tools\bin\sdkmanager.bat" --sdk_root=$sdkRoot "system-images;android-34;google_apis;x86_64"
}

# 2) List valid device IDs (optional - use "pixel_5" or "Nexus 5" if pixel_6 fails)
Write-Host "`nAvailable devices (first column is ID for -d):"
& "$sdkRoot\cmdline-tools\bin\avdmanager.bat" list device

# 3) Create AVD (use -d 0 for default device to avoid invalid ID)
Write-Host "`nCreating AVD Pixel_6_API34..."
& "$sdkRoot\cmdline-tools\bin\avdmanager.bat" create avd -n "Pixel_6_API34" -k "system-images;android-34;google_apis;x86_64" -d "pixel_5" --force

# 4) List AVDs to confirm
Write-Host "`nAVDs:"
& "$sdkRoot\emulator\emulator.exe" -list-avds

# 5) Start emulator
Write-Host "`nStarting emulator..."
& "$sdkRoot\emulator\emulator.exe" -avd "Pixel_6_API34" -no-snapshot-load
