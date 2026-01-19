# ZeroTier Stale Route Cleanup Wrapper Script
# Purpose: Auto-detect stale gateways and call fast cleanup script

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Administrator privileges required" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please right-click and select 'Run as Administrator'" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Check if fast cleanup script exists
$FastScriptPath = Join-Path $ScriptDir "cleanup-stale-routes-fast.ps1"
if (-not (Test-Path $FastScriptPath)) {
    Write-Host "[ERROR] cleanup-stale-routes-fast.ps1 not found" -ForegroundColor Red
    Write-Host "Please ensure it is in the same directory" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "ZeroTier Stale Route Cleanup Tool" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Detecting stale gateways..." -ForegroundColor Cyan
Write-Host ""

# Detect stale gateways
$activeGateways = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Where-Object { $_.NextHop -ne '0.0.0.0' } |
    Select-Object -ExpandProperty NextHop -Unique |
    ForEach-Object { $_.ToString() }

$allGateways = Get-NetRoute -ErrorAction SilentlyContinue |
    Where-Object { $_.NextHop -ne '0.0.0.0' } |
    Select-Object -ExpandProperty NextHop -Unique |
    ForEach-Object { $_.ToString() }

$staleGateways = $allGateways |
    Where-Object { $_ -notin $activeGateways -and $_ -notlike '25.255.*' -and $_ -ne '127.0.0.1' -and $_ -notlike '*:*' }

if ($staleGateways) {
    Write-Host "Detected stale gateways:" -ForegroundColor Yellow
    $staleGateways | ForEach-Object { Write-Host "  - $_" -ForegroundColor Cyan }
    Write-Host ""

    # Convert to array to handle single string case
    $gwList = @($staleGateways)
    $gw = $gwList[0]
    $count = (Get-NetRoute -NextHop $gw -ErrorAction SilentlyContinue |
        Where-Object { $_.DestinationPrefix -ne '0.0.0.0/0' }).Count

    Write-Host "Routes associated with this gateway: $count" -ForegroundColor Cyan
    Write-Host ""

    $confirm = Read-Host "Delete all routes pointing to this gateway? (Y/N)"
    if ($confirm -eq 'Y' -or $confirm -eq 'y') {
        Write-Host ""
        Write-Host "Starting fast cleanup..." -ForegroundColor Yellow
        Write-Host ""
        $arguments = "-ExecutionPolicy Bypass -NoProfile -File `"{0}`" `"{1}`" -Force" -f $FastScriptPath, $gw
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = $arguments
        $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
    } else {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] No obvious stale gateways detected" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Current active default route gateways:" -ForegroundColor Cyan
    $activeGateways | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
    Write-Host "All gateways in routing table:" -ForegroundColor Cyan
    $allGateways | Where-Object { $_ -notlike '*:*' } | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""

    $userGw = Read-Host "Enter gateway to cleanup (e.g. 192.168.1.1, press Enter to exit)"
    if ($userGw) {
        Write-Host ""
        Write-Host "Starting fast cleanup..." -ForegroundColor Yellow
        Write-Host ""
        $arguments = "-ExecutionPolicy Bypass -NoProfile -File `"{0}`" `"{1}`" -Force" -f $FastScriptPath, $userGw
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = $arguments
        $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
    } else {
        Write-Host "No gateway specified, exiting." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Read-Host "Press Enter to exit"
