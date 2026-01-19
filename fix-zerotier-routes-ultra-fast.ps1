# FixZeroTierRoutes.ps1 - Ultra fast version with route.exe batch processing

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "Fixing ZeroTier routing configuration..." -ForegroundColor Green

# Get gateways
$zeroTierGateway = $null
$zeroTierInterfaceIndex = $null

# Detect ZeroTier route split mode
$zeroTierSplitRoutes = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
    ($_.DestinationPrefix -eq "0.0.0.0/1" -or $_.DestinationPrefix -eq "128.0.0.0/1") -and $_.RouteMetric -gt 1000
}

if ($zeroTierSplitRoutes) {
    $zeroTierGateway = $zeroTierSplitRoutes[0].NextHop
    $zeroTierInterfaceIndex = $zeroTierSplitRoutes[0].InterfaceIndex
    Write-Host "Detected ZeroTier default route split mode" -ForegroundColor Cyan
    Write-Host "ZeroTier Gateway: $zeroTierGateway (Interface: $zeroTierInterfaceIndex)" -ForegroundColor Cyan
} else {
    $ztDefaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Where-Object {
        $_.RouteMetric -gt 1000 -or $_.NextHop -like "25.255.255.254"
    } | Sort-Object RouteMetric -Descending | Select-Object -First 1

    if ($ztDefaultRoute) {
        $zeroTierGateway = $ztDefaultRoute.NextHop
        $zeroTierInterfaceIndex = $ztDefaultRoute.InterfaceIndex
        Write-Host "Detected ZeroTier traditional routing mode" -ForegroundColor Cyan
        Write-Host "ZeroTier Gateway: $zeroTierGateway (Interface: $zeroTierInterfaceIndex)" -ForegroundColor Cyan
    } else {
        $ztAdapters = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*ZeroTier*" }
        if ($ztAdapters) {
            $zeroTierInterfaceIndex = $ztAdapters[0].ifIndex
            $ztRoute = Get-NetRoute -InterfaceIndex $zeroTierInterfaceIndex -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } | Select-Object -First 1
            if ($ztRoute) {
                $zeroTierGateway = $ztRoute.NextHop
                Write-Host "ZeroTier gateway identified: $zeroTierGateway" -ForegroundColor Cyan
            }
        }
    }
}

# Get local gateway
$localRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne $zeroTierGateway }

if ($localRoutes) {
    $localGateway = $localRoutes[0].NextHop
    $localInterfaceIndex = $localRoutes[0].InterfaceIndex
    Write-Host "Local gateway: $localGateway (Interface: $localInterfaceIndex)" -ForegroundColor Green
} else {
    Write-Host "Error: Unable to find local gateway!" -ForegroundColor Red
    pause
    exit 1
}

# Private IP ranges
$privateRanges = @(
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "169.254.0.0/16",
    "127.0.0.0/8",
    "224.0.0.0/4",
    "255.255.255.255/32"
)

# Read China IP ranges
$chinaRanges = @()
$chinaFilePath = "china-ip.txt"

if (Test-Path $chinaFilePath) {
    $chinaRanges = Get-Content $chinaFilePath | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+/\d+$' }
    Write-Host "Read $($chinaRanges.Count) China IP ranges from $chinaFilePath" -ForegroundColor Green
} else {
    Write-Host "Warning: $chinaFilePath not found, will only process private address ranges" -ForegroundColor Yellow
}

$allRanges = $privateRanges + $chinaRanges
Write-Host "Total address ranges to process: $($allRanges.Count)" -ForegroundColor Green

# Create a batch file for ultra-fast route processing
$batchFile = "$env:TEMP\add_routes_temp.bat"
@"
@echo off
setlocal enabledelayedexpansion
set ADDED=0
set SKIPPED=0
set FAILED=0

"@ | Out-File -FilePath $batchFile -Encoding ASCII

foreach ($range in $allRanges) {
    $cidr = $range
    "route add $cidr $localGateway METRIC 1 IF $localInterfaceIndex >nul 2>&1`r`nif !errorlevel! equ 0 (set /a ADDED+=1) else (route add $cidr $localGateway METRIC 1 IF $localInterfaceIndex >nul 2>&1`r`nif !errorlevel! equ 0 (set /a ADDED+=1) else (set /a SKIPPED+=1))`r`n" | Out-File -FilePath $batchFile -Encoding ASCII -Append
}

@"
echo Routes added: !ADDED!
echo Routes skipped: !SKIPPED!
endlocal
"@ | Out-File -FilePath $batchFile -Encoding ASCII -Append

Write-Host "Starting route configuration (using batch file for maximum speed)..." -ForegroundColor Yellow

# Execute batch file and capture output
$output = cmd /c $batchFile 2>&1
Write-Host $output

# Clean up
Remove-Item $batchFile -ErrorAction SilentlyContinue

Write-Host "`nRoute configuration completed!" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan
Write-Host "Local Gateway: $localGateway (Interface: $localInterfaceIndex)" -ForegroundColor White
if ($zeroTierGateway) {
    Write-Host "ZeroTier Gateway: $zeroTierGateway (Interface: $zeroTierInterfaceIndex)" -ForegroundColor White
}
Write-Host "Total ranges processed: $($allRanges.Count)" -ForegroundColor White
Write-Host "------------------------" -ForegroundColor Cyan
Write-Host "China IPs and private IPs will now use local gateway, other traffic goes through ZeroTier." -ForegroundColor Green

Write-Host "`nCurrent routing table summary:" -ForegroundColor Cyan
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object InterfaceAlias, DestinationPrefix, NextHop, RouteMetric | Format-Table -AutoSize

pause
