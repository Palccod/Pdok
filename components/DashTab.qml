pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// Dash tab: CPU, memory, disk, battery bars + network throughput.
Rectangle {
  id: root

  color: "transparent"
  radius: 0

  property var svc: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  Flickable {
    id: scroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: contentCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: contentCol
      width: scroll.width
      spacing: Style.space(14)

      // Section: system
      Item {
        width: parent.width
        height: sysHeader.implicitHeight

        Text {
          id: sysHeader
          anchors.left: parent.left
          text: "System"
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.svc ? root.svc.uptimeText : ""
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      MetricBar {
        width: parent.width
        fg: root.fg
        fontFamily: root.fontFamily
        label: "CPU"
        valueText: root.svc ? Math.round(root.svc.cpuPercent) + "%" : "…"
        ratio: root.svc ? root.svc.cpuPercent / 100 : 0
      }

      MetricBar {
        width: parent.width
        fg: root.fg
        fontFamily: root.fontFamily
        label: "Memory"
        valueText: root.svc && root.svc.memText.length > 0
          ? Math.round(root.svc.memPercent) + "%  ·  " + root.svc.memText : "…"
        ratio: root.svc ? root.svc.memPercent / 100 : 0
      }

      MetricBar {
        width: parent.width
        fg: root.fg
        fontFamily: root.fontFamily
        label: "Disk /"
        valueText: root.svc && root.svc.diskText.length > 0
          ? Math.round(root.svc.diskPercent) + "%  ·  " + root.svc.diskText : "…"
        ratio: root.svc ? root.svc.diskPercent / 100 : 0
      }

      MetricBar {
        width: parent.width
        visible: root.svc ? root.svc.hasBattery : false
        fg: root.fg
        fontFamily: root.fontFamily
        label: root.svc && root.svc.batteryCharging ? "Battery ⚡" : "Battery"
        valueText: root.svc ? root.svc.batteryPercent + "%" : ""
        ratio: root.svc ? root.svc.batteryPercent / 100 : 0
      }

      // Section: network
      Text {
        text: "Network"
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      Item {
        width: parent.width
        height: netCol.implicitHeight

        Column {
          id: netCol
          width: parent.width
          spacing: Style.space(6)

          Row {
            spacing: Style.space(8)

            Text {
              text: "↓"
              textFormat: Text.PlainText
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.svc ? root.svc.fmtKb(root.svc.netDownKb) : "…"
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: Style.space(90)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "↑"
              textFormat: Text.PlainText
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              opacity: 0.8
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.svc ? root.svc.fmtKb(root.svc.netUpKb) : "…"
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: root.fg
            opacity: 0.08
          }
        }
      }
    }
  }
}
