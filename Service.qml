pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "bridge" as PdokBridge

// Shared per-shell service: the Daily tab state (tasks/todos/notes + gif
// deck) and the Work tab's GitHub dashboard sources.
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

  // Task/todo/notes text arrives from files the user (or IPC callers) write:
  // normalize escape noise to plain text with real line breaks — rendered
  // with Text.PlainText afterwards, so nothing here can inject formatting.
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

  // ---- github dashboard ------------------------------------------------------
  // Two sources. The contribution heatmap reuses the dev.git plugin: its
  // collector (already authed through `gh`) writes
  // ~/.local/state/omarchy/git/overview.json — we trigger it and read the
  // state file. Recent commits come straight from the GitHub API through the
  // authenticated gh CLI. Last payload is cached under the state dir so the
  // tab renders instantly on shell start.
  property string ghLogin: ""
  property string ghName: ""
  // Profile footer avatar: GitHub profile picture cached under the state
  // dir (downloaded with curl), bumped so widgets can cache-bust their
  // Image source. Falls back to ~/.face client-side when absent.
  property string ghAvatarUrl: ""
  property string avatarFetchedUrl: ""
  property int avatarVersion: 0
  readonly property string avatarPath: stateDir + "/pdok-avatar.png"
  readonly property string avatarTmpPath: stateDir + "/pdok-avatar.tmp"

  // Custom avatar: a user-picked image (gif/png/jpg/jpeg/webp) copied
  // byte-for-byte under the state dir, so animated GIFs stay animated. The
  // copy lands under one fixed name — Qt sniffs the image format from the
  // content, not the extension — and whether it's a GIF is remembered in
  // the meta JSON so the footer knows to render an AnimatedImage. While
  // active it takes priority over the GitHub avatar; clearing returns to it.
  readonly property string customAvatarPath: stateDir + "/pdok-avatar-custom"
  readonly property string customAvatarTmpPath: stateDir + "/pdok-avatar-custom.tmp"
  readonly property string avatarMetaPath: stateDir + "/pdok-avatar.json"
  property bool customAvatarActive: false
  property bool customAvatarGif: false
  property var ghCommits: []
  property string ghUpdatedAt: ""
  property string ghError: ""
  property bool ghRefreshing: false

  property var ghCalendar: ({})

  // dev.git's queues, flattened for the Work tab: the four OPEN WORK counts
  // plus the user's own open PRs (which may live in other people's repos).
  property var ghOpenWork: ({ review: 0, assignedPrs: 0, assignedIssues: 0, authoredIssues: 0, authoredPrs: [] })

  readonly property string gitOverviewPath: stateDir + "/git/overview.json"
  // dev.git's collector, found relative to this plugin:
  // plugins/palccod.pdok/../dev.git/bin/gitwork
  readonly property string gitworkPath: {
    var url = String(Qt.resolvedUrl("../dev.git/bin/gitwork"))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  Component.onCompleted: {
    // Publish for widgets hosted by replacement bars (ruixen.bar etc.),
    // whose `bar.shell` facade cannot resolve plugin services. See
    // bridge/Bridge.qml; the host facade stays the primary path.
    PdokBridge.Bridge.service = root
    mkdirProc.running = true
    root.refreshGifs()
    root.refreshGithub()
  }

  // Unpublish so a widget falling back to the bridge never binds to a
  // dying instance.
  Component.onDestruction: if (PdokBridge.Bridge.service === root) PdokBridge.Bridge.service = null

  // ---- state file ----------------------------------------------------------

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

  // Tasks completed `offset` days ago (0 = today), for the streak grid's
  // hover tooltip.
  function dayDoneCount(offset) {
    if (offset < 0) return 0
    var key = dayKey(offset)
    var list = Array.isArray(daily.done[key]) ? daily.done[key] : []
    return list.length
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

  // ---- github dashboard sources ---------------------------------------------

  Timer {
    interval: 15 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refreshGithub()
  }

  function refreshGithub() {
    if (ghUserProc.running || ghEventsProc.running || gitworkProc.running) return
    root.ghRefreshing = true
    ghUserProc.running = true
    root.runGitwork()
  }

  // The contribution heatmap: run dev.git's collector against its own state
  // file, then let the FileView below pick up whatever it wrote.
  function runGitwork() {
    if (root.gitworkPath === "" || gitworkProc.running) return
    gitworkProc.command = [root.gitworkPath, "-output", root.gitOverviewPath]
    gitworkProc.running = true
  }

  Process {
    id: gitworkProc
    stderr: StdioCollector { waitForEnd: true }
    // The watcher may not have armed if the file did not exist yet; reload
    // once the collector has had its chance to write.
    onExited: Qt.callLater(gitOverviewFile.reload)
  }

  FileView {
    id: gitOverviewFile
    path: root.gitOverviewPath
    watchChanges: true
    printErrors: false
    onLoaded: root.parseGitOverview(text())
    onLoadFailed: { /* keep the last good snapshot */ }
  }

  function parseGitOverview(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      var provs = parsed && Array.isArray(parsed.providers) ? parsed.providers : []
      var cal = ({})
      for (var i = 0; i < provs.length; i++) {
        var p = provs[i] || {}
        if (String(p.kind) !== "github") continue
        // A failed run (network blip) overwrites the state file with a
        // not-ready record; keep the last good snapshot instead of
        // regressing the whole tab until the next successful run.
        if (p.ready !== true) return
        cal = p.calendar || {}
        // The collector resolves identity too; fill blanks from it.
        if (root.ghLogin === "") root.ghLogin = String(p.username || "")
        if (root.ghName === "") root.ghName = String(p.displayName || "")
        break
      }
      var counts = Array.isArray(cal.counts) ? cal.counts : []
      root.ghCalendar = {
        supported: cal.supported === true && counts.length > 0,
        start: String(cal.start || ""),
        end: String(cal.end || ""),
        weeks: Number(cal.weeks || 0),
        counts: counts,
        levels: Array.isArray(cal.levels) ? cal.levels : [],
        monthStarts: Array.isArray(cal.monthStarts) ? cal.monthStarts : [],
        total: Number(cal.total || 0),
        current: Number(cal.current || 0),
        longest: Number(cal.longest || 0),
        today: Number(cal.today || 0),
        max: Number(cal.max || 0)
      }
      // Open-work counts and the authored-PR queue, straight from the
      // collector's totals; the PR list is whitelisted field by field.
      var totals = p.totals && typeof p.totals === "object" ? p.totals : {}
      var cnt = function(k) {
        var v = Math.floor(Number(totals[k]))
        return isFinite(v) && v > 0 ? v : 0
      }
      var rawPrs = Array.isArray(p.authoredPrs) ? p.authoredPrs : []
      var prRows = []
      for (var j = 0; j < rawPrs.length && prRows.length < 10; j++) {
        var it = rawPrs[j] || {}
        var repo = String(it.repository || "")
        var num = Math.floor(Number(it.number))
        if (repo === "" || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)) continue
        if (!isFinite(num) || num <= 0) continue
        prRows.push({
          number: num,
          title: String(it.title || "").slice(0, 160),
          repository: repo,
          url: /^https:\/\/github\.com\//.test(String(it.url || ""))
            ? String(it.url) : "https://github.com/" + repo + "/pull/" + num,
          updatedAt: String(it.updatedAt || ""),
          draft: it.draft === true
        })
      }
      root.ghOpenWork = {
        review: cnt("reviewRequests"),
        assignedPrs: cnt("assignedPrs"),
        assignedIssues: cnt("assignedIssues"),
        authoredIssues: cnt("authoredIssues"),
        authoredPrs: prRows
      }
      root.persistGithub()
    } catch (e) {
      // Malformed file: keep whatever good data is already in memory.
    }
  }

  // Recent commits: gh -> whoami -> public events, filtered to pushes.
  Process {
    id: ghUserProc
    command: ["/usr/sbin/gh", "api", "user", "--jq", ".login + \"\\t\" + (.name // \"\") + \"\\t\" + (.avatar_url // \"\")"]
    stderr: StdioCollector {
      waitForEnd: true
      property string errText: ""
      onStreamFinished: errText = text.trim()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = text.trim().split("\t")
        if (parts.length < 1 || parts[0] === "") {
          root.ghRefreshing = false
          root.ghError = "gh: no login — run `gh auth login`"
          return
        }
        if (!/^[A-Za-z0-9-]{1,39}$/.test(parts[0])) {
          root.ghRefreshing = false
          root.ghError = "gh: unexpected login"
          return
        }
        root.ghLogin = parts[0]
        root.ghName = parts.length > 1 ? parts[1] : ""
        root.ghError = ""
        // Only githubusercontent avatar hosts are fetched; anything else is
        // ignored rather than passed to curl.
        var av = parts.length > 2 ? String(parts[2] || "") : ""
        if (/^https:\/\/avatars\.githubusercontent\.com\//.test(av)) root.ghAvatarUrl = av
        root.maybeFetchAvatar()
        // ghLogin is regex-validated above, so building the argv here is safe.
        // The public events feed omits commit details, so go through commit
        // search instead: own pushes across all repos, newest first, last 30d.
        var since = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10)
        ghEventsProc.command = ["/usr/sbin/gh", "api",
          "search/commits?q=author:" + root.ghLogin + "+committer-date:%3E" + since
            + "&sort=committer-date&order=desc&per_page=20"]
        ghEventsProc.running = true
      }
    }
    onExited: function(exitCode) {
      // Whatever happened, the spinner must not stick; the collector may
      // already have filled ghLogin, so failure and success reset alike.
      if (exitCode !== 0) {
        var lines = ghUserProc.stderr.data.split("\n").filter(function(l) { return l !== "" })
        root.ghError = lines.length > 0
          ? "gh: " + lines[lines.length - 1].slice(0, 120)
          : "gh: user lookup failed"
      }
      root.ghRefreshing = false
    }
  }

  // Avatar download: curl to a temp file, then an atomic rename into place
  // so the widget never reads a half-written image.
  function maybeFetchAvatar() {
    if (root.ghAvatarUrl === "" || root.ghAvatarUrl === root.avatarFetchedUrl) return
    if (avatarDlProc.running || avatarMvProc.running) return
    avatarDlProc.command = ["/usr/sbin/curl", "-fsSL", "--max-time", "10",
                            "-o", root.avatarTmpPath, root.ghAvatarUrl]
    avatarDlProc.running = true
  }

  Process {
    id: avatarDlProc
    command: []
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      // Mark attempted either way so a dead avatar URL cannot hot-loop.
      root.avatarFetchedUrl = root.ghAvatarUrl
      if (exitCode === 0) {
        avatarMvProc.command = ["/usr/bin/mv", root.avatarTmpPath, root.avatarPath]
        avatarMvProc.running = true
      }
    }
  }

  Process {
    id: avatarMvProc
    command: []
    onExited: function(exitCode) { if (exitCode === 0) root.avatarVersion++ }
  }

  FileView {
    id: avatarFile
    path: root.avatarPath
    watchChanges: false
    printErrors: false
    onLoaded: root.avatarVersion++
    // File vanished (state dir wiped): retry the download on next refresh.
    onLoadFailed: root.avatarFetchedUrl = ""
  }

  // ---- custom avatar --------------------------------------------------------
  // Meta JSON remembers active+isGif across restarts; the image itself is the
  // copied file. setCustomAvatar returns a status line for the picker/IPC —
  // "avatar=..." closes the picker, anything else is shown in place.
  // Validation happens synchronously; the copy is the same cp-to-tmp →
  // atomic-mv dance as the GitHub download, so the footer never reads a
  // half-written file and the active flag only flips once the bytes are in
  // place (a failed copy just leaves the previous avatar showing).

  FileView {
    id: avatarMetaFile
    path: root.avatarMetaPath
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        root.customAvatarActive = d.active === true
        root.customAvatarGif = d.gif === true
      } catch (e) {}
    }
    onLoadFailed: { /* no custom avatar chosen yet */ }
  }

  function persistAvatarMeta() {
    avatarMetaFile.setText(JSON.stringify({ active: root.customAvatarActive, gif: root.customAvatarGif }))
  }

  property bool _pendingAvatarGif: false

  function setCustomAvatar(raw) {
    var p = String(raw === undefined || raw === null ? "" : raw).trim()
    // Empty path = reset to the GitHub avatar.
    if (p.length === 0) return root.clearCustomAvatar()
    if (p.charAt(0) === "~") p = home + p.slice(1)
    if (p.charAt(0) !== "/") return "invalid path — use an absolute file path (~/... ok)"
    if (!/^[A-Za-z0-9 ._(),'!+\/-]+$/.test(p)) return "invalid path — unsupported characters"
    var parts = p.split("/")
    for (var i = 0; i < parts.length; i++)
      if (parts[i] === "..") return "invalid path — no .. segments"
    if (!/\.(gif|png|jpg|jpeg|webp)$/i.test(p)) return "not an image — gif, png, jpg or webp"
    if (avatarCopyProc.running || avatarPlaceProc.running) return "busy — try again in a moment"
    root._pendingAvatarGif = /\.gif$/i.test(p)
    avatarCopyProc.command = ["/usr/bin/cp", "--", p, root.customAvatarTmpPath]
    avatarCopyProc.running = true
    return "avatar=ok"
  }

  function clearCustomAvatar() {
    if (avatarClearProc.running) return "busy — try again in a moment"
    avatarClearProc.command = ["/usr/bin/rm", "-f", root.customAvatarPath, root.customAvatarTmpPath]
    avatarClearProc.running = true
    return "avatar=github"
  }

  Process {
    id: avatarCopyProc
    command: []
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      avatarPlaceProc.command = ["/usr/bin/mv", root.customAvatarTmpPath, root.customAvatarPath]
      avatarPlaceProc.running = true
    }
  }

  Process {
    id: avatarPlaceProc
    command: []
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.customAvatarActive = true
      root.customAvatarGif = root._pendingAvatarGif
      root.persistAvatarMeta()
      root.avatarVersion++
    }
  }

  Process {
    id: avatarClearProc
    command: []
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.customAvatarActive = false
      root.customAvatarGif = false
      root.persistAvatarMeta()
      root.avatarVersion++
    }
  }

  Process {
    id: ghEventsProc
    stderr: StdioCollector {
      waitForEnd: true
      property string errText: ""
      onStreamFinished: errText = text.trim()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseGhEvents(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var lines = ghEventsProc.stderr.data.split("\n").filter(function(l) { return l !== "" })
        root.ghError = lines.length > 0
          ? "gh: " + lines[lines.length - 1].slice(0, 120)
          : "gh: events unavailable"
      }
      root.ghRefreshing = false
    }
  }

  function parseGhEvents(raw) {
    root.ghRefreshing = false
    var rows = []
    var seen = {}
    try {
      var res = JSON.parse(String(raw || "{}"))
      var items = Array.isArray(res.items) ? res.items : []
      for (var i = 0; i < items.length && rows.length < 20; i++) {
        var it = items[i] || {}
        var sha = String(it.sha || "")
        if (!/^[0-9a-f]{7,40}$/.test(sha)) continue
        var short = sha.slice(0, 7)
        if (seen[short]) continue
        seen[short] = true
        var repo = it.repository && it.repository.full_name
          ? String(it.repository.full_name) : ""
        if (repo === "" || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)) continue
        var commit = it.commit || {}
        var msg = String(commit.message || "").split("\n")[0]
        if (msg.length > 200) msg = msg.slice(0, 200)
        var time = commit.author && commit.author.date ? String(commit.author.date) : ""
        rows.push({
          repo: repo,
          sha: short,
          fullSha: sha,
          message: msg,
          time: time,
          url: "https://github.com/" + repo + "/commit/" + sha
        })
      }
      root.ghCommits = rows
      root.ghUpdatedAt = new Date().toISOString()
      root.ghError = ""
      root.persistGithub()
    } catch (err) {
      root.ghError = "GitHub: " + String(err && err.message ? err.message : err)
    }
  }

  FileView {
    id: ghCacheFile
    path: root.stateDir + "/pdok-github.json"
    atomicWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.restoreGithub(text())
    onLoadFailed: root.ghRefreshing = false
  }

  function persistGithub() {
    ghCacheFile.setText(JSON.stringify({
      ghLogin: root.ghLogin,
      ghName: root.ghName,
      ghUpdatedAt: root.ghUpdatedAt,
      ghCommits: root.ghCommits,
      ghCalendar: root.ghCalendar,
      ghOpenWork: root.ghOpenWork
    }))
  }

  function restoreGithub(content) {
    try {
      var d = JSON.parse(String(content || "{}"))
      if (!d || typeof d !== "object") return
      if (/^[A-Za-z0-9-]{1,39}$/.test(String(d.ghLogin || ""))) root.ghLogin = String(d.ghLogin)
      if (typeof d.ghName === "string") root.ghName = d.ghName.slice(0, 100)
      if (typeof d.ghUpdatedAt === "string") root.ghUpdatedAt = d.ghUpdatedAt
      if (Array.isArray(d.ghCommits)) {
        var rows = []
        for (var i = 0; i < d.ghCommits.length && rows.length < 20; i++) {
          var r = d.ghCommits[i] || {}
          if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(String(r.repo || ""))) continue
          if (!/^[0-9a-f]{7,40}$/.test(String(r.sha || ""))) continue
          var cached = String(r.sha || "")
          rows.push({
            repo: String(r.repo),
            sha: cached.slice(0, 7),
            fullSha: /^[0-9a-f]{40}$/.test(cached) ? cached : cached,
            message: String(r.message || "").slice(0, 200),
            time: String(r.time || ""),
            url: "https://github.com/" + String(r.repo) + "/commit/" + cached
          })
        }
        root.ghCommits = rows
      }
      // Last good dashboard snapshot: only used while the live overview
      // cannot provide one (failed collector run, file missing).
      var cal = d.ghCalendar
      if (cal && typeof cal === "object" && cal.supported === true
          && Array.isArray(cal.counts) && cal.counts.length > 0) {
        root.ghCalendar = cal
      }
      var w = d.ghOpenWork
      if (w && typeof w === "object") {
        root.ghOpenWork = {
          review: Math.max(0, Math.floor(Number(w.review) || 0)),
          assignedPrs: Math.max(0, Math.floor(Number(w.assignedPrs) || 0)),
          assignedIssues: Math.max(0, Math.floor(Number(w.assignedIssues) || 0)),
          authoredIssues: Math.max(0, Math.floor(Number(w.authoredIssues) || 0)),
          authoredPrs: Array.isArray(w.authoredPrs) ? w.authoredPrs : []
        }
      }
    } catch (e) { /* stale cache — first fetch overwrites it */ }
  }

  // ---- formatting helpers (shared with the tabs) ---------------------------
}
