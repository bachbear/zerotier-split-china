# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2025-01-19

### Added
- **History file tracking** (`.zt-route-history.txt`)
  - Records the last configured gateway address and timestamp
  - Enables automatic detection of gateway changes

- **Smart cleanup mechanism**
  - Automatically detects when the local gateway has changed
  - Only removes routes pointing to the previous gateway (recorded in history)
  - Preserves user-configured routes to other gateways

- **Fast batch route deletion**
  - Uses temporary batch files with `route delete` commands
  - Significantly faster than individual PowerShell cmdlet calls
  - Displays deletion time and count

### Changed
- **Route addition method**: Switched from `New-NetRoute` to `route add` command
  - Much faster execution speed
  - Better performance when adding thousands of China IP routes

- **Route persistence behavior**
  - Routes are now PERSISTENT (survive system reboot)
  - Previous version used `-PolicyStore ActiveStore` (temporary routes)
  - Smart cleanup on gateway changes replaces the need for temporary routes

### Improved
- **Gateway change detection**
  - Compares current gateway with last recorded gateway
  - Provides clear status messages about gateway state
  - Shows last configuration timestamp

- **User feedback**
  - Added more informative status messages during cleanup
  - Progress indicators for route operations
  - Clear distinction between first run and subsequent runs

### Technical Details
- Added `Convert-CidrToMask` function to convert CIDR notation to subnet mask format (required by `route.exe`)
- Added `Remove-OldRoutes` function that generates and executes temporary batch files
- History file is created in the same directory as the script (`.zt-route-history.txt`)

## [1.0.0] - Initial Release

### Features
- Automatic ZeroTier gateway detection (supports /1 split routes and traditional mode)
- Private IP route configuration (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, etc.)
- China IP route configuration from `china-ip.txt`
- Temporary routes using `-PolicyStore ActiveStore` (cleared on reboot)
- Administrator privilege checking
- Detailed network configuration display

### Known Limitations
- Routes were temporary and cleared on reboot
- Required re-running script after each system reboot
- No mechanism to clean up stale routes when gateway changes
