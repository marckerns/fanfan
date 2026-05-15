![fanfan](docs/icon.png)

# fanfan

A macOS menu bar app that puts you back in charge of your fans.

[![release](https://img.shields.io/github/v/release/hoobnn/fanfan?style=flat-square)](https://github.com/hoobnn/fanfan/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-26.0%2B-black?style=flat-square)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange?style=flat-square)](https://swift.org)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

[中文文档](README.zh.md)

## Install

Download the latest DMG from [Releases](https://github.com/hoobnn/fanfan/releases/latest), or:

```bash
curl -fsSL https://raw.githubusercontent.com/hoobnn/fanfan/main/scripts/install.sh | bash
```

Requires macOS 26+ (Apple Silicon or Intel). One password prompt on first launch — that's it.

## How it works

Writing fan speeds requires root. Instead of running the whole app as root,
fanfan installs a tiny C LaunchDaemon that owns the SMC handle and accepts
exactly three commands over a Unix socket: `PING`, `SET`, `AUTO`.

```
fanfan.app  ──unix socket──▶  fanfan-smcd (root)  ──IOKit──▶  SMC
```

The app itself runs unprivileged. Temperature reads go straight through IOKit.

## Acknowledgements

Forked from [solofan](https://github.com/SoloTeamDev/solofan), which builds on
[ffan](https://github.com/hoobnnlounnas/ffan). Thanks to both.

[MIT](LICENSE) © 2026 hoobnn
