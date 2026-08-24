import QtQuick
import Quickshell
import Quickshell.Io

// Polls `twingate status` and drives the connection via `systemctl start/stop
// twingate` (the `twingate` CLI's own start/stop subcommands depend on a
// `twingate-classic` helper binary that's missing from some packagings, e.g.
// the AUR `twingate-bin` package, so this talks to systemd directly).
// See README.md for the required sudoers setup. Kept separate from
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

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 300)
  readonly property bool busy: whichProcess.running || statusProcess.running || actionProcess.running

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
    if (!installed || actionProcess.running) return
    _desired = 1
    runAction(["sudo", "-n", "/usr/bin/systemctl", "start", "twingate"], "Connecting…")
  }

  function stop() {
    if (!installed || actionProcess.running) return
    _desired = 0
    runAction(["sudo", "-n", "/usr/bin/systemctl", "stop", "twingate"], "Disconnecting…")
  }

  function runAction(command, label) {
    lastError = ""
    actionStatus = label || ""
    actionProcess.command = command
    actionProcess.running = true
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
        root._desired = -1
        root.lastError = root.elideStatus(actionStderr.text || actionStdout.text || "Twingate command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }
}
