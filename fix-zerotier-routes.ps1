# FixZeroTierRoutes.ps1 - Fix ZeroTier routes to keep China and private IPs on local gateway

# Check for administrator privileges
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

# 1. Get local gateway and ZeroTier gateway
$localGateway = $null
$zeroTierGateway = $null
$localInterfaceIndex = $null
$zeroTierInterfaceIndex = $null

# Detect if ZeroTier has enabled default route splitting (/1 routes)
# ZeroTier uses 0.0.0.0/1 and 128.0.0.0/1 to hijack all traffic
$zeroTierSplitRoutes = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
    ($_.DestinationPrefix -eq "0.0.0.0/1" -or $_.DestinationPrefix -eq "128.0.0.0/1") -and
    $_.RouteMetric -gt 1000
}

if ($zeroTierSplitRoutes) {
    $zeroTierGateway = $zeroTierSplitRoutes[0].NextHop
    $zeroTierInterfaceIndex = $zeroTierSplitRoutes[0].InterfaceIndex
    Write-Host "Detected ZeroTier default route split mode" -ForegroundColor Cyan
    Write-Host "ZeroTier Gateway: $zeroTierGateway (Interface Index: $zeroTierInterfaceIndex)" -ForegroundColor Cyan
} else {
    # Traditional mode: Find ZeroTier default route
    $ztDefaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Where-Object {
        $_.RouteMetric -gt 1000 -or $_.NextHop -like "25.255.255.254"
    } | Sort-Object RouteMetric -Descending | Select-Object -First 1

    if ($ztDefaultRoute) {
        $zeroTierGateway = $ztDefaultRoute.NextHop
        $zeroTierInterfaceIndex = $ztDefaultRoute.InterfaceIndex
        Write-Host "Detected ZeroTier traditional routing mode" -ForegroundColor Cyan
        Write-Host "ZeroTier Gateway: $zeroTierGateway (Interface Index: $zeroTierInterfaceIndex)" -ForegroundColor Cyan
    } else {
        Write-Host "Warning: ZeroTier gateway not detected, trying to identify by interface name..." -ForegroundColor Yellow
        $ztAdapters = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*ZeroTier*" }
        if ($ztAdapters) {
            $zeroTierInterfaceIndex = $ztAdapters[0].ifIndex
            $ztRoute = Get-NetRoute -InterfaceIndex $zeroTierInterfaceIndex -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } | Select-Object -First 1
            if ($ztRoute) {
                $zeroTierGateway = $ztRoute.NextHop
                Write-Host "ZeroTier gateway identified via interface: $zeroTierGateway" -ForegroundColor Cyan
            }
        }
    }
}

# Get local default gateway (non-ZeroTier interface)
$localRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne $zeroTierGateway }

if ($localRoutes) {
    $localGateway = $localRoutes[0].NextHop
    $localInterfaceIndex = $localRoutes[0].InterfaceIndex
    Write-Host "Found local gateway: $localGateway (Interface Index: $localInterfaceIndex)" -ForegroundColor Green
} else {
    Write-Host "Warning: Local default gateway not found, trying alternative method..." -ForegroundColor Yellow

    $networkAdapters = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway }
    foreach ($adapter in $networkAdapters) {
        if ($adapter.IPv4DefaultGateway.NextHop -ne $zeroTierGateway) {
            $localGateway = $adapter.IPv4DefaultGateway.NextHop
            $localInterfaceIndex = $adapter.InterfaceIndex
            Write-Host "Found alternate local gateway: $localGateway (Interface Index: $localInterfaceIndex)" -ForegroundColor Green
            break
        }
    }
}

if (-not $localGateway) {
    Write-Host "Error: Unable to find local gateway!" -ForegroundColor Red
    pause
    exit 1
}

# 2. Define IP ranges that should go through local gateway
$privateRanges = @(
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "169.254.0.0/16",
    "127.0.0.0/8",
    "224.0.0.0/4",
    "255.255.255.255/32"
)

