pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Port of ruixen.notch's CavaFeed: spawns cava and turns its raw stdout
// into a normalized, smoothed levels array. cava's native pipewire backend
// (source = auto, the default sink's monitor) needs no pactl fallback; a
// missing cava binary exits 42 and latches cavaAvailable off (no retry
// loop) until enabled is toggled again. Peak-normalized per frame so
// volume doesn't change bar height, EMA-smoothed, and settled back to flat
// after 260ms without a frame so bars never freeze on the last peak.
QtObject {
  id: root

  property bool enabled: false
  property int bands: 24
  readonly property int fps: 30

  property var levels: root.flat()
  property real lastReadMs: 0

  function flat() {
    var a = []
    for (var i = 0; i < root.bands; i++) a.push(0)
    return a
  }

  property bool cavaAvailable: true

  property Process cavaProc: Process {
    id: cavaProc
    command: ["sh", "-c",
      "command -v cava >/dev/null 2>&1 || exit 42; " +
      "cfg=\"${XDG_RUNTIME_DIR:-/tmp}/pdok-cava-visualizer.conf\"; " +
      "printf '%s\\n' '[general]' 'framerate = " + root.fps + "' 'bars = " + root.bands + "' 'autosens = 0' 'sensitivity = 70' '' " +
      "'[input]' 'method = pipewire' 'source = auto' '' " +
      "'[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' 'ascii_max_range = 1000' 'channels = mono' 'mono_option = average' '' " +
      "'[smoothing]' 'noise_reduction = 45' > \"$cfg\"; exec cava -p \"$cfg\""]
    // Bound, never imperatively assigned — an imperative assignment here
    // would destroy the binding and let cava outlive every gate.
    running: root.enabled && root.cavaAvailable && !cavaProc.backoff
    property bool backoff: false
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => root.readBars(line)
    }
    onExited: (exitCode) => {
      if (exitCode === 42) {
        root.cavaAvailable = false
        return
      }
      if (root.enabled) {
        cavaProc.backoff = true
        restartTimer.restart()
      }
    }
  }

  property Timer restartTimer: Timer {
    id: restartTimer
    interval: 1200
    onTriggered: cavaProc.backoff = false
  }

  property bool idleSettled: false

  property Timer idleTimer: Timer {
    interval: 120
    running: root.enabled
    repeat: true
    onTriggered: {
      if (root.idleSettled) return
      if (Date.now() - root.lastReadMs > 260) {
        root.levels = root.flat()
        root.prevLevels = root.flat()
        root.idleSettled = true
      }
    }
  }

  onEnabledChanged: {
    levels = flat()
    prevLevels = flat()
    idleSettled = false
    if (enabled) {
      lastReadMs = 0
      cavaAvailable = true
    }
  }

  readonly property real noiseFloor: 15
  readonly property real emaSmoothing: 0.3
  readonly property real levelFloor: 0.01
  property var prevLevels: root.flat()

  function readBars(line) {
    var t = line.trim()
    if (!t) return
    var parts = t.split(/[;\s]+/)
    if (parts.length < root.bands) return

    var raw = []
    var peak = 0
    for (var i = 0; i < root.bands; i++) {
      var n = parseInt(parts[i])
      if (isNaN(n)) n = 0
      raw.push(n)
      if (n > peak) peak = n
    }

    var prev = (root.prevLevels && root.prevLevels.length === root.bands) ? root.prevLevels : root.flat()

    var out = []
    for (var j = 0; j < root.bands; j++) {
      // Relative to the loudest bar in this frame; the noise floor keeps
      // a near-silent frame from being amplified toward full height.
      var v = peak > root.noiseFloor ? raw[j] / peak : 0
      var smoothed = root.emaSmoothing * prev[j] + (1 - root.emaSmoothing) * v
      if (smoothed < root.levelFloor) smoothed = 0
      out.push(smoothed)
    }

    root.prevLevels = out
    root.levels = out
    root.lastReadMs = Date.now()
    root.idleSettled = false
  }
}
