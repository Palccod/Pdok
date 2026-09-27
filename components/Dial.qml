pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Ruixen-style circular dial: a round tonal badge wrapping a Canvas ring
// that sweeps 270deg (45deg gap at the bottom, Material-3 gap-progress
// style). Accent arc with a thick white tip tick; center glyph. Click and
// scroll both act: `activated()` on click, `moved(delta)` per scroll step
// (0.05, matching Omarchy's audio panel convention).
Rectangle {
  id: root

  property string glyph: ""
  property string mutedGlyph: ""
  property bool muted: false
  property real value: 0          // 0..1
  property string caption: ""
  property color accent: "#3ecf5b"
  property color fg: "#ffffff"
  property string fontFamily: "JetBrainsMono Nerd Font"
  signal activated()
  signal moved(real delta)

  width: 56
  height: caption.length > 0 ? 56 + 18 : 56
  radius: width / 2
  color: Qt.rgba(1, 1, 1, 0.06)

  // Display override: muted reads as zero without touching the real value.
  readonly property real effectiveValue: muted ? 0 : Math.max(0, Math.min(1, value))
  onEffectiveValueChanged: ringCanvas.requestPaint()
  onAccentChanged: ringCanvas.requestPaint()

  Canvas {
    id: ringCanvas
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2, cy = height / 2
      var r = width / 2 - 8
      // Start at ~7:30 on a clock face, sweep 270deg clockwise; the gap
      // sits at the bottom.
      var startAngle = Math.PI / 2 + Math.PI / 4
      var totalSweep = Math.PI * 2 - Math.PI / 2
      var endAngle = startAngle + root.effectiveValue * totalSweep
      // Gap around the tip: 6px converted to radians at this radius.
      var gapRad = 6 / r
      var trackStart = Math.min(startAngle + totalSweep, endAngle + gapRad)
      ctx.lineWidth = 3
      ctx.lineCap = "round"
      ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15)
      ctx.beginPath()
      ctx.arc(cx, cy, r, trackStart, startAngle + totalSweep)
      ctx.stroke()

      ctx.strokeStyle = root.accent
      ctx.beginPath()
      var progressEnd = Math.max(startAngle, endAngle - gapRad)
      ctx.arc(cx, cy, r, startAngle, progressEnd)
      ctx.stroke()

      // Thick white tip tick, always drawn (sits at 0 position when
      // muted/empty) -- same treatment as the notch's dials.
      var tipR1 = r - 2, tipR2 = r + 3
      ctx.lineWidth = 5
      ctx.lineCap = "round"
      ctx.strokeStyle = "#ffffff"
      ctx.beginPath()
      ctx.moveTo(cx + tipR1 * Math.cos(endAngle), cy + tipR1 * Math.sin(endAngle))
      ctx.lineTo(cx + tipR2 * Math.cos(endAngle), cy + tipR2 * Math.sin(endAngle))
      ctx.stroke()
    }
  }

  Text {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: root.caption.length > 0 ? -6 : 0
    text: root.muted && root.mutedGlyph.length > 0 ? root.mutedGlyph : root.glyph
    textFormat: Text.PlainText
    // Same fixed red the notch uses for "muted/off" (semantic, not theme).
    color: root.muted && root.mutedGlyph.length > 0 ? "#e05252" : root.fg
    font.family: root.fontFamily
    font.pixelSize: 20
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 2
    visible: root.caption.length > 0
    text: root.caption
    textFormat: Text.PlainText
    color: root.fg
    opacity: 0.5
    font.family: root.fontFamily
    font.pixelSize: 9
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    property real accumulator: 0
    onClicked: root.activated()
    onWheel: function(wheel) {
      var steps = wheel.angleDelta.y > 0 ? 1 : (wheel.angleDelta.y < 0 ? -1 : 0)
      if (steps !== 0) root.moved(0.05 * steps)
      wheel.accepted = true
    }
  }
}
