pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// GitHub-style contribution grid for the last 10 weeks: 10 columns (weeks,
// oldest left) × 7 rows (Mon..Sun). Green like the reference dashboards —
// full intensity when a day's daily tasks were all completed, translucent
// for partially-completed days. Today gets a ring.
Rectangle {
  id: root

  color: "transparent"

  property var svc: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color doneGreen: "#3fb950"
  readonly property int gap: 3
  // Today sits in the current weekday's row (Mon=0), last column.
  readonly property int todayIndex: {
    var t = new Date()
    return ((t.getDay() + 6) % 7) * 10 + 9
  }

  height: gridCol.implicitHeight

  Column {
    id: gridCol
    width: parent.width
    spacing: Style.space(8)

    // Stats row
    Item {
      width: parent.width
      height: Math.max(streakNum.implicitHeight, totalText.implicitHeight)

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Text {
          id: streakNum
          anchors.verticalCenter: parent.verticalCenter
          text: root.svc ? String(root.svc.streak) : "0"
          textFormat: Text.PlainText
          color: root.svc && root.svc.streak > 0 ? root.doneGreen : root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.baselineOffset: 0
          text: "day streak"
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        id: totalText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.svc ? root.svc.totalDaysDone + " days done" : ""
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Grid: 10 × 7 cells
    Item {
      id: gridArea
      width: parent.width
      height: width * 7 / 10

      readonly property real cell: (width - 9 * root.gap) / 10

      Repeater {
        model: 70

        delegate: Rectangle {
          id: cellRect

          required property int index

          readonly property int col: index % 10
          readonly property int row: Math.floor(index / 10)
          readonly property int state: root.svc && root.svc.dailyGrid.length === 70
            ? root.svc.dailyGrid[index] : 0
          readonly property bool isToday: index === root.todayIndex

          x: col * (gridArea.cell + root.gap)
          y: row * (gridArea.cell + root.gap)
          width: gridArea.cell
          height: gridArea.cell
          radius: Style.space(3)
          color: {
            if (state === 2) return root.doneGreen
            if (state === 1) return Qt.rgba(root.doneGreen.r, root.doneGreen.g, root.doneGreen.b, 0.35)
            return Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07)
          }
          border.width: isToday ? 1 : 0
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.5)

          Behavior on color { ColorAnimation { duration: 300 } }
        }
      }
    }

    // Weekday legend
    Text {
      text: "last 10 weeks · Mon → Sun"
      textFormat: Text.PlainText
      color: root.fg
      opacity: 0.35
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