# 3. Read China IP ranges from file
$chinaRanges = @()
$chinaFilePath = "china-ip.txt"

if (Test-Path $chinaFilePath) {
    $chinaRanges = Get-Content $chinaFilePath | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+/\d+$' }
    Write-Host "Read $($chinaRanges.Count) China IP ranges from $chinaFilePath" -ForegroundColor Green
} else {
    Write-Host "Warning: $chinaFilePath not found, will only process private address ranges" -ForegroundColor Yellow
}

# 4. Merge all address ranges to process
$allRanges = $privateRanges + $chinaRanges

Write-Host "Total address ranges to process: $($allRanges.Count)" -ForegroundColor Green
Write-Host "Starting route configuration..." -ForegroundColor Yellow

# 5. Configure routes
$routesAdded = 0
$routesSkipped = 0
$routesDeleted = 0

$useSpecificRoutes = $zeroTierSplitRoutes -ne $null

if ($useSpecificRoutes) {
    Write-Host "Detected ZeroTier /1 route splitting, will add specific route rules to override" -ForegroundColor Yellow
}

foreach ($range in $allRanges) {
    $existingRoute = Get-NetRoute -DestinationPrefix $range -ErrorAction SilentlyContinue | Where-Object {
        $_.NextHop -eq $localGateway -and $_.InterfaceIndex -eq $localInterfaceIndex
    }

    if ($existingRoute) {
        Write-Host "Route already exists: $range -> $localGateway" -ForegroundColor Gray
        $routesSkipped++
        continue
    }

    $conflictingRoutes = Get-NetRoute -DestinationPrefix $range -ErrorAction SilentlyContinue | Where-Object {
        $_.NextHop -eq $zeroTierGateway
    }

    if ($conflictingRoutes) {
        foreach ($cr in $conflictingRoutes) {
            Remove-NetRoute -DestinationPrefix $range -NextHop $cr.NextHop -InterfaceIndex $cr.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "Removed conflicting route: $range -> $($cr.NextHop)" -ForegroundColor Yellow
            $routesDeleted++
        }
    }

    try {
        New-NetRoute -DestinationPrefix $range -NextHop $localGateway -InterfaceIndex $localInterfaceIndex -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
        Write-Host "Added route: $range -> $localGateway" -ForegroundColor Green
        $routesAdded++
    }
    catch {
        Write-Host "Failed to add route: $range - $_" -ForegroundColor Red
    }
}

# 6. Display summary
Write-Host "`nRoute configuration completed!" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan
Write-Host "Local Gateway: $localGateway (Interface Index: $localInterfaceIndex)" -ForegroundColor White
if ($zeroTierGateway) {
    Write-Host "ZeroTier Gateway: $zeroTierGateway (Interface Index: $zeroTierInterfaceIndex)" -ForegroundColor White
    Write-Host "ZeroTier Mode: $(if ($useSpecificRoutes) { 'Default Route Split (/1)' } else { 'Traditional Mode' })" -ForegroundColor White
}
Write-Host "Total ranges processed: $($allRanges.Count)" -ForegroundColor White
Write-Host "Routes added: $routesAdded" -ForegroundColor Green
Write-Host "Routes skipped: $routesSkipped" -ForegroundColor Yellow
if ($routesDeleted -gt 0) {
    Write-Host "Conflicting routes removed: $routesDeleted" -ForegroundColor Yellow
}
Write-Host "------------------------" -ForegroundColor Cyan
Write-Host "China IPs and private IPs will now use local gateway, other traffic goes through ZeroTier." -ForegroundColor Green

# 7. Display current routing table summary
Write-Host "`nCurrent routing table summary:" -ForegroundColor Cyan
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object InterfaceAlias, DestinationPrefix, NextHop, RouteMetric | Format-Table -AutoSize

pause
