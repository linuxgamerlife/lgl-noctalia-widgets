# LGL Noctalia Widgets

LGL ports and adaptations of KDE Plasma widgets for
[Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell) and
KineticWE's `noctalia-kwe` fork. These are not simple mirrors: the original
widgets have been converted to Noctalia's plugin APIs, modified for LGL's use,
and extended and packaged for others who want to use them.

Each app is maintained independently within this monorepo and includes its own
installer, plugin catalog, detailed documentation, and license. The original
projects and authors are credited in [Origins and thanks](#origins-and-thanks).

## Apps

| App | Plugin ID | Description | License |
| --- | --- | --- | --- |
| [LGL AI Usage](apps/lgl-ai-usage/) | `lukk17/ai-usage` | AI limits, spend, and account balances[^ai-usage] | GPL-3.0-or-later |
| [LGL DualSense Battery](apps/lgl-dualsense/) | `deadYokai/dualsense` | DualSense battery, lightbar, and profile controls[^dualsense] | MIT |
| [LGL Modern SysMonitor Plus](apps/lgl-modern-sysmonitor-plus/) | `unsaidspeech/modern-sysmonitor-plus` | CPU, GPU, memory, disk, and network monitoring[^sysmonitor] | GPL-2.0-or-later |
| [LGL Steam Controller Battery](apps/lgl-steam-controller/) | `jahrek/steam-controller` | Steam Controller battery and wireless status[^steam-controller] | MIT |

## Installation

Each app has separate installers for upstream Noctalia and `noctalia-kwe`.
Run the appropriate installer from the repository root, for example:

```bash
# Upstream Noctalia
./apps/lgl-ai-usage/install.sh

# KineticWE noctalia-kwe
./apps/lgl-ai-usage/install-kwe.sh
```

See the app's README for its requirements, settings, and complete installation
instructions.

## Repository layout

```text
apps/
├── lgl-ai-usage/
├── lgl-dualsense/
├── lgl-modern-sysmonitor-plus/
└── lgl-steam-controller/
```

The apps have different licenses. Refer to the `LICENSE` file within each app
directory for the terms that apply to that app.

## Origins and thanks

Many thanks to the original authors whose work made these ports possible. LGL's
versions preserve the applicable upstream licenses and document the changes and
Noctalia-specific implementation in each app's README.

[^ai-usage]: Based on the [AI Usage KDE Plasma widget](https://github.com/lukk17/ai-usage-widget) by Łukasz Sarna.
[^dualsense]: Uses ideas from Jahrek's [Steam Controller Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget) and DualSense protocol and profile work from deadYokai's [ds4u](https://git.yokai.digital/deadYokai/ds4u).
[^sysmonitor]: Based on [Modern SysMonitor Plus](https://github.com/UnsaidSpeech/modern-sysmonitor-plus) by UnsaidSpeech, itself based on the original Modern SysMonitor by Joao Gabriel Medeiros.
[^steam-controller]: Based on Jahrek's [Steam Controller Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget).
