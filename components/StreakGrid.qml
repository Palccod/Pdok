pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// GitHub-style contribution grid: small fixed-size cells, one column per
// week for a full trailing year, 7 rows Mon..Sun. Green like the reference —
// solid when a day's daily tasks were all completed, translucent for partial
// days. The year is wider than the drawer, so it scrolls horizontally
// (landing on today); month labels ride the grid with collision suppression,
// while the stats row and legend stay pinned.
Rectangle {
  id: root

  color: "transparent"

  property var svc: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color doneGreen: "#3fb950"
  readonly property int cellSize: 11
  readonly property int gapSize: 3
  readonly property int step: cellSize + gapSize
  readonly property int weeks: 53
  readonly property int gridW: weeks * step - gapSize
  readonly property int gridH: 7 * step - gapSize
  // Weekday of today, Monday = 0.
  readonly property int dow: (new Date().getDay() + 6) % 7
  readonly property int todayCol: weeks - 1
  readonly property int todayRow: dow

  // Day offset behind today for grid cell (row r, col c). Column c's top
  // row is its Monday; the current week's Monday is `dow` days ago.
  function dayOffset(r, c) {
    return dow + (weeks - 1 - c) * 7 - r
  }

  // The month this column's Monday falls in, or "" when it continues the
  // previous column's month.
  function monthName(col) {
    var monOffset = dayOffset(0, col)
    var d = new Date()
    d = new Date(d.getFullYear(), d.getMonth(), d.getDate() - monOffset)
    if (col > 0) {
      var prev = new Date()
      prev = new Date(prev.getFullYear(), prev.getMonth(), prev.getDate() - dayOffset(0, col - 1))
      if (prev.getMonth() === d.getMonth()) return ""
    }
    return Qt.formatDate(d, "MMM")
  }

  // Hover text for a grid cell: how many tasks were done, and when.
  function tooltipFor(offset) {
    if (offset < 0) return ""
    var d = new Date()
    d = new Date(d.getFullYear(), d.getMonth(), d.getDate() - offset)
    var when = Qt.formatDate(d, "MMM d, yyyy")
    var n = root.svc ? root.svc.dayDoneCount(offset) : 0
    if (n <= 0) return "No tasks done on " + when
    return n + (n === 1 ? " task done on " : " tasks done on ") + when
  }

  // Show a label only if it keeps ~three columns of clear space from the
  // last one shown; year-boundary months one week apart would otherwise
  // render as "SepOct".
  function monthShown(col) {
    if (monthName(col) === "") return false
    var lastShown = -999
    for (var c = 0; c < col; c++) {
      if (monthName(c) !== "" && c - lastShown >= 3) lastShown = c
    }
    return col - lastShown >= 3
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
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
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

    // Last seven days at a glance: completed-task counts under day
    // initials, today highlighted. Complements the color-only year grid.
    Item {
      id: weekStrip
      width: parent.width
      height: Style.space(30)

      readonly property var days: {
        var rows = []
        for (var off = 6; off >= 0; off--) {
          var d = new Date()
          d = new Date(d.getFullYear(), d.getMonth(), d.getDate() - off)
          rows.push({
            offset: off,
            letter: Qt.formatDate(d, "ddd"),
            count: root.svc ? root.svc.dayDoneCount(off) : 0
          })
        }
        return rows
      }

      Repeater {
        model: weekStrip.days

        delegate: Item {
          id: dayCell

          required property var modelData
          required property int index

          x: index * (parent.width / 7)
          width: parent.width / 7
          height: parent.height

          Column {
            anchors.centerIn: parent

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: dayCell.modelData.letter
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: 9
              font.bold: dayCell.modelData.offset === 0
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: String(dayCell.modelData.count)
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: dayCell.modelData.count > 0
            }
          }
        }
      }
    }

    // Scrollable year: month labels and grid travel together; today's week
    // is on screen when the tab opens.
    Flickable {
      id: hscroll

      width: parent.width
      height: Style.space(12) + root.gridH
      contentWidth: root.gridW
      contentHeight: height
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentWidth > width

      function scrollToEnd() {
        contentX = Math.max(0, contentWidth - width)
      }
      Component.onCompleted: Qt.callLater(scrollToEnd)
      onVisibleChanged: if (visible) Qt.callLater(scrollToEnd)

      // Month labels
      Item {
        x: 0
        y: 0
        width: root.gridW
        height: Style.space(12)

      Repeater {
        model: root.weeks

        delegate: Text {
          required property int index

          x: index * root.step
          y: 0
          text: root.monthShown(index) ? root.monthName(index) : ""
          visible: root.monthShown(index)
            && x >= hscroll.contentX + 2
            && x + implicitWidth <= hscroll.contentX + hscroll.width - 2
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: 9
        }
      }
    }

      // Grid
      Item {
        id: gridArea
        // Below the month-label row; inside the Flickable nothing auto-flows.
        y: Style.space(12)
        width: root.gridW
        height: root.gridH

        property int hoverOffset: -1
        property real hoverMX: 0
        property real hoverMY: 0

      Repeater {
        model: root.weeks * 7

        delegate: Rectangle {
          id: cellRect

          required property int index

          readonly property int col: index % root.weeks
          readonly property int row: Math.floor(index / root.weeks)
          readonly property int offset: root.dayOffset(row, col)
          readonly property int state: root.svc ? root.svc.dayState(offset) : 0
          readonly property bool isToday: col === root.todayCol && row === root.todayRow

          x: col * root.step
          y: row * root.step
          width: root.cellSize
          height: root.cellSize
          radius: 2
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

      MouseArea {
        id: gridHover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        onPositionChanged: function(mouse) {
          var col = Math.floor(mouse.x / root.step)
          var row = Math.floor(mouse.y / root.step)
          if (col < 0 || col >= root.weeks || row < 0 || row >= 7) {
            gridArea.hoverOffset = -1
            return
          }
          gridArea.hoverMX = mouse.x
          gridArea.hoverMY = mouse.y
          gridArea.hoverOffset = root.dayOffset(row, col)
        }
        onExited: gridArea.hoverOffset = -1
      }

      PanelToolTip {
        visible: gridHover.containsMouse && gridArea.hoverOffset >= 0
          && root.tooltipFor(gridArea.hoverOffset) !== ""
        text: root.tooltipFor(gridArea.hoverOffset)
        fontFamily: root.fontFamily
        delay: 120
        // Park beside the cursor, flipping left near the right edge.
        x: {
          var w = width > 0 ? width : implicitWidth
          return gridHover.mouseX + w + 10 <= gridArea.width
            ? gridHover.mouseX + 10 : Math.max(0, gridHover.mouseX - w - 10)
        }
        y: Math.max(0, Math.min(gridArea.height - height,
          gridHover.mouseY - height - 6))
      }
      }
    }

    // Legend
    Item {
      width: parent.width
      height: Style.space(12)

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Less"
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: 9
        }

        Repeater {
          model: [
            Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07),
            Qt.rgba(root.doneGreen.r, root.doneGreen.g, root.doneGreen.b, 0.25),
            Qt.rgba(root.doneGreen.r, root.doneGreen.g, root.doneGreen.b, 0.6),
            root.doneGreen
          ]

          delegate: Rectangle {
            required property var modelData
            width: root.cellSize - 3
            height: width
            radius: 2
            color: modelData
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "More"
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: 9
        }
      }
    }
  }
}
