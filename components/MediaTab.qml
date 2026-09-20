pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// Media tab: now-playing with playback controls. Prefers the first-party
// omarchy.media service (preferred-player logic + OSD feedback) and falls
// back to direct Mpris when it is disabled.
Rectangle {
  id: root

  color: "transparent"

  property var shell: null        // bar.shell, to reach omarchy.media
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  // Mpris fallback
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var directPlayer: {
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (p && (p.trackTitle || p.trackArtist)) return p
    }
    return players.length > 0 ? players[0] : null
  }

  // omarchy.media's active player, when available
  readonly property var mediaService: shell && shell.serviceFor
    ? shell.serviceFor("omarchy.media") : null
  readonly property var activePlayer: mediaService
    ? mediaService.activePlayer : directPlayer

  readonly property bool hasPlayer: !!activePlayer
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string identity: activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || "") : ""
  readonly property bool playing: activePlayer && activePlayer.isPlaying

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

      // Art + track info
      Row {
        width: parent.width
        visible: root.hasPlayer
        spacing: Style.space(12)

        Rectangle {
          width: Style.space(96)
          height: Style.space(96)
          radius: Style.space(4)
          color: root.localArtUrl.length > 0 ? "transparent" : Util.alpha(root.fg, 0.1)

          Image {
            anchors.fill: parent
            visible: root.localArtUrl.length > 0
            source: root.localArtUrl
            fillMode: Image.PreserveAspectCrop
            smooth: true
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

        Column {
          width: parent.width - Style.space(96) - Style.space(12)
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
              color: Color.accent
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

      // Controls
      Row {
        visible: root.hasPlayer
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(18)

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
      }
    }
  }
}
