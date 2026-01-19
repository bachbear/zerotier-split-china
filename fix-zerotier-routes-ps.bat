@echo off
REM Fast ZeroTier route fix using PowerShell with route.exe
REM Requires Administrator privileges

setlocal

echo Detecting network configuration...

REM Detect ZeroTier gateway
for /f "tokens=*" %%a in ('powershell -Command "$zt = Get-NetRoute -DestinationPrefix '0.0.0.0/0' ^| Where-Object { $_.NextHop -like '25.255.*' -or $_.RouteMetric -gt 1000 } ^| Select-Object -First 1 -ExpandProperty NextHop; Write-Output $zt"') do set ZT_GATEWAY=%%a

REM Get local gateway (exclude ZeroTier)
for /f "tokens=*" %%a in ('powershell -Command "$routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' ^| Where-Object { $_.NextHop -ne '%ZT_GATEWAY%' } ^| Select-Object -First 1; Write-Output \"$($routes.NextHop) $($routes.InterfaceIndex)\""') do set LOCAL_INFO=%%a

for /f "tokens=1,2" %%a in ("%LOCAL_INFO%") do (
    set LOCAL_GATEWAY=%%a
    set IF_INDEX=%%b
)

if "%LOCAL_GATEWAY%"=="" (
    echo Error: Cannot detect local gateway!
    pause
    exit /b 1
)

echo Local Gateway: %LOCAL_GATEWAY%
echo Interface Index: %IF_INDEX%
if not "%ZT_GATEWAY%"=="" echo ZeroTier Gateway: %ZT_GATEWAY%
echo.

echo Adding private IP routes...
route add 10.0.0.0 mask 255.0.0.0 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
route add 172.16.0.0 mask 255.240.0.0 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
route add 192.168.0.0 mask 255.255.0.0 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
route add 169.254.0.0 mask 255.255.0.0 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
route add 127.0.0.0 mask 255.0.0.0 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
route add 224.0.0.0 mask 240.0.0.0 %LOCAL_GATEWAY% METRIC 1 IF %IF_INDEX% >nul 2>&1
echo Private routes added.
echo.

if exist "china-ip.txt" (
    echo Processing China IP ranges...
    echo Using route.exe for fast batch processing...
    echo.

    REM Count lines first
    for /f %%a in ('type "china-ip.txt" ^| find /c /v ""') do set TOTAL=%%a
    echo Total routes to process: %TOTAL%
    echo.

    REM Process using PowerShell for better performance
    powershell -NoProfile -Command "& { $gw = '%LOCAL_GATEWAY%'; $ifIdx = %IF_INDEX%; $count = 0; foreach ($r in Get-Content 'china-ip.txt') { $null = route add $r $gw METRIC 1 IF $ifIdx 2^>&1; if ($? -or $LASTEXITCODE -eq 0) { $count++ } elseif ($LASTEXITCODE -eq 1) { # Try once more if route exists conflict route delete $r 2^>&1 ^| Out-Null; $null = route add $r $gw METRIC 1 IF $ifIdx 2^>&1; if ($?) { $count++ } } }; Write-Host \"Routes processed: $count\" -ForegroundColor Green }"

    echo.
) else (
    echo Warning: china-ip.txt not found.
)

echo.
echo ============================================
echo Route configuration completed!
echo Local Gateway: %LOCAL_GATEWAY%
echo Interface: %IF_INDEX%
echo ============================================
echo.

pause
endlocal
