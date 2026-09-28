pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Ruixen-style circular dial: a round tonal badge wrapping a Canvas ring
// that sweeps 270deg (45deg gap at the bottom, Material-3 gap-progress
// style). Accent arc with a thick tip tick; center glyph. Click and scroll
// both act: `activated()` on click, `moved(delta)` per scroll step (0.05,
// matching Omarchy's audio panel convention).
Rectangle {
  id: root

  property string glyph: ""
  property string mutedGlyph: ""
  property bool muted: false
  property real value: 0          // 0..1
  property color accent: Color.accent
  property color fg: Color.foreground
  property color danger: Color.urgent
  property string fontFamily: Style.font.family
  signal activated()
  signal moved(real delta)

  width: 56
  height: 56
  radius: width / 2
  color: Qt.rgba(fg.r, fg.g, fg.b, 0.06)

  // Display override: muted reads as zero without touching the real value.
  readonly property real effectiveValue: muted ? 0 : Math.max(0, Math.min(1, value))
  onEffectiveValueChanged: ringCanvas.requestPaint()
  onAccentChanged: ringCanvas.requestPaint()
  onFgChanged: ringCanvas.requestPaint()

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
      ctx.lineWidth = 4
      ctx.lineCap = "round"
      ctx.strokeStyle = Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
      ctx.beginPath()
      ctx.arc(cx, cy, r, trackStart, startAngle + totalSweep)
      ctx.stroke()

      ctx.strokeStyle = root.accent
      ctx.beginPath()
      var progressEnd = Math.max(startAngle, endAngle - gapRad)
      ctx.arc(cx, cy, r, startAngle, progressEnd)
      ctx.stroke()

      // Thick tip tick, always drawn (sits at 0 position when muted or
      // empty) — same treatment as the notch's dials.
      var tipR1 = r - 2, tipR2 = r + 3
      ctx.lineWidth = 5
      ctx.lineCap = "round"
      ctx.strokeStyle = root.fg
      ctx.beginPath()
      ctx.moveTo(cx + tipR1 * Math.cos(endAngle), cy + tipR1 * Math.sin(endAngle))
      ctx.lineTo(cx + tipR2 * Math.cos(endAngle), cy + tipR2 * Math.sin(endAngle))
      ctx.stroke()
    }
  }

  Text {
    anchors.centerIn: parent
    text: root.muted && root.mutedGlyph.length > 0 ? root.mutedGlyph : root.glyph
    textFormat: Text.PlainText
    // Semantic "muted/off" color, not theme-linked — same reasoning as the
    // notch's red bell.
    color: root.muted && root.mutedGlyph.length > 0 ? root.danger : root.fg
    font.family: root.fontFamily
    font.pixelSize: 20
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  // WheelHandler, not MouseArea.onWheel: it claims wheel events directly
  // and blocks them from reaching the Flickable above, which was eating
  // every scroll over the dials.
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(ev) {
      var steps = ev.angleDelta.y > 0 ? 1 : (ev.angleDelta.y < 0 ? -1 : 0)
      if (steps !== 0) root.moved(0.05 * steps)
      ev.accepted = true
    }
  }
}
