# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) · [SemVer](https://semver.org/spec/v2.0.0.html)

## [1.0.1] - 2026-05-15

### Added
- App now appears in Launchpad (`LSUIElement` set to `NO`); Dock icon is hidden immediately in `applicationWillFinishLaunching` to minimize the brief flash.

### Fixed
- Eliminated ~40% idle main-thread CPU caused by `FanBladeView`'s `TimelineView(.animation)` ticking at display-refresh rate while the popover was closed. The `NSHostingController` is now mounted on popover open and torn down on close.

## [1.0.0] - 2026-05-15

First public release. Runs on macOS 26+, Apple Silicon and Intel.

### Added
- Real-time CPU/GPU temperature monitoring via IOKit / SMC.
- Three control modes: Manual, Automatic, System.
- Automatic controller with rolling history, ±200 RPM hysteresis, and four presets (Silent / Balanced / Performance / Custom).
- Per-fan independent RPM control on multi-fan machines; graceful no-fan fallback on fanless models.
- Status bar display modes (temperature / power / fan % / icon) and configurable high-temp alert.
- Launch at Login via `ServiceManagement`; English and Simplified Chinese localization.

### Security
- Privileged SMC writes isolated to a minimal C LaunchDaemon (`com.hoobnn.fanfan.smcd`); the app itself runs unprivileged.
- Daemon socket exposes only three commands: `PING`, `SET`, `AUTO`.
- Releases are Developer ID signed and notarized.

[1.0.1]: https://github.com/hoobnn/fanfan/releases/tag/v1.0.1
[1.0.0]: https://github.com/hoobnn/fanfan/releases/tag/v1.0.0
