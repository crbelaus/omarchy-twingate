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
  property string _loginOutput: ""
  property bool _loginUrlOpened: false
  property string _logoutOutput: ""

  // Hard ceiling on how much a single command may hand back.
  readonly property int _maxOutputBytes: 65536

  // Every command runs behind `head -c`, so the ceiling is enforced by the
  // kernel pipe rather than by us: once the limit is reached head exits, the
  // read end closes, and the producer takes SIGPIPE. A compromised or
  // malfunctioning `twingate` binary therefore cannot make the shell buffer
  // unbounded output anywhere — not in a parser, not in a property.
  //
  // The command is passed as bash's positional arguments (`bash -c <script>
  // <argv0> <argv...>`) and referenced as "$@", so nothing that came out of
  // the CLI is ever spliced into a shell string.
  readonly property string _quietRunner:
    'exec 2>/dev/null; "$@" | head -c ' + _maxOutputBytes + '; exit ${PIPESTATUS[0]}'
  readonly property string _mergedRunner:
    '"$@" 2>&1 | head -c ' + _maxOutputBytes + '; exit ${PIPESTATUS[0]}'

  // Bounded, stderr discarded — for commands whose stdout we parse.
  function boundedQuiet(argv) {
    return ["bash", "-c", _quietRunner, "twingate-panel"].concat(argv)
  }

  // Bounded, stderr folded into stdout — for commands whose failure message we
  // want to show the user.
  function boundedMerged(argv) {
    return ["bash", "-c", _mergedRunner, "twingate-panel"].concat(argv)
  }

  // Second layer of defence: even inside the ceiling, never let a property
  // grow past it, and stop reading once we are at the limit.
  function appendBounded(current, chunk) {
    if (current.length >= root._maxOutputBytes) return current
    var next = current + chunk
    return next.length > root._maxOutputBytes ? next.substring(0, root._maxOutputBytes) : next
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
      whichProcess.command = boundedQuiet(["which", "twingate"])
      whichProcess.running = true
    }
  }

  function refreshStatusAndAccounts() {
    if (!installed) return
    var launched = false
    if (!statusProcess.running) {
      _statusOutput = ""
      statusProcess.command = boundedQuiet(["twingate", "status"])
      statusProcess.running = true
      launched = true
    }
    if (!resourcesProcess.running) {
      _resourcesOutput = ""
      resourcesProcess.command = boundedQuiet(["twingate", "resources"])
      resourcesProcess.running = true
      launched = true
    }
    if (!accountsProcess.running) {
      _accountsOutput = ""
      accountsProcess.command = boundedQuiet(["twingate", "account", "list"])
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
    actionProcess.command = boundedMerged(command)
    actionProcess.running = true
  }

  function login(network) {
    var name = String(network || "").trim()
    if (!installed || name === "" || loginProcess.running) return
    _loginOutput = ""
    _loginUrlOpened = false
    lastError = ""
    actionStatus = "Starting Twingate login…"
    loginProcess.networkName = name
    loginProcess.command = boundedMerged(["twingate", "account", "add"])
    loginProcess.running = true
  }

  function logout(email) {
    var id = String(email || "").trim()
    if (!installed || id === "" || logoutProcess.running) return
    _logoutOutput = ""
    lastError = ""
    loggingOutEmail = id
    logoutProcess.command = boundedMerged(["twingate", "account", "logout", id])
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
        if (root._statusOutput.length >= root._maxOutputBytes) statusProcess.running = false
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
        if (root._resourcesOutput.length >= root._maxOutputBytes) resourcesProcess.running = false
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
        if (root._accountsOutput.length >= root._maxOutputBytes) accountsProcess.running = false
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
        if (root._actionOutput.length >= root._maxOutputBytes) actionProcess.running = false
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elideStatus(root._actionOutput || "Twingate command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root._actionOutput = ""
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
    stdout: SplitParser {
      onRead: function(line) {
        root._loginOutput = root.appendBounded(root._loginOutput, line + "\n")
        root.openAuthUrlFrom(line)
        if (root._loginOutput.length >= root._maxOutputBytes) loginProcess.running = false
      }
    }
    onStarted: {
      write(networkName + "\n")
      networkName = ""
    }
    onExited: function(exitCode) {
      var opened = root.openAuthUrlFrom(root._loginOutput)
      if (exitCode !== 0 && !opened) {
        root.lastError = root.elideStatus(root._loginOutput || "Twingate login failed")
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
        if (root._logoutOutput.length >= root._maxOutputBytes) logoutProcess.running = false
      }
    }
    onStarted: write("y\n")
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = root.elideStatus(root._logoutOutput || "Twingate logout failed")
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
