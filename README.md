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

Either way, `sudo systemctl start/stop twingate` runs from a background
process with no TTY and no askpass helper, so it needs a `NOPASSWD` sudoers
rule to work at all — otherwise it fails the same way plain sudo always does
without a terminal (`sudo: a password is required`). `twingate status` never
hits this, since it only reads a local socket and needs no privileges — only
start/stop do.

**You don't need to set this up by hand.** The first time you click the icon,
if the sudoers rule isn't there yet, the widget shows "click to authorize" in
the tooltip; clicking again prompts for your password through a native
polkit dialog (via `pkexec`, the same mechanism Omarchy's built-in Tailscale
widget uses for its own one-time privileged setup) and installs the rule
itself. The action you clicked for runs automatically right after.

The rule it installs is scoped to exactly those two commands:

```
<you> ALL=(root) NOPASSWD: /usr/bin/systemctl start twingate, /usr/bin/systemctl stop twingate
```

installed to `/etc/sudoers.d/twingate` (root-owned, mode `0440`, validated
with `visudo -c` before anything is written — a bad rule is deleted instead
of installed). It does not grant passwordless `sudo` for anything else,
including other `systemctl` subcommands or units.

To remove it later: `sudo rm /etc/sudoers.d/twingate`.

If `pkexec`/polkit isn't available on your system, install the same rule by
hand instead:

```bash
printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl start twingate, /usr/bin/systemctl stop twingate\n' "$(whoami)" > /tmp/twingate-sudoers
visudo -c -f /tmp/twingate-sudoers && sudo install -o root -g root -m 0440 /tmp/twingate-sudoers /etc/sudoers.d/twingate
rm -f /tmp/twingate-sudoers
```

## Troubleshooting

- **Icon shows "Not installed"** — the `twingate` binary isn't on `PATH` for
  the shell the bar runs in. Confirm `which twingate` works.
- **Tooltip says "click to authorize"** — click the icon again and approve
  the polkit prompt to install the sudoers rule.
- **Tooltip shows a different sudo/password error, or no polkit dialog
  appears** — `pkexec`/polkit may not be set up on your system; fall back to
  the manual install command above.
- **Icon stays on "Checking…" or seems stuck** — `twingate status` can hang
  while the daemon socket is flapping; the widget kills a stuck status check
  after 10s and retries on the next poll.

## Security

The sudoers rule above is the only privilege escalation this plugin performs,
and it's limited to starting/stopping the `twingate.service` unit — the same
access the official CLI already asks for interactively. Installing that rule
is itself privileged, so it only ever runs through `pkexec`, which shows you
a native, OS-owned password dialog naming the exact command it's elevating —
the plugin never handles your password directly. The script `pkexec` runs is
static (no user input is interpolated into it; your username is passed as an
inert argument) and validates the rule with `visudo -c` before installing it,
deleting it instead if validation fails. The plugin does not read, store, or
transmit your Twingate credentials; all authentication is handled by the
Twingate client itself.
