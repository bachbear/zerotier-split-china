@echo off
echo ============================================
echo ZeroTier Route Configuration - Cleanup
echo ============================================
echo.
echo This will remove all routes pointing to local gateway
echo and restore all traffic through ZeroTier.
echo.
echo Running...
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0cleanup-routes-simple.ps1"

echo.
echo Press any key to exit...
pause >nul
