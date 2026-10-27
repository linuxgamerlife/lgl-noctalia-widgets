# Noctalia Widgets

A collection of plugins for Noctalia Shell and KineticWE's `noctalia-kwe`
fork. Each app is maintained independently within this monorepo and includes
its own installation instructions, plugin catalog, documentation, and license.

## Apps

| App | Plugin ID | Description | License |
| --- | --- | --- | --- |
| [AI Usage](apps/ai-usage/) | `lukk17/ai-usage` | AI limits, spend, and account balances | GPL-3.0-or-later |
| [DualSense Battery](apps/dualsense/) | `deadYokai/dualsense` | DualSense battery, lightbar, and profile controls | MIT |
| [Modern SysMonitor Plus](apps/modern-sysmonitor-plus/) | `unsaidspeech/modern-sysmonitor-plus` | CPU, GPU, memory, disk, and network monitoring | GPL-2.0-or-later |
| [Steam Controller Battery](apps/steam-controller/) | `jahrek/steam-controller` | Steam Controller battery and wireless status | MIT |

## Installation

Each app has separate installers for upstream Noctalia and `noctalia-kwe`.
Run the appropriate installer from the repository root, for example:

```bash
# Upstream Noctalia
./apps/ai-usage/install.sh

# KineticWE noctalia-kwe
./apps/ai-usage/install-kwe.sh
```

See the app's README for its requirements, settings, and complete installation
instructions.

## Repository layout

```text
apps/
├── ai-usage/
├── dualsense/
├── modern-sysmonitor-plus/
└── steam-controller/
```

The apps have different licenses. Refer to the `LICENSE` file within each app
directory for the terms that apply to that app.
