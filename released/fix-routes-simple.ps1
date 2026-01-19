# Simple and fast ZeroTier route fix
# Requires Administrator privileges

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please run as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "Detecting network configuration..." -ForegroundColor Cyan

# Detect ZeroTier route split mode (/1 routes) - Default Route Override enabled
$zeroTierSplitRoutes = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
    ($_.DestinationPrefix -eq "0.0.0.0/1" -or $_.DestinationPrefix -eq "128.0.0.0/1") -and
    $_.RouteMetric -gt 1000
}

if ($zeroTierSplitRoutes) {
    # ZeroTier Default Route Override is enabled
    $ztGateway = $zeroTierSplitRoutes[0].NextHop
    $ztIfIndex = $zeroTierSplitRoutes[0].InterfaceIndex
    Write-Host "Detected ZeroTier Default Route Override mode" -ForegroundColor Yellow
    Write-Host "ZeroTier Gateway: $ztGateway (Interface: $ztIfIndex)" -ForegroundColor Cyan
} else {
    # Traditional mode: find ZeroTier default route
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
if ($ztGateway) {
    Write-Host "ZeroTier Gateway: $ztGateway" -ForegroundColor Cyan
}
Write-Host ""

# Private routes
$privateRoutes = @(
    "10.0.0.0 mask 255.0.0.0",
    "172.16.0.0 mask 255.240.0.0",
    "192.168.0.0 mask 255.255.0.0",
    "169.254.0.0 mask 255.255.0.0",
    "127.0.0.0 mask 255.0.0.0",
    "224.0.0.0 mask 240.0.0.0"
)

Write-Host "Adding private IP routes..." -ForegroundColor Yellow
foreach ($route in $privateRoutes) {
    $null = & route add $route $localGateway METRIC 1 IF $ifIndex 2>&1
}
Write-Host "Private routes added." -ForegroundColor Green
Write-Host ""

# China IP ranges
if (Test-Path "china-ip.txt") {
    $chinaRoutes = Get-Content "china-ip.txt"
    Write-Host "Processing China IP ranges..." -ForegroundColor Yellow
    Write-Host "Total routes: $($chinaRoutes.Count)" -ForegroundColor Cyan
    Write-Host ""

    $count = 0
    $skipped = 0

    foreach ($cidr in $chinaRoutes) {
        $result = & route add $cidr $localGateway METRIC 1 IF $ifIndex 2>&1
        if ($LASTEXITCODE -eq 0) {
            $count++
        } elseif ($result -match "exists" -or $result -match "The route") {
            $skipped++
        }

        # Progress indicator every 100 routes
        if (($count + $skipped) % 100 -eq 0) {
            Write-Host "Processed: $($count + $skipped)/$($chinaRoutes.Count)" -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "Routes added: $count" -ForegroundColor Green
    Write-Host "Routes skipped (already exist): $skipped" -ForegroundColor Yellow
} else {
    Write-Host "Warning: china-ip.txt not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Route configuration completed!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "How it works:" -ForegroundColor Cyan
Write-Host "- China IPs and private IPs route to local gateway: $localGateway" -ForegroundColor Green
if ($zeroTierSplitRoutes) {
    Write-Host "- ZeroTier Default Route Override is enabled (/1 routes)" -ForegroundColor Yellow
    Write-Host "- China IP routes use longest prefix match to override ZeroTier /1 routes" -ForegroundColor Yellow
} elseif ($ztGateway) {
    Write-Host "- Other traffic goes through ZeroTier: $ztGateway" -ForegroundColor Yellow
}
Write-Host ""

# Show default routes
Write-Host "Current default routes:" -ForegroundColor Cyan
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object InterfaceAlias, NextHop, RouteMetric | Format-Table -AutoSize

# Show /1 routes if they exist
if ($zeroTierSplitRoutes) {
    Write-Host ""
    Write-Host "ZeroTier /1 split routes:" -ForegroundColor Cyan
    Get-NetRoute | Where-Object { $_.DestinationPrefix -match "/1$" } | Select-Object DestinationPrefix, NextHop, RouteMetric | Format-Table -AutoSize
}
