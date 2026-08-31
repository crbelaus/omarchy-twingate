import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "crbelaus.twingate"
  ipcTarget: "crbelaus.twingate"
  manageIpc: false

  property string focusSection: "header"
  property int accountIndex: 0
  property int resourceIndex: 0
  property bool cursorActive: false
  property bool loginPromptOpen: false
  property string loginNetworkText: ""
  property int phraseIndex: 0
  readonly property var activePhrases: [
    "Encrypting connections",
    "Reaching resources",
    "Guarding traffic",
    "Verifying identity",
    "Sealing tunnels"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showResources: twingate.active && twingate.resources.length > 0
  // Only claim the header cursor when the switch is actually on screen —
  // "header" stays navigable, but an absent CLI leaves nothing to highlight.
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && twingate.installed
  readonly property color iconColor: twingate.active ? foreground : dim
  readonly property string toggleHint: twingate.active ? "Disconnect Twingate" : "Connect Twingate"
  readonly property color barIconColor: twingate.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"

  function selectedAccount() {
    if (twingate.accounts.length === 0) return null
    return twingate.accounts[Math.max(0, Math.min(accountIndex, twingate.accounts.length - 1))]
  }

  function selectedResource() {
    if (twingate.resources.length === 0) return null
    return twingate.resources[Math.max(0, Math.min(resourceIndex, twingate.resources.length - 1))]
  }

  function openLoginPrompt() {
    loginPromptOpen = true
    loginNetworkText = ""
    Qt.callLater(function() { if (loginRow.networkFieldItem) loginRow.networkFieldItem.forceActiveFocus() })
  }

  function closeLoginPrompt() {
    loginPromptOpen = false
    loginNetworkText = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function submitLogin() {
    if (loginNetworkText.trim() === "") return
    twingate.login(loginNetworkText)
    closeLoginPrompt()
  }

  function ensureCursor() {
    if (accountIndex >= twingate.accounts.length) accountIndex = Math.max(0, twingate.accounts.length - 1)
    if (resourceIndex >= twingate.resources.length) resourceIndex = Math.max(0, twingate.resources.length - 1)
    if (focusSection === "accounts" && twingate.accounts.length === 0) focusSection = "header"
    if (focusSection === "resources" && !showResources) focusSection = "login"
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0) focusSection = twingate.accounts.length > 0 ? "accounts" : "login"
    } else if (focusSection === "accounts") {
      if (dy < 0) {
        if (accountIndex <= 0) focusSection = "header"
        else accountIndex--
      } else if (accountIndex < twingate.accounts.length - 1) {
        accountIndex++
      } else {
        focusSection = "login"
      }
    } else if (focusSection === "login") {
      if (dy < 0) {
        if (twingate.accounts.length > 0) { focusSection = "accounts"; accountIndex = twingate.accounts.length - 1 }
        else focusSection = "header"
      } else if (showResources) {
        focusSection = "resources"
      }
    } else if (focusSection === "resources") {
      if (dy < 0) {
        if (resourceIndex <= 0) focusSection = "login"
        else resourceIndex--
      } else if (resourceIndex < twingate.resources.length - 1) {
        resourceIndex++
      }
    }
    ensureCursor()
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") twingate.toggle()
    else if (focusSection === "accounts") { var a = selectedAccount(); if (a) twingate.logout(a.email) }
    else if (focusSection === "login") root.openLoginPrompt()
    else if (focusSection === "resources") { var r = selectedResource(); if (r) twingate.copyToClipboard(r.address) }
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "accounts" && accountColumn && accountIndex >= 0 && accountIndex < accountColumn.children.length) scrollItemIntoView(accountColumn.children[accountIndex])
    else if (focusSection === "resources" && resourceColumn && resourceIndex >= 0 && resourceIndex < resourceColumn.children.length) scrollItemIntoView(resourceColumn.children[resourceIndex])
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
  }

  function setAccountCursor(index) {
    cursorActive = true
    focusSection = "accounts"
    accountIndex = index
  }

  function setResourceCursor(index) {
    cursorActive = true
    focusSection = "resources"
    resourceIndex = index
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    loginPromptOpen = false
    if (panelFlick) panelFlick.contentY = 0
    twingate.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onAccountIndexChanged: scrollCursorIntoView()
  onResourceIndexChanged: scrollCursorIntoView()

  Service {
    id: twingate
    settings: root.settings
  }

  Connections {
    target: twingate
    function onAccountsChanged() { root.ensureCursor() }
    function onResourcesChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { twingate.refresh(); return "ok" }
    function start(): void { twingate.start() }
    function stop(): void { twingate.stop() }
    function status(): string { return twingate.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        TwingateIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          crossed: twingate.installed && !twingate.active
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) twingate.toggle()
      else if (buttonCode === Qt.MiddleButton) twingate.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.loginPromptOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") twingate.toggle()
        else if (t === "r" || t === "R") twingate.refresh()
        else if (t === "l" || t === "L") root.openLoginPrompt()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // Exposed for the hero's trailingControl, whose `root` resolves to
            // PanelHero (not this Panel) — reach panel state via `header`.
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Twingate"
              meta: !twingate.installed ? twingate.statusText : (twingate.active ? root.heroPhraseText : "Disconnected")
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: twingate.active ? 1.0 : 0.5
              iconComponent: Component {
                TwingateIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  crossed: twingate.installed && !twingate.active
                }
              }

              // Compact on/off switch on the trailing edge of the hero, and the
              // header's only cursor target. The service already flips `active`
              // optimistically, so the knob throws the instant you click it.
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: twingate.installed
                  checked: twingate.active
                  busy: twingate.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: twingate.toggle()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: twingate.actionStatus !== "" || twingate.lastError !== ""
            width: parent.width
            text: twingate.actionStatus !== "" ? twingate.actionStatus : twingate.lastError
            color: twingate.lastError !== "" && twingate.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
          }

          CursorSurface {
            visible: !twingate.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "Twingate CLI is not installed or not on PATH."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: twingate.installed
            foreground: root.foreground
          }

          Column {
            visible: twingate.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "ACCOUNT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: accountColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: twingate.accounts
                AccountRow {
                  required property var modelData
                  required property int index
                  width: accountColumn.width
                  account: modelData
                  rowIndex: index
                }
              }
            }

            LoginRow {
              id: loginRow
              width: parent.width
            }
          }

          PanelSeparator {
            visible: twingate.active
            foreground: root.foreground
          }

          Column {
            visible: twingate.active
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: twingate.hiddenResourceCount > 0
                ? "RESOURCES (" + twingate.hiddenResourceCount + " HIDDEN)"
                : "RESOURCES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: twingate.resources.length === 0
              width: parent.width
              text: "No authorized resources found."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: resourceColumn
              visible: root.showResources
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: twingate.resources
                ResourceRow {
                  required property var modelData
                  required property int index
                  width: resourceColumn.width
                  resource: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && twingate.active
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component LoginRow: Column {
    id: loginRowRoot
    property alias networkFieldItem: networkField
    spacing: Style.space(6)

    CursorSurface {
      width: parent.width
      hasCursor: root.cursorActive && root.focusSection === "login"
      foreground: root.foreground
      implicitHeight: loginContent.implicitHeight + Style.spacing.rowPaddingX
      visible: !root.loginPromptOpen

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: twingate.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
        enabled: !twingate.busy
        onEntered: { root.cursorActive = true; root.focusSection = "login" }
        onClicked: root.openLoginPrompt()
      }

      RowLayout {
        id: loginContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(8)

        Text {
          text: "󰐕"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          Layout.fillWidth: true
          text: "Add account"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }
    }

    Column {
      visible: root.loginPromptOpen
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: networkField
        width: parent.width
        foreground: root.foreground
        placeholderText: "Network name (e.g. acme)"
        text: root.loginNetworkText
        onTextChanged: root.loginNetworkText = text
        onAccepted: root.submitLogin()
        Keys.onEscapePressed: root.closeLoginPrompt()
      }

      Text {
        width: parent.width
        text: "Press enter to continue, esc to cancel — this opens your browser to finish signing in."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }

  component AccountRow: CursorSurface {
    id: accountRow
    property var account: null
    property int rowIndex: 0
    readonly property bool loggingOut: account && twingate.loggingOutEmail === String(account.email || "")

    hasCursor: root.cursorActive && root.focusSection === "accounts" && root.accountIndex === rowIndex
    foreground: root.foreground
    fill: root.hoverFill
    opacity: loggingOut ? 0.5 : 1.0

    implicitHeight: accountContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.ArrowCursor
      onEntered: root.setAccountCursor(accountRow.rowIndex)
    }

    RowLayout {
      id: accountContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: "󰀉"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: accountRow.account ? String(accountRow.account.email || "Unknown") : "Unknown"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          Layout.fillWidth: true
          text: accountRow.account ? String(accountRow.account.network || accountRow.account.networkUrl || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }

      PanelActionButton {
        iconText: "󰍃"
        tooltipText: "Log out"
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        enabled: !twingate.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: if (accountRow.account) twingate.logout(accountRow.account.email)
      }
    }
  }

  component ResourceRow: CursorSurface {
    id: resourceRow
    property var resource: null
    property int rowIndex: 0
    readonly property string resourceName: resource ? String(resource.name || "Unknown") : "Unknown"
    readonly property string resourceAddress: resource ? String(resource.address || "") : ""
    readonly property bool locked: resource && resource.locked === true

    hasCursor: root.cursorActive && root.focusSection === "resources" && root.resourceIndex === rowIndex
    foreground: root.foreground

    implicitHeight: resourceContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.ArrowCursor
      onEntered: root.setResourceCursor(resourceRow.rowIndex)
    }

    RowLayout {
      id: resourceContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: resourceRow.locked ? "󰍁" : "󰢥"
        color: resourceRow.locked ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: resourceLabels
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: resourceRow.resourceName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          Layout.fillWidth: true
          text: resourceRow.resourceAddress
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }

      PanelActionButton {
        id: copyButton
        iconText: "󰆏"
        tooltipText: "Copy address"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: resourceRow.resourceAddress !== ""
        Layout.alignment: Qt.AlignVCenter
        onClicked: twingate.copyToClipboard(resourceRow.resourceAddress)
      }
    }
  }
}
