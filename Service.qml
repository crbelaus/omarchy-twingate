import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Polls `twingate status`, `twingate resources`, and `twingate account list`,
// and drives connection, login, and logout via the `twingate` CLI.
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
  property var resources: []
  property int hiddenResourceCount: 0
  property var accounts: []
  property string actionStatus: ""
  property string lastError: ""
  property string loggingOutEmail: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 300)
  readonly property bool busy: whichProcess.running || statusProcess.running || resourcesProcess.running
    || accountsProcess.running || actionProcess.running || loginProcess.running || logoutProcess.running

  property string _statusOutput: ""
  property string _resourcesOutput: ""
  property string _accountsOutput: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginUrlOpened: false
  property string _logoutOutput: ""
  property string _logoutError: ""

  // Upper bound on any single command's accumulated output. A compromised or
  // malfunctioning `twingate` binary could otherwise stream unbounded stdout/
  // stderr into memory before elideStatus() ever gets a chance to truncate it.
  readonly property int _maxOutputChars: 65536

  function appendBounded(current, chunk) {
    if (current.length >= root._maxOutputChars) return current
    var next = current + chunk
    return next.length > root._maxOutputChars ? next.substring(0, root._maxOutputChars) : next
  }

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

  function copyToClipboard(value) {
    var text = String(value || "")
    if (text === "") return
    Util.execDetached("printf %s " + Util.shellQuote(text) + " | wl-copy")
  }

  function refresh() {
    if (installed) {
      refreshStatusAndAccounts()
      return
    }
    if (!whichProcess.running) {
      whichProcess.command = ["which", "twingate"]
      whichProcess.running = true
    }
  }

  function refreshStatusAndAccounts() {
    if (!installed) return
    var launched = false
    if (!statusProcess.running) {
      _statusOutput = ""
      statusProcess.command = ["twingate", "status"]
      statusProcess.running = true
      launched = true
    }
    if (!resourcesProcess.running) {
      _resourcesOutput = ""
      resourcesProcess.command = ["twingate", "resources"]
      resourcesProcess.running = true
      launched = true
    }
    if (!accountsProcess.running) {
      _accountsOutput = ""
      accountsProcess.command = ["twingate", "account", "list"]
      accountsProcess.running = true
      launched = true
    }
    if (launched && !pollWatchdog.running) pollWatchdog.start()
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
    runAction(["pkexec", "twingate", "connect"], "Connecting…")
  }

  function stop() {
    if (!installed || actionProcess.running) return
    _desired = 0
    runAction(["pkexec", "twingate", "disconnect"], "Disconnecting…")
  }

  function runAction(command, label) {
    lastError = ""
    actionStatus = label || ""
    _actionOutput = ""
    _actionError = ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function login(network) {
    var name = String(network || "").trim()
    if (!installed || name === "" || loginProcess.running) return
    _loginOutput = ""
    _loginError = ""
    _loginUrlOpened = false
    lastError = ""
    actionStatus = "Starting Twingate login…"
    loginProcess.networkName = name
    loginProcess.command = ["twingate", "account", "add"]
    loginProcess.running = true
  }

  function logout(email) {
    var id = String(email || "").trim()
    if (!installed || id === "" || logoutProcess.running) return
    _logoutOutput = ""
    _logoutError = ""
    lastError = ""
    loggingOutEmail = id
    logoutProcess.command = ["twingate", "account", "logout", id]
    logoutProcess.running = true
  }

  function openAuthUrlFrom(text) {
    if (_loginUrlOpened) return true
    var match = String(text || "").match(/https?:\/\/\S+/)
    if (match && match[0]) {
      _loginUrlOpened = true
      Qt.openUrlExternally(match[0])
      actionStatus = "Opened Twingate login"
      actionStatusTimer.restart()
      return true
    }
    return false
  }

  function handleLoginOutput(data, isError) {
    var text = String(data || "")
    if (isError) _loginError = appendBounded(_loginError, text + "\n")
    else _loginOutput = appendBounded(_loginOutput, text + "\n")
    openAuthUrlFrom(text)
    if (_loginOutput.length >= _maxOutputChars || _loginError.length >= _maxOutputChars) {
      loginProcess.running = false
    }
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
    // A status/resources/accounts process that never exits (the twingated
    // socket can hang while the network is coming and going) would otherwise
    // leave the panel stale forever. Reap anything still running well inside
    // the refresh interval so the next tick starts clean.
    id: pollWatchdog
    interval: 10000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (resourcesProcess.running) resourcesProcess.running = false
      if (accountsProcess.running) accountsProcess.running = false
    }
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
      if (root.installed) root.refreshStatusAndAccounts()
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
    stdout: SplitParser {
      onRead: function(line) {
        root._statusOutput = root.appendBounded(root._statusOutput, line + "\n")
        if (root._statusOutput.length >= root._maxOutputChars) statusProcess.running = false
      }
    }
    onExited: function(exitCode) {
      root.parseStatus(root._statusOutput, exitCode)
    }
  }

  Process {
    id: resourcesProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        root._resourcesOutput = root.appendBounded(root._resourcesOutput, line + "\n")
        if (root._resourcesOutput.length >= root._maxOutputChars) resourcesProcess.running = false
      }
    }
    onExited: function(exitCode) {
      var parsed = Model.parseResources(root._resourcesOutput)
      root.resources = parsed.resources
      root.hiddenResourceCount = parsed.hiddenCount
    }
  }

  Process {
    id: accountsProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        root._accountsOutput = root.appendBounded(root._accountsOutput, line + "\n")
        if (root._accountsOutput.length >= root._maxOutputChars) accountsProcess.running = false
      }
    }
    onExited: function(exitCode) {
      root.accounts = Model.parseAccounts(root._accountsOutput)
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        root._actionOutput = root.appendBounded(root._actionOutput, line + "\n")
        if (root._actionOutput.length >= root._maxOutputChars) actionProcess.running = false
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        root._actionError = root.appendBounded(root._actionError, line + "\n")
        if (root._actionError.length >= root._maxOutputChars) actionProcess.running = false
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elideStatus(root._actionError || root._actionOutput || "Twingate command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root._actionOutput = ""
      root._actionError = ""
      delayedRefresh.restart()
    }
  }

  // The network name goes over stdin — `twingate account add` has no
  // non-interactive flag for it.
  Process {
    id: loginProcess
    property string networkName: ""
    running: false
    command: []
    stdinEnabled: true
    stdout: SplitParser { onRead: function(data) { root.handleLoginOutput(data, false) } }
    stderr: SplitParser { onRead: function(data) { root.handleLoginOutput(data, true) } }
    onStarted: {
      write(networkName + "\n")
      networkName = ""
    }
    onExited: function(exitCode) {
      var combined = String(root._loginOutput || "") + "\n" + String(root._loginError || "")
      var opened = root.openAuthUrlFrom(combined)
      if (exitCode !== 0 && !opened) {
        root.lastError = root.elideStatus(combined || "Twingate login failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else if (!opened) {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  // The confirmation prompt goes over stdin — `twingate account logout` has
  // no non-interactive "yes" flag.
  Process {
    id: logoutProcess
    running: false
    command: []
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        root._logoutOutput = root.appendBounded(root._logoutOutput, line + "\n")
        if (root._logoutOutput.length >= root._maxOutputChars) logoutProcess.running = false
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        root._logoutError = root.appendBounded(root._logoutError, line + "\n")
        if (root._logoutError.length >= root._maxOutputChars) logoutProcess.running = false
      }
    }
    onStarted: write("y\n")
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = root.elideStatus(root._logoutError || root._logoutOutput || "Twingate logout failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root.loggingOutEmail = ""
      delayedRefresh.restart()
    }
  }
}
