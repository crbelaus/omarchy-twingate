import QtQuick
import Quickshell
import Quickshell.Io

// Polls `twingate status` and drives the connection via `systemctl start/stop
// twingate` (the `twingate` CLI's own start/stop subcommands depend on a
// `twingate-classic` helper binary that's missing from some packagings, e.g.
// the AUR `twingate-bin` package, so this talks to systemd directly).
// Authorizes the required sudoers rule itself via pkexec on first use; see
// README.md for details. Kept separate from
// BarWidget.qml so a future panel (resources, account switching, ...) can
// sit on top of the same state without touching the bar icon.
Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false

  // Optimistic state so the icon reacts the instant you click, rather than
  // waiting for the next poll. _desired is -1 while we just follow the real
  // state, or 0/1 while a toggle is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)

  property string statusText: "Checking…"
  property string actionStatus: ""
  property string lastError: ""

  // Set once a start/stop fails with a sudo permission error, so the next
  // click authorizes via pkexec instead of retrying the same failing sudo
  // call. _pendingDesired remembers which action (1 = start, 0 = stop) to
  // retry once authorization succeeds.
  property bool needsSudoSetup: false
  property int _pendingDesired: -1

  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 300)
  readonly property bool busy: whichProcess.running || statusProcess.running || actionProcess.running || authProcess.running

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function isSudoPermissionError(text) {
    var t = String(text || "")
    return /password is required/i.test(t) || /terminal is required/i.test(t)
      || /no tty present/i.test(t) || /^sudo:/im.test(t)
  }

  function refresh() {
    if (installed) {
      refreshStatus()
      return
    }
    if (!whichProcess.running) {
      whichProcess.command = ["which", "twingate"]
      whichProcess.running = true
    }
  }

  function refreshStatus() {
    if (!installed || statusProcess.running) return
    statusProcess.command = ["twingate", "status"]
    statusProcess.running = true
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  function parseStatus(raw, exitCode) {
    var text = String(raw || "").split("\n")[0].trim()
    if (exitCode !== 0 || text === "") {
      running = false
      statusText = "Unavailable"
      return
    }
    running = text.toLowerCase().indexOf("online") === 0
    // Reality caught up to the pending toggle — stop overriding.
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    statusText = running ? "Connected" : (text.charAt(0).toUpperCase() + text.slice(1))
  }

  function toggle() {
    if (!installed || actionProcess.running) return
    if (active) stop()
    else start()
  }

  function start() {
    if (!installed || actionProcess.running || authProcess.running) return
    if (needsSudoSetup) { _pendingDesired = 1; authorizeSudoAccess(); return }
    _desired = 1
    runAction(["sudo", "-n", "/usr/bin/systemctl", "start", "twingate"], "Connecting…")
  }

  function stop() {
    if (!installed || actionProcess.running || authProcess.running) return
    if (needsSudoSetup) { _pendingDesired = 0; authorizeSudoAccess(); return }
    _desired = 0
    runAction(["sudo", "-n", "/usr/bin/systemctl", "stop", "twingate"], "Disconnecting…")
  }

  function runAction(command, label) {
    lastError = ""
    actionStatus = label || ""
    actionProcess.command = command
    actionProcess.running = true
  }

  // One-time privileged setup, mirrored from Omarchy's own Tailscale plugin
  // (its Service.qml authorizes the Tailscale operator via a bare `pkexec
  // tailscale set --operator=...`). Here pkexec runs a small root shell
  // script instead, since installing a sudoers file needs more than one
  // command; userName is passed as a positional argument ($1) rather than
  // interpolated into the script text, so it can't be used for injection.
  function authorizeSudoAccess() {
    if (!installed || authProcess.running || userName === "") return
    lastError = ""
    actionStatus = "Authorizing sudo access…"
    var script = "set -e\n" +
      "file=/etc/sudoers.d/twingate\n" +
      "printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl start twingate, /usr/bin/systemctl stop twingate\\n' \"$1\" > \"$file\"\n" +
      "chown root:root \"$file\"\n" +
      "chmod 0440 \"$file\"\n" +
      "visudo -c -f \"$file\" || { rm -f \"$file\"; exit 1; }\n"
    authProcess.command = ["pkexec", "sh", "-c", script, "sh", userName]
    authProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    // A status process that never exits (the twingated socket can hang while
    // the network is coming and going) would otherwise leave the icon stale
    // forever. Reap it well inside the refresh interval so the next tick
    // starts clean.
    id: pollWatchdog
    interval: 10000
    repeat: false
    onTriggered: { if (statusProcess.running) statusProcess.running = false }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatus()
      else {
        root.running = false
        root.statusText = "Not installed"
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.parseStatus(statusStdout.text, exitCode)
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var errText = actionStderr.text || actionStdout.text || ""
        if (root.isSudoPermissionError(errText)) {
          root.needsSudoSetup = true
          root._pendingDesired = root._desired
          root._desired = -1
          root.lastError = "Twingate needs sudo access — click to authorize"
        } else {
          root._desired = -1
          root.lastError = root.elideStatus(errText || "Twingate command failed")
        }
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: authProcess
    running: false
    command: []
    stdout: StdioCollector { id: authStdout; waitForEnd: true }
    stderr: StdioCollector { id: authStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = root.elideStatus(authStderr.text || authStdout.text || "Sudo authorization failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
        return
      }
      root.needsSudoSetup = false
      root.lastError = ""
      root.actionStatus = "Sudo access authorized"
      actionStatusTimer.restart()
      var pending = root._pendingDesired
      root._pendingDesired = -1
      if (pending === 1) root.start()
      else if (pending === 0) root.stop()
    }
  }
}
