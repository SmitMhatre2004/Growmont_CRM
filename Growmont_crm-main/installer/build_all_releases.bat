@echo off
rem Builds the Windows installer and the Android APK for the version in
rem flutterapp\pubspec.yaml. Runs build_release.ps1 first, then
rem build_android_release.ps1 only if the Windows build succeeded.
rem Outputs land in installer\Output\. Double-click or run from any folder.

setlocal
set "SCRIPT_DIR=%~dp0"

echo.
echo ===== [1/2] Windows release =====
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build_release.ps1"
if errorlevel 1 (
    echo.
    echo Windows release FAILED - Android build skipped.
    goto :fail
)

echo.
echo ===== [2/2] Android release =====
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build_android_release.ps1"
if errorlevel 1 (
    echo.
    echo Android release FAILED.
    goto :fail
)

echo.
echo ===== Both releases built. Files are in %SCRIPT_DIR%Output =====
echo Upload the .exe, .apk and both .sha256 files to the GitHub release,
echo and commit flutterapp\android\released_version_codes.txt.
pause
endlocal
exit /b 0

:fail
pause
endlocal
exit /b 1
