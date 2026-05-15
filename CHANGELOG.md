# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) · [SemVer](https://semver.org/spec/v2.0.0.html)

## [1.0.4] - 2026-05-15

### Added
- Settings now includes an **About** section with the installed version/build and a **Check for Updates** button that queries the GitHub Releases API and offers a one-click download if a newer version is available.

### Changed
- Renamed the Simplified Chinese locale directory from `zh-Hans.lproj` to `zh.lproj` and updated `knownRegions` accordingly.

## [1.0.3] - 2026-05-15

### Performance
- Tiered `SystemMonitor` polling: fast tier (CPU/GPU temp + fan RPM) still runs every tick, while the full sensor scan now runs at most every `max(6 s, interval × 3)`, cutting IOKit traffic on Macs with rich SMC catalogues.
- Cache per-fan `Mn` / `Mx` SMC limits once per fan-count instead of re-reading them every tick; caching only commits once every read succeeds so transient startup / wake-from-sleep failures still self-heal.
- `ControlsCard` now consumes a value-typed `ControlsSnapshot` and conforms to `Equatable`, letting SwiftUI skip body re-evaluation on unrelated `@Published` ticks (e.g. 2 s temperature updates) and cancel pending debounced slider writes on `.onDisappear`.
- Cap the rotating fan blade animation to 30 fps (down from display-refresh rate) and lift the static accent bloom + inner dot out of `TimelineView` so they stop re-evaluating every frame.

## [1.0.2] - 2026-05-15

### Performance
- Halved menu-bar icon animation CPU cost: lowered frame rate from 30 fps to 15 fps, skips `setImage:` calls when the quantized rotation slot is unchanged, and switched to template image mode so WindowServer handles tinting centrally.

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

[1.0.3]: https://github.com/hoobnn/fanfan/releases/tag/v1.0.3
[1.0.2]: https://github.com/hoobnn/fanfan/releases/tag/v1.0.2
[1.0.1]: https://github.com/hoobnn/fanfan/releases/tag/v1.0.1
[1.0.0]: https://github.com/hoobnn/fanfan/releases/tag/v1.0.0
