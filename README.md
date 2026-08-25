# Omarchy Rob Plugins

Rob's Omarchy bar, clock, menu, system-updates, vitals, and workspaces
plugins. Drop them into Omarchy with one command.

## What's included

| Plugin | Description |
|--------|-------------|
| `rob.bar` | Status bar with widgets (ActiveWindow, Indicators, KeyboardLayout, Microphone, Spacer, Tray) |
| `rob.clock` | Date/time label with calendar popup |
| `rob.menu` | Omarchy command menu (Quickshell-powered) |
| `rob.system-updates` | Pacman icon with pending update count |
| `rob.vitals` | CPU, memory, and disk usage in the bar |
| `rob.workspaces` | Workspace number indicators |

## Requirements

- An existing [Omarchy](https://omarchy.org) installation.

## Install

```bash
git clone https://github.com/computerstuff1/omarchy-rob-plugins.git
cd omarchy-rob-plugins
./install.sh
```

The script is idempotent — re-running it is safe. Plugins are overwritten in
place; stale `*.bak.*` plugin dirs from older runs are pruned first.

## What the installer does

1. Checks that `omarchy` is installed.
2. Prunes stale `*.bak.*` plugin backups.
3. Copies all six `rob.*` plugins into `~/.config/omarchy/plugins/`.
4. Restarts the omarchy shell.
