pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Control tab, rice-control-center style: first-party quick toggles (do not
// disturb, night light, stay awake), radio toggles with device lists
// (Wi-Fi via nmcli, Bluetooth via bluetoothctl), output sliders (master
// volume through PipeWire, display brightness through brightnessctl) and
// live system readouts (CPU/RAM/net from /proc, disk from df).
Rectangle {
  id: root

  color: "transparent"

  property var shell: null        // bar.shell, for first-party service access
  property color fg: Color.foreground
  property color accent: Color.accent
  property color danger: Color.urgent
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.5)

  // First-party service proxies. Under replacement bars serviceFor() is a
  // null stub, so fall through to the allowlisted firstPartyServiceFor()
  // exactly like MediaTab does for omarchy.media.
  function firstParty(id) {
    if (!shell) return null
    var viaHost = typeof shell.serviceFor === "function" ? shell.serviceFor(id) : null
    if (viaHost) return viaHost
    return typeof shell.firstPartyServiceFor === "function" ? shell.firstPartyServiceFor(id) : null
  }
  readonly property var notifService: firstParty("omarchy.notifications")
  readonly property var nightService: firstParty("omarchy.nightlight")
  readonly property var idleService: firstParty("omarchy.idle")

  // ---------------------------------------------------------------- glyphs
  readonly property string glyphDnd: "󰂛"
  readonly property string glyphNight: "󰖔"
  readonly property string glyphIdle: "󰌾"
  readonly property string glyphWifi: "󰤨"
  readonly property string glyphWifiOff: "󰤭"
  readonly property string glyphBt: "󰂯"
  readonly property string glyphVol: "󰕾"
  readonly property string glyphVolMuted: "󰸈"
  readonly property string glyphBri: "󰃟"
  readonly property string glyphCpu: "󰻠"
  readonly property string glyphRam: "󰍛"
  readonly property string glyphDisk: "󰋊"
  readonly property string glyphNet: "󰤢"
  readonly property string glyphRefresh: "󰑐"

  // ------------------------------------------------------------ network/BT
  property string wifiState: "unknown"        // enabled | disabled | unknown
  property var wifiNetworks: []
  property string wifiError: ""
  property bool btPowered: false
  property var btDevices: []
  property string btError: ""

  // Wi-Fi list rows: nmcli -t escapes ":" as "\:"; swap for a sentinel.
  function parseWifiList(raw) {
    var rows = []
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line === "") continue
      var parts = line.replace(/\\:/g, "\u0001").split(":")
      if (parts.length < 3) continue
      var ssid = parts[1].replace(/\u0001/g, ":").trim()
      if (ssid === "") continue
      var sig = Math.max(0, Math.min(100, Math.round(Number(parts[2]) || 0)))
      rows.push({
        ssid: ssid.slice(0, 32),
        signal: sig,
        active: parts[0] === "*",
        security: parts.length > 3 ? parts[3].replace(/\u0001/g, ":") : ""
      })
    }
    rows.sort(function(a, b) { return (b.active - a.active) || (b.signal - a.signal) })
    return rows.slice(0, 8)
  }

  function parseBtDevices(raw) {
    var rows = []
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length && rows.length < 6; i++) {
      var line = lines[i].trim()
      if (line.indexOf("Device ") !== 0) continue
      var rest = line.slice(7)
      var sp = rest.indexOf(" ")
      if (sp <= 0) continue
      var mac = rest.slice(0, sp)
      if (!/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(mac)) continue
      rows.push({ mac: mac, name: rest.slice(sp + 1).slice(0, 40) })
    }
    return rows
  }

  function refreshWifi() {
    if (!wifiStateProc.running) wifiStateProc.running = true
    if (!wifiListProc.running) wifiListProc.running = true
  }
  function refreshBt() {
    if (!btStateProc.running) btStateProc.running = true
    if (!btListProc.running) btListProc.running = true
  }
  function refreshBrightness() {
    if (!briReadProc.running) briReadProc.running = true
  }

  onVisibleChanged: {
    if (!visible) return
    refreshWifi()
    refreshBt()
    refreshBrightness()
    dfProc.running = true
  }

  Process {
    id: wifiStateProc
    command: ["/usr/sbin/nmcli", "-t", "-f", "WIFI", "radio"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.wifiState = text.trim() === "disabled" ? "disabled" : (text.trim() === "enabled" ? "enabled" : "unknown")
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.wifiError = "nmcli failed"
    }
  }

  Process {
    id: wifiListProc
    command: ["/usr/sbin/nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"]
    stderr: StdioCollector { waitForEnd: true }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.wifiNetworks = root.parseWifiList(text)
        root.wifiError = ""
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.wifiError = "scan failed"
    }
  }

  Process {
    id: wifiToggleProc
    command: []
    stderr: StdioCollector { waitForEnd: true }
    onExited: root.refreshWifi()
  }

  Process {
    id: btStateProc
    command: ["/usr/bin/bluetoothctl", "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var m = /^[\s]*Powered: (.+)$/.exec(lines[i])
          if (m) root.btPowered = m[1].trim() === "yes"
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        // No controller while rfkill-blocked; show the real (off) state.
        root.btPowered = false
        root.btError = "bluetoothctl failed"
      }
    }
  }

  Process {
    id: btListProc
    command: ["/usr/bin/bluetoothctl", "devices", "Connected"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.btDevices = root.parseBtDevices(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.btError = "device list failed"
    }
  }

  Process {
    id: btToggleProc
    command: []
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.btError = "could not power bluetooth"
      root.refreshBt()
    }
  }

  // ------------------------------------------------------------- brightness
  property int briCur: -1
  property int briMax: 0
  property real briDisplay: -1      // live drag position until the next read
  readonly property real briValue: briDisplay >= 0 ? briDisplay : (briMax > 0 && briCur >= 0 ? Math.min(1, briCur / briMax) : 0)

  Process {
    id: briReadProc
    command: ["/usr/sbin/brightnessctl", "-m"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Machine format is device,<class>,<cur>,<NN>%,<max> — anchor on
        // the percent field rather than fixed positions.
        var parts = text.trim().split(",")
        var pctIdx = -1
        for (var i = 0; i < parts.length; i++)
          if (pctIdx === -1 && parts[i].charAt(parts[i].length - 1) === "%") pctIdx = i
        if (pctIdx < 1 || pctIdx + 1 >= parts.length) return
        var cur = Math.round(Number(parts[pctIdx - 1]) || 0)
        var max = Math.round(Number(parts[pctIdx + 1]) || 0)
        if (max <= 0) return
        root.briCur = cur
        root.briMax = max
        root.briDisplay = -1
      }
    }
  }

  property real briQueued: -1
  Process {
    id: briSetProc
    command: []
    onExited: {
      if (root.briQueued >= 0) {
        var v = root.briQueued
        root.briQueued = -1
        root.setBrightness(v)
      } else {
        root.refreshBrightness()
      }
    }
  }

  function setBrightness(v) {
    if (!root.visible) return
    root.briDisplay = v
    if (briSetProc.running) { briQueued = v; return }
    briSetProc.command = ["/usr/sbin/brightnessctl", "set", Math.max(1, Math.round(v * 100)) + "%"]
    briSetProc.running = true
  }

  // -------------------------------------------------------------- df (disk)
  property string diskText: ""
  Timer {
    interval: 30000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: dfProc.running = true
  }
  Process {
    id: dfProc
    // One fixed command for both disk usage and uptime (constant string —
    // nothing interpolated).
    command: ["/bin/sh", "-c", "df -B1 --output=used,size / | tail -n1; cat /proc/uptime"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.trim().split("\n")
        if (lines.length >= 1) {
          var f = lines[0].trim().split(/\s+/)
          if (f.length >= 2) {
            var used = Number(f[0]), size = Number(f[1])
            if (isFinite(used) && isFinite(size) && size > 0)
              root.diskText = root.fmtBytes(used) + " / " + root.fmtBytes(size)
          }
        }
        if (lines.length >= 2) {
          var sec = Number(lines[lines.length - 1].trim().split(" ")[0])
          if (isFinite(sec) && sec > 0) {
            var d = Math.floor(sec / 86400)
            var h = Math.floor((sec % 86400) / 3600)
            root.uptimeText = d > 0
              ? "up " + d + "d " + h + "h"
              : "up " + h + "h " + Math.floor((sec % 3600) / 60) + "m"
          }
        }
      }
    }
  }

  // -------------------------------------------------- /proc CPU, RAM, net
  property real cpuPerc: 0
  property real ramPerc: 0
  property real downRate: 0        // bytes/s
  property real upRate: 0
  property string uptimeText: ""
  property var cpuLast: null
  property var netLast: null

  Timer {
    interval: 2000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleProc()
  }

  function readProcFile(path, cb) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) cb(xhr.status === 200 ? xhr.responseText : "")
    }
    try { xhr.open("GET", "file://" + path); xhr.send() } catch (e) { cb("") }
  }

  function sampleProc() {
    readProcFile("/proc/stat", function(body) {
      var lines = String(body || "").split("\n")
      var cpu = null
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].indexOf("cpu ") === 0) {
          var f = lines[i].slice(4).trim().split(/\s+/).map(Number)
          if (f.length >= 4 && f.every(isFinite)) {
            var idle = f[3] + (f.length > 4 ? f[4] : 0)
            var total = 0
            for (var j = 0; j < f.length; j++) total += f[j]
            cpu = { idle: idle, total: total }
          }
          break
        }
      }
      if (cpu && root.cpuLast && cpu.total > root.cpuLast.total) {
        var dt = cpu.total - root.cpuLast.total
        var di = cpu.idle - root.cpuLast.idle
        root.cpuPerc = Math.max(0, Math.min(100, Math.round((dt - di) / dt * 100)))
      }
      if (cpu) root.cpuLast = cpu
    })

    readProcFile("/proc/meminfo", function(body) {
      var total = 0, avail = 0
      var lines = String(body || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = /^(MemTotal|MemAvailable):\s+(\d+)\s+kB/.exec(lines[i])
        if (!m) continue
        if (m[1] === "MemTotal") total = Number(m[2])
        else avail = Number(m[2])
      }
      if (total > 0 && avail > 0)
        root.ramPerc = Math.max(0, Math.min(100, Math.round((total - avail) / total * 100)))
    })

    readProcFile("/proc/net/dev", function(body) {
      var rx = 0, tx = 0
      var lines = String(body || "").split("\n")
      for (var i = 2; i < lines.length; i++) {
        var p = lines[i].split(":")
        if (p.length < 2) continue
        var iface = p[0].trim()
        if (iface === "lo" || iface === "") continue
        var f = p[1].trim().split(/\s+/).map(Number)
        if (f.length < 9 || !isFinite(f[0]) || !isFinite(f[8])) continue
        rx += f[0]; tx += f[8]
      }
      var now = Date.now()
      if (root.netLast && now > root.netLast.at) {
        var dt = (now - root.netLast.at) / 1000
        root.downRate = Math.max(0, (rx - root.netLast.rx) / dt)
        root.upRate = Math.max(0, (tx - root.netLast.tx) / dt)
      }
      root.netLast = { at: now, rx: rx, tx: tx }
    })
  }

  function fmtBytes(n) {
    var b = Math.max(0, Number(n) || 0)
    if (b >= 1024 * 1024 * 1024) return (b / (1024 * 1024 * 1024)).toFixed(1) + "G"
    if (b >= 1024 * 1024) return (b / (1024 * 1024)).toFixed(0) + "M"
    if (b >= 1024) return (b / 1024).toFixed(0) + "K"
    return Math.round(b) + "B"
  }

  function fmtRate(bps) {
    var b = Math.max(0, Number(bps) || 0)
    if (b >= 1024 * 1024) return (b / (1024 * 1024)).toFixed(1) + "M"
    if (b >= 1024) return (b / 1024).toFixed(0) + "K"
    return Math.round(b) + ""
  }

  // --------------------------------------------------------------- master out
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool sinkReady: !!sink && !!sink.audio
  property bool sinkMuted: sinkReady ? sink.audio.muted === true : false

  // `audio` (volume/mute) only populates once the sink is tracked — and the
  // registry itself only populates when a tracker watches the raw node list.
  PwObjectTracker { objects: Pipewire.nodes ? Pipewire.nodes.values : [] }

  // ------------------------------------------------------------ section bits
  // Ruixen pattern: each section is a tonal pane (white 0.06, radius 10)
  // holding black sub-panels (radius 8) — the grey only ever shows as the
  // gutter around/between the black panels.
  component Pane: Rectangle {
    // The notch's card: transparent fill + 1.5px white-0.14 outline;
    // the quick-controls pane overrides to 2.5px / radius 14.
    property real borderWidth: 1.5
    width: parent ? parent.width : 0
    radius: 10
    color: "transparent"
    border.color: Qt.rgba(fg.r, fg.g, fg.b, 0.14)
    border.width: borderWidth
    clip: true
    height: childrenRect.height + 16
  }

  component BlackPanel: Rectangle {
    width: parent ? parent.width - 16 : 0
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    radius: 8
    color: Qt.rgba(fg.r, fg.g, fg.b, 0.05)
  }

  component SysPanel: Rectangle {
    id: chip

    required property string icon
    required property string label
    required property string value

    // Two panels per Grid row; parent is the Grid.
    width: parent ? (parent.width - (parent.columnSpacing || 0)) / 2 : 0
    color: Qt.rgba(fg.r, fg.g, fg.b, 0.05)
    radius: 8
    height: 48

    Row {
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.icon
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: 16
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
          text: chip.label
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: 9
        }

        Text {
          text: chip.value
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: 12
          font.bold: true
          elide: Text.ElideRight
          width: Math.min(implicitWidth, 110)
        }
      }
    }
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
      spacing: Style.space(12)

      // ------------------------------------------------------ quick toggles
      SectionHeader {
        title: "QUICK TOGGLES"
        fg: root.fg
        fontFamily: root.fontFamily
      }

      Pane {
        borderWidth: 2.5
        radius: 14
        height: 60

        Row {
          id: togglesRow
          anchors.centerIn: parent
          spacing: 8

          QuickToggle {
            glyph: root.glyphDnd
            accent: root.accent
            fg: root.fg
            fontFamily: root.fontFamily
            checked: root.notifService ? root.notifService.doNotDisturb === true : false
            onToggled: function(next) { if (root.notifService) root.notifService.setDoNotDisturb(next) }
          }

          QuickToggle {
            glyph: root.glyphNight
            accent: root.accent
            fg: root.fg
            fontFamily: root.fontFamily
            checked: root.nightService ? root.nightService.enabled === true : false
            onToggled: function(next) { if (root.nightService) root.nightService.setNightlight(next) }
          }

          QuickToggle {
            glyph: root.glyphIdle
            accent: root.accent
            fg: root.fg
            fontFamily: root.fontFamily
            checked: root.idleService ? root.idleService.stayAwake === true : false
            onToggled: function(next) { if (root.idleService) root.idleService.setIdleEnabled(!next) }
          }

          QuickToggle {
            glyph: root.wifiState === "enabled" ? root.glyphWifi : root.glyphWifiOff
            accent: root.accent
            fg: root.fg
            fontFamily: root.fontFamily
            checked: root.wifiState === "enabled"
            onToggled: function(next) {
              if (root.wifiState !== "enabled" && root.wifiState !== "disabled") return
              wifiToggleProc.command = ["/usr/sbin/nmcli", "radio", "wifi", next ? "on" : "off"]
              wifiToggleProc.running = true
            }
          }

          QuickToggle {
            glyph: root.glyphBt
            accent: root.accent
            fg: root.fg
            fontFamily: root.fontFamily
            checked: root.btPowered
            onToggled: function(next) {
              root.btError = ""
              if (next) {
                // A soft rfkill block (fn-key airplane mode) leaves bluetoothctl
                // with no controller to power on; unblock first, then retry until
                // the adapter registers with bluetoothd.
                btToggleProc.command = ["/bin/sh", "-c",
                  "/usr/sbin/rfkill unblock bluetooth; n=0; " +
                  "until /usr/bin/bluetoothctl power on 2>/dev/null; do " +
                  "n=$((n+1)); [ $n -ge 20 ] && exit 1; /usr/sbin/sleep 0.3; done"]
              } else {
                btToggleProc.command = ["/usr/bin/bluetoothctl", "power", "off"]
              }
              btToggleProc.running = true
            }
          }
        }
      }

      // ------------------------------------------------------------- output
      SectionHeader {
        title: "OUTPUT"
        fg: root.fg
        fontFamily: root.fontFamily
      }

      Pane {
        height: dialsRow.implicitHeight + 20

        Row {
          id: dialsRow
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: 10
          spacing: 34

          Dial {
            glyph: root.glyphVol
            mutedGlyph: root.glyphVolMuted
            muted: root.sinkMuted
            caption: Math.round((root.sinkReady ? Number(root.sink.audio.volume) || 0 : 0) * 100) + "%"
            accent: root.accent
            fg: root.fg
            danger: root.danger
            fontFamily: root.fontFamily
            visible: root.sinkReady
            onActivated: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
            onMoved: function(d) {
              if (!root.sink || !root.sink.audio) return
              var v = Math.max(0, Math.min(1, (Number(root.sink.audio.volume) || 0) + d))
              root.sink.audio.volume = v
            }
          }

          Dial {
            glyph: root.glyphBri
            caption: Math.round(Math.max(0, Math.min(1, root.briValue)) * 100) + "%"
            accent: root.accent
            fg: root.fg
            fontFamily: root.fontFamily
            visible: root.briMax > 0 || root.briDisplay >= 0
            onMoved: function(d) {
              root.setBrightness(Math.max(0.01, Math.min(1, root.briValue + d)))
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: !root.sinkReady && !(root.briMax > 0 || root.briDisplay >= 0)
          text: "No output devices"
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: 11
        }
      }

      // ------------------------------------------------------------- network
      SectionHeader {
        title: "NETWORK"
        fg: root.fg
        fontFamily: root.fontFamily

        Text {
          text: root.glyphRefresh
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: 13
          color: root.fg
          opacity: netRefreshMa.containsMouse ? 1.0 : 0.6

          MouseArea {
            id: netRefreshMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.refreshWifi(); root.refreshBt() }
          }
        }
      }

      Pane {
        height: netPanel.implicitHeight + 20

        Column {
          id: netPanel
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: 10
          spacing: 4

          BlackPanel {
            height: wifiCol.implicitHeight > 0 ? wifiCol.implicitHeight + 8 : 0
            visible: wifiCol.implicitHeight > 0

            Column {
              id: wifiCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: 4
              spacing: 2
              visible: root.wifiState === "enabled" && root.wifiNetworks.length > 0

              Repeater {
                model: root.wifiNetworks

                delegate: Rectangle {
                  id: netRow

                  required property var modelData

                  width: parent.width
                  height: 28
                  radius: 6
                  color: netMa.containsMouse ? Qt.rgba(fg.r, fg.g, fg.b, 0.08) : "transparent"

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.glyphWifi
                    textFormat: Text.PlainText
                    color: netRow.modelData.active ? root.accent : root.fg
                    opacity: netRow.modelData.active ? 1.0 : 0.55
                    font.family: root.fontFamily
                    font.pixelSize: 12
                  }

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 30
                    anchors.right: signalText.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: netRow.modelData.ssid
                    textFormat: Text.PlainText
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                  }

                  Text {
                    id: signalText
                    anchors.right: activeTick.visible ? activeTick.left : parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: netRow.modelData.signal + "%"
                    textFormat: Text.PlainText
                    color: root.fg
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: 10
                  }

                  Text {
                    id: activeTick
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰄬"
                    textFormat: Text.PlainText
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    visible: netRow.modelData.active
                  }

                  MouseArea {
                    id: netMa
                    anchors.fill: parent
                    hoverEnabled: true
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.wifiState === "disabled"
            text: "Wi-Fi is off"
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: 11
            leftPadding: 8
          }

          Text {
            width: parent.width
            visible: root.wifiState === "enabled" && root.wifiNetworks.length === 0 && !wifiListProc.running
            text: "No networks found"
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: 11
            leftPadding: 8
          }

          Text {
            width: parent.width
            visible: root.wifiError !== ""
            text: root.wifiError
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: 11
            leftPadding: 8
          }

          // Bluetooth devices — one black panel listing connected devices.
          BlackPanel {
            height: root.btPowered && root.btDevices.length > 0 ? btCol.implicitHeight + 8 : 0
            visible: root.btPowered && root.btDevices.length > 0

            Column {
              id: btCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: 4
              spacing: 2

              Repeater {
                model: root.btDevices

                delegate: Rectangle {
                  id: btRow

                  required property var modelData

                  width: parent.width
                  height: 28
                  radius: 6
                  color: "transparent"

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.glyphBt
                    textFormat: Text.PlainText
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: 12
                  }

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 30
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: btRow.modelData.name
                    textFormat: Text.PlainText
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.btPowered && root.btDevices.length === 0
            text: "No connected devices"
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: 11
            leftPadding: 8
          }

          Text {
            width: parent.width
            visible: root.btError !== ""
            text: root.btError
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: 11
            leftPadding: 8
          }
        }
      }

      // -------------------------------------------------------------- system
      SectionHeader {
        title: "SYSTEM"
        fg: root.fg
        fontFamily: root.fontFamily
      }

      Pane {
        height: sysGrid.implicitHeight + 30

        Grid {
          id: sysGrid
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: 10
          width: parent.width - 16
          columns: 2
          columnSpacing: 8
          rowSpacing: 8

          SysPanel { icon: root.glyphCpu; label: "CPU"; value: root.cpuPerc + "%" }
          SysPanel { icon: root.glyphRam; label: "MEMORY"; value: root.ramPerc + "%" }
          SysPanel { icon: root.glyphDisk; label: "DISK /"; value: root.diskText === "" ? "…" : root.diskText }
          SysPanel {
            icon: root.glyphNet
            label: "NETWORK"
            value: "↓" + root.fmtRate(root.downRate) + " ↑" + root.fmtRate(root.upRate)
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 8
          visible: root.uptimeText !== ""
          text: root.uptimeText
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: 10
        }
      }

      // Breathing room at the bottom.
      Item { width: parent.width; height: Style.space(4) }
    }
  }
}
