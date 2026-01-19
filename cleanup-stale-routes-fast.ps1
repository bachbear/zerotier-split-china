# Fast route cleanup using route.exe batch processing
# Removes routes pointing to a specific gateway much faster than Remove-NetRoute
# Requires Administrator privileges

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please run as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Fast Route Cleanup Tool (route.exe)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Parse arguments
$targetGateway = $args | Where-Object { $_ -notmatch "^-" } | Select-Object -First 1
$force = $args -contains "-Force"

if (-not $targetGateway) {
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\cleanup-stale-routes-fast.ps1 <gateway_address>" -ForegroundColor White
    Write-Host ""
    Write-Host "Example:" -ForegroundColor Yellow
    Write-Host "  .\cleanup-stale-routes-fast.ps1 192.168.1.1" -ForegroundColor White
    Write-Host "  .\cleanup-stale-routes-fast.ps1 192.168.1.1 -Force" -ForegroundColor White
    Write-Host ""
    exit 0
}

Write-Host "Target gateway: $targetGateway" -ForegroundColor Yellow

# Find all routes pointing to this gateway using Get-NetRoute (faster than parsing route print)
Write-Host ""
Write-Host "Finding routes pointing to $targetGateway..." -ForegroundColor Cyan

$routesToRemove = Get-NetRoute -NextHop $targetGateway -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -ne "0.0.0.0/0" }

if (-not $routesToRemove) {
    Write-Host "No routes found pointing to $targetGateway." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($routesToRemove.Count) routes to delete." -ForegroundColor Yellow

# Convert routes to route.exe format and generate batch file
# route.exe format: route delete <network> mask <netmask> <gateway>
$batchCommands = @()

foreach ($route in $routesToRemove) {
    # Parse DestinationPrefix (e.g., "1.0.1.0/24")
    $prefixParts = $route.DestinationPrefix -split '/'
    $network = $prefixParts[0]
    $prefixLength = [int]$prefixParts[1]

    # Convert prefix length to subnet mask
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

    # Generate route delete command
    # route.exe can delete by network and mask only, doesn't need gateway
    $batchCommands += "route delete $network mask $mask"
}

# Write to temporary batch file
$tempBatch = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.bat'
$batchCommands | Out-File -FilePath $tempBatch -Encoding ASCII

Write-Host "Generated batch file: $tempBatch" -ForegroundColor Gray
Write-Host ""

# Confirmation
if (-not $force) {
    Write-Host "WARNING: This will delete all routes pointing to $targetGateway!" -ForegroundColor Red
    $confirm = Read-Host "Confirm deletion? (Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Remove-Item $tempBatch -Force
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "Starting fast cleanup using route.exe..." -ForegroundColor Yellow
Write-Host ""

# Execute the batch file and capture output
$startTime = Get-Date

& cmd /c $tempBatch 2>&1 | Tee-Object -Variable output

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds

# Clean up temp file
Remove-Item $tempBatch -Force

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Fast cleanup completed!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Time taken: $([math]::Round($duration, 2)) seconds" -ForegroundColor Green
Write-Host ""

# Count remaining routes pointing to target gateway
$remainingRoutes = Get-NetRoute -NextHop $targetGateway -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -ne "0.0.0.0/0" }
if ($remainingRoutes) {
    Write-Host "Remaining routes pointing to $targetGateway : $($remainingRoutes.Count)" -ForegroundColor Yellow
} else {
    Write-Host "All routes successfully removed!" -ForegroundColor Green
}
Write-Host ""

# Show remaining default routes
Write-Host "Current default routes:" -ForegroundColor Cyan
Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, NextHop, RouteMetric | Format-Table -AutoSize
