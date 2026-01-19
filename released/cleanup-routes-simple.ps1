# Simple ZeroTier route cleanup script
# Removes all routes added by fix-routes-simple.ps1
# Requires Administrator privileges

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please run as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "ZeroTier Route Cleanup Script" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Detect ZeroTier gateway and local gateway
Write-Host "Detecting network configuration..." -ForegroundColor Cyan

# Detect ZeroTier route split mode (/1 routes)
$zeroTierSplitRoutes = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
    ($_.DestinationPrefix -eq "0.0.0.0/1" -or $_.DestinationPrefix -eq "128.0.0.0/1") -and
    $_.RouteMetric -gt 1000
}

if ($zeroTierSplitRoutes) {
    $ztGateway = $zeroTierSplitRoutes[0].NextHop
    Write-Host "Detected ZeroTier Default Route Override mode" -ForegroundColor Yellow
    Write-Host "ZeroTier Gateway: $ztGateway" -ForegroundColor Cyan
} else {
    $ztRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object {
        $_.NextHop -like "25.255.*" -or $_.RouteMetric -gt 1000
    }
    $ztGateway = if ($ztRoutes) { $ztRoutes[0].NextHop } else { $null }
    if ($ztGateway) {
        Write-Host "Detected ZeroTier traditional routing mode" -ForegroundColor Yellow
        Write-Host "ZeroTier Gateway: $ztGateway" -ForegroundColor Cyan
    }
}

# Get local gateway (exclude ZeroTier gateway)
$localRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne $ztGateway }
$localGateway = $localRoutes[0].NextHop
$ifIndex = $localRoutes[0].InterfaceIndex

Write-Host "Local Gateway: $localGateway" -ForegroundColor Green
Write-Host "Interface Index: $ifIndex" -ForegroundColor Green
Write-Host ""

# Check for -Force parameter
$force = $args -contains "-Force"

# Confirm (skip if -Force is specified)
if (-not $force) {
    Write-Host "This will remove routes pointing to local gateway:" -ForegroundColor Yellow
    Write-Host "  - Private IP routes (10.0.0.0/8, 172.16.0.0/12, etc.)" -ForegroundColor Yellow
    Write-Host "  - China IP routes (from china-ip.txt)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This will restore all routing to go through ZeroTier." -ForegroundColor Yellow
    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "Starting cleanup..." -ForegroundColor Yellow
Write-Host ""

# Private routes (same format as fix-routes-simple.ps1)
$privateRoutes = @(
    "10.0.0.0 mask 255.0.0.0",
    "172.16.0.0 mask 255.240.0.0",
    "192.168.0.0 mask 255.255.0.0",
    "169.254.0.0 mask 255.255.0.0",
    "127.0.0.0 mask 255.0.0.0",
    "224.0.0.0 mask 240.0.0.0"
)

Write-Host "Removing private IP routes..." -ForegroundColor Yellow
foreach ($route in $privateRoutes) {
    $null = & route delete $route $localGateway 2>&1
}
Write-Host "Private routes removed." -ForegroundColor Green
Write-Host ""

# China IP ranges - use route.exe directly for speed
if (Test-Path "china-ip.txt") {
    $chinaRoutes = Get-Content "china-ip.txt"
    Write-Host "Processing China IP routes..." -ForegroundColor Yellow
    Write-Host "Total routes: $($chinaRoutes.Count)" -ForegroundColor Cyan
    Write-Host ""

    $count = 0
    $skipped = 0

    foreach ($cidr in $chinaRoutes) {
        $result = & route delete $cidr $localGateway 2>&1
        if ($LASTEXITCODE -eq 0) {
            $count++
        } else {
            $skipped++
        }

        # Progress indicator every 100 routes
        if (($count + $skipped) % 100 -eq 0) {
            Write-Host "Processed: $($count + $skipped)/$($chinaRoutes.Count) (Removed: $count)" -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "Routes removed: $count" -ForegroundColor Green
    Write-Host "Routes skipped (not found): $skipped" -ForegroundColor Yellow
} else {
    Write-Host "Warning: china-ip.txt not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Route cleanup completed!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Show remaining default routes
Write-Host "Current default routes:" -ForegroundColor Cyan
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object InterfaceAlias, NextHop, RouteMetric | Format-Table -AutoSize

# Show /1 routes if they exist
if ($zeroTierSplitRoutes) {
    Write-Host ""
    Write-Host "ZeroTier /1 split routes (still active):" -ForegroundColor Cyan
    Get-NetRoute | Where-Object { $_.DestinationPrefix -match "/1$" } | Select-Object DestinationPrefix, NextHop, RouteMetric | Format-Table -AutoSize
    Write-Host ""
    Write-Host "Note: ZeroTier Default Route Override is still enabled." -ForegroundColor Yellow
    Write-Host "All traffic will now go through ZeroTier." -ForegroundColor Yellow
}
