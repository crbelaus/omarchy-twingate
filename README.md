# Twingate for Omarchy

Shows whether the [Twingate](https://www.twingate.com/) VPN is connected from
the Omarchy bar, and lets you connect or disconnect with a click.

## Install

```bash
omarchy plugin add https://github.com/crbelaus/omarchy-twingate --enable
```

Requires the [Twingate Linux client](https://www.twingate.com/download) to be
installed (`twingate` CLI + `twingate.service`).

## Use

- The lock icon fills in when Twingate is connected.
- Left-click the icon to connect or disconnect.
- Hover for the current status, or the last error if something failed.

## Settings

| Key                  | Description               | Default |
| --------------------- | -------------------------- | ------- |
| `refreshIntervalSec`  | How often to poll `twingate status`, in seconds | `15` |

## Sudo setup (required to connect/disconnect)

The widget connects/disconnects by running `sudo systemctl start twingate` /
`sudo systemctl stop twingate` directly, rather than `twingate start`/`stop`.

That's a deliberate workaround: the `twingate` CLI's own `start`/`stop`
subcommands re-exec themselves as `sudo twingate-classic service-start` (a
private, root-copied helper binary that some packagings — notably the AUR
`twingate-bin` package — never install), so `twingate start`/`stop` fail with
`sudo: twingate-classic: command not found` even in an interactive terminal,
password or not. `systemctl start/stop twingate` controls the exact same
`twingate.service` unit and works fine on its own. Check
`ls /usr/bin/twingate-classic` — if it exists on your system, the CLI's own
`start`/`stop` may work for you and this workaround isn't required.

Either way, running `sudo systemctl start/stop twingate` from a background
process (no TTY, no askpass helper) fails the same way plain sudo always does
without a terminal:

```
sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper
sudo: a password is required
```

`twingate status` doesn't hit this, since it only reads a local socket and
needs no privileges — only start/stop do.

The fix is a `NOPASSWD` sudoers rule scoped to exactly those two commands, so
your Twingate password prompt disappears without granting broader passwordless
sudo access. Run:

```bash
printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl start twingate, /usr/bin/systemctl stop twingate\n' "$(whoami)" > /tmp/twingate-sudoers
visudo -c -f /tmp/twingate-sudoers && sudo install -o root -g root -m 0440 /tmp/twingate-sudoers /etc/sudoers.d/twingate
rm -f /tmp/twingate-sudoers
```

- `visudo -c -f` validates the syntax before anything touches `/etc/sudoers.d`,
  so a typo can't lock you out of `sudo`.
- `install -m 0440` matches the permissions `sudo` requires for files in
  `/etc/sudoers.d` (root-owned, read-only).
- The rule only ever lets your user run those two exact `systemctl` command
  lines as root — it does not grant passwordless `sudo` for anything else,
  including other `systemctl` subcommands or units.

To remove it later: `sudo rm /etc/sudoers.d/twingate`.

## Troubleshooting

- **Icon shows "Not installed"** — the `twingate` binary isn't on `PATH` for
  the shell the bar runs in. Confirm `which twingate` works.
- **Tooltip shows a sudo/password error** — you haven't added the sudoers
  rule above yet.
- **Icon stays on "Checking…" or seems stuck** — `twingate status` can hang
  while the daemon socket is flapping; the widget kills a stuck status check
  after 10s and retries on the next poll.

## Security

The sudoers rule above is the only privilege escalation this plugin performs,
and it's limited to starting/stopping the `twingate.service` unit — the same
access the official CLI already asks for interactively. The plugin does not
read, store, or transmit your Twingate credentials; all authentication is
handled by the Twingate client itself.
