pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Ruixen-style quick toggle: a square tonal button, accent-filled with a
// black glyph when on, white-alpha with a white glyph when off -- the exact
// treatment the notch's quick-controls column uses (color animates over
// 120ms). State is the caller's; pass the service property as `checked`
// and flip it in the `toggled` handler.
Rectangle {
  id: root

  property string glyph: ""
  property string label: ""
  property bool checked: false
  property int size: 40
  property color accent: "#3ecf5b"
  property color fg: "#ffffff"
  property string fontFamily: "JetBrainsMono Nerd Font"
  signal toggled(bool next)

  width: size
  height: label.length > 0 ? size + 16 : size
  color: "transparent"

  Rectangle {
    id: button
    width: root.size
    height: root.size
    radius: root.size / 4
    color: root.checked ? root.accent : Qt.rgba(1, 1, 1, 0.06)
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: root.glyph
      textFormat: Text.PlainText
      color: root.checked ? "#000000" : root.fg
      font.family: root.fontFamily
      font.pixelSize: root.size * 0.4
    }

    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggled(!root.checked)
    }
  }

  Text {
    anchors.top: button.bottom
    anchors.topMargin: 3
    anchors.horizontalCenter: button.horizontalCenter
    visible: root.label.length > 0
    text: root.label
    textFormat: Text.PlainText
    color: root.fg
    opacity: 0.5
    font.family: root.fontFamily
    font.pixelSize: 9
  }
}
