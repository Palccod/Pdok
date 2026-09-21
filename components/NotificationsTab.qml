pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// Notifications tab: notification history read from omarchy.notifications' on-disk
// store (shared pdok service), with read/unread dimming and mark-all-read.
Rectangle {
  id: root

  color: "transparent"

  property var svc: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  readonly property int displayLimit: 60

  function relTime(ts) {
    var delta = Math.max(0, Date.now() - ts)
    var mins = Math.floor(delta / 60000)
    if (mins < 1) return "now"
    if (mins < 60) return mins + "m"
    var hours = Math.floor(mins / 60)
    if (hours < 24) return hours + "h"
    var days = Math.floor(hours / 24)
    return days + "d"
  }

  Flickable {
    id: scroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: alertsCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: alertsCol
      width: scroll.width
      spacing: Style.space(14)

      Item {
        width: parent.width
        height: alertsHeader.implicitHeight

        Text {
          id: alertsHeader
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.svc && root.svc.unreadCount > 0
            ? root.svc.unreadCount + " unread" : "All read"
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Rectangle {
          id: markReadBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.svc && root.svc.unreadCount > 0
          width: markReadText.implicitWidth + Style.space(20)
          height: markReadText.implicitHeight + Style.space(10)
          radius: height / 2
          color: markReadMa.pressed ? Style.pressedFill
            : markReadMa.containsMouse ? Style.hoverFill : "transparent"
          border.width: 1
          border.color: root.fg
          opacity: 0.85

          Text {
            id: markReadText
            anchors.centerIn: parent
            text: "Mark read"
            textFormat: Text.PlainText
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: markReadMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.svc) root.svc.markAllRead()
          }
        }
      }

      Text {
        width: parent.width
        visible: !root.svc || root.svc.entries.length === 0
        text: "No notifications yet —\nthey'll pile up here."
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        topPadding: Style.space(30)
        lineHeight: 1.3
      }

      Repeater {
        model: {
          if (!root.svc) return 0
          return Math.min(root.svc.entries.length, root.displayLimit)
        }

        delegate: Rectangle {
          id: rowRoot

          required property int index

          readonly property var entry: root.svc ? root.svc.entries[index] : null
          readonly property bool unread: root.svc ? root.svc.isUnread(entry) : false
          readonly property bool critical: !!entry && entry.urgency >= 2

          width: parent.width
          height: rowCol.implicitHeight + Style.space(24)
          radius: Style.space(6)
          color: {
            if (rowMa.containsMouse) return Style.selectedFill
            if (unread) return Style.hoverFill
            return "transparent"
          }

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(2)
            width: Style.space(3)
            radius: width / 2
            color: rowRoot.critical ? Color.urgent : Color.accent
            opacity: rowRoot.unread ? 1.0 : 0.35
            visible: !!rowRoot.entry
          }

          MouseArea {
            id: rowMa
            anchors.fill: parent
            enabled: !!rowRoot.entry
            hoverEnabled: true
            cursorShape: rowRoot.unread ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
              if (rowRoot.unread && root.svc)
                root.svc.markEntryRead(rowRoot.entry.id)
            }
          }

          Column {
            id: rowCol
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(4)

            Item {
              width: parent.width
              height: Math.max(appText.implicitHeight, timeText.implicitHeight)

              Text {
                id: appText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: rowRoot.entry ? rowRoot.entry.app : ""
                textFormat: Text.PlainText
                color: root.fg
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width - timeText.width - Style.space(10)
              }

              Text {
                id: timeText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: rowRoot.entry ? root.relTime(rowRoot.entry.timestamp) : ""
                textFormat: Text.PlainText
                color: rowRoot.unread ? Color.accent : root.fg
                opacity: rowRoot.unread ? 0.9 : 0.35
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              width: parent.width
              text: rowRoot.entry ? (rowRoot.entry.summary.length > 0 ? rowRoot.entry.summary : "(no title)") : ""
              textFormat: Text.PlainText
              color: root.fg
              opacity: rowRoot.unread ? 1.0 : 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: rowRoot.unread
              elide: Text.ElideRight
              visible: !!rowRoot.entry
            }

            Text {
              width: parent.width
              text: rowRoot.entry ? rowRoot.entry.body : ""
              textFormat: Text.PlainText
              color: root.fg
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              elide: Text.ElideRight
              maximumLineCount: 3
              lineHeight: 1.2
              visible: !!rowRoot.entry && rowRoot.entry.body.length > 0
            }
          }
        }
      }
    }
  }
}
