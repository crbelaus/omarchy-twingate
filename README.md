# Twingate for Omarchy

Shows whether the [Twingate](https://www.twingate.com/) VPN is connected from
the Omarchy bar. Click the icon to open a panel with connection status,
authorized resources, and account login/logout — similar to the built-in
Tailscale widget.

## Install

```bash
omarchy plugin add https://github.com/crbelaus/omarchy-twingate --enable
```

Requires the [Twingate](https://www.twingate.com/) Linux client to be
installed via the [`twingate`](https://aur.archlinux.org/packages/twingate)
AUR package.

## Use

- The lock icon fills in when Twingate is connected.
- Click the icon to open the panel.
- The switch in the panel header connects or disconnects Twingate.
- Right-click the bar icon to toggle without opening the panel.
- The **ACCOUNT** section shows your logged-in account (email and network)
  with a log-out button, and an **Add account** row to log in — it opens your
  browser to finish authentication after you type your network name.
- The **RESOURCES** section lists your authorized resources while connected,
  with a button to copy each address to the clipboard.

### Keyboard shortcuts

Inside the panel:

- `j` / `k` or arrows: move cursor
- `enter` / `space`: activate current row (toggle, log out, copy address)
- `t`: toggle Twingate
- `r`: refresh status
- `l`: open the login prompt
- `esc`: close (or cancel the login prompt)

## Settings

| Key                  | Description               | Default |
| --------------------- | -------------------------- | ------- |
| `refreshIntervalSec`  | How often to poll `twingate status`, resources, and account info, in seconds | `15` |

## Troubleshooting

- **Icon shows "Not installed"** — the `twingate` binary isn't on `PATH` for
  the shell the bar runs in. Confirm `which twingate` works.
- **Connect/disconnect fails** — confirm `twingate connect` / `twingate
  disconnect` work from a terminal. The widget just runs those commands
  directly and surfaces whatever error they return.
- **Icon stays on "Checking…" or seems stuck** — `twingate status` can hang
  while the daemon socket is flapping; the widget kills a stuck status check
  after 10s and retries on the next poll.
- **Resources list is empty** — resources only load while connected, and the
  panel only requests the default (non-hidden) list; a hint in the section
  header shows how many background resources are hidden.

## Security

The plugin runs `twingate status`, `twingate resources`, and `twingate
account list` as your own user. Connecting and disconnecting run `twingate
connect` / `twingate disconnect` via `pkexec`, matching what the CLI itself
requires. Logging in runs `twingate account add` (which opens your browser
for authentication); logging out runs `twingate account logout` for the
selected account. None of this reads, stores, or transmits your Twingate
credentials — all authentication is handled by the Twingate client itself.
