pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons

// Shared per-shell service: notification history (from omarchy.notifications'
// on-disk history), read/unread tracking, and slow system metrics sampling.
// Bar widgets (one per monitor) bind to this instead of each sampling /proc.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool initialized: false

  // ---- panel registry -------------------------------------------------------
  // One bar widget per monitor, but the IPC target is claimed by whichever
  // instance registers first — so SUPER+Z toggled the laptop screen no matter
  // where focus was. Widgets register here and IPC open/close/toggle route
  // through the panel on Hyprland's focused monitor.
  property var panels: []

  function registerPanel(panel) {
    if (!panel) return
    var next = root.panels.slice()
    if (next.indexOf(panel) === -1) next.push(panel)
    root.panels = next
  }

  function unregisterPanel(panel) {
    var next = []
    for (var i = 0; i < root.panels.length; i++)
      if (root.panels[i] !== panel) next.push(root.panels[i])
    root.panels = next
  }

  function focusedScreenName() {
    return Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
  }

  function panelForFocused() {
    var want = focusedScreenName()
    if (want.length > 0) {
      for (var i = 0; i < root.panels.length; i++)
        if (root.panels[i].screenName === want) return root.panels[i]
    }
    return root.panels.length > 0 ? root.panels[0] : null
  }

  function openOnFocused() { var p = panelForFocused(); if (p) p.open() }
  function closeOnFocused() { var p = panelForFocused(); if (p) p.close() }
  function toggleOnFocused() { var p = panelForFocused(); if (p) p.toggle() }

  // Switch the focused panel to a tab id and open it; returns that panel so
  // callers can act on the focused instance specifically (e.g. show the
  // folder picker). Callers validate the id against their own tabs list
  // first; an unknown id leaves things alone.
  function openTabOnFocused(id) {
    var p = panelForFocused()
    if (!p) return null
    for (var i = 0; i < p.tabs.length; i++) {
      if (p.tabs[i].id === id) {
        p.tab = id
        p.open()
        return p
      }
    }
    return null
  }

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omarchy"

  // ---- notification history ----------------------------------------------
  // The directory IS the history (same store omarchy.notifications replays
  // from); we only read it. Unread = entries newer than lastSeen.
  readonly property string historyDir: stateDir + "/notifications/history/"
  readonly property int maxEntries: 80

  property var entries: []
  // File names queued into the current/last jq read; entries take their
  // unique id from these (daemon notification ids can repeat over time).
  property var _pendingFiles: []
  property double lastSeen: 0
  // Per-entry read flags, keyed by history file name (unique). The
  // watermark covers "mark all"; individually clicked entries are flagged
  // so a click never touches neighbouring rows. Flags are pruned to the
  // current unread set on every persist, so the map stays small.
  property var readIds: ({})
  property bool stateLoaded: false

  function isUnread(entry) {
    if (!entry) return false
    return entry.timestamp > lastSeen && !readIds[entry.id]
  }

  readonly property int unreadCount: {
    var count = 0
    for (var i = 0; i < entries.length; i++)
      if (isUnread(entries[i])) count++
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
    root.refreshGifs()
    root.sampleMetrics()
    root.sampleDisk()
  }
  function refresh() {
    if (listProc.running) return
    listProc.command = ["/usr/bin/ls", "-1t", root.historyDir]
    listProc.running = true
  }

  function persistState() {
    if (!root.stateLoaded) return
    // Keep flags only for entries the watermark doesn't already cover.
    var ids = {}
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e.timestamp > root.lastSeen && root.readIds[e.id]) ids[e.id] = true
    }
    root.readIds = ids
    stateFile.setText(JSON.stringify({ lastSeen: root.lastSeen, readIds: ids }))
  }

  function loadStateFlags(d) {
    if (d && d.readIds && typeof d.readIds === "object" && !Array.isArray(d.readIds))
      root.readIds = d.readIds
  }

  function markEntryRead(id) {
    var key = String(id === undefined || id === null ? "" : id)
    if (key.length === 0 || root.readIds[key]) return
    var next = {}
    for (var k in root.readIds) next[k] = true
    next[key] = true
    root.readIds = next
    persistState()
  }

  // Mark every currently-listed entry at or older than `timestamp` read,
  // individually (without moving the watermark, so newer entries — and the
  // watermark's meaning for future arrivals — are untouched).
  function markReadUpTo(timestamp) {
    var ts = Number(timestamp)
    if (!isFinite(ts)) return
    var next = {}
    for (var k in root.readIds) next[k] = true
    var changed = false
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e.timestamp <= ts && !root.readIds[e.id]) {
        next[e.id] = true
        changed = true
      }
    }
    if (changed) {
      root.readIds = next
      persistState()
    }
  }

  function markAllRead() {
    root.lastSeen = Date.now()
    root.readIds = {}
    if (root.stateLoaded)
      stateFile.setText(JSON.stringify({ lastSeen: root.lastSeen, readIds: {} }))
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
        root.loadStateFlags(d)
      } catch (e) {}
      root.stateLoaded = true
    }
    onLoadFailed: root.stateLoaded = true
  }

  Process {
    id: mkdirProc
    command: ["/usr/bin/mkdir", "-p", root.stateDir, root.gifsDir]
  }

  // ---- Daily tab -----------------------------------------------------------
  // Recurring daily tasks (with per-day completion + streak history),
  // persistent todos, and a scratchpad — all in one state file. Day keys are
  // local dates ("YYYY-MM-DD"); `days` records fully-completed days at the
  // moment they complete so later task edits don't rewrite history.

  readonly property string gifsDir: stateDir + "/pdok/gifs/"
  // The desktop-widgets photo deck folder, if present — its GIFs show here
  // too (read-only; drop folders stay independent).
  readonly property string dwPhotosDir: home + "/.config/omarchy/plugins/dagyr.desktop-widgets/photos"
  readonly property string dwPhotosUrl: "file://" + dwPhotosDir

  property var gifFiles: []
  // Custom GIF directory chosen by the user (empty = default sources:
  // gifsDir + the desktop-widgets photos folder).
  property string customGifDir: ""
  readonly property string activeGifDir: customGifDir !== "" ? customGifDir : gifsDir

  property var daily: ({ tasks: [], done: {}, days: {}, todos: [], notes: "" })
  property bool dailyLoaded: false
  property int _idSeq: 0

  FileView {
    id: dailyFile
    path: root.stateDir + "/pdok-daily.json"
    atomicWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        root.loadDaily(d)
      } catch (e) {}
      root.dailyLoaded = true
    }
    onLoadFailed: root.dailyLoaded = true
  }

  function loadDaily(d) {
    var base = { tasks: [], done: {}, days: {}, todos: [], notes: "" }
    if (d && typeof d === "object") {
      if (Array.isArray(d.tasks)) {
        for (var i = 0; i < d.tasks.length && i < 100; i++) {
          var t = d.tasks[i]
          if (t && typeof t.text === "string" && t.text.length > 0)
            base.tasks.push({ id: String(t.id || ("t" + i)), text: cleanText(t.text).slice(0, 200) })
        }
      }
      if (d.done && typeof d.done === "object") base.done = clampDayMap(d.done)
      if (d.days && typeof d.days === "object") base.days = clampDayMap(d.days)
      if (Array.isArray(d.todos)) {
        for (var j = 0; j < d.todos.length && j < 200; j++) {
          var td = d.todos[j]
          if (td && typeof td.text === "string" && td.text.length > 0)
            base.todos.push({ id: String(td.id || ("d" + j)), text: cleanText(td.text).slice(0, 200), done: td.done === true })
        }
      }
      if (typeof d.notes === "string") base.notes = cleanText(d.notes).slice(0, 5000)
    }
    root.daily = base
  }

  // Day-keyed map → keep only valid keys, newest 400 entries.
  function clampDayMap(m) {
    var keys = []
    for (var k in m) if (/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(k)) keys.push(k)
    keys.sort()
    if (keys.length > 400) keys = keys.slice(keys.length - 400)
    var out = {}
    for (var i = 0; i < keys.length; i++) out[keys[i]] = m[keys[i]]
    return out
  }

  function dayKey(offset) {
    var d = new Date()
    if (offset) d = new Date(d.getFullYear(), d.getMonth(), d.getDate() - offset)
    return Qt.formatDate(d, "yyyy-MM-dd")
  }

  function genId(prefix) {
    root._idSeq = (root._idSeq + 1) % 1000
    return prefix + Date.now() + "-" + root._idSeq
  }

  function saveDaily() {
    if (!root.dailyLoaded) return
    dailyFile.setText(JSON.stringify(root.daily))
  }

  function dayDone(key) {
    return daily.days[key] === true
  }

  function todayDoneIds() {
    var list = daily.done[dayKey(0)]
    return Array.isArray(list) ? list : []
  }

  // Consecutive completed days ending today (or yesterday if today is not
  // finished yet).
  readonly property int streak: {
    var n = 0
    var start = dayDone(dayKey(0)) ? 0 : 1
    for (var i = start; i < 3660; i++) {
      if (dayDone(dayKey(i))) n++
      else break
    }
    return n
  }

  readonly property int totalDaysDone: {
    var n = 0
    for (var k in daily.days) if (daily.days[k] === true) n++
    return n
  }

  // Grid state for a day, `offset` days before today (0 = today, negative =
  // future): 0 none / 1 partial / 2 fully done.
  function dayState(offset) {
    if (offset < 0) return 0
    var key = dayKey(offset)
    if (daily.days[key] === true) return 2
    var doneCount = Array.isArray(daily.done[key]) ? daily.done[key].length : 0
    if (doneCount > 0) return 1
    return 0
  }

  function addTask(raw) {
    var t = cleanText(raw).slice(0, 200)
    if (!t || daily.tasks.length >= 100) return
    var next = Util.cloneJson(daily)
    next.tasks = next.tasks.concat([{ id: genId("t"), text: t }])
    daily = next
    saveDaily()
  }

  function removeTask(id) {
    var next = Util.cloneJson(daily)
    var keep = []
    for (var i = 0; i < next.tasks.length; i++)
      if (next.tasks[i].id !== id) keep.push(next.tasks[i])
    next.tasks = keep
    // Drop the task's per-day ticks so stale ids don't linger as ghosts.
    var cleanedDone = {}
    for (var key in next.done) {
      var list = Array.isArray(next.done[key]) ? next.done[key] : []
      var filtered = []
      for (var j = 0; j < list.length; j++)
        if (list[j] !== id) filtered.push(list[j])
      if (filtered.length > 0) cleanedDone[key] = filtered
    }
    next.done = cleanedDone
    daily = next
    saveDaily()
  }

  function toggleTask(id) {
    var key = dayKey(0)
    var next = Util.cloneJson(daily)
    var list = Array.isArray(next.done[key]) ? next.done[key].slice() : []
    var idx = list.indexOf(id)
    if (idx >= 0) list.splice(idx, 1)
    else list.push(id)
    if (list.length > 0) next.done[key] = list
    else delete next.done[key]
    var allDone = next.tasks.length > 0
    for (var j = 0; j < next.tasks.length; j++) {
      if (list.indexOf(next.tasks[j].id) < 0) { allDone = false; break }
    }
    if (allDone) next.days[key] = true
    else delete next.days[key]
    daily = next
    saveDaily()
  }

  function addTodo(raw) {
    var t = cleanText(raw).slice(0, 200)
    if (!t || daily.todos.length >= 200) return
    var next = Util.cloneJson(daily)
    next.todos = next.todos.concat([{ id: genId("d"), text: t, done: false }])
    daily = next
    saveDaily()
  }

  function toggleTodo(id) {
    var next = Util.cloneJson(daily)
    for (var i = 0; i < next.todos.length; i++) {
      if (next.todos[i].id === id) next.todos[i].done = !next.todos[i].done
    }
    daily = next
    saveDaily()
  }

  function removeTodo(id) {
    var next = Util.cloneJson(daily)
    var keep = []
    for (var i = 0; i < next.todos.length; i++)
      if (next.todos[i].id !== id) keep.push(next.todos[i])
    next.todos = keep
    daily = next
    saveDaily()
  }

  function setNotes(raw) {
    var t = String(raw === undefined || raw === null ? "" : raw).slice(0, 5000)
    if (t === daily.notes) return
    var next = Util.cloneJson(daily)
    next.notes = t
    daily = next
    saveDaily()
  }

  // ---- GIF deck listing -----------------------------------------------------
  // Whitelisted image names from the pdok drop folder and (read-only) the
  // desktop-widgets photo folder, deduped by name. A customGifDir replaces
  // both sources with that one directory.

  function isImageName(name) {
    // Parentheses/commas/apostrophes appear constantly in downloaded files
    // ("200 (1) (10 FPS).gif") — names go into file:// URLs, never a shell.
    return /^[A-Za-z0-9][A-Za-z0-9 ._(),'!+-]*\.(gif|png|jpg|jpeg|webp)$/.test(name)
  }

  // Validate and apply a user-chosen GIF directory. Accepts "" to return to
  // the default sources. Paths must be absolute after ~ expansion, with no
  // ".." segments — the ls argv stays a fixed array either way, this keeps
  // IPC callers from pointing the deck at odd places.
  function setGifDir(raw) {
    var p = String(raw === undefined || raw === null ? "" : raw).trim()
    if (p.length === 0) {
      if (root.customGifDir === "") return true
      root.customGifDir = ""
      root.refreshGifs()
      return true
    }
    if (p.charAt(0) === "~") p = home + p.slice(1)
    if (p.charAt(0) !== "/") return false
    if (!/^[A-Za-z0-9 ._(),'!+\/-]+$/.test(p)) return false
    var parts = p.split("/")
    for (var i = 0; i < parts.length; i++)
      if (parts[i] === "..") return false
    p = p.replace(/\/+$/, "")
    if (p === root.customGifDir) return true
    root.customGifDir = p
    root.refreshGifs()
    return true
  }

  // Directory currently listed by gifListProc; a dir change landing while a
  // listing is in flight queues one relaunch instead of being dropped to
  // the next 60s timer tick.
  property string _listedDir: ""
  property string _queuedListDir: ""

  function refreshGifs() {
    var dir = root.customGifDir !== "" ? root.customGifDir : root.gifsDir
    if (!gifListProc.running) {
      root._queuedListDir = ""
      root._listedDir = dir
      gifListProc.command = ["/usr/bin/ls", "-1", dir]
      gifListProc.running = true
    } else if (dir !== root._listedDir) {
      root._queuedListDir = dir
    }
    if (root.customGifDir === "" && !gifListProc2.running) {
      gifListProc2.command = ["/usr/bin/ls", "-1", root.dwPhotosDir]
      gifListProc2.running = true
    }
  }

  function applyGifFiles(mine, theirs) {
    var merged = []
    var seen = {}
    var i
    var mineBase = root.customGifDir !== "" ? root.customGifDir : root.gifsDir
    for (i = 0; i < mine.length; i++) {
      var m = mineBase + (mineBase.charAt(mineBase.length - 1) === "/" ? "" : "/") + mine[i]
      if (!seen[mine[i].toLowerCase()]) { seen[mine[i].toLowerCase()] = true; merged.push("file://" + m) }
    }
    if (root.customGifDir === "") {
      for (i = 0; i < theirs.length; i++) {
        if (!seen[theirs[i].toLowerCase()]) { seen[theirs[i].toLowerCase()] = true; merged.push(root.dwPhotosUrl + "/" + theirs[i]) }
      }
    }
    root.gifFiles = merged
  }

  Process {
    id: gifListProc
    onExited: {
      if (root._queuedListDir !== "" && root._queuedListDir !== root._listedDir) {
        root._listedDir = root._queuedListDir
        gifListProc.command = ["/usr/bin/ls", "-1", root._queuedListDir]
        root._queuedListDir = ""
        gifListProc.running = true
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        var mine = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim()
          if (isImageName(name)) mine.push(name)
        }
        root._gifMine = mine
        root.applyGifFiles(root._gifMine, root._gifTheirs)
      }
    }
  }

  Process {
    id: gifListProc2
    stdout: StdioCollector {
      onStreamFinished: {
        var theirs = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim()
          if (isImageName(name)) theirs.push(name)
        }
        root._gifTheirs = theirs
        root.applyGifFiles(root._gifMine, root._gifTheirs)
      }
    }
  }

  property var _gifMine: []
  property var _gifTheirs: []

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.refreshGifs()
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
        root._pendingFiles = files
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
            id: root._pendingFiles && root._pendingFiles[i] !== undefined
              ? String(root._pendingFiles[i]) : String(i),
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
