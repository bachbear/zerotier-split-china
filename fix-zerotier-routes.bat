@echo off
REM Ultra-fast ZeroTier route fix using direct batch processing
REM Requires Administrator privileges

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Please run as Administrator!
    pause
    exit /b 1
)

echo Detecting network configuration...
echo.

REM Get gateway info using PowerShell
for /f "tokens=*" %%a in ('powershell -Command "$routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0'; $local = $routes ^| Where-Object { $_.NextHop -notlike '25.255.*' } ^| Select-Object -First 1; if ($local) { Write-Output $local.NextHop }"') do set LOCAL_GATEWAY=%%a
for /f "tokens=*" %%a in ('powershell -Command "$routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0'; $local = $routes ^| Where-Object { $_.NextHop -notlike '25.255.*' } ^| Select-Object -First 1; if ($local) { Write-Output $local.InterfaceIndex }"') do set IF_INDEX=%%a

if "%LOCAL_GATEWAY%"=="" (
    echo Error: Cannot detect local gateway!
    pause
    exit /b 1
)

echo Local Gateway: %LOCAL_GATEWAY%
echo Interface Index: %IF_INDEX%
echo.

REM Add private routes first
echo Adding private IP routes...
route add 10.0.0.0/8 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
route add 172.16.0.0/12 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
route add 192.168.0.0/16 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
route add 169.254.0.0/16 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
route add 127.0.0.0/8 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
route add 224.0.0.0/4 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
echo Private routes added.
echo.

REM Process China IP ranges if file exists
if exist "china-ip.txt" (
    echo Processing China IP ranges from china-ip.txt...
    echo This will take 1-2 minutes for ~8800 routes...
    echo.

    REM Create temporary batch file with all route commands
    set TEMP_BAT=%TEMP%\china_routes_temp.bat
    echo @echo off > "%TEMP_BAT%"
    echo setlocal enabledelayedexpansion >> "%TEMP_BAT%"
    echo set COUNT=0 >> "%TEMP_BAT%"

    REM Read china-ip.txt and generate route commands
    for /f "usebackq tokens=*" %%r in ("china-ip.txt") do (
        echo route add %%r %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX%^>nul 2^>^&1 >> "%TEMP_BAT%"
        echo if %%errorlevel%% equ 0 set /a COUNT+=1 >> "%TEMP_BAT%"
    )

    echo echo Routes added: !COUNT! >> "%TEMP_BAT%"
    echo endlocal >> "%TEMP_BAT%"

    REM Execute the batch file
    call "%TEMP_BAT%"
    del "%TEMP_BAT%" 2>nul

    echo.
) else (
    echo Warning: china-ip.txt not found, only private routes configured.
)

echo.
echo ============================================
echo Route configuration completed!
echo Local Gateway: %LOCAL_GATEWAY%
echo Interface: %IF_INDEX%
echo ============================================
echo.
echo Verifying routes...
route print -4 | findstr "0.0.0.0/0"

echo.
pause
