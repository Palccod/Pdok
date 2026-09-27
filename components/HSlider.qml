pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// Horizontal 0..1 slider drawn from primitives so it matches the drawer's
// flat look. The slider never writes its own `value` (that stays the
// caller's binding); while dragging it only lifts a local `dragValue` into
// the visual fill and emits `moved` continuously, so callers can push the
// new value into hardware without a feedback loop.
Rectangle {
  id: root

  property real value: 0
  property color fg: Color.foreground
  property color accent: Color.accent
  signal moved(real newValue)

  width: 120
  height: Style.space(22)
  radius: height / 2
  color: "transparent"

  // What the fill and knob show: the live drag position while pressed,
  // the external truth otherwise.
  readonly property real shown: ma.pressed ? dragValue : value
  property real dragValue: 0

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: Style.space(6)
    radius: height / 2
    color: root.fg
    opacity: 0.12

    Rectangle {
      id: fill
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.max(0, Math.min(1, root.shown)) * track.width
      radius: parent.radius
      color: root.accent
    }
  }

  Rectangle {
    id: knob
    width: ma.pressed ? Style.space(13) : (ma.containsMouse ? Style.space(12) : Style.space(10))
    height: width
    radius: width / 2
    color: root.accent
    anchors.verticalCenter: parent.verticalCenter
    x: Math.max(0, Math.min(parent.width - width, root.shown * (parent.width - width)))
    Behavior on width { NumberAnimation { duration: 90 } }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    function apply(px) {
      var w = root.width - knob.width
      if (w <= 0) return
      var frac = Math.max(0, Math.min(1, (px - knob.width / 2) / w))
      root.dragValue = frac
      root.moved(frac)
    }

    onClicked: function(mouse) { apply(mouse.x) }
    onPositionChanged: function(mouse) { if (pressed) apply(mouse.x) }
    onPressedChanged: if (pressed) root.dragValue = root.value
  }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(ev) {
      var step = ev.angleDelta.y > 0 ? 0.05 : -0.05
      var next = Math.max(0, Math.min(1, root.value + step))
      if (next !== root.value) root.moved(next)
      ev.accepted = true
    }
  }
}
