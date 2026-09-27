pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.Commons
import qs.Ui

// Media tab: now-playing with playback controls, a live output visualizer
// driven by PipeWire peak samples, and a per-app volume mixer. Prefers the
// first-party omarchy.media service (preferred-player logic + OSD feedback)
// and falls back to direct Mpris when it is disabled.
Rectangle {
  id: root

  color: "transparent"

  property var shell: null        // bar.shell, to reach omarchy.media
  property color fg: "#ffffff"
  property color accent: "#3ecf5b"
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.5)

  // Mpris fallback
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var directPlayer: {
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (p && (p.trackTitle || p.trackArtist)) return p
    }
    return players.length > 0 ? players[0] : null
  }

  // omarchy.media's active player, when available. Replacement bars (e.g.
  // ruixen.bar) hand widgets a facade whose serviceFor() is a deliberate
  // null stub, but first-party services stay reachable through the
  // allowlisted firstPartyServiceFor() — omarchy.media is on that list.
  readonly property var mediaService: shell && shell.serviceFor
    ? (shell.serviceFor("omarchy.media")
       || (typeof shell.firstPartyServiceFor === "function"
           ? shell.firstPartyServiceFor("omarchy.media") : null))
    : null
  readonly property var activePlayer: mediaService
    ? mediaService.activePlayer : directPlayer

  readonly property bool hasPlayer: !!activePlayer
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string identity: activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || "") : ""
  readonly property bool playing: activePlayer && activePlayer.isPlaying

  // Shuffle / repeat, when the player supports them. loopState cycles
  // None -> Track -> Playlist -> None.
  readonly property bool shuffleOn: activePlayer && activePlayer.shuffleSupported ? activePlayer.shuffle === true : false
  readonly property int loopState: activePlayer ? Number(activePlayer.loopState) : 0
  readonly property string glyphVol: "󰕾"
  readonly property string glyphVolMuted: "󰸈"
  readonly property string glyphShuffle: "󰒡"
  readonly property string glyphRepeat: "󰑷"
  readonly property string glyphRepeatOnce: "󰑹"

  // Progress. Quickshell's MprisPlayer exposes position and length in
  // SECONDS (ms precision); `length` is only meaningful when lengthSupported
  // holds — otherwise it falls back to mirroring position.
  readonly property bool lengthKnown: activePlayer
    && activePlayer.lengthSupported === true && Number(activePlayer.length) > 0
  readonly property real lengthSec: lengthKnown ? Number(activePlayer.length) : 0
  readonly property bool canSeek: activePlayer && activePlayer.canSeek === true
  property real positionSec: 0

  // Album art only from local files — never fetch over the network from the
  // shell process.
  readonly property string localArtUrl: {
    var url = activePlayer && activePlayer.trackArtUrl ? String(activePlayer.trackArtUrl) : ""
    return url.indexOf("file://") === 0 ? url : ""
  }

  // ------------------------------------------------------------ visualizer
  // Real output levels: sample the default sink's peak monitor into a
  // scrolling bar buffer rendered on a Canvas. Nothing plays = flat line.
  readonly property int vizBars: 52
  readonly property var sinkNode: Pipewire.defaultAudioSink
  property var vizLevels: []

  PwNodePeakMonitor {
    id: peakMonitor
    node: root.sinkNode
    enabled: root.visible && !!root.sinkNode
  }

  Timer {
    interval: 40
    running: root.visible && !!root.sinkNode
    repeat: true
    onTriggered: {
      var p = Math.max(0, Math.min(1, Number(peakMonitor.peak) || 0))
      // Sliding window: grow to vizBars, then drop the oldest sample.
      var levels = root.vizLevels.slice()
      levels.push(p)
      if (levels.length > root.vizBars) levels = levels.slice(1)
      root.vizLevels = levels
      viz.requestPaint()
    }
  }

  // ------------------------------------------------------------ app mixer
  // Active playback streams (one row per app). `type` is a PwNodeType flag
  // mask (1 Audio | 4 Stream | 8 Source | 16 Sink) — a playback stream has
  // Audio+Stream+Sink; input streams carry Source instead. `audio` and
  // `properties` populate once the tracker below sees the raw node list.
  readonly property var sinkStreams: {
    var out = []
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !n.isSink) continue
      if ((Number(n.type) & 1) !== 1) continue   // audio only
      out.push(n)
    }
    return out
  }

  // Tracking bootstraps the Pipewire registry itself (nodes stay empty
  // until some tracker watches the raw list) and populates `audio`
  // (volume/mute) and `properties` (labels) on the mixer streams, plus the
  // output sink for the peak monitor.
  PwObjectTracker { objects: Pipewire.nodes ? Pipewire.nodes.values : [] }

  // Position does not update reactively — the documented pattern is to
  // re-read it on a timer while the tab is visible.
  Timer {
    interval: 500
    running: root.visible && root.hasPlayer
    repeat: true
    triggeredOnStart: true
    onTriggered: root.positionSec = root.activePlayer ? Number(root.activePlayer.position) || 0 : 0
  }

  function runAction(action) {
    if (root.mediaService && typeof root.mediaService.runAction === "function") {
      root.mediaService.runAction(action, true)
    } else if (root.activePlayer) {
      if (action === "next" && root.activePlayer.canGoNext) root.activePlayer.next()
      else if (action === "previous" && root.activePlayer.canGoPrevious) root.activePlayer.previous()
      else if (action === "playPause" && root.activePlayer.canTogglePlaying) root.activePlayer.togglePlaying()
    }
  }

  function fmtTime(sec) {
    var t = Math.max(0, Math.floor(Number(sec) || 0))
    var h = Math.floor(t / 3600)
    var m = Math.floor((t % 3600) / 60)
    var s = t % 60
    if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  function streamLabel(node) {
    if (!node) return ""
    var p = node.properties || {}
    return String(p["application.name"] || node.description || p["media.name"] || node.name || "")
  }

  Flickable {
    id: scroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: mediaCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: mediaCol
      width: scroll.width
      spacing: Style.space(12)

      // Empty state
      Text {
        width: parent.width
        visible: !root.hasPlayer
        text: "Nothing playing"
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        topPadding: Style.space(30)
      }

      // Art + track info — ruixen vinyl: a circular disc (slow spin while
      // playing) inside a full-circle progress ring. The ring's Canvas
      // repaints off the progress timer below.
      Row {
        width: parent.width
        visible: root.hasPlayer
        spacing: Style.space(12)

        Item {
          width: Style.space(108)
          height: Style.space(108)
          anchors.verticalCenter: parent.verticalCenter

          // Full-circle progress ring: track = unplayed remainder only,
          // accent arc up to the head, thick white tip tick — the dial
          // treatment, opened to a full 360deg sweep.
          Canvas {
            id: discRing
            anchors.fill: parent

            readonly property real ratio: {
              if (root.lengthSec <= 0) return 0
              var r = root.positionSec / root.lengthSec
              return isFinite(r) ? Math.max(0, Math.min(1, r)) : 0
            }
            onRatioChanged: requestPaint()

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var cx = width / 2, cy = height / 2
              var r = width / 2 - 4
              var start = -Math.PI / 2
              var end = start + discRing.ratio * Math.PI * 2
              var gapRad = 5 / r
              ctx.lineWidth = 4
              ctx.lineCap = "round"
              ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15)
              ctx.beginPath()
              ctx.arc(cx, cy, r, Math.min(start + Math.PI * 2, end + gapRad), start + Math.PI * 2)
              ctx.stroke()
              if (discRing.ratio > 0) {
                ctx.strokeStyle = root.accent
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, Math.max(start, end - gapRad))
                ctx.stroke()
              }
              ctx.lineWidth = 5
              ctx.strokeStyle = "#ffffff"
              ctx.beginPath()
              ctx.moveTo(cx + (r - 2) * Math.cos(end), cy + (r - 2) * Math.sin(end))
              ctx.lineTo(cx + (r + 3) * Math.cos(end), cy + (r + 3) * Math.sin(end))
              ctx.stroke()
            }
          }

          // Plain Rectangle.clip doesn't follow radius — ClippingRectangle
          // does (the exact gotcha the notch's own comments call out).
          ClippingRectangle {
            width: Style.space(92)
            height: Style.space(92)
            anchors.centerIn: parent
            radius: width / 2
            color: root.localArtUrl.length > 0 ? "transparent" : Util.alpha(root.fg, 0.1)

            Image {
              id: discImage
              anchors.fill: parent
              visible: root.localArtUrl.length > 0
              source: root.localArtUrl
              fillMode: Image.PreserveAspectCrop
              smooth: true
              asynchronous: true

              // Slow vinyl-style spin while playing (~28s/rev). Rotates
              // the Image itself, never the clip rectangle, so the
              // circle's antialiased edge stays put while pixels move.
              RotationAnimation on rotation {
                running: root.playing
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 28000
                onRunningChanged: if (!running) discImage.rotation = 0
              }
            }

            Text {
              visible: root.localArtUrl.length === 0
              anchors.centerIn: parent
              text: "󰝚"
              textFormat: Text.PlainText
              color: root.fg
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }
          }
        }

        Column {
          width: parent.width - Style.space(108) - Style.space(12)
          spacing: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            text: root.title.length > 0 ? root.title : "Unknown title"
            textFormat: Text.PlainText
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: root.artist
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            visible: text.length > 0
          }

          Text {
            width: parent.width
            text: root.album
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            visible: text.length > 0
          }

          Text {
            width: parent.width
            text: root.identity.length > 0 ? "via " + root.identity : ""
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            visible: text.length > 0
          }
        }
      }

      // Progress
      Column {
        width: parent.width
        visible: root.hasPlayer
        spacing: Style.space(4)

        Item {
          id: seekArea
          width: parent.width
          height: Style.space(18)

          Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Style.space(6)
            radius: height / 2
            color: root.fg
            opacity: seekMa.enabled && seekMa.containsMouse ? 0.2 : 0.12

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: {
                if (root.lengthSec <= 0) return 0
                var r = root.positionSec / root.lengthSec
                if (!isFinite(r) || r < 0) r = 0
                return parent.width * Math.min(1, r)
              }
              radius: parent.radius
              color: root.accent
            }
          }

          MouseArea {
            id: seekMa
            anchors.fill: parent
            enabled: root.canSeek && root.lengthKnown
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            function seekTo(x) {
              if (parent.width <= 0) return
              var frac = Math.max(0, Math.min(1, x / parent.width))
              var target = frac * root.lengthSec
              if (root.activePlayer.positionSupported)
                root.activePlayer.position = target
              else
                root.activePlayer.seek(target - root.positionSec)
              root.positionSec = target
            }

            onClicked: function(mouse) { seekTo(mouse.x) }
            onPositionChanged: function(mouse) { if (pressed) seekTo(mouse.x) }
          }
        }

        Item {
          width: parent.width
          height: timeElapsed.implicitHeight

          Text {
            id: timeElapsed
            anchors.left: parent.left
            text: root.fmtTime(root.positionSec)
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            text: root.fmtTime(root.lengthSec)
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            visible: root.lengthKnown
          }
        }
      }

      // Output visualizer — newest sample at the right edge.
      Canvas {
        id: viz
        width: parent.width
        height: Style.space(56)
        visible: !!root.sinkNode

        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          var n = root.vizBars
          var bw = width / n
          var levels = root.vizLevels
          var offset = n - levels.length
          for (var i = 0; i < levels.length; i++) {
            var v = Math.max(0, Math.min(1, levels[i]))
            var h = Math.max(2, v * height)
            ctx.fillStyle = Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30 + 0.70 * v)
            ctx.fillRect((offset + i) * bw + 1, height - h, Math.max(1, bw - 2), h)
          }
        }
      }

      // Controls
      Row {
        visible: root.hasPlayer
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(14)

        MediaButton {
          glyph: root.glyphShuffle
          fg: root.fg
          fontFamily: root.fontFamily
          enabled: root.activePlayer && root.activePlayer.shuffleSupported === true
          onClicked: if (root.activePlayer) root.activePlayer.shuffle = !root.activePlayer.shuffle

          Text {
            anchors.centerIn: parent
            visible: root.shuffleOn
            text: "•"
            textFormat: Text.PlainText
            color: root.accent
            font.pixelSize: Style.font.subtitle
            anchors.verticalCenterOffset: Style.space(11)
          }
        }

        MediaButton {
          glyph: "󰒮"
          fg: root.fg
          fontFamily: root.fontFamily
          enabled: root.activePlayer && root.activePlayer.canGoPrevious !== false
          onClicked: root.runAction("previous")
        }

        MediaButton {
          glyph: root.playing ? "󰏤" : "󰐊"
          fg: root.fg
          fontFamily: root.fontFamily
          isPrimary: true
          enabled: root.activePlayer && root.activePlayer.canTogglePlaying !== false
          onClicked: root.runAction("playPause")
        }

        MediaButton {
          glyph: "󰒭"
          fg: root.fg
          fontFamily: root.fontFamily
          enabled: root.activePlayer && root.activePlayer.canGoNext !== false
          onClicked: root.runAction("next")
        }

        MediaButton {
          glyph: root.loopState === 1 ? root.glyphRepeatOnce : root.glyphRepeat
          fg: root.fg
          fontFamily: root.fontFamily
          enabled: root.activePlayer && root.activePlayer.loopSupported === true
          onClicked: {
            if (!root.activePlayer) return
            // MprisLoopState: 0 None, 1 Track, 2 Playlist.
            root.activePlayer.loopState = root.loopState === 2 ? 0 : root.loopState + 1
          }

          Text {
            anchors.centerIn: parent
            visible: root.loopState !== 0
            text: "•"
            textFormat: Text.PlainText
            color: root.accent
            font.pixelSize: Style.font.subtitle
            anchors.verticalCenterOffset: Style.space(11)
          }
        }
      }

      // ---------------------------------------------------------- app mixer
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.sinkStreams.length > 0

        SectionHeader {
          width: parent.width
          title: "APP VOLUME"
          fg: root.fg
          fontFamily: root.fontFamily
        }

        Repeater {
          model: root.sinkStreams

          delegate: Item {
            id: mixRow

            required property var modelData

            width: parent.width
            height: Style.space(28)

            readonly property string label: root.streamLabel(modelData)
            readonly property bool muted: modelData.audio ? modelData.audio.muted === true : false

            Text {
              id: mixGlyph
              anchors.left: parent.left
              anchors.leftMargin: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              text: mixRow.muted ? root.glyphVolMuted : root.glyphVol
              textFormat: Text.PlainText
              color: mixRow.muted ? root.dim : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (mixRow.modelData.audio) mixRow.modelData.audio.muted = !mixRow.modelData.audio.muted
              }
            }

            Text {
              id: mixLabel
              anchors.left: mixGlyph.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth + 2, Style.space(96))
              text: mixRow.label
              textFormat: Text.PlainText
              color: mixRow.muted ? root.dim : root.fg
              opacity: mixRow.muted ? 0.6 : 1.0
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            HSlider {
              anchors.left: mixLabel.right
              anchors.leftMargin: Style.space(8)
              anchors.right: mixPct.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              fg: root.fg
              value: mixRow.modelData.audio ? Number(mixRow.modelData.audio.volume) || 0 : 0
              onMoved: function(v) { if (mixRow.modelData.audio) mixRow.modelData.audio.volume = v }
            }

            Text {
              id: mixPct
              anchors.right: parent.right
              anchors.rightMargin: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round((mixRow.modelData.audio ? Number(mixRow.modelData.audio.volume) || 0 : 0) * 100) + "%"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // Breathing room at the bottom.
      Item { width: parent.width; height: Style.space(4) }
    }
  }
}
