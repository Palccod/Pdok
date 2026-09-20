pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// One metric row: label + value on top, thin progress bar underneath.
Item {
  id: root

  property string label: ""
  property string valueText: ""
  property real ratio: 0
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  readonly property real clampedRatio: {
    var r = Number(ratio)
    if (!isFinite(r) || r < 0) r = 0
    return Math.min(1, r)
  }
  readonly property bool hot: clampedRatio >= 0.9

  height: labelRow.height + Style.space(6) + trackHeight
  readonly property int trackHeight: Style.space(6)

  Item {
    id: labelRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      textFormat: Text.PlainText
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      width: Math.min(implicitWidth, parent.width - valueText.width - Style.space(8))
    }

    Text {
      id: valueText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.valueText
      textFormat: Text.PlainText
      color: root.hot ? Color.urgent : root.fg
      opacity: root.hot ? 1.0 : 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    id: track
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.trackHeight
    radius: height / 2
    color: root.fg
    opacity: 0.12

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clampedRatio
      radius: parent.radius
      color: root.hot ? Color.urgent : Color.accent
      opacity: root.clampedRatio > 0 ? 1.0 : 0.0
      Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }
  }
}
