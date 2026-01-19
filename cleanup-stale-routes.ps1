# Cleanup script for routes pointing to invalid/old gateways
# Example: Removes routes pointing to 192.168.1.1 when that gateway no longer exists
# Requires Administrator privileges

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please run as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Stale Route Cleanup Tool" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Parse command line arguments
$targetGateway = $args | Where-Object { $_ -notmatch "^-" } | Select-Object -First 1
$force = $args -contains "-Force"
$autoDetect = $args -contains "-AutoDetect"

if ($autoDetect -and -not $targetGateway) {
    # Auto-detect potentially invalid gateways
    Write-Host "Detecting potentially invalid gateways..." -ForegroundColor Yellow

    # Get all gateways in routing table
    $allGateways = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -ne "0.0.0.0" } | Select-Object -ExpandProperty NextHop -Unique

    # Get current active default route gateways
    $activeGateways = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -ne "0.0.0.0" } | Select-Object -ExpandProperty NextHop -Unique

    Write-Host "Current active default gateways:" -ForegroundColor Green
    $activeGateways | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }

    Write-Host ""
    Write-Host "All gateways in routing table:" -ForegroundColor Cyan
    $allGateways | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }

    # Find inactive gateways (potentially invalid)
    $staleGateways = $allGateways | Where-Object { $_ -notin $activeGateways -and $_ -notlike "25.255.*" -and $_ -ne "127.0.0.1" }

    if ($staleGateways) {
        Write-Host ""
        Write-Host "Potentially invalid gateways:" -ForegroundColor Yellow
        $staleGateways | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }

        # Count routes for each suspicious gateway
        Write-Host ""
        Write-Host "Route count for suspicious gateways:" -ForegroundColor Yellow
        foreach ($gw in $staleGateways) {
            $routeCount = (Get-NetRoute -NextHop $gw -ErrorAction SilentlyContinue).Count
            Write-Host "  $gw : $routeCount routes" -ForegroundColor Cyan
        }

        Write-Host ""
        $targetGateway = $staleGateways | Select-Object -First 1
        Write-Host "Will cleanup gateway: $targetGateway" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "No obvious invalid gateways found." -ForegroundColor Green
        $inputGateway = Read-Host "Please enter gateway to cleanup (e.g., 192.168.1.1)"
        if ($inputGateway) {
            $targetGateway = $inputGateway
        } else {
            Write-Host "No gateway specified, exiting." -ForegroundColor Yellow
            exit 0
        }
    }
}

if (-not $targetGateway) {
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\cleanup-stale-routes.ps1 <gateway_address>     # Cleanup routes for specified gateway" -ForegroundColor White
    Write-Host "  .\cleanup-stale-routes.ps1 -AutoDetect           # Auto-detect and cleanup invalid gateway routes" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\cleanup-stale-routes.ps1 192.168.1.1" -ForegroundColor White
    Write-Host "  .\cleanup-stale-routes.ps1 192.168.1.1 -Force   # Skip confirmation" -ForegroundColor White
    Write-Host "  .\cleanup-stale-routes.ps1 -AutoDetect" -ForegroundColor White
    Write-Host ""
    exit 0
}

Write-Host "Target gateway: $targetGateway" -ForegroundColor Yellow

# Find all routes pointing to this gateway
Write-Host ""
Write-Host "Finding routes pointing to $targetGateway..." -ForegroundColor Cyan

$routesToRemove = Get-NetRoute -NextHop $targetGateway -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -ne "0.0.0.0/0" }

if (-not $routesToRemove) {
    Write-Host "No routes found pointing to $targetGateway." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($routesToRemove.Count) routes:" -ForegroundColor Yellow

# Group by network prefix for better display
$routesByPrefix = $routesToRemove | Group-Object { $_.DestinationPrefix -replace '/\d+$', '' } | Sort-Object Count -Descending

Write-Host ""
Write-Host "Route distribution (by network segment, showing top 20):" -ForegroundColor Cyan
$routesByPrefix | Select-Object -First 20 | ForEach-Object {
    $prefix = $_.Name
    $count = $_.Count
    $sampleRoute = $_.Group[0]
    Write-Host "  $prefix : $count routes (example: $($sampleRoute.DestinationPrefix))" -ForegroundColor White
}

# Show some specific routes
Write-Host ""
Write-Host "Sample specific routes:" -ForegroundColor Cyan
$routesToRemove | Select-Object -First 10 | ForEach-Object {
    Write-Host "  $($_.DestinationPrefix) via $($_.NextHop)" -ForegroundColor Gray
}

if ($routesToRemove.Count -gt 10) {
    $more = $routesToRemove.Count - 10
    Write-Host "  ... and $more more routes" -ForegroundColor Gray
}

# Confirmation
if (-not $force) {
    Write-Host ""
    Write-Host "WARNING: This will delete all routes pointing to $targetGateway!" -ForegroundColor Red
    $confirm = Read-Host "Confirm deletion? (Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "Starting cleanup..." -ForegroundColor Yellow
Write-Host ""

$count = 0
$errors = 0

foreach ($route in $routesToRemove) {
    try {
        Remove-NetRoute -DestinationPrefix $route.DestinationPrefix -NextHop $route.NextHop -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop -Confirm:$false
        $count++

        # Progress display every 100 routes
        if ($count % 100 -eq 0) {
            Write-Host "Deleted: $count/$($routesToRemove.Count)" -ForegroundColor Gray
        }
    } catch {
        $errors++
        if ($errors -le 5) {
            Write-Host "Failed: $($route.DestinationPrefix) - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Cleanup completed!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Successfully deleted: $count routes" -ForegroundColor Green
if ($errors -gt 0) {
    Write-Host "Failed to delete: $errors routes" -ForegroundColor Red
}
Write-Host ""

# Show remaining default routes
Write-Host "Current default routes:" -ForegroundColor Cyan
Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, NextHop, RouteMetric | Format-Table -AutoSize
