pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(fg, 1.55)

  // Nerd Font glyphs, same set the Git panel draws with.
  readonly property string glyphCommit: ""
  readonly property string glyphRepo: ""
  readonly property string glyphStreak: "󰈸"
  readonly property string glyphRefresh: "󰑐"

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

        PanelSectionHeader {
          id: ghHeader
          anchors.left: parent.left
          text: "GITHUB"
          foreground: root.fg
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

      // Full-year contribution heatmap, drawn as one canvas (a scene graph
      // node per day is pure overhead) — same math as the Git panel.
      Item {
        id: yearGraph
        width: parent.width
        visible: root.svc && root.svc.ghCalendar.supported === true
        implicitHeight: monthLabelHeight + pitch * 7

        readonly property var calendar: root.svc ? root.svc.ghCalendar : ({})
        readonly property var counts: calendar.counts || []
        readonly property var levels: calendar.levels || []
        readonly property int weeks: Number(calendar.weeks || 0)
        readonly property int labelWidth: Style.space(24)
        readonly property int pitch: weeks > 0
          ? Math.max(3, Math.floor((width - labelWidth) / weeks)) : 0
        readonly property int gap: pitch >= 7 ? Math.max(1, Style.space(2)) : 1
        readonly property int cell: Math.max(2, pitch - gap)
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

        Item {
          id: monthRuler
          anchors.left: parent.left
          anchors.leftMargin: yearGraph.labelWidth
          anchors.top: parent.top
          width: yearGraph.weeks * yearGraph.pitch
          height: yearGraph.monthLabelHeight

          Repeater {
            model: yearGraph.calendar ? yearGraph.calendar.monthStarts : []

            Text {
              required property var modelData
              required property int index

              visible: Number(modelData) > 0
              x: index * yearGraph.pitch
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

        Repeater {
          model: [{ row: 1, label: "Mon" }, { row: 3, label: "Wed" }, { row: 5, label: "Fri" }]

          Text {
            required property var modelData

            x: 0
            y: yearGraph.monthLabelHeight + modelData.row * yearGraph.pitch
              + (yearGraph.cell - implicitHeight) / 2
            text: modelData.label
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Canvas {
          id: grid
          x: yearGraph.labelWidth
          y: yearGraph.monthLabelHeight
          width: yearGraph.weeks * yearGraph.pitch
          height: yearGraph.pitch * 7
          renderStrategy: Canvas.Cooperative

          readonly property string paintKey: [
            yearGraph.counts.length, yearGraph.levels.length,
            yearGraph.calendar ? yearGraph.calendar.end : "",
            yearGraph.calendar ? yearGraph.calendar.total : 0,
            yearGraph.calendar ? yearGraph.calendar.max : 0,
            yearGraph.pitch, yearGraph.cell,
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
            var radius = yearGraph.cell >= 6 ? 2 : 1
            for (var i = 0; i < total; i++) {
              var col = Math.floor(i / 7)
              var row = i % 7
              ctx.fillStyle = yearGraph.levelColor(Number(levels[i] || 0))
              ctx.beginPath()
              ctx.roundedRect(col * yearGraph.pitch, row * yearGraph.pitch, yearGraph.cell, yearGraph.cell, radius, radius)
              ctx.fill()
            }
            // Today sits last in the series; ring it so "did I ship today" is
            // answerable at a glance.
            if (total > 0) {
              var last = total - 1
              ctx.strokeStyle = root.fg
              ctx.lineWidth = 1
              ctx.beginPath()
              ctx.roundedRect(Math.floor(last / 7) * yearGraph.pitch + 0.5, (last % 7) * yearGraph.pitch + 0.5,
                              yearGraph.cell - 1, yearGraph.cell - 1, radius, radius)
              ctx.stroke()
            }
          }

          MouseArea {
            id: gridHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton

            onPositionChanged: function(mouse) {
              if (yearGraph.pitch <= 0) { yearGraph.hoverIndex = -1; return }
              var col = Math.floor(mouse.x / yearGraph.pitch)
              var row = Math.floor(mouse.y / yearGraph.pitch)
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

      // Section: recent commits
      Item {
        width: parent.width
        height: commitsHeader.implicitHeight

        PanelSectionHeader {
          id: commitsHeader
          anchors.left: parent.left
          text: "RECENT COMMITS"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Text {
          anchors.right: parent.right
          anchors.baseline: commitsHeader.baseline
          text: root.glyphRefresh
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
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

      Repeater {
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
            anchors.right: parent.right
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
        }
      }
    }
  }
}
