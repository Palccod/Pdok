pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Ruixen-style quick toggle: a square tonal button. Active = brighter
// tonal fill with the ACCENT GLYPH (the tab-active treatment -- the
// background never takes the accent, only the icon); off = dim tonal
// fill with a white glyph. Color animates over 120ms. State is the
// caller's; pass the service property as `checked` and flip it in the
// `toggled` handler.
Rectangle {
  id: root

  property string glyph: ""
  property bool checked: false
  property int size: 40
  property color accent: "#3ecf5b"
  property color fg: "#ffffff"
  property string fontFamily: "JetBrainsMono Nerd Font"
  signal toggled(bool next)

  width: size
  height: size
  radius: size / 4
  color: root.checked ? Qt.rgba(1, 1, 1, 0.14) : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.06))
  Behavior on color { ColorAnimation { duration: 120 } }

  Text {
    anchors.centerIn: parent
    text: root.glyph
    textFormat: Text.PlainText
    color: root.checked ? root.accent : root.fg
    opacity: root.checked ? 1.0 : 0.8
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
