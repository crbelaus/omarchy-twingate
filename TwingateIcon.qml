import QtQuick
import qs.Commons

// Lock glyph representing the Twingate secure connection, shared by the bar
// button and the panel hero so both stay in sync with a single definition.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Text {
    anchors.centerIn: parent
    text: "󰌾"
    color: root.color
    font.family: Style.font.family
    font.pixelSize: root.iconSize
  }
}
