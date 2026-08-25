# Twingate for Omarchy

Shows whether the [Twingate](https://www.twingate.com/) VPN is connected from
the Omarchy bar, and lets you connect or disconnect with a click.

## Install

```bash
omarchy plugin add https://github.com/crbelaus/omarchy-twingate --enable
```

Requires the [Twingate](https://www.twingate.com/) Linux client to be
installed via the [`twingate`](https://aur.archlinux.org/packages/twingate)
AUR package.

## Use

- The lock icon fills in when Twingate is connected.
- Left-click the icon to connect or disconnect.
- Hover for the current status, or the last error if something failed.

## Settings

| Key                  | Description               | Default |
| --------------------- | -------------------------- | ------- |
| `refreshIntervalSec`  | How often to poll `twingate status`, in seconds | `15` |

## Troubleshooting

- **Icon shows "Not installed"** — the `twingate` binary isn't on `PATH` for
  the shell the bar runs in. Confirm `which twingate` works.
- **Connect/disconnect fails** — confirm `twingate connect` / `twingate
  disconnect` work from a terminal. The widget just runs those commands
  directly and surfaces whatever error they return.
- **Icon stays on "Checking…" or seems stuck** — `twingate status` can hang
  while the daemon socket is flapping; the widget kills a stuck status check
  after 10s and retries on the next poll.

## Security

The plugin runs `twingate status`, `twingate connect`, and `twingate
disconnect` as your own user — no privilege escalation, sudo, or polkit is
involved. It does not read, store, or transmit your Twingate credentials;
all authentication is handled by the Twingate client itself.
