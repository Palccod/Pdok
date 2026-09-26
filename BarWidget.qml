pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "bridge" as PdokBridge

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
  // Primary path: the bar host's scoped facade — the first-party bar scopes
  // it to this plugin, so serviceFor() reaches our own live service.
  // Fallback: the engine-wide bridge singleton. Replacement bars (e.g.
  // ruixen.bar) are handed a facade whose serviceFor() is a deliberate null
  // stub — Omarchy never exposes service resolution to them — so widgets
  // they host would otherwise never see the service. The binding
  // re-evaluates on its own when the service publishes (or is torn down).
  readonly property var svc: {
    var viaHost = bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("palccod.pdok") : null
    return viaHost || PdokBridge.Bridge.service
  }

  // Per-widget settings (inline shell.json entry): "side" (left|right),
  // "width" (drawer px, 280–640), "gifDir" (absolute path or ~/-prefixed;
  // empty = default sources).
  readonly property string side: setting("side", "right") === "left" ? "left" : "right"
  readonly property string gifDir: String(setting("gifDir", ""))
  readonly property int panelWidth: {
    var w = Math.round(Number(setting("width", 400)))
    if (!isFinite(w) || w <= 0) w = 400
    return Math.max(280, Math.min(640, w))
  }

  // The service reads the deck folder off its own customGifDir; push the
  // inline setting into it whenever either side (re)loads.
  function pushGifDir() {
    if (svc && typeof svc.setGifDir === "function") svc.setGifDir(gifDir)
  }
  onGifDirChanged: pushGifDir()
  onSvcChanged: {
    pushGifDir()
    if (svc && typeof svc.registerPanel === "function") svc.registerPanel(root)
  }

  // This instance's output, matched against Hyprland's focused monitor when
  // IPC routes open/close/toggle (see Service.panelForFocused).
  readonly property string screenName: sidePanel.screen ? sidePanel.screen.name : ""

  Component.onDestruction: {
    if (svc && typeof svc.unregisterPanel === "function") svc.unregisterPanel(root)
  }

  // IPC must reach the drawer on the focused monitor, not whichever widget
  // instance won the ipcTarget registration race.
  function route(what) {
    if (svc && typeof svc.toggleOnFocused === "function") {
      if (what === "open") svc.openOnFocused()
      else if (what === "close") svc.closeOnFocused()
      else svc.toggleOnFocused()
      return
    }
    if (what === "open") root.open()
    else if (what === "close") root.close()
    else root.toggle()
  }

  property string tab: "daily"
  // Bumped by requestPicker(); the DailyTab instance in this panel opens the
  // folder picker on each bump. Per-panel, so IPC can target the focused
  // monitor's drawer without touching the other one.
  property int pickerNonce: 0
  function requestPicker() { root.pickerNonce++ }
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

    function open(): void { root.route("open") }
    function close(): void { root.route("close") }
    function show(): void { root.route("open") }
    function hide(): void { root.route("close") }
    function toggle(): void { root.route("toggle") }

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
        screen: sidePanel.screen ? sidePanel.screen.name : "",
        focusedScreen: root.svc && root.svc.focusedScreenName ? root.svc.focusedScreenName() : "",
        focusedPanelScreen: root.svc && root.svc.panelForFocused && root.svc.panelForFocused() && root.svc.panelForFocused().screenName ? root.svc.panelForFocused().screenName : "",
        gifs: root.svc ? root.svc.gifFiles.length : -1,
        gifDir: root.svc ? root.svc.activeGifDir : "",
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

    function setGifDir(dir: string): string {
      return root.applyGifDir(dir)
    }

    // Open the drawer (on the focused monitor) on Daily with the picker up.
    // The nonce targets that panel's own DailyTab, so the other monitor's
    // instance stays untouched.
    function pickGifDir(): string {
      if (root.svc && typeof root.svc.openTabOnFocused === "function") {
        var p = root.svc.openTabOnFocused("daily")
        if (p && typeof p.requestPicker === "function") p.requestPicker()
        return "picker opened"
      }
      root.tab = "daily"
      root.route("open")
      return "picker opened"
    }

    function setTab(tab: string): string {
      // "alerts" kept as an alias for the pre-rename tab id.
      var wanted = tab === "alerts" ? "notifications" : tab
      for (var i = 0; i < root.tabs.length; i++) {
        if (root.tabs[i].id === wanted) {
          if (root.svc && typeof root.svc.openTabOnFocused === "function")
            root.svc.openTabOnFocused(wanted)
          else {
            root.tab = wanted
            root.route("open")
          }
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

  // Validate, apply and persist a GIF directory. Shared by the IPC command
  // and the in-drawer folder picker (whose "use"/"reset" buttons show the
  // returned status line and close on success — a "gifDir=" reply).
  function applyGifDir(dir: string): string {
    if (!svc) return "service unavailable"
    if (!svc.setGifDir(dir))
      return "invalid path — use an absolute directory (~/... ok), no .."
    var next = {}
    var current = settings ? settings : {}
    for (var k in current) next[k] = current[k]
    next.gifDir = String(dir).trim()
    root.settings = next
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, next)
    return "gifDir=" + svc.activeGifDir + " gifs=" + svc.gifFiles.length
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
          applyDir: root.applyGifDir
          pickerNonce: root.pickerNonce
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
