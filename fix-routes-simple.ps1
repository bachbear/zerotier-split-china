# Simple and fast ZeroTier route fix
# Requires Administrator privileges

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please run as Administrator!" -ForegroundColor Red
    exit 1
}

# History file to track last configured gateway
$HistoryFile = Join-Path $PSScriptRoot ".zt-route-history.txt"

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

# Read history file to get last configured gateway
$lastGateway = $null
$lastSetTime = $null
if (Test-Path $HistoryFile) {
    try {
        $historyContent = Get-Content $HistoryFile -Raw
        if ($historyContent -match 'Gateway:\s*(\S+)') {
            $lastGateway = $matches[1]
        }
        if ($historyContent -match 'Time:\s*(.+)') {
            $lastSetTime = $matches[1]
        }
    } catch {
        Write-Host "Warning: Failed to read history file, will continue with cleanup" -ForegroundColor Yellow
    }
}

# Function to convert CIDR to subnet mask
function Convert-CidrToMask {
    param([int]$prefixLength)

    $mask = switch ($prefixLength) {
        8 { "255.0.0.0" }
        9 { "255.128.0.0" }
        10 { "255.192.0.0" }
        11 { "255.224.0.0" }
        12 { "255.240.0.0" }
        13 { "255.248.0.0" }
        14 { "255.252.0.0" }
        15 { "255.254.0.0" }
        16 { "255.255.0.0" }
        17 { "255.255.128.0" }
        18 { "255.255.192.0" }
        19 { "255.255.224.0" }
        20 { "255.255.240.0" }
        21 { "255.255.248.0" }
        22 { "255.255.252.0" }
        23 { "255.255.254.0" }
        24 { "255.255.255.0" }
        25 { "255.255.255.128" }
        26 { "255.255.255.192" }
        27 { "255.255.255.224" }
        28 { "255.255.255.240" }
        29 { "255.255.255.248" }
        30 { "255.255.255.252" }
        31 { "255.255.255.254" }
        32 { "255.255.255.255" }
        default { "0.0.0.0" }
    }
    return $mask
}

# Function to generate route delete batch for old gateway
function Remove-OldRoutes {
    param([string]$oldGateway)

    Write-Host "Cleaning up old routes pointing to: $oldGateway" -ForegroundColor Yellow
    Write-Host ""

    # Get all routes pointing to old gateway (excluding default route)
    $oldRoutes = Get-NetRoute -NextHop $oldGateway -ErrorAction SilentlyContinue |
        Where-Object { $_.DestinationPrefix -ne "0.0.0.0/0" }

    if ($oldRoutes) {
        $count = $oldRoutes.Count
        Write-Host "Found $count old routes to remove..." -ForegroundColor Cyan

        # Generate temporary batch file for fast deletion
        $tempBatch = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.bat'
        $batchCommands = @()

        foreach ($route in $oldRoutes) {
            # Parse CIDR notation
            $prefixParts = $route.DestinationPrefix -split '/'
            $network = $prefixParts[0]
            $prefixLength = [int]$prefixParts[1]

            # Convert to subnet mask
            $mask = Convert-CidrToMask $prefixLength

            # Generate route delete command
            $batchCommands += "route delete $network mask $mask $oldGateway"
        }

        # Write to batch file and execute
        $batchCommands | Out-File -FilePath $tempBatch -Encoding ASCII -ErrorAction Stop

        Write-Host "Removing old routes..." -ForegroundColor Yellow
        $startTime = Get-Date

        & cmd /c $tempBatch 2>&1 | Out-Null

        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds

        # Clean up temp file
        Remove-Item $tempBatch -Force -ErrorAction SilentlyContinue

        Write-Host "Removed $count routes in $([math]::Round($duration, 2)) seconds" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "No old routes found to clean up" -ForegroundColor Gray
        Write-Host ""
    }
}

# Check if gateway changed and clean up old routes
if ($lastGateway -and $lastGateway -ne $localGateway) {
    Write-Host "Gateway changed from '$lastGateway' to '$localGateway'" -ForegroundColor Yellow
    Write-Host "Last configured: $lastSetTime" -ForegroundColor Gray
    Write-Host ""
    Remove-OldRoutes $lastGateway
} elseif ($lastGateway -eq $localGateway) {
    Write-Host "Gateway unchanged: $localGateway" -ForegroundColor Gray
    Write-Host "Last configured: $lastSetTime" -ForegroundColor Gray
    Write-Host "Skipping cleanup, will add/update routes..." -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "No previous configuration found" -ForegroundColor Gray
    Write-Host "This appears to be the first run" -ForegroundColor Gray
    Write-Host ""
}

# Private routes in CIDR notation
$privateRoutes = @(
    @{Cidr = "10.0.0.0/8"; Mask = "255.0.0.0"},
    @{Cidr = "172.16.0.0/12"; Mask = "255.240.0.0"},
    @{Cidr = "192.168.0.0/16"; Mask = "255.255.0.0"},
    @{Cidr = "169.254.0.0/16"; Mask = "255.255.0.0"},
    @{Cidr = "127.0.0.0/8"; Mask = "255.0.0.0"},
    @{Cidr = "224.0.0.0/4"; Mask = "240.0.0.0.0"}
)

Write-Host "Adding private IP routes..." -ForegroundColor Yellow
foreach ($route in $privateRoutes) {
    $null = & route add $route.Cidr $localGateway METRIC 1 IF $ifIndex 2>&1
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
            Write-Host "Processed: $($count + $skipped)/$($chinaRoutes.Count) (Added: $count, Skipped: $skipped)" -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "Routes added: $count" -ForegroundColor Green
    Write-Host "Routes skipped (already exist): $skipped" -ForegroundColor Yellow

    # Update history file
    $historyContent = @"
ZeroTier Route Configuration History
========================================
Gateway: $localGateway
Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Routes: $($privateRoutes.Count + $count)
"@

    try {
        $historyContent | Out-File -FilePath $HistoryFile -Encoding UTF8 -ErrorAction Stop
        Write-Host "History file updated: $HistoryFile" -ForegroundColor Gray
    } catch {
        Write-Host "Warning: Failed to update history file" -ForegroundColor Yellow
    }
} else {
    Write-Host "Warning: china-ip.txt not found" -ForegroundColor Yellow

    # Update history file for private routes only
    $historyContent = @"
ZeroTier Route Configuration History
========================================
Gateway: $localGateway
Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Routes: $($privateRoutes.Count)
"@

    try {
        $historyContent | Out-File -FilePath $HistoryFile -Encoding UTF8 -ErrorAction Stop
        Write-Host "History file updated: $HistoryFile" -ForegroundColor Gray
    } catch {
        Write-Host "Warning: Failed to update history file" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Route configuration completed!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "How it works:" -ForegroundColor Cyan
Write-Host "- China IPs and private IPs route to local gateway: $localGateway" -ForegroundColor Green
Write-Host "- Routes are PERSISTENT (survive reboot)" -ForegroundColor Yellow
Write-Host "- Script automatically cleans old routes when gateway changes" -ForegroundColor Yellow
Write-Host "- History file tracks configuration for smart cleanup" -ForegroundColor Gray
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
