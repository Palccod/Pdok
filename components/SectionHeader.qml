pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Ruixen-style section header: bold white title with an optional trailing
// action slot, over an inset hairline divider (white 0.14, pulled in 8px
// from the edges) -- the divider treatment the notch uses between calendar
// sections, not a full-width rule.
Rectangle {
  id: root

  property string title: ""
  property color fg: Color.foreground
  property string fontFamily: Style.font.family
  default property alias trailing: trailingSlot.data
  signal refreshed()

  width: parent ? parent.width : 0
  height: row.implicitHeight + 10
  color: "transparent"

  Item {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: titleText.implicitHeight

    Text {
      id: titleText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.title
      textFormat: Text.PlainText
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: 12
      font.bold: true
    }

    Item {
      id: trailingSlot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
  }

  Rectangle {
    anchors.top: row.bottom
    anchors.topMargin: 5
    anchors.left: parent.left
    anchors.leftMargin: 8
    anchors.right: parent.right
    anchors.rightMargin: 8
    height: 1
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
  }
}
