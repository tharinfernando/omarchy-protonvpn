# Proton VPN — Omarchy bar widget

Status and one-click fastest-server connection for Proton VPN in the Omarchy
status bar.

## Features

- Bar icon: theme-colored Proton VPN mark with connected/disconnected state.
- Details panel with:
  - Connected server and location
  - Server load and protocol
  - Tunnel IP
  - Collapsible list of free-server countries (click the header or press `s`)
  - Refresh action
- Left click opens the panel.
- Right click connects to the fastest eligible Proton server or disconnects.
- Middle click refreshes status.
- Keyboard navigation: `j`/`k`, `enter`, `t`, `c`, `s`, `r`, and `esc`.

## Backend

This plugin uses Proton's official Linux CLI. It does not use `wg-quick`,
static WireGuard files, downloaded server configs, or custom DNS commands.

```bash
protonvpn connect       # fastest eligible server
protonvpn disconnect
protonvpn status
```

The official CLI performs server selection, NetworkManager setup, DNS, and
firewall handling. On a Free plan, Proton selects the fastest available free
server. The GUI and CLI cannot run simultaneously; close `protonvpn-app`
before using the bar toggle with this backend.

## Requirements

- `proton-vpn-cli` installed and signed in
- `wl-copy` for copy actions

Install the official Arch package with:

```bash
omarchy pkg add proton-vpn-cli
protonvpn signin
```

## Setup

```bash
ln -s "$(pwd)" ~/.config/omarchy/plugins/tharin.protonvpn
omarchy plugin enable tharin.protonvpn
omarchy bar move tharin.protonvpn --section right
```

The shell hot-reloads changes. Force discovery if needed:

```bash
omarchy-shell shell rescanPlugins
```

## Settings

| Key                  | Type    | Default | Meaning                        |
|----------------------|---------|---------|--------------------------------|
| `refreshIntervalSec` | integer | 30      | CLI status poll interval       |

Set it with:

```bash
omarchy bar set tharin.protonvpn refreshIntervalSec 30
```
