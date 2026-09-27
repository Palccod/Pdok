pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Commons

// Compact 3D photo deck (pattern from dagyr.desktop-widgets' gallery):
// three tilted, darkened back layers fanned behind a front card that plays
// GIFs via AnimatedImage. Click the right half to advance, left half to go
// back; back cards spread wider on hover.
Rectangle {
  id: root

  color: "transparent"

  property var files: []            // file:// URLs, whitelisted by the service
  property string dirLabel: ""      // active directory, for the empty state
  property color fg: "#ffffff"
  property string fontFamily: Style.font.family
  property int intervalMs: 15000

  // Raised when the user asks for the folder picker (folder button on the
  // card, or the empty-state entry).
  signal pickRequested()

  readonly property int cardCount: Math.min(4, files.length)
  property int index: 0
  readonly property string currentPath: files.length > 0 ? files[index % files.length] : ""
  readonly property bool isGif: currentPath.toLowerCase().indexOf(".gif") !== -1
  readonly property string title: {
    var parts = currentPath.split("/")
    return parts.length > 0 ? parts[parts.length - 1] : ""
  }
  readonly property bool hovered: frontHover.hovered

  function next() {
    if (files.length > 0) index = (index + 1) % files.length
  }

  function prev() {
    if (files.length > 0) index = (index - 1 + files.length) % files.length
  }

  function fileAt(offset) {
    if (files.length === 0) return ""
    return files[(index + offset + files.length * 4) % files.length]
  }

  height: Style.space(216)

  Timer {
    interval: root.intervalMs
    running: root.files.length > 1
    repeat: true
    onTriggered: root.next()
  }

  // Back layers: deepest first, static images only (cheaper than animating
  // four GIFs), peaking out from behind the front card.
  Repeater {
    model: 3

    delegate: Item {
      id: backCard

      required property int index

      readonly property real depth: 3 - index  // 3, 2, 1
      readonly property bool active: root.cardCount > index + 1
      readonly property real spread: root.hovered ? 1.5 : 1.0
      readonly property real baseRot: index === 0 ? -4.6 : (index === 1 ? 3.8 : -2.8)
      readonly property real baseX: index === 0 ? -7 : (index === 1 ? 6 : -4)

      width: frontCard.width * (0.985 - 0.018 * index)
      height: frontCard.height * (0.985 - 0.018 * index)
      anchors.verticalCenter: frontCard.verticalCenter
      visible: active
      z: 1 + index
      rotation: baseRot * (root.hovered ? 1.3 : 1.0)
      x: (frontCard.width - width) / 2 + baseX * spread

      Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
      Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

      Item {
        id: backSrc
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Image {
          anchors.fill: parent
          source: backCard.active ? root.fileAt(backCard.index + 1) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          smooth: true
          opacity: status === Image.Ready ? 1.0 : 0.0
        }

        Rectangle {
          anchors.fill: parent
          color: "black"
          opacity: 0.12 + 0.14 * (backCard.depth - 1)
        }
      }

      Item {
        id: backMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
          anchors.fill: parent
          radius: Style.space(10)
          color: "black"
        }
      }

      MultiEffect {
        anchors.fill: parent
        source: backSrc
        maskEnabled: true
        maskSource: backMask
      }
    }
  }

  // Front card
  Rectangle {
    id: frontCard
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(12)
    height: parent.height - Style.space(24)
    radius: Style.space(10)
    color: Util.alpha(root.fg, 0.06)
    z: 5

    Item {
      id: frontMask
      anchors.fill: parent
      visible: false
      layer.enabled: true

      Rectangle {
        anchors.fill: parent
        radius: frontCard.radius
        color: "black"
      }
    }

    // Static image (png/jpg/webp or gif still loading elsewhere)
    Image {
      id: frontStill
      anchors.fill: parent
      visible: !root.isGif
      source: !root.isGif && root.currentPath !== "" ? root.currentPath : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      opacity: status === Image.Ready ? 1.0 : 0.0
      Behavior on opacity { NumberAnimation { duration: 300 } }
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: frontMask
      }
    }

    // Animated GIF
    AnimatedImage {
      id: frontGif
      anchors.fill: parent
      visible: root.isGif
      source: root.isGif ? root.currentPath : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: false
      smooth: true
      playing: root.visible && root.isGif
      paused: false
      cache: false
      opacity: status === AnimatedImage.Ready ? 1.0 : 0.0
      Behavior on opacity { NumberAnimation { duration: 250 } }

      onStatusChanged: {
        if (status === AnimatedImage.Ready) {
          playing = true
          paused = false
        }
      }

      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: frontMask
      }
    }

    // Paper edge
    Rectangle {
      anchors.fill: parent
      radius: frontCard.radius
      color: "transparent"
      border.color: root.fg
      border.width: 1
      opacity: 0.14
    }

    // Hover overlay: title + index
    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: Style.space(40)
      radius: frontCard.radius
      opacity: root.hovered ? 1.0 : 0.0
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.72) }
        GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.25) }
        GradientStop { position: 1.0; color: "transparent" }
      }

      Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: Style.space(8)
        anchors.leftMargin: Style.space(12)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(64)
        text: root.title
        textFormat: Text.PlainText
        color: "#ffffff"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(8)
        width: countText.implicitWidth + Style.space(12)
        height: Style.space(18)
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.6)

        Text {
          id: countText
          anchors.centerIn: parent
          text: root.files.length > 0 ? (root.index + 1) + " / " + root.files.length : "0 / 0"
          textFormat: Text.PlainText
          color: "#ffffff"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // Empty state
    Column {
      anchors.centerIn: parent
      visible: root.files.length === 0
      spacing: Style.space(6)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "󰚝"
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
      }

      Text {
        width: frontCard.width - Style.space(24)
        text: root.dirLabel.length > 0
          ? "No images in " + root.dirLabel
          : "Drop GIFs in ~/.local/state/omarchy/pdok/gifs"
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: pickLabel.implicitWidth + Style.space(16)
        height: pickLabel.implicitHeight + Style.space(8)
        radius: height / 2
        color: pickMa.containsMouse ? Style.hoverFill : "transparent"
        border.width: 1
        border.color: root.fg
        opacity: 0.7

        Text {
          id: pickLabel
          anchors.centerIn: parent
          text: "Choose folder…"
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: pickMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.pickRequested()
        }
      }
    }

    HoverHandler {
      id: frontHover
    }

    // Click: right half next, left half previous
    MouseArea {
      anchors.fill: parent
      enabled: root.files.length > 1
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.x > frontCard.width / 2) root.next()
        else root.prev()
      }
    }

    // Folder picker entry, bottom-right of the card on hover.
    Rectangle {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(8)
      width: Style.space(26)
      height: Style.space(26)
      radius: height / 2
      color: pickBtnMa.containsMouse ? Qt.rgba(0, 0, 0, 0.85) : Qt.rgba(0, 0, 0, 0.6)
      opacity: root.hovered ? 1.0 : 0.0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

      Text {
        anchors.centerIn: parent
        text: "󰉋"
        textFormat: Text.PlainText
        color: "#ffffff"
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        id: pickBtnMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pickRequested()
      }
    }
  }
}
