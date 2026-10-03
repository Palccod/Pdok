pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui

// Drawer footer, pinned under every tab: the user's avatar and name.
// Avatar preference order: the user's own pick (copied into the state dir
// by the service; GIFs render via AnimatedImage), then the GitHub profile
// picture, then ~/.face, then the AccountsService icon, then a plain
// initial-on-circle. Clicking the avatar opens the in-drawer image picker
// (pickRequested). Name: GitHub display name, then login, then $USER.
Rectangle {
  id: root

  property var svc: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family
  signal pickRequested()

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string userName: {
    var n = svc ? String(svc.ghName || "") : ""
    if (n.length > 0) return n
    var login = svc ? String(svc.ghLogin || "") : ""
    if (login.length > 0) return login
    return Quickshell.env("USER") || ""
  }
  readonly property string userLogin: svc ? String(svc.ghLogin || "") : ""

  readonly property bool useCustom: svc ? svc.customAvatarActive === true : false
  // avatarVersion cache-busts both the GitHub download and a re-picked
  // custom avatar (same fixed destination path → same URL otherwise).
  readonly property string customUrl: useCustom && svc
    ? "file://" + String(svc.customAvatarPath || "") + "?v=" + (svc.avatarVersion || 0) : ""
  readonly property bool customReady: customGif.visible || customImg.visible
  // Framing dialed in on the picker's preview (zoom 1 = whole image, pan
  // offsets normalized -1..1 across each axis's actual overflow).
  readonly property real framingZoom: svc ? Number(svc.avatarZoom) || 1 : 1
  readonly property real framingOx: svc ? Number(svc.avatarOx) || 0 : 0
  readonly property real framingOy: svc ? Number(svc.avatarOy) || 0 : 0

  color: "transparent"
  height: Style.space(58)

  // Hairline separating the footer from the tab above it.
  Rectangle {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 1
    color: root.fg
    opacity: 0.1
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    Item {
      id: avatarCircle
      width: Style.space(38)
      height: Style.space(38)
      clip: true
      anchors.verticalCenter: parent.verticalCenter

      // Circle mask shared by every avatar candidate — Rectangle.clip clips
      // to the bounding rect and ignores radius, so an opaque image would
      // render as a square overflowing the ring without it.
      Item {
        id: circleMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
          anchors.fill: parent
          radius: avatarCircle.width / 2
          color: "black"
        }
      }

      // Initials fallback also backs transparent GIFs/PNGs.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Util.alpha(root.fg, 0.08)
      }

      // Custom pick wrappers: the layer+mask must live on a CIRCLE-SIZED
      // item — MultiEffect stretches maskSource over the source item's own
      // bounds, so masking the oversized image directly stretches the circle
      // into a square. The oversized image is a plain child; the wrapper's
      // layer clips it to the circle box and the mask rounds it.
      // NOTE: the wrapper itself is always visible — binding its visible to
      // the child's knots the two together (the child's reported visibility
      // then depends on the wrapper's) and both stay false forever.
      Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: circleMask
        }

        // Animated when it's a GIF (GifDeck's pattern: playing bound, cache
        // off so re-picks reload). Geometry is manual — fit-scaled by the
        // saved framing, pannable — so a huge GIF (1920×1080 retro2_live)
        // can show its whole frame instead of a center slice.
        AnimatedImage {
          id: customGif
          readonly property bool active: root.useCustom && root.svc.customAvatarGif === true
          visible: active && status === AnimatedImage.Ready
          source: active ? root.customUrl : ""
          asynchronous: false
          smooth: true
          playing: active && avatarCircle.visible
          cache: false
          readonly property real natW: implicitWidth || 1
          readonly property real natH: implicitHeight || 1
          readonly property real fit: Math.min(avatarCircle.width / natW, avatarCircle.height / natH)
          readonly property real sc: fit * root.framingZoom
          width: natW * sc
          height: natH * sc
          x: (avatarCircle.width - width) / 2 + root.framingOx * Math.max(0, (width - avatarCircle.width) / 2)
          y: (avatarCircle.height - height) / 2 + root.framingOy * Math.max(0, (height - avatarCircle.height) / 2)

          onStatusChanged: {
            if (status === AnimatedImage.Ready) {
              playing = true
              paused = false
            }
          }
        }
      }

      // Static custom pick (png/jpg/webp).
      Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: circleMask
        }

        Image {
          id: customImg
          readonly property bool active: root.useCustom && root.svc.customAvatarGif === false
          visible: active && status === Image.Ready
          source: active ? root.customUrl : ""
          smooth: true
          asynchronous: true
          readonly property real natW: implicitWidth || 1
          readonly property real natH: implicitHeight || 1
          readonly property real fit: Math.min(avatarCircle.width / natW, avatarCircle.height / natH)
          readonly property real sc: fit * root.framingZoom
          width: natW * sc
          height: natH * sc
          x: (avatarCircle.width - width) / 2 + root.framingOx * Math.max(0, (width - avatarCircle.width) / 2)
          y: (avatarCircle.height - height) / 2 + root.framingOy * Math.max(0, (height - avatarCircle.height) / 2)
        }
      }

      // GitHub avatar (service bumps avatarVersion after a download so the
      // Image cache busts via the ?v query — toLocalFile() drops the query).
      Image {
        id: ghAvatar
        anchors.fill: parent
        source: root.svc && String(root.svc.avatarPath || "").length > 0
          ? "file://" + root.svc.avatarPath + "?v=" + (root.svc.avatarVersion || 0) : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        visible: !root.customReady && status === Image.Ready
        asynchronous: true
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: circleMask
        }
      }

      Image {
        id: faceAvatar
        anchors.fill: parent
        source: root.home.length > 0 ? "file://" + root.home + "/.face" : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        visible: !root.customReady && !ghAvatar.visible && status === Image.Ready
        asynchronous: true
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: circleMask
        }
      }

      Image {
        id: acctAvatar
        anchors.fill: parent
        source: "file:///var/lib/AccountsService/icons/" + (Quickshell.env("USER") || "")
        fillMode: Image.PreserveAspectCrop
        smooth: true
        visible: !root.customReady && !ghAvatar.visible && !faceAvatar.visible && status === Image.Ready
        asynchronous: true
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: circleMask
        }
      }

      Text {
        anchors.centerIn: parent
        visible: !root.customReady && !ghAvatar.visible && !faceAvatar.visible && !acctAvatar.visible
        text: root.userName.length > 0 ? root.userName.charAt(0).toUpperCase() : "?"
        textFormat: Text.PlainText
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      // Hover affordance: scrim + pencil over the image — the avatar is a
      // button. No ring; the user wants the circle border gone.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.4)
        visible: avatarMa.containsMouse

        Text {
          anchors.centerIn: parent
          text: "󰏫"
          textFormat: Text.PlainText
          color: "#ffffff"
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      MouseArea {
        id: avatarMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pickRequested()
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        text: root.userName.length > 0 ? root.userName : "Pdok"
        textFormat: Text.PlainText
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
        width: Math.min(implicitWidth, Style.space(220))
      }

      Text {
        text: root.userLogin.length > 0 ? "@" + root.userLogin : ""
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: Math.min(implicitWidth, Style.space(220))
        visible: text.length > 0
      }
    }
  }
}
