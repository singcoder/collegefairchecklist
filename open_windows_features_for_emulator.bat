@echo off
REM Opens Windows Features so you can enable Virtual Machine Platform
REM and Windows Hypervisor Platform (required for x86_64 emulator).
REM Run this, check both options, reboot, then run create_avd_and_run.bat again.
start optionalfeatures
