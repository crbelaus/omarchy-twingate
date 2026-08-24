import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Twingate connection status in the bar. Click toggles the connection.
// State polling and start/stop live in Service.qml so a future panel can
// build on the same state without touching this file.
BarWidget {
  id: root
  moduleName: "crbelaus.twingate"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggle() { service.toggle() }
  function refresh() { service.refresh() }

  Service {
    id: service
    settings: root.settings
  }

  IpcHandler {
    target: root.moduleName

    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function start(): void { service.start() }
    function stop(): void { service.stop() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌾"
    active: service.active
    activeColor: Color.accent
    tooltipText: !service.installed
      ? "Twingate: " + service.statusText
      : (service.actionStatus !== ""
        ? "Twingate: " + service.actionStatus
        : (service.lastError !== ""
          ? "Twingate: " + service.lastError
          : "Twingate: " + service.statusText + " — click to " + (service.active ? "disconnect" : "connect")))

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }
}
