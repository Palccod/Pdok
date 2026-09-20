pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Shared per-shell service: notification history (from omarchy.notifications'
// on-disk history), read/unread tracking, and slow system metrics sampling.
// Bar widgets (one per monitor) bind to this instead of each sampling /proc.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool initialized: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omarchy"

  // ---- notification history ----------------------------------------------
  // The directory IS the history (same store omarchy.notifications replays
  // from); we only read it. Unread = entries newer than lastSeen.
  readonly property string historyDir: stateDir + "/notifications/history/"
  readonly property int maxEntries: 80

  property var entries: []
  property double lastSeen: 0
  property bool stateLoaded: false

  readonly property int unreadCount: {
    var count = 0
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].timestamp > lastSeen) count++
      else break
    }
    return count
  }

  // Notification bodies arrive in inconsistent shapes depending on the app:
  // KDE Connect sends double-escaped HTML ("&lt;br/&gt;") and literal "\n"
  // sequences, others send real newlines or raw tags. Normalize to plain
  // text with real line breaks — rendered with Text.PlainText afterwards,
  // so nothing here can inject formatting.
  function cleanText(raw) {
    var s = String(raw === undefined || raw === null ? "" : raw)
    s = s.replace(/&lt;/g, "<")
    s = s.replace(/&gt;/g, ">")
    s = s.replace(/&quot;/g, "\"")
    s = s.replace(/&#0?39;/g, "'")
    s = s.replace(/&apos;/g, "'")
    s = s.replace(/&amp;/g, "&")
    s = s.replace(/<br\s*\/?>/gi, "\n")
    s = s.replace(/<[^>]*>/g, "")
    s = s.split("\\n").join("\n")
    s = s.replace(/\n{3,}/g, "\n\n")
    return s.trim()
  }

  // ---- system metrics ------------------------------------------------------
  property real cpuPercent: 0
  property real memPercent: 0
  property string memText: ""
  property real netDownKb: 0
  property real netUpKb: 0
  property string uptimeText: ""
  property bool hasBattery: false
  property int batteryPercent: 0
  property bool batteryCharging: false
  property real diskPercent: 0
  property string diskText: ""

  property double _cpuPrevIdle: -1
  property double _cpuPrevTotal: 0
  property double _netPrevRx: -1
  property double _netPrevTx: 0

  // Battery device paths, filled in after whitelisting the contents of
  // /sys/class/power_supply (only BAT* and AC* names are accepted).
  property string _batCapPath: ""
  property string _batAcPath: ""

  Component.onCompleted: {
    mkdirProc.running = true
    powerListProc.running = true
    root.refresh()
    root.sampleMetrics()
    root.sampleDisk()
  }

  function refresh() {
    if (listProc.running) return
    listProc.command = ["/usr/bin/ls", "-1t", root.historyDir]
    listProc.running = true
  }

  // Mark everything at or older than `timestamp` as read. The read marker
  // is a single watermark (same model as omarchy.notifications' store), so
  // clicking one entry also clears older unread ones; newer entries stay
  // unread.
  function markReadUpTo(timestamp) {
    var ts = Number(timestamp)
    if (!isFinite(ts) || ts <= root.lastSeen) return
    root.lastSeen = ts
    if (root.stateLoaded)
      stateFile.setText(JSON.stringify({ lastSeen: root.lastSeen }))
  }

  function markAllRead() {
    root.markReadUpTo(Date.now())
  }

  // ---- state file ----------------------------------------------------------

  FileView {
    id: stateFile
    path: root.stateDir + "/pdok.json"
    atomicWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        if (d && isFinite(Number(d.lastSeen))) root.lastSeen = Number(d.lastSeen)
      } catch (e) {}
      root.stateLoaded = true
    }
    onLoadFailed: root.stateLoaded = true
  }

  Process {
    id: mkdirProc
    command: ["/usr/bin/mkdir", "-p", root.stateDir]
  }

  // ---- notification history reading (two fixed-argv steps) ----------------

  Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: {
        var files = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim()
          if (name.length === 0) continue
          if (!/^[0-9]+-[0-9]+\.json$/.test(name)) continue
          files.push(name)
          if (files.length >= root.maxEntries) break
        }
        if (files.length === 0) {
          root.entries = []
          return
        }
        if (readProc.running) return
        var argv = ["/usr/bin/jq", "-s", "-c", "."]
        for (var j = 0; j < files.length; j++) argv.push(root.historyDir + files[j])
        readProc.command = argv
        readProc.running = true
      }
    }
  }

  Process {
    id: readProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        if (!Array.isArray(data)) return
        var clean = []
        for (var i = 0; i < data.length; i++) {
          var e = data[i]
          if (!e || typeof e !== "object") continue
          var ts = Number(e.timestamp)
          var urg = Math.round(Number(e.urgency))
          clean.push({
            id: String(e.id !== undefined ? e.id : i),
            app: cleanText(e.app),
            appIcon: typeof e.appIcon === "string" ? e.appIcon : "",
            summary: cleanText(e.summary),
            body: cleanText(e.body),
            urgency: isFinite(urg) ? Math.min(3, Math.max(0, urg)) : 1,
            timestamp: isFinite(ts) ? ts : 0
          })
        }
        root.entries = clean
      }
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // ---- system metrics sampling ---------------------------------------------

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.sampleMetrics()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.sampleDisk()
  }

  function sampleMetrics() {
    if (!statProc.running) statProc.running = true
    if (!memProc.running) memProc.running = true
    if (!netProc.running) netProc.running = true
    if (!upProc.running) upProc.running = true
    if (root.hasBattery && !batProc.running) batProc.running = true
  }

  function sampleDisk() {
    if (!dfProc.running) dfProc.running = true
  }

  Process {
    id: statProc
    command: ["/usr/bin/cat", "/proc/stat"]
    stdout: StdioCollector {
      onStreamFinished: {
        var line = ""
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].indexOf("cpu ") === 0) { line = lines[i]; break }
        }
        if (line.length === 0) return
        var parts = line.split(/\s+/)
        var idle = 0, total = 0
        for (var j = 1; j < parts.length; j++) {
          var v = Number(parts[j])
          if (!isFinite(v)) continue
          total += v
          if (j === 4 || j === 5) idle += v  // idle + iowait
        }
        if (total <= 0) return
        if (root._cpuPrevIdle >= 0 && total > root._cpuPrevTotal) {
          var dTotal = total - root._cpuPrevTotal
          var dIdle = idle - root._cpuPrevIdle
          var pct = (1 - dIdle / dTotal) * 100
          root.cpuPercent = Math.min(100, Math.max(0, pct))
        }
        root._cpuPrevIdle = idle
        root._cpuPrevTotal = total
      }
    }
  }

  Process {
    id: memProc
    command: ["/usr/bin/cat", "/proc/meminfo"]
    stdout: StdioCollector {
      onStreamFinished: {
        var totalKb = 0, availKb = 0
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].indexOf("MemTotal:") === 0)
            totalKb = Number(lines[i].replace(/[^0-9]/g, ""))
          else if (lines[i].indexOf("MemAvailable:") === 0)
            availKb = Number(lines[i].replace(/[^0-9]/g, ""))
        }
        if (!(totalKb > 0) || !(availKb >= 0)) return
        var usedKb = Math.max(0, totalKb - availKb)
        root.memPercent = Math.min(100, Math.max(0, (usedKb / totalKb) * 100))
        root.memText = root.fmtGb(usedKb) + " / " + root.fmtGb(totalKb)
      }
    }
  }

  Process {
    id: netProc
    command: ["/usr/bin/cat", "/proc/net/dev"]
    stdout: StdioCollector {
      onStreamFinished: {
        var rx = 0, tx = 0
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var idx = lines[i].indexOf(":")
          if (idx < 0) continue
          var iface = lines[i].slice(0, idx).trim()
          if (iface === "lo" || iface.length === 0) continue
          var fields = lines[i].slice(idx + 1).trim().split(/\s+/)
          if (fields.length < 9) continue
          var r = Number(fields[0]), t = Number(fields[8])
          if (isFinite(r)) rx += r
          if (isFinite(t)) tx += t
        }
        if (root._netPrevRx >= 0) {
          // Sample period is the 2s metrics timer; negative deltas (counter
          // reset, interface swapped) fall back to zero for one tick.
          root.netDownKb = Math.max(0, (rx - root._netPrevRx) / 2 / 1024)
          root.netUpKb = Math.max(0, (tx - root._netPrevTx) / 2 / 1024)
        }
        root._netPrevRx = rx
        root._netPrevTx = tx
      }
    }
  }

  Process {
    id: upProc
    command: ["/usr/bin/cat", "/proc/uptime"]
    stdout: StdioCollector {
      onStreamFinished: {
        var secs = Number(text.trim().split(/\s+/)[0])
        if (!isFinite(secs) || secs <= 0) return
        root.uptimeText = root.fmtUptime(Math.floor(secs))
      }
    }
  }

  // Battery: one cat for both capacity and AC-online, two lines out.
  Process {
    id: batProc
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        var cap = Number(lines[0])
        var ac = Number(lines[1])
        if (isFinite(cap)) root.batteryPercent = Math.min(100, Math.max(0, Math.round(cap)))
        if (isFinite(ac)) root.batteryCharging = ac > 0
      }
    }
  }

  // Whitelist power supply names — no separators, fixed prefixes only.
  Process {
    id: powerListProc
    command: ["/usr/bin/ls", "-1", "/sys/class/power_supply"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim()
          if (/^BAT[0-9]+$/.test(name) && root._batCapPath.length === 0) {
            root._batCapPath = "/sys/class/power_supply/" + name + "/capacity"
            root.hasBattery = true
          } else if (/^AC[0-9A-Za-z]*$/.test(name) && root._batAcPath.length === 0) {
            root._batAcPath = "/sys/class/power_supply/" + name + "/online"
          }
        }
        if (root.hasBattery && root._batAcPath.length > 0)
          batProc.command = ["/usr/bin/cat", root._batCapPath, root._batAcPath]
        else if (root.hasBattery)
          batProc.command = ["/usr/bin/cat", root._batCapPath]
        else
          root.hasBattery = false
      }
    }
  }

  Process {
    id: dfProc
    command: ["/usr/bin/df", "-k", "-P", "/"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        if (lines.length < 2) return
        var fields = lines[1].trim().split(/\s+/)
        if (fields.length < 5) return
        var blocks = Number(fields[1]), used = Number(fields[2])
        if (!(blocks > 0) || !(used >= 0)) return
        root.diskPercent = Math.min(100, Math.max(0, (used / blocks) * 100))
        root.diskText = root.fmtGb(used * 1024) + " / " + root.fmtGb(blocks * 1024)
      }
    }
  }

  // ---- formatting helpers (shared with the tabs) ---------------------------

  function fmtGb(kb) {
    var gb = kb / (1024 * 1024)
    if (gb >= 100) return Math.round(gb) + " GB"
    if (gb >= 10) return gb.toFixed(1) + " GB"
    return gb.toFixed(2) + " GB"
  }

  function fmtKb(kbPerSec) {
    if (kbPerSec >= 1024) return (kbPerSec / 1024).toFixed(1) + " MB/s"
    if (kbPerSec >= 10) return Math.round(kbPerSec) + " KB/s"
    return kbPerSec.toFixed(1) + " KB/s"
  }

  function fmtUptime(secs) {
    var d = Math.floor(secs / 86400)
    var h = Math.floor((secs % 86400) / 3600)
    var m = Math.floor((secs % 3600) / 60)
    if (d > 0) return d + "d " + h + "h"
    if (h > 0) return h + "h " + m + "m"
    return m + "m"
  }
}
