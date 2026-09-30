pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
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
  readonly property string glyphMic: "󰍬"
  readonly property string glyphMicMuted: "󰍭"
  readonly property string glyphBri: "󰃟"
  readonly property string glyphCpu: "󰻠"
  readonly property string glyphRam: "󰍛"
  readonly property string glyphDisk: "󰋊"
  readonly property string glyphNet: "󰤢"
  readonly property string glyphRefresh: "󰑐"

  // ---------------------------------------------------------------- wi-fi
  // Quickshell.Networking — the same NetworkManager backend the omarchy
  // network panel uses, so connected/known state is real, and scanning is
  // the device's own scannerEnabled flag (no nmcli parsing).
  readonly property var netDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: {
    for (var i = 0; i < netDevices.length; i++)
      if (netDevices[i] && netDevices[i].type === DeviceType.Wifi) return netDevices[i]
    return null
  }
  readonly property bool wifiOn: Networking.wifiEnabled === true
  readonly property var wifiNetworksRaw: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []

  // Connected first, then strongest signal; hidden SSIDs dropped.
  // Primitives only — omarchy's Model normalizes for the same reason: a
  // live QObject per delegate has segfaulted quickshell on scan churn.
  readonly property var wifiNetworks: {
    var rows = []
    var raw = wifiNetworksRaw
    for (var i = 0; i < raw.length; i++) {
      var n = raw[i]
      if (!n || !n.name || String(n.name) === "") continue
      rows.push({
        ssid: String(n.name),
        connected: n.connected === true,
        known: n.known === true,
        signal: Math.round((Number(n.signalStrength) || 0) * 100),
        security: n.security
      })
    }
    rows.sort(function(a, b) {
      return ((b.connected ? 1 : 0) - (a.connected ? 1 : 0))
        || (b.signal - a.signal)
    })
    return rows.slice(0, 10)
  }

  property string passwordSsid: ""
  property string passwordText: ""

  function netSecured(sec) {
    try { return sec !== undefined && sec !== null && sec !== WifiSecurityType.None }
    catch (e) { return false }
  }
  function netBySsid(ssid) {
    for (var i = 0; i < wifiNetworksRaw.length; i++) {
      var n = wifiNetworksRaw[i]
      if (n && String(n.ssid || "") === ssid) return n
    }
    return null
  }
  function connectNet(ssid) {
    var n = netBySsid(ssid)
    if (!n) return
    if (n.connected === true) { if (typeof n.disconnect === "function") n.disconnect(); return }
    if (netSecured(n.security) && n.known !== true) {
      root.passwordSsid = ssid
      root.passwordText = ""
      return
    }
    if (typeof n.connect === "function") n.connect()
  }
  function submitWifiPassword() {
    var ssid = root.passwordSsid
    if (ssid === "" || root.passwordText.length === 0) return
    var n = netBySsid(ssid)
    if (n && typeof n.connectWithPsk === "function") n.connectWithPsk(root.passwordText)
    root.passwordSsid = ""
    root.passwordText = ""
  }

  // Signal-strength wifi glyph, omarchy's mapping (0-100 -> 5 bars).
  function wifiIconFor(strength) {
    var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    var pct = Math.max(0, Math.min(100, Math.round(Number(strength) || 0)))
    return icons[Math.max(0, Math.min(4, Math.ceil(pct / 20) - 1))]
  }

  // Scanner runs only while the tab is visible (the panel's own release
  // pattern, simplified): enable on show, disable on hide or device swap.
  property var _scannerDevice: null
  function syncScanner() {
    var dev = visible ? wifiDevice : null
    if (_scannerDevice && _scannerDevice !== dev) _scannerDevice.scannerEnabled = false
    _scannerDevice = dev
    if (_scannerDevice) _scannerDevice.scannerEnabled = true
  }

  // ------------------------------------------------------------ bluetooth
  // Quickshell.Bluetooth — real discovery: adapter.discovering drives the
  // BlueZ scan and Bluetooth.devices picks up whatever it finds.
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btPowered: btAdapter ? btAdapter.enabled === true : false
  readonly property bool btScanning: btAdapter ? btAdapter.discovering === true : false

  readonly property var btDevices: {
    var devs = Bluetooth.devices ? Bluetooth.devices.values : []
    var rows = []
    for (var i = 0; i < devs.length; i++) {
      var d = devs[i]
      if (!d || !d.name || String(d.name) === "") continue
      rows.push(d)
    }
    rows.sort(function(a, b) {
      return ((b.connected === true) - (a.connected === true))
        || String(a.name).localeCompare(String(b.name))
    })
    return rows.slice(0, 8)
  }

  function btScan() {
    if (!btAdapter) return
    // Off->on restarts the inquiry even if discovery is already running.
    btAdapter.discovering = false
    btScanDelay.restart()
  }

  Timer { id: btScanDelay; interval: 300; onTriggered: if (root.btAdapter) root.btAdapter.discovering = true }

  // rfkill can hide the adapter from BlueZ entirely; clear it before
  // powering on (the notch uses the same helper).
  Process {
    id: rfkillPower
    command: []
    stderr: StdioCollector { waitForEnd: true }
    onExited: if (root.btAdapter) root.btAdapter.enabled = true
  }

  function btToggleDevice(d) {
    if (!d) return
    if (d.connected === true && typeof d.disconnect === "function") d.disconnect()
    else if (typeof d.connect === "function") d.connect()
  }

  onVisibleChanged: {
    syncScanner()
    dfProc.running = true
  }
  onWifiDeviceChanged: syncScanner()

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
        if (!briReadProc.running) briReadProc.running = true
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

  // /proc samples via one fixed-constant shell line. The XHR file://
  // reads this replaces were unreliable (silently empty across shell
  // restarts); the df process right above proves the process path works.
  Process {
    id: procSampler
    command: ["/bin/sh", "-c",
      "head -n 1 /proc/stat; " +
      "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; " +
      "cat /proc/net/dev"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseProcSample(text, Date.now())
    }
  }

  Timer {
    interval: 2000
    running: root.visible
    repeat: true
    onTriggered: if (!procSampler.running) procSampler.running = true
  }

  function parseProcSample(body, now) {
    var lines = String(body || "").split("\n")

    // CPU: first line is the aggregate counters.
    if (lines.length > 0 && lines[0].indexOf("cpu ") === 0) {
      var f = lines[0].slice(4).trim().split(/\s+/).map(Number)
      if (f.length >= 4 && f.every(isFinite)) {
        var idle = f[3] + (f.length > 4 ? f[4] : 0)
        var total = 0
        for (var j = 0; j < f.length; j++) total += f[j]
        var cpu = { idle: idle, total: total }
        if (root.cpuLast && cpu.total > root.cpuLast.total) {
          var dt = cpu.total - root.cpuLast.total
          var di = cpu.idle - root.cpuLast.idle
          root.cpuPerc = Math.max(0, Math.min(100, Math.round((dt - di) / dt * 100)))
        }
        root.cpuLast = cpu
      }
    }

    // Memory: the grep leaves exactly the two fields we need.
    var memTotal = 0, memAvail = 0
    for (var i = 1; i < lines.length; i++) {
      var m = /^(MemTotal|MemAvailable):\s+(\d+)\s+kB/.exec(lines[i])
      if (!m) continue
      if (m[1] === "MemTotal") memTotal = Number(m[2])
      else memAvail = Number(m[2])
    }
    if (memTotal > 0 && memAvail > 0)
      root.ramPerc = Math.max(0, Math.min(100, Math.round((memTotal - memAvail) / memTotal * 100)))

    // Network throughput: sum rx/tx bytes across every interface but lo.
    var rx = 0, tx = 0
    for (var k = 0; k < lines.length; k++) {
      var p = lines[k].split(":")
      if (p.length < 2) continue
      var iface = p[0].trim()
      if (iface === "lo" || iface === "") continue
      var nf = p[1].trim().split(/\s+/).map(Number)
      if (nf.length < 9 || !isFinite(nf[0]) || !isFinite(nf[8])) continue
      rx += nf[0]; tx += nf[8]
    }
    if (root.netLast && now > root.netLast.at) {
      var dts = (now - root.netLast.at) / 1000
      root.downRate = Math.max(0, (rx - root.netLast.rx) / dts)
      root.upRate = Math.max(0, (tx - root.netLast.tx) / dts)
    }
    root.netLast = { at: now, rx: rx, tx: tx }
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

  // Microphone (default source) — same treatment as the output dial.
  readonly property var mic: Pipewire.defaultAudioSource
  readonly property bool micReady: !!mic && !!mic.audio
  property bool micMuted: micReady ? mic.audio.muted === true : false

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
            glyph: root.wifiOn ? root.glyphWifi : root.glyphWifiOff
            accent: root.accent
            fg: root.fg
            fontFamily: root.fontFamily
            checked: root.wifiOn
            onToggled: function(next) { Networking.wifiEnabled = next }
          }

          QuickToggle {
            glyph: root.glyphBt
            accent: root.accent
            fg: root.fg
            fontFamily: root.fontFamily
            checked: root.btPowered
            onToggled: function(next) {
              if (!root.btAdapter) return
              // A soft rfkill block (fn-key airplane mode) leaves no
              // controller to power on; unblock first, then set power.
              if (next) {
                rfkillPower.command = ["/bin/sh", "-c",
                  "/usr/sbin/rfkill unblock bluetooth; " +
                  "/usr/bin/bluetoothctl power on >/dev/null 2>&1; exit 0"]
                rfkillPower.running = true
              } else {
                root.btAdapter.enabled = false
              }
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
          anchors.centerIn: parent
          spacing: 20

          Dial {
            glyph: root.glyphVol
            mutedGlyph: root.glyphVolMuted
            muted: root.sinkMuted
            value: root.sinkReady ? Number(root.sink.audio.volume) || 0 : 0
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
            glyph: root.glyphMic
            mutedGlyph: root.glyphMicMuted
            muted: root.micMuted
            value: root.micReady ? Number(root.mic.audio.volume) || 0 : 0
            accent: root.accent
            fg: root.fg
            danger: root.danger
            fontFamily: root.fontFamily
            visible: root.micReady
            onActivated: if (root.mic && root.mic.audio) root.mic.audio.muted = !root.mic.audio.muted
            onMoved: function(d) {
              if (!root.mic || !root.mic.audio) return
              var v = Math.max(0, Math.min(1, (Number(root.mic.audio.volume) || 0) + d))
              root.mic.audio.volume = v
            }
          }

          Dial {
            glyph: root.glyphBri
            value: root.briValue
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
          visible: !root.sinkReady && !root.micReady && !(root.briMax > 0 || root.briDisplay >= 0)
          text: "No output devices"
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: 11
        }
      }

      // --------------------------------------------------------------- wi-fi
      SectionHeader {
        title: "WI-FI"
        fg: root.fg
        fontFamily: root.fontFamily
      }

      Pane {
        height: wifiPanel.implicitHeight + 20

        Column {
          id: wifiPanel
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: 10
          spacing: 4

          Text {
            width: parent.width
            visible: !root.wifiOn
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
            visible: root.wifiOn && root.wifiNetworks.length === 0
            text: "Scanning for networks…"
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: 11
            leftPadding: 8
          }

          Repeater {
            model: root.wifiOn ? root.wifiNetworks : []

            delegate: Rectangle {
              id: netRow

              required property var modelData

              width: parent.width
              height: netRow.passwordOpen ? 56 : 38
              radius: 8
              color: Qt.rgba(fg.r, fg.g, fg.b, 0.05)
              Behavior on height { NumberAnimation { duration: 90 } }

              readonly property bool connected: netRow.modelData.connected
              readonly property bool secured: root.netSecured(netRow.modelData.security)
              readonly property bool passwordOpen: root.passwordSsid === netRow.modelData.ssid
              readonly property string statusText: connected ? "Connected" : ""

              Row {
                id: netBody
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.top: parent.top
                anchors.topMargin: 6
                spacing: 10

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.wifiIconFor(netRow.modelData.signal)
                  textFormat: Text.PlainText
                  color: netRow.connected ? root.accent : root.fg
                  opacity: netRow.connected ? 1.0 : 0.7
                  font.family: root.fontFamily
                  font.pixelSize: 16
                }

                Column {
                  width: netBody.width - 26 - netLock.width - netBody.spacing * 2 - 30
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    width: parent.width
                    text: String(netRow.modelData.ssid || "")
                    textFormat: Text.PlainText
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.bold: netRow.connected
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    visible: netRow.statusText !== ""
                    text: netRow.statusText
                    textFormat: Text.PlainText
                    color: root.fg
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: 10
                  }
                }

                Text {
                  id: netLock
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰌾"
                  textFormat: Text.PlainText
                  visible: netRow.secured && !netRow.connected
                  color: root.fg
                  opacity: 0.4
                  font.family: root.fontFamily
                  font.pixelSize: 12
                }
              }

              // Inline passphrase prompt, omarchy-panel style: opens on a
              // secured, unknown network click; Enter connects.
              QQC2.TextField {
                visible: netRow.passwordOpen
                anchors.left: parent.left
                anchors.leftMargin: 46
                anchors.right: parent.right
                anchors.rightMargin: 46
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                echoMode: TextInput.Password
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.fg
                placeholderText: "password"
                onTextChanged: root.passwordText = text
                onAccepted: root.submitWifiPassword()
                Component.onCompleted: if (netRow.passwordOpen) forceActiveFocus()
              }

              MouseArea {
                id: netMa
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: netBody.height + 12
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.passwordSsid = ""
                  root.connectNet(netRow.modelData.ssid)
                }
              }
            }
          }
        }
      }

      // ---------------------------------------------------------- bluetooth
      SectionHeader {
        title: "BLUETOOTH"
        fg: root.fg
        fontFamily: root.fontFamily

        Text {
          text: root.glyphRefresh
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: 13
          color: root.fg
          opacity: btRefreshMa.containsMouse ? 1.0 : 0.6

          MouseArea {
            id: btRefreshMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.btScan()
          }
        }
      }

      Pane {
        height: btPanel.implicitHeight + 20

        Column {
          id: btPanel
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: 10
          spacing: 4

          Text {
            width: parent.width
            visible: !root.btPowered
            text: "Bluetooth is off"
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: 11
            leftPadding: 8
          }

          Text {
            width: parent.width
            visible: root.btPowered && root.btScanning && root.btDevices.length === 0
            text: "Scanning…"
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: 11
            leftPadding: 8
          }

          Text {
            width: parent.width
            visible: root.btPowered && !root.btScanning && root.btDevices.length === 0
            text: "No devices found"
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: 11
            leftPadding: 8
          }

          Repeater {
            model: root.btPowered ? root.btDevices : []

            delegate: Rectangle {
              id: btRow

              required property var modelData

              width: parent.width
              height: 38
              radius: 8
              color: btMa.containsMouse ? Qt.rgba(fg.r, fg.g, fg.b, 0.08) : Qt.rgba(fg.r, fg.g, fg.b, 0.05)

              readonly property bool connected: btRow.modelData.connected === true
              readonly property bool paired: btRow.modelData.paired === true

              Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyphBt
                textFormat: Text.PlainText
                color: btRow.connected ? root.accent : root.fg
                opacity: btRow.connected ? 1.0 : 0.6
                font.family: root.fontFamily
                font.pixelSize: 14
              }

              Column {
                anchors.left: parent.left
                anchors.leftMargin: 34
                anchors.right: btStatus.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                  width: parent.width
                  text: String(btRow.modelData.name || "")
                  textFormat: Text.PlainText
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  font.bold: btRow.connected
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: btRow.modelData.batteryAvailable === true
                  text: "battery " + Math.round(Number(btRow.modelData.battery) * 100) + "%"
                  textFormat: Text.PlainText
                  color: root.fg
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: 10
                }
              }

              Text {
                id: btStatus
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: btRow.connected ? "connected" : (btRow.paired ? "paired" : "")
                textFormat: Text.PlainText
                color: btRow.connected ? root.accent : root.fg
                opacity: btRow.connected ? 1.0 : 0.5
                font.family: root.fontFamily
                font.pixelSize: 10
                font.bold: btRow.connected
              }

              MouseArea {
                id: btMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: btRow.paired || btRow.connected ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.btToggleDevice(btRow.modelData)
              }
            }
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
