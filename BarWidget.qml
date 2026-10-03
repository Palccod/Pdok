pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "bridge" as PdokBridge

import "components"

// Pdok — a side notch. One bar button opens a drawer that hugs the screen
// edge (right by default, right-click the button to flip sides) with tabs
// for daily tasks, a GitHub work dashboard, media, and quick settings.
Panel {
  id: root

  moduleName: "palccod.pdok"
  ipcTarget: "palccod.pdok"
  // Own the IpcHandler so we can expose state/setSide next to open/close.
  manageIpc: false

  // Theme-aware like the notch (which reads Color.accent for its cava
  // colors): the bar's own foreground, the shell theme's accent, and the
  // theme's urgent color for muted/off states.
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color danger: Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Shared per-shell service: daily state (tasks/todos/notes + gif deck)
  // and the Work tab's GitHub dashboard sources.
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

  // Called on the focused panel by pickAvatar (IPC); the picker lives in
  // this same scope, so opening it needs no nonce round-trip.
  function openAvatarPicker() { avatarPicker.openFor("") }

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
    { id: "daily", label: "Daily", glyph: "󰃭" },
    { id: "work", label: "Work", glyph: "󰊢" },
    { id: "media", label: "Media", glyph: "󰝚" },
    { id: "control", label: "Control", glyph: "󰌺" }
  ]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened && svc) {
      svc.refreshGifs()
      svc.refreshGithub()
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
        cardOrigin: sidePanel.cardOrigin,
        contentWidth: sidePanel.contentWidth,
        contentHeight: sidePanel.contentHeight,
        screenW: sidePanel.screenW,
        barW: sidePanel.barW,
        screen: sidePanel.screen ? sidePanel.screen.name : "",
        focusedScreen: root.svc && root.svc.focusedScreenName ? root.svc.focusedScreenName() : "",
        gifs: root.svc ? root.svc.gifFiles.length : -1,
        gifDir: root.svc ? root.svc.activeGifDir : "",
        avatarCustom: svc ? svc.customAvatarActive : false,
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

    // Custom footer avatar: an absolute image path (gif/png/jpg/jpeg/webp;
    // ~ ok) copied into the service's state dir — GIFs stay animated.
    // Rendered whole-image (fit); setAvatarFramed adds the picker cropper's
    // zoom (1..8) and pan offsets (-1..1). clearAvatar returns to GitHub.
    function setAvatar(path: string): string {
      return svc ? svc.setCustomAvatar(path) : "service unavailable"
    }

    function setAvatarFramed(path: string, zoom: real, ox: real, oy: real): string {
      return svc ? svc.setCustomAvatar(path, zoom, ox, oy) : "service unavailable"
    }

    function clearAvatar(): string {
      return svc ? svc.setCustomAvatar("") : "service unavailable"
    }

    // Open the drawer (on the focused monitor) with the avatar picker up.
    function pickAvatar(): string {
      if (root.svc && typeof root.svc.panelForFocused === "function") {
        var fp = root.svc.panelForFocused()
        if (fp) {
          if (typeof fp.open === "function") fp.open()
          if (typeof fp.openAvatarPicker === "function") fp.openAvatarPicker()
          return "picker opened"
        }
      }
      root.open()
      avatarPicker.openFor("")
      return "picker opened"
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
      // "dash" kept as an alias for the pre-rename system-monitor tab (now Work).
      var wanted = tab === "dash" ? "work" : tab
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

      // Tab chrome — ruixen TabButton pills: tonal fill when active
      // (white 0.14) with the accent-coloured glyph, transparent with a
      // subtle hover otherwise, 120ms color animation.
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
          height: Style.space(44)
          spacing: Style.space(6)

          Repeater {
            model: root.tabs

            delegate: Rectangle {
              id: tabBtn

              required property var modelData

              width: (parent.width - tabRow.spacing * (root.tabs.length - 1)) / root.tabs.length
              height: parent.height
              radius: 12
              color: {
                var f = root.foreground
                if (root.tab === modelData.id) return Qt.rgba(f.r, f.g, f.b, 0.14)
                return tabMa.containsMouse ? Qt.rgba(f.r, f.g, f.b, 0.07) : "transparent"
              }
              Behavior on color { ColorAnimation { duration: 120 } }

              Column {
                anchors.centerIn: parent
                spacing: 2

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: tabBtn.modelData.glyph
                  textFormat: Text.PlainText
                  color: root.tab === tabBtn.modelData.id ? root.accent : root.foreground
                  opacity: root.tab === tabBtn.modelData.id ? 1.0 : 0.55
                  font.family: root.fontFamily
                  font.pixelSize: 18
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: tabBtn.modelData.label
                  textFormat: Text.PlainText
                  color: root.foreground
                  opacity: root.tab === tabBtn.modelData.id ? 1.0 : 0.45
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  font.bold: root.tab === tabBtn.modelData.id
                }
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
      }

      // Tab stack
      Item {
        id: tabStack
        anchors.top: tabChrome.bottom
        anchors.topMargin: Style.space(22)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(10)

        WorkTab {
          anchors.fill: parent
          visible: root.tab === "work"
          svc: root.svc
          bar: root.bar
          fg: root.foreground
          accent: root.accent
          urgent: root.danger
          fontFamily: root.fontFamily
        }

        DailyTab {
          anchors.fill: parent
          visible: root.tab === "daily"
          svc: root.svc
          fg: root.foreground
          accent: root.accent
          danger: root.danger
          fontFamily: root.fontFamily
          applyDir: root.applyGifDir
          pickerNonce: root.pickerNonce
        }

        MediaTab {
          anchors.fill: parent
          visible: root.tab === "media"
          shell: root.bar ? root.bar.shell : null
          fg: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
        }

        ControlTab {
          anchors.fill: parent
          visible: root.tab === "control"
          shell: root.bar ? root.bar.shell : null
          fg: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
        }
      }

      // Persistent footer: avatar + user name under every tab.
      ProfileFooter {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        svc: root.svc
        fg: root.foreground
        fontFamily: root.fontFamily
        onPickRequested: avatarPicker.openFor("")
      }

      // Avatar picker overlay — covers the whole drawer, above every tab.
      FilePicker {
        id: avatarPicker
        anchors.fill: parent
        svc: root.svc
        fg: root.foreground
        fontFamily: root.fontFamily
        applyFile: function(path, zoom, ox, oy) {
          return svc ? svc.setCustomAvatar(path, zoom, ox, oy) : "service unavailable"
        }
      }
    }
  }
}
