# PingMonitor Changelog

## [2.1.0r9] - 2026-02-27
### Fixed
- Fixed status bar speed: horizontal left-right layout (↑xx ↓xx) with configurable spacing (-/+ stepper in settings)
- Fixed widget not appearing in system widgets list (build.sh now signs widget extension separately)

## [2.1.0r7] - 2026-02-27
### Improved
- Rewrote status bar speed display using custom NSView for stacked vertical layout (↑ green / ↓ blue)

## [2.1.0r6] - 2026-02-27
### Fixed
- Fixed status bar network speed not displaying (replaced broken multi-line layout with horizontal ↓/↑ text)

## [2.1.0r5] - 2026-02-27
### Improved
- Fixed empty state UI centering on Monitor & Host Management pages
- Replaced 3D pie chart with flat donut chart (SectorMark), moved text stats below chart
- Added status bar network speed display (↑/↓ stacked) with toggle and unit selector (Auto/KB/MB) in Settings

## [2.1.0] - 2026-02-26
### Added
- Real-time Network Speed Monitoring (Upload/Download, interface selection)
- Unified Service Shortcuts Panel (Web/SSH/Custom)
- SSH customized port & password/key authentication support

### Fixed
- Fixed v2.0.58 launch crash (Decoding error due to missing fields in old saved data)
- Fixed data loss on reinstall by switching from App Group UserDefaults to standard UserDefaults
- Fixed launch crash when distributed via DMG (Gatekeeper rejection due to Xcode ad-hoc entitlements)
- Fixed launch crash due to duplicate keys (`services.open`) in `Localization.swift` dictionary definitions
