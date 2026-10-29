<div align="center">

# LGL Noctalia Widgets

**KDE Plasma widgets, rebuilt and improved for Noctalia Shell and Noctalia KWE.**

[![Apps](https://img.shields.io/badge/apps-5-purple)](#apps)
[![Noctalia](https://img.shields.io/badge/Noctalia-v5-blue)](https://github.com/noctalia-dev/noctalia-shell)
[![Noctalia KWE](https://img.shields.io/badge/noctalia--kwe-v5.3.0-blue)](#install)
[![Language](https://img.shields.io/badge/Luau-plugins-00A2FF)](#how-the-ports-work)
[![Support on Ko-fi](https://img.shields.io/badge/Support_on-Ko--fi-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/linuxgamerlife)

</div>

---

## Overview

LGL Noctalia Widgets is a collection of KDE Plasma widget ports and related
adaptations for [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell)
and KineticWE's `noctalia-kwe` fork.

These are not simple mirrors. Each app has been converted to Noctalia's Luau
plugin APIs, adapted for LGL's desktop, improved where useful, and packaged so
other Noctalia users can install it easily.

- Native Noctalia v5 services, desktop widgets, bar widgets, and panels
- Separate installers for upstream Noctalia and Noctalia KWE
- Theme-aware colours and Noctalia host-panel integration
- Self-contained documentation, tests where available, and uninstall tools
- Original projects, authors, and licences retained and credited

---

## Apps

| App | What it does | Plugin API | Licence |
|---|---|---:|---|
| [**LGL AI Usage**](apps/lgl-ai-usage/) | Shows AI limits, spend, balances, and local OpenCode statistics in desktop, bar, and panel views[^ai-usage] | 24 | GPL-3.0-or-later |
| [**LGL DualSense Battery**](apps/lgl-dualsense/) | Shows DualSense battery and connection state with live input visualisation, lightbar, player LED, and optional `ds4u` profile controls[^dualsense] | 17 | MIT |
| [**LGL Modern SysMonitor Plus**](apps/lgl-modern-sysmonitor-plus/) | Monitors CPU, GPU, memory, disks, fans, temperatures, and network activity[^sysmonitor] | 22 | GPL-2.0-or-later |
| [**LGL Steam Controller Battery**](apps/lgl-steam-controller/) | Shows Steam Controller 2 battery, charging, connection, wireless signal and live input state[^steam-controller] | 17 | MIT |
| [**LGL Weather & Time**](apps/lgl-weather-time/) | Shows a location-aware clock, current conditions and forecast with a full-bleed procedural weather scene, plus privacy-first location handling[^weather-time] | 24 | GPL-3.0-or-later |

Open an app's README for its requirements, settings, hardware notes, and full
installation instructions.

---

## Install

### Clone all apps

Clone the complete monorepo if you want to keep or try multiple apps:

```bash
git clone https://github.com/linuxgamerlife/lgl-noctalia-widgets.git
cd lgl-noctalia-widgets
```

Each app has one installer for Noctalia KWE and one for upstream Noctalia. Run
the appropriate script from the repository root, for example:

```bash
# KineticWE's noctalia-kwe fork
./apps/lgl-ai-usage/install-kwe.sh

# Upstream Noctalia
./apps/lgl-ai-usage/install.sh
```

The scripts link the selected plugin into the correct user data directory and
honour `NOCTALIA_DATA_HOME` and `XDG_DATA_HOME`. Installation does not combine
the apps; install only the ones you want.

### Clone only one app

Git cannot clone a subdirectory directly, but sparse checkout can fetch a
lightweight working copy containing only the selected app. Start with:

```bash
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/linuxgamerlife/lgl-noctalia-widgets.git
cd lgl-noctalia-widgets
```

Then choose one app below. Run either the KWE installer or the upstream
installer, not both.

#### LGL AI Usage

```bash
git sparse-checkout set apps/lgl-ai-usage

./apps/lgl-ai-usage/install-kwe.sh  # Noctalia KWE
# OR
./apps/lgl-ai-usage/install.sh      # Upstream Noctalia
```

#### LGL DualSense Battery

```bash
git sparse-checkout set apps/lgl-dualsense

./apps/lgl-dualsense/install-kwe.sh  # Noctalia KWE
# OR
./apps/lgl-dualsense/install.sh      # Upstream Noctalia
```

#### LGL Modern SysMonitor Plus

```bash
git sparse-checkout set apps/lgl-modern-sysmonitor-plus

./apps/lgl-modern-sysmonitor-plus/install-kwe.sh  # Noctalia KWE
# OR
./apps/lgl-modern-sysmonitor-plus/install.sh      # Upstream Noctalia
```

#### LGL Steam Controller Battery

```bash
git sparse-checkout set apps/lgl-steam-controller

./apps/lgl-steam-controller/install-kwe.sh  # Noctalia KWE
# OR
./apps/lgl-steam-controller/install.sh      # Upstream Noctalia
```

#### LGL Weather & Time

```bash
git sparse-checkout set apps/lgl-weather-time

./apps/lgl-weather-time/install-kwe.sh  # Noctalia KWE
# OR
./apps/lgl-weather-time/install.sh      # Upstream Noctalia
```

The root README and repository metadata remain present in a sparse checkout,
but the unselected app directories are not checked out. To include another app
later, use `git sparse-checkout add apps/<app-directory>`.

---

## How the Ports Work

The original KDE widgets use technologies such as QML, Plasma APIs, KWallet,
and KDE-specific data engines. The LGL ports replace those pieces with Noctalia
v5 equivalents:

| KDE / Plasma | LGL Noctalia ports |
|---|---|
| QML widget interface | Luau `ui.*` trees |
| Plasma data sources | Headless Noctalia services and Linux system interfaces |
| Plasma desktop placement | Noctalia desktop-widget entries |
| Panel popup | Noctalia bar-widget and panel entries where applicable |
| KDE palette roles | Live Noctalia palette roles with optional overrides |
| KWallet | Secret Service through `secret-tool` where credentials are needed |

Every port keeps its own technical documentation because the supported
hardware, services, dependencies, and upstream licence differ.

---

## Project Layout

```text
apps/
├── lgl-ai-usage/
├── lgl-dualsense/
├── lgl-modern-sysmonitor-plus/
├── lgl-steam-controller/
└── lgl-weather-time/
```

Each app directory contains its plugin payload, catalog entry, installers,
uninstallers, app-level README, licence, and tests when available. The nested
README inside each plugin payload is the detailed technical reference.

---

## Origins and Thanks

Many thanks to the original authors whose work made these ports possible. LGL's
versions retain the applicable upstream licences and document the Noctalia-
specific implementation and improvements in each app's README.

[^ai-usage]: Based on the [AI Usage KDE Plasma widget](https://github.com/lukk17/ai-usage-widget) by Łukasz Sarna.
[^dualsense]: Uses the desktop-card approach inspired by Jahrek's [Steam Controller Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget), with DualSense protocol and profile work informed by deadYokai's [ds4u](https://git.yokai.digital/deadYokai/ds4u).
[^sysmonitor]: Based on Modern SysMonitor Plus by UnsaidSpeech, itself based on [Modern SysMonitor](https://github.com/joaogabrielmedeiros/kde_plasma_widgets) by Joao Gabriel Medeiros.
[^steam-controller]: Based on Jahrek's [Steam Controller Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget).
[^weather-time]: Weather data by [Open-Meteo](https://open-meteo.com/) under [CC BY 4.0](https://open-meteo.com/en/license). The widget draws its own procedural scene and does not reuse Noctalia's IP-based auto-location.

---

## Licences

The apps use different licences. Refer to the `LICENSE` file in each app
directory for the terms that apply to that app. No single repository-wide
licence overrides those individual terms.

---

<div align="center">
Made for <a href="https://github.com/noctalia-dev/noctalia-shell">Noctalia</a> · adapted by <a href="https://www.youtube.com/@linuxgamerlife">LinuxGamerLife</a>
</div>
