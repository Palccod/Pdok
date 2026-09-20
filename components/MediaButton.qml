pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// Round playback button. Self-contained: pass glyph, colors, font.
Rectangle {
  id: mediaBtn

  property string glyph: ""
  property color fg: Color.foreground
  property string fontFamily: Style.font.family
  property bool isPrimary: false
  signal clicked()

  width: isPrimary ? Style.space(46) : Style.space(38)
  height: width
  radius: width / 2
  color: {
    if (!enabled) return "transparent"
    if (ma.pressed) return Style.pressedFill
    if (ma.containsMouse) return Style.hoverFill
    return isPrimary ? Style.selectedFill : "transparent"
  }
  border.width: isPrimary && !ma.pressed && !ma.containsMouse ? 1 : 0
  border.color: mediaBtn.fg
  opacity: enabled ? 1.0 : 0.35

  Text {
    anchors.centerIn: parent
    text: mediaBtn.glyph
    textFormat: Text.PlainText
    color: mediaBtn.fg
    font.family: mediaBtn.fontFamily
    font.pixelSize: mediaBtn.isPrimary ? Style.font.iconLarge : Style.font.icon
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: mediaBtn.clicked()
  }
}
