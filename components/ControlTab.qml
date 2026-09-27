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
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(fg, 1.55)

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
  component HeaderRow: Item {
    width: parent ? parent.width : 0
    height: hdr.implicitHeight

    required property string title
    property bool showRefresh: false
    signal refreshed()

    PanelSectionHeader {
      id: hdr
      anchors.left: parent.left
      text: parent.title
      foreground: root.fg
      fontFamily: root.fontFamily
    }

    Text {
      visible: parent.showRefresh
      anchors.right: parent.right
      anchors.baseline: hdr.baseline
      text: root.glyphRefresh
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      color: root.fg
      opacity: refreshMa.containsMouse ? 1.0 : 0.7

      MouseArea {
        id: refreshMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: parent.parent.refreshed()
      }
    }
  }

  component SysChip: Rectangle {
    id: chip

    required property string icon
    required property string label
    required property string value

    // Two chips per Grid row; parent is the Grid.
    width: parent ? (parent.width - (parent.columnSpacing || 0)) / 2 : 0
    color: Util.alpha(root.fg, 0.05)
    radius: Style.space(6)
    height: Style.space(46)

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.icon
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          text: chip.label
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          text: chip.value
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          width: Math.min(implicitWidth, Style.space(100))
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
      HeaderRow { title: "QUICK TOGGLES" }

      QuickToggle {
        glyph: root.glyphDnd
        label: "Do not disturb"
        fg: root.fg
        fontFamily: root.fontFamily
        checked: root.notifService ? root.notifService.doNotDisturb === true : false
        onToggled: function(next) { if (root.notifService) root.notifService.setDoNotDisturb(next) }
      }

      QuickToggle {
        glyph: root.glyphNight
        label: "Night light"
        fg: root.fg
        fontFamily: root.fontFamily
        checked: root.nightService ? root.nightService.enabled === true : false
        onToggled: function(next) { if (root.nightService) root.nightService.setNightlight(next) }
      }

      QuickToggle {
        glyph: root.glyphIdle
        label: "Stay awake"
        fg: root.fg
        fontFamily: root.fontFamily
        checked: root.idleService ? root.idleService.stayAwake === true : false
        onToggled: function(next) { if (root.idleService) root.idleService.setIdleEnabled(!next) }
      }

      QuickToggle {
        glyph: root.wifiState === "enabled" ? root.glyphWifi : root.glyphWifiOff
        label: "Wi-Fi"
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
        label: "Bluetooth"
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

      // ------------------------------------------------------------- output
      HeaderRow { title: "OUTPUT" }

      // Master volume
      Row {
        width: parent.width
        visible: root.sinkReady
        spacing: Style.space(10)
        leftPadding: Style.space(2)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.sinkMuted ? root.glyphVolMuted : root.glyphVol
          textFormat: Text.PlainText
          color: root.sinkMuted ? root.dim : root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
          }
        }

        HSlider {
          id: volSlider
          width: parent.width - Style.space(64)
          anchors.verticalCenter: parent.verticalCenter
          fg: root.fg
          value: root.sinkReady ? Number(root.sink.audio.volume) || 0 : 0
          onMoved: function(v) { if (root.sink && root.sink.audio) root.sink.audio.volume = v }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(40)
          text: Math.round((root.sinkReady ? Number(root.sink.audio.volume) || 0 : 0) * 100) + "%"
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
        }
      }

      // Brightness
      Row {
        width: parent.width
        visible: root.briMax > 0 || root.briDisplay >= 0
        spacing: Style.space(10)
        leftPadding: Style.space(2)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.glyphBri
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }

        HSlider {
          width: parent.width - Style.space(64)
          anchors.verticalCenter: parent.verticalCenter
          fg: root.fg
          value: root.briValue
          onMoved: function(v) { root.setBrightness(v) }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(40)
          text: Math.round(Math.max(0, Math.min(1, root.briValue)) * 100) + "%"
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
        }
      }

      // ------------------------------------------------------------- network
      HeaderRow {
        title: "NETWORK"
        showRefresh: true
        onRefreshed: { root.refreshWifi(); root.refreshBt() }
      }

      Text {
        width: parent.width
        visible: root.wifiError !== ""
        text: root.wifiError
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Wi-Fi networks
      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: root.wifiState === "enabled"

        Repeater {
          model: root.wifiNetworks

          delegate: Rectangle {
            id: netRow

            required property var modelData

            width: parent.width
            height: Style.space(30)
            radius: Style.space(6)
            color: netMa.containsMouse ? Style.hoverFill : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.glyphWifi
              textFormat: Text.PlainText
              color: netRow.modelData.active ? Color.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(30)
              anchors.right: signalText.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: netRow.modelData.ssid
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              id: signalText
              anchors.right: activeTick.visible ? activeTick.left : parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: netRow.modelData.signal + "%"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              id: activeTick
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "󰄬"
              textFormat: Text.PlainText
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
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

      Text {
        width: parent.width
        visible: root.wifiState === "disabled"
        text: "Wi-Fi is off"
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        leftPadding: Style.space(8)
      }

      Text {
        width: parent.width
        visible: root.wifiState === "enabled" && root.wifiNetworks.length === 0 && !wifiListProc.running
        text: "No networks found"
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        leftPadding: Style.space(8)
      }

      Text {
        width: parent.width
        visible: root.btError !== ""
        text: root.btError
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Bluetooth devices
      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: root.btPowered && root.btDevices.length > 0

        Repeater {
          model: root.btDevices

          delegate: Rectangle {
            id: btRow

            required property var modelData

            width: parent.width
            height: Style.space(30)
            radius: Style.space(6)
            color: "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.glyphBt
              textFormat: Text.PlainText
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(30)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: btRow.modelData.name
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.btPowered && root.btDevices.length === 0
        text: "No connected devices"
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        leftPadding: Style.space(8)
      }

      // -------------------------------------------------------------- system
      HeaderRow { title: "SYSTEM" }

      Grid {
        width: parent.width
        columns: 2
        columnSpacing: Style.space(8)
        rowSpacing: Style.space(8)

        SysChip { icon: root.glyphCpu; label: "CPU"; value: root.cpuPerc + "%" }
        SysChip { icon: root.glyphRam; label: "MEMORY"; value: root.ramPerc + "%" }
        SysChip { icon: root.glyphDisk; label: "DISK /"; value: root.diskText === "" ? "…" : root.diskText }
        SysChip {
          icon: root.glyphNet
          label: "NETWORK"
          value: "↓" + root.fmtRate(root.downRate) + " ↑" + root.fmtRate(root.upRate)
        }
      }

      Text {
        width: parent.width
        visible: root.uptimeText !== ""
        text: root.uptimeText
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        leftPadding: Style.space(2)
      }

      // Breathing room at the bottom.
      Item { width: parent.width; height: Style.space(4) }
    }
  }
}
