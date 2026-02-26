# PingMonitor Changelog

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
