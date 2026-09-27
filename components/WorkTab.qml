pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Work tab: GitHub dashboard and recent commits, dressed like the dev.git
// panel — same heatmap canvas, level colors, streak footer and two-line rows.
// The dashboard reuses dev.git's collector state (see Service.qml); commits
// come from the gh CLI. Nothing here is clickable except commit rows, which
// open the commit in the browser through the bar host's run().
Rectangle {
  id: root

  color: "transparent"
  radius: 0

  property var svc: null
  property var bar: null
  property color fg: "#ffffff"
  property color accent: "#3ecf5b"
  property color urgent: "#e05252"
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.5)

  // Nerd Font glyphs, same set the Git panel draws with.
  readonly property string glyphCommit: ""
  readonly property string glyphRepo: ""
  readonly property string glyphRequest: ""
  readonly property string glyphIssue: ""
  readonly property string glyphStreak: "󰈸"
  readonly property string glyphRefresh: "󰑐"
  readonly property string glyphCopy: "󰆏"
  readonly property string glyphCheck: "󰄬"

  // Last copied commit; the row shows a check mark until the timer clears.
  property string copiedSha: ""

  function copySha(row) {
    if (!row || !/^[0-9a-f]{40}$/.test(String(row.fullSha || ""))) return
    copyProc.command = ["/usr/sbin/wl-copy", row.fullSha]
    copyProc.running = true
    root.copiedSha = row.sha
    copiedTimer.restart()
  }

  Timer {
    id: copiedTimer
    interval: 1600
    onTriggered: root.copiedSha = ""
  }

  Process {
    id: copyProc
  }


  readonly property var openWork: svc ? svc.ghOpenWork : ({ review: 0, assignedPrs: 0, assignedIssues: 0, authoredIssues: 0, authoredPrs: [] })

  // Identity shown in the hero line: "Name · @login", or just one of them.
  readonly property string heroIdentity: {
    var name = svc ? svc.ghName : ""
    var login = svc ? svc.ghLogin : ""
    if (name !== "" && login !== "" && name !== login) return name + " · @" + login
    if (login !== "") return "@" + login
    if (name !== "") return name
    return ""
  }

  readonly property string heroMeta: {
    if (!svc) return ""
    if (svc.ghRefreshing) return "REFRESHING…"
    var ago = timeAgo(svc.ghUpdatedAt, Date.now())
    if (ago === "" || ago === "just now") return "JUST NOW"
    return ago.toUpperCase() + " AGO"
  }

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function plural(n, one, many) { return n + " " + (n === 1 ? one : many) }
  function groupDigits(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",") }

  function timeAgo(iso, now) {
    if (!iso) return ""
    var ms = new Date(iso).getTime()
    if (!isFinite(ms)) return ""
    var seconds = Math.floor(Math.max(0, now - ms) / 1000)
    if (seconds < 60) return "just now"
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h"
    var days = Math.floor(hours / 24)
    if (days < 30) return days + "d"
    var months = Math.floor(days / 30)
    if (months < 12) return months + "mo"
    return Math.floor(months / 12) + "y"
  }

  function openUrl(url) {
    if (!url || !bar) return
    bar.run("omarchy launch browser " + Util.shellQuote(url))
  }

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

      // Section: github dashboard
      Item {
        width: parent.width
        height: ghHeader.implicitHeight

        SectionHeader {
          id: ghHeader
          anchors.left: parent.left
          title: "GITHUB"
          fg: root.fg
          fontFamily: root.fontFamily
        }

        Text {
          anchors.right: parent.right
          anchors.baseline: ghHeader.baseline
          text: {
            var base = root.heroIdentity
            if (base === "") return root.heroMeta
            return root.heroMeta === "" ? base : base + "  ·  " + root.heroMeta
          }
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
          width: Math.min(implicitWidth, parent.width - ghHeader.width - Style.space(12))
        }
      }

      // Auth hint when the collector cannot see GitHub.
      Text {
        width: parent.width
        visible: root.svc && !root.svc.ghCalendar.supported
        text: {
          if (!root.svc) return ""
          if (root.svc.ghLogin === "") return "Sign in with `gh auth login` to see your GitHub activity."
          return "Contribution data unavailable yet — the dev.git collector has not reported."
        }
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      // Full-year contribution heatmap at the Daily streak grid's cell
      // size, horizontally scrollable (newest week starts on screen); the
      // weekday gutter stays pinned while the months scroll underneath.
      Item {
        id: yearGraph
        width: parent.width
        visible: root.svc && root.svc.ghCalendar.supported === true
        implicitHeight: monthLabelHeight + gridH

        readonly property var calendar: root.svc ? root.svc.ghCalendar : ({})
        readonly property var counts: calendar.counts || []
        readonly property var levels: calendar.levels || []
        readonly property int weeks: Number(calendar.weeks || 0)
        readonly property int labelWidth: Style.space(24)
        // Same cell size as the Daily tab's StreakGrid.
        readonly property int cellSize: 11
        readonly property int gapSize: 3
        readonly property int step: cellSize + gapSize
        readonly property int gridW: weeks * step
        readonly property int gridH: 7 * step - gapSize
        readonly property int monthLabelHeight: Math.round(Style.font.caption * 1.4)

        property int hoverIndex: -1

        function levelColor(level) {
          if (level <= 0) return root.alpha(root.fg, 0.10)
          return root.alpha(root.accent, [0, 0.28, 0.50, 0.74, 1.0][Math.min(4, level)])
        }

        function dateAt(index) {
          if (!root.svc || calendar.start === "") return null
          var start = new Date(calendar.start + "T00:00:00")
          if (isNaN(start.getTime())) return null
          start.setDate(start.getDate() + index)
          return start
        }

        // Show a month label only if it keeps ~three glyph widths of clear
        // space from the last one shown; short months at 4-week steps would
        // otherwise collide ("SepOct").
        function monthVisible(index) {
          var ms = calendar ? calendar.monthStarts : []
          if (index >= ms.length || Number(ms[index] || 0) <= 0) return false
          var minWeeks = Math.max(2, Math.ceil((Style.font.caption * 3.0) / step))
          var last = -999
          for (var i = 0; i <= index; i++) {
            if (Number(ms[i] || 0) <= 0) continue
            if (i - last >= minWeeks) last = i
          }
          return last === index
        }

        function tooltipFor(index) {
          if (index < 0 || index >= counts.length) return ""
          var count = Number(counts[index] || 0)
          var label = count === 0 ? "No contributions" : root.plural(count, "contribution", "contributions")
          var date = dateAt(index)
          if (!date) return label
          var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
          return label + " on " + months[date.getMonth()] + " " + date.getDate() + ", " + date.getFullYear()
        }

        Flickable {
          id: hscroll
          // The viewport begins after the pinned gutter, so scrolled cells
          // can never render under the weekday labels.
          x: yearGraph.labelWidth
          width: parent.width - yearGraph.labelWidth
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          contentWidth: yearGraph.gridW
          contentHeight: height
          clip: true
          interactive: contentWidth > width
          boundsBehavior: Flickable.StopAtBounds

          // Land on the most recent week; scrolling back stays where the
          // user leaves it until the tab is reopened.
          function scrollToEnd() {
            contentX = Math.max(0, contentWidth - width)
          }
          Component.onCompleted: Qt.callLater(scrollToEnd)
          onVisibleChanged: if (visible) Qt.callLater(scrollToEnd)

          Item {
            width: hscroll.contentWidth
            height: hscroll.height

            // Month ruler, scrolls with the grid.
            Item {
              anchors.top: parent.top
              width: yearGraph.gridW
              height: yearGraph.monthLabelHeight

              Repeater {
                model: yearGraph.calendar ? yearGraph.calendar.monthStarts : []

                Text {
                  required property var modelData
                  required property int index

                  visible: yearGraph.monthVisible(index)
                  x: index * yearGraph.step
                  text: visible
                    ? ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                       "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][Number(modelData)]
                    : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Canvas {
              id: grid
              y: yearGraph.monthLabelHeight
              width: yearGraph.gridW
              height: yearGraph.gridH
              renderStrategy: Canvas.Cooperative

              readonly property string paintKey: [
                yearGraph.counts.length, yearGraph.levels.length,
                yearGraph.calendar ? yearGraph.calendar.end : "",
                yearGraph.calendar ? yearGraph.calendar.total : 0,
                yearGraph.calendar ? yearGraph.calendar.max : 0,
                yearGraph.cellSize, yearGraph.step,
                String(root.accent), String(root.fg)
              ].join(":")

              onPaintKeyChanged: requestPaint()
              onWidthChanged: requestPaint()
              onHeightChanged: requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var levels = yearGraph.levels
                var total = yearGraph.counts.length
                for (var i = 0; i < total; i++) {
                  var col = Math.floor(i / 7)
                  var row = i % 7
                  ctx.fillStyle = yearGraph.levelColor(Number(levels[i] || 0))
                  ctx.beginPath()
                  ctx.roundedRect(col * yearGraph.step, row * yearGraph.step,
                                  yearGraph.cellSize, yearGraph.cellSize, 2, 2)
                  ctx.fill()
                }
                // Today sits last in the series; ring it so "did I ship today" is
                // answerable at a glance.
                if (total > 0) {
                  var last = total - 1
                  ctx.strokeStyle = root.fg
                  ctx.lineWidth = 1
                  ctx.beginPath()
                  ctx.roundedRect(Math.floor(last / 7) * yearGraph.step + 0.5,
                                  (last % 7) * yearGraph.step + 0.5,
                                  yearGraph.cellSize - 1, yearGraph.cellSize - 1, 2, 2)
                  ctx.stroke()
                }
              }

              MouseArea {
                id: gridHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                onPositionChanged: function(mouse) {
                  var col = Math.floor(mouse.x / yearGraph.step)
                  var row = Math.floor(mouse.y / yearGraph.step)
                  var index = col * 7 + row
                  yearGraph.hoverIndex = (row >= 0 && row < 7 && index >= 0 && index < yearGraph.counts.length) ? index : -1
                }
                onExited: yearGraph.hoverIndex = -1
              }

              PanelToolTip {
                visible: gridHover.containsMouse && yearGraph.hoverIndex >= 0
                text: yearGraph.tooltipFor(yearGraph.hoverIndex)
                fontFamily: root.fontFamily
                delay: 120
                // Qt would center the popup over the whole canvas and bury
                // the month ruler; park it beside the cursor instead,
                // flipping to the left when the cell is near the right edge
                // and clamped inside the grid.
                x: {
                  var w = width > 0 ? width : implicitWidth
                  var left = gridHover.mouseX - w - 10
                  return gridHover.mouseX + w + 10 <= grid.width
                    ? gridHover.mouseX + 10 : Math.max(0, left)
                }
                y: Math.max(0, Math.min(grid.height - height,
                  gridHover.mouseY - height - 6))
              }
            }
          }
        }

        // Weekday gutter, pinned while the months scroll.
        Repeater {
          model: [{ row: 1, label: "Mon" }, { row: 3, label: "Wed" }, { row: 5, label: "Fri" }]

          Text {
            required property var modelData

            x: 0
            y: yearGraph.monthLabelHeight + modelData.row * yearGraph.step
              + (yearGraph.cellSize - implicitHeight) / 2
            text: modelData.label
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Streak on the left, intensity key on the right — the graph's footer.
      Item {
        width: parent.width
        visible: yearGraph.visible
        implicitHeight: Math.max(streakText.implicitHeight, legendRow.implicitHeight)

        Text {
          id: streakText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - legendRow.width - Style.space(12)
          text: {
            var cal = root.svc ? root.svc.ghCalendar : null
            if (!cal || cal.supported !== true) return ""
            var parts = []
            parts.push(cal.current > 0
              ? root.glyphStreak + " " + root.plural(cal.current, "day streak", "day streak")
              : "No active streak")
            if (cal.longest > 0) parts.push("longest " + root.plural(cal.longest, "day", "days"))
            parts.push("today " + cal.today)
            return parts.join("  ·  ")
          }
          textFormat: Text.PlainText
          color: root.svc && root.svc.ghCalendar.current > 0 ? root.fg : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Row {
          id: legendRow
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            rightPadding: Style.space(3)
            text: "Less"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: [0, 1, 2, 3, 4]

            Rectangle {
              required property var modelData
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(8)
              height: Style.space(8)
              radius: 2
              color: yearGraph.levelColor(modelData)
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.space(3)
            text: "More"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Section: open work — the four dev.git count cards
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: yearGraph.visible

        SectionHeader {
          width: parent.width
          title: "OPEN WORK"
          fg: root.fg
          fontFamily: root.fontFamily
        }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(8)

          readonly property real cellWidth: (width - columnSpacing) / 2

          WorkStat {
            width: parent.cellWidth
            value: root.openWork.review
            label: "AWAITING REVIEW"
            glyph: root.glyphRequest
            urgent: value > 0
            onActivated: root.openUrl("https://github.com/pulls?q=is%3Aopen+is%3Apr+review-requested%3A%40me")
          }

          WorkStat {
            width: parent.cellWidth
            value: root.openWork.assignedPrs
            label: "ASSIGNED PRS"
            glyph: root.glyphRequest
            urgent: value > 0
            onActivated: root.openUrl("https://github.com/pulls?q=is%3Aopen+is%3Apr+assignee%3A%40me")
          }

          WorkStat {
            width: parent.cellWidth
            value: root.openWork.assignedIssues
            label: "ASSIGNED ISSUES"
            glyph: root.glyphIssue
            urgent: value > 0
            onActivated: root.openUrl("https://github.com/issues?q=is%3Aopen+is%3Aissue+assignee%3A%40me")
          }

          WorkStat {
            width: parent.cellWidth
            value: root.openWork.authoredIssues
            label: "AUTHORED ISSUES"
            glyph: root.glyphIssue
            urgent: value > 0
            onActivated: root.openUrl("https://github.com/issues?q=is%3Aopen+is%3Aissue+author%3A%40me")
          }
        }
      }

      // Section: your open PRs — the collector's authored-PR queue
      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: yearGraph.visible

        SectionHeader {
          width: parent.width
          title: "YOUR OPEN PRS"
          fg: root.fg
          fontFamily: root.fontFamily
        }

        Repeater {
          model: root.openWork.authoredPrs || []

          delegate: Item {
            id: prRow

            required property var modelData

            width: parent.width
            height: prCol.implicitHeight + Style.space(8)

            Column {
              id: prCol
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: prAge.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: prRow.modelData.draft ? root.glyphIssue : root.glyphRequest
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(8) - Style.font.body
                  text: (prRow.modelData.draft ? "DRAFT · " : "")
                    + prRow.modelData.title + "  #" + prRow.modelData.number
                  textFormat: Text.PlainText
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Text {
                width: parent.width - Style.space(8) - Style.font.body
                text: prRow.modelData.repository
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideLeft
              }
            }

            Text {
              id: prAge
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.timeAgo(prRow.modelData.updatedAt, Date.now())
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openUrl(prRow.modelData.url)
            }
          }
        }

        Text {
          width: parent.width
          visible: (root.openWork.authoredPrs || []).length === 0
          text: "No open pull requests."
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // Section: recent commits
      Item {
        width: parent.width
        height: commitsHeader.height

        SectionHeader {
          id: commitsHeader
          anchors.left: parent.left
          anchors.right: parent.right
          title: "RECENT COMMITS"
          fg: root.fg
          fontFamily: root.fontFamily

          Text {
            text: root.glyphRefresh
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: 13
            color: root.svc && root.svc.ghRefreshing ? root.dim : root.fg
            opacity: root.svc && root.svc.ghRefreshing ? 0.4 : 0.8

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.svc) root.svc.refreshGithub()
            }
          }
        }

      }

      Text {
        width: parent.width
        visible: root.svc && root.svc.ghError !== ""
        text: root.svc ? root.svc.ghError : ""
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: root.svc && !root.svc.ghRefreshing && root.svc.ghError === "" && root.svc.ghCommits.length === 0
        text: "No recent commits."
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Commit list: five rows visible, the rest scroll in the pocket so
      // the tab keeps breathing room at the bottom of the drawer.
      Item {
        id: commitsArea
        width: parent.width
        // Five uniform rows + the gaps between them; measured, not guessed.
        readonly property real rowH: commitsRepeater.count > 0 && commitsRepeater.itemAt(0)
          ? commitsRepeater.itemAt(0).height : 0
        height: Math.min(commitsFlick.contentHeight,
          5 * rowH + 4 * commitsCol.spacing)

        Flickable {
          id: commitsFlick
          anchors.fill: parent
          contentWidth: width
          contentHeight: commitsCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: commitsCol
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              id: commitsRepeater
              model: root.svc ? root.svc.ghCommits : []


              delegate: Item {
                id: commitRow

                required property var modelData

                width: parent.width
                height: commitCol.implicitHeight + Style.space(8)

                readonly property color rowFg: root.fg

                Column {
                  id: commitCol
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: rowAge.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.glyphCommit
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - Style.space(8) - Style.font.body
                      text: commitRow.modelData.message
                      textFormat: Text.PlainText
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Item { width: Style.font.body; height: 1 }

                    Text {
                      width: parent.width - Style.space(8) - Style.font.body
                      text: commitRow.modelData.repo + "  ·  " + commitRow.modelData.sha
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideLeft
                    }
                  }
                }

                Text {
                  id: rowAge
                  anchors.right: copyBtn.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.timeAgo(commitRow.modelData.time, Date.now())
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openUrl(commitRow.modelData.url)
                }

                // Copy button, above the row's own click area.
                Text {
                  id: copyBtn
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.copiedSha === commitRow.modelData.sha
                    ? root.glyphCheck : "copy"
                  color: root.copiedSha === commitRow.modelData.sha
                    ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copySha(commitRow.modelData)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // dev.git's StatBox, same shape: bordered hover card, big number, caption
  // label, glyph tinted urgent when the count is non-zero.
  component WorkStat: CursorSurface {
    id: statBox

    property int value: 0
    property string label: ""
    property string glyph: ""
    property bool urgent: false
    signal activated()

    foreground: root.fg
    hasCursor: boxHover.containsMouse
    bordered: true
    implicitHeight: Math.max(Style.space(48),
      boxValue.implicitHeight + boxLabel.implicitHeight + Style.space(14))

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(9)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: statBox.glyph
        visible: text !== ""
        color: statBox.urgent ? root.urgent : root.alpha(root.fg, 0.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconLarge
      }

      Column {
        width: parent.width - parent.spacing - Style.font.iconLarge
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          id: boxValue
          width: parent.width
          text: String(statBox.value)
          color: statBox.urgent ? root.urgent : root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          id: boxLabel
          width: parent.width
          text: statBox.label
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      id: boxHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: statBox.activated()
    }
  }
}
