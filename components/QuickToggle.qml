pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// Quick-settings row: leading glyph, label, trailing slide switch. The whole
// row is clickable; state is the caller's (pass the service property as
// `checked` and flip it in the `toggled` handler).
Rectangle {
  id: root

  property string glyph: ""
  property string label: ""
  property bool checked: false
  property color fg: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  signal toggled(bool next)

  width: parent ? parent.width : 200
  height: Style.space(34)
  radius: Style.space(6)
  color: ma.pressed ? Style.pressedFill : (ma.containsMouse ? Style.hoverFill : "transparent")

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      textFormat: Text.PlainText
      color: root.checked ? root.accent : root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      textFormat: Text.PlainText
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      width: Math.min(implicitWidth, root.width - Style.space(72))
    }
  }

  Rectangle {
    id: switchTrack
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(34)
    height: Style.space(18)
    radius: height / 2
    color: root.checked ? root.accent : root.fg
    opacity: root.checked ? 0.9 : 0.18
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Rectangle {
      id: knob
      width: parent.height - Style.space(4)
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      x: root.checked ? parent.width - width - Style.space(2) : Style.space(2)
      color: root.checked ? Color.background : root.fg
      opacity: 1.0
      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled(!root.checked)
  }
}
