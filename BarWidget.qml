pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

import "components"

// Pdok — a side notch. One bar button opens a drawer that hugs the screen
// edge (right by default, right-click the button to flip sides) with tabs
// for system metrics, media, and notification history.
Panel {
  id: root

  moduleName: "palccod.pdok"
  ipcTarget: "palccod.pdok"
  // Own the IpcHandler so we can expose state/setSide next to open/close.
  manageIpc: false

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Shared per-shell service: notification history + metrics sampling.
  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("palccod.pdok") : null

  // Per-widget settings (inline shell.json entry): "side" (left|right),
  // "width" (drawer px, 280–640).
  readonly property string side: setting("side", "right") === "left" ? "left" : "right"
  readonly property int panelWidth: {
    var w = Math.round(Number(setting("width", 400)))
    if (!isFinite(w) || w <= 0) w = 400
    return Math.max(280, Math.min(640, w))
  }

  property string tab: "daily"
  readonly property var tabs: [
    { id: "daily", label: "Daily" },
    { id: "dash", label: "Dash" },
    { id: "media", label: "Media" },
    { id: "notifications", label: "Notifications" }
  ]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened && svc) {
      svc.refresh()
      svc.refreshGifs()
    }
  }

  IpcHandler {
    target: "palccod.pdok"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }

    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        side: root.side,
        width: root.panelWidth,
        settings: root.settings,
        barPosition: root.bar ? root.bar.position : null,
        unread: root.svc ? root.svc.unreadCount : -1,
        cardOrigin: sidePanel.cardOrigin,
        contentWidth: sidePanel.contentWidth,
        contentHeight: sidePanel.contentHeight,
        screenW: sidePanel.screenW,
        barW: sidePanel.barW,
        gifs: root.svc ? root.svc.gifFiles.length : -1,
        dailyTasks: root.svc ? root.svc.daily.tasks.length : -1,
        doneToday: root.svc ? root.svc.todayDoneIds().length : -1,
        streak: root.svc ? root.svc.streak : -1,
        todos: root.svc ? root.svc.daily.todos.length : -1,
        notesChars: root.svc ? root.svc.daily.notes.length : -1
      })
    }

    function setSide(side: string): string {
      if (side !== "left" && side !== "right") return "side must be left or right"
      root.setSide(side)
      return "side=" + root.side
    }

    function setTab(tab: string): string {
      // "alerts" kept as an alias for the pre-rename tab id.
      var wanted = tab === "alerts" ? "notifications" : tab
      for (var i = 0; i < root.tabs.length; i++) {
        if (root.tabs[i].id === wanted) {
          root.tab = wanted
          root.open()
          return "tab=" + wanted
        }
      }
      return "unknown tab"
    }

    function markRead(): string {
      if (!root.svc) return "service unavailable"
      root.svc.markAllRead()
      return "unread=" + root.svc.unreadCount
    }

    function readAt(timestamp: double): string {
      if (!root.svc) return "service unavailable"
      root.svc.markReadUpTo(timestamp)
      return "unread=" + root.svc.unreadCount
    }

    function readId(id: string): string {
      if (!root.svc) return "service unavailable"
      // Only history-file names are valid entry ids.
      if (!/^[0-9]+-[0-9]+\.json$/.test(id)) return "invalid id"
      root.svc.markEntryRead(id)
      return "unread=" + root.svc.unreadCount
    }

    function dailyAddTask(text: string): string {
      if (!root.svc) return "service unavailable"
      root.svc.addTask(text)
      return "tasks=" + root.svc.daily.tasks.length
    }

    function dailyToggleTask(index: int): string {
      if (!root.svc) return "service unavailable"
      var i = Math.round(Number(index))
      if (!isFinite(i) || i < 0 || i >= root.svc.daily.tasks.length) return "bad index"
      root.svc.toggleTask(root.svc.daily.tasks[i].id)
      return "doneToday=" + root.svc.todayDoneIds().length + " streak=" + root.svc.streak
    }

    function dailyRemoveTask(index: int): string {
      if (!root.svc) return "service unavailable"
      var i = Math.round(Number(index))
      if (!isFinite(i) || i < 0 || i >= root.svc.daily.tasks.length) return "bad index"
      root.svc.removeTask(root.svc.daily.tasks[i].id)
      return "tasks=" + root.svc.daily.tasks.length
    }

    function dailySummary(): string {
      if (!root.svc) return "service unavailable"
      return JSON.stringify({
        tasks: root.svc.daily.tasks.length,
        doneToday: root.svc.todayDoneIds().length,
        streak: root.svc.streak,
        totalDaysDone: root.svc.totalDaysDone,
        todos: root.svc.daily.todos.length,
        gifs: root.svc.gifFiles.length
      })
    }
  }

  function setSide(s) {
    var next = {}
    var current = settings ? settings : {}
    for (var k in current) next[k] = current[k]
    next.side = s === "left" ? "left" : "right"
    root.settings = next
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, next)
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fixedWidth: Style.bar.iconSlot
    labelVisible: false
    hasVisualContent: true
    tooltipText: "Pdok  ·  right-click to flip side"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton)
        root.setSide(root.side === "right" ? "left" : "right")
    }

    // Drawer icon: outlined card with a filled strip on the active side.
    Item {
      anchors.centerIn: parent
      width: Style.space(14)
      height: Style.space(14)

      Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: Style.space(4)
        border.width: Math.max(1, Style.space(1))
        border.color: root.foreground
      }

      Rectangle {
        width: parent.width * 0.34
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: root.side === "right" ? parent.right : undefined
        anchors.left: root.side === "left" ? parent.left : undefined
        anchors.margins: Style.space(2)
        radius: Style.space(2)
        color: root.foreground
      }
    }

    // Unread dot.
    Rectangle {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(1)
      anchors.rightMargin: Style.space(1)
      width: Style.space(6)
      height: Style.space(6)
      radius: width / 2
      color: Color.urgent
      border.width: 1
      border.color: root.bar ? root.bar.background : Color.background
      visible: root.svc ? root.svc.unreadCount > 0 : false
    }
  }

  SidePanel {
    id: sidePanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    side: root.side
    contentWidth: sidePanel.fittedContentWidth(root.panelWidth)
    contentHeight: sidePanel.availableCardHeight
    focusTarget: keyCatcher

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    Item {
      anchors.fill: parent

      // Tab chrome
      Item {
        id: tabChrome
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: tabRow.height

        Row {
          id: tabRow
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(30)

          Repeater {
            model: root.tabs

            delegate: Rectangle {
              id: tabBtn

              required property var modelData

              width: parent.width / root.tabs.length
              height: parent.height
              radius: Style.space(6)
              color: {
                if (root.tab === modelData.id) return Style.selectedFill
                if (tabMa.containsMouse) return Style.hoverFill
                return "transparent"
              }

              Text {
                anchors.centerIn: parent
                text: tabBtn.modelData.label
                textFormat: Text.PlainText
                color: root.foreground
                opacity: root.tab === tabBtn.modelData.id ? 1.0 : 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: root.tab === tabBtn.modelData.id
              }

              MouseArea {
                id: tabMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.tab = tabBtn.modelData.id
              }
            }
          }
        }

        Rectangle {
          anchors.top: tabRow.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.space(6)
          height: 1
          color: root.foreground
          opacity: 0.1
        }
      }

      // Tab stack
      Item {
        anchors.top: tabChrome.bottom
        anchors.topMargin: Style.space(22)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        DashTab {
          anchors.fill: parent
          visible: root.tab === "dash"
          svc: root.svc
          fg: root.foreground
          fontFamily: root.fontFamily
        }

        DailyTab {
          anchors.fill: parent
          visible: root.tab === "daily"
          svc: root.svc
          fg: root.foreground
          fontFamily: root.fontFamily
        }

        MediaTab {
          anchors.fill: parent
          visible: root.tab === "media"
          shell: root.bar ? root.bar.shell : null
          fg: root.foreground
          fontFamily: root.fontFamily
        }

        NotificationsTab {
          anchors.fill: parent
          visible: root.tab === "notifications"
          svc: root.svc
          fg: root.foreground
          fontFamily: root.fontFamily
        }
      }
    }
  }
}
