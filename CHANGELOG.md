# PingMonitor Changelog

## [2.1.0] - 2026-02-27
### Added
- **Status Bar Customization**: Real-time network speed monitor (↑/↓) in the status bar with toggle icon, configurable total width, font size, and text weight.
- **Advanced Network Speed Page**: Added refresh interval picker (1s-10s) and traffic history trend charts (30m / 1h / 24h / 7d) with total Traffic up/down statistics.
- **SSH Connectivity**: Re-engineered SSH shortcut connections to bypass AppleScript permission dialogs using `.command` files and `expect` scripts for auto-password auth.
- **UI Grid Consistency**: Fixed empty state UI centering and enforced uniform card heights across Monitor and Host Management grids.
- **Charts**: Replaced legacy 3D Pie Chart with natively sleek `SectorMark` donut charts in the Dashboard.

### Fixed
- Fixed status bar severe misalignment and center-offsetting when content width text overflows.
- Fixed widget not appearing in system lists (improved build script code signing for widget extensions).
- Fixed network interface sorting (active/traffic interfaces now float to top).

- Real-time Network Speed Monitoring (Upload/Download, interface selection)
- Unified Service Shortcuts Panel (Web/SSH/Custom)
- SSH customized port & password/key authentication support

### Fixed
- Fixed v2.0.58 launch crash (Decoding error due to missing fields in old saved data)
- Fixed data loss on reinstall by switching from App Group UserDefaults to standard UserDefaults
- Fixed launch crash when distributed via DMG (Gatekeeper rejection due to Xcode ad-hoc entitlements)
- Fixed launch crash due to duplicate keys (`services.open`) in `Localization.swift` dictionary definitions
