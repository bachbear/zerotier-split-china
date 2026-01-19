@echo off
echo ============================================
echo ZeroTier Route Configuration - Add Routes
echo ============================================
echo.
echo This will add routes for:
echo   - China IP addresses (via local gateway)
echo   - Private IP addresses (via local gateway)
echo.
echo Running...
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0fix-routes-simple.ps1"

echo.
echo Press any key to exit...
pause >nul
