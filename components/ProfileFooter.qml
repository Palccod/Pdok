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

      // User-picked avatar, animated when it's a GIF (GifDeck's pattern:
      // AnimatedImage with playing bound, cache off so re-picks reload).
      AnimatedImage {
        id: customGif
        readonly property bool active: root.useCustom && root.svc.customAvatarGif === true
        anchors.fill: parent
        visible: active && status === AnimatedImage.Ready
        source: active ? root.customUrl : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        smooth: true
        playing: active && avatarCircle.visible
        cache: false
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: circleMask
        }

        onStatusChanged: {
          if (status === AnimatedImage.Ready) {
            playing = true
            paused = false
          }
        }
      }

      // Static custom pick (png/jpg/webp).
      Image {
        id: customImg
        readonly property bool active: root.useCustom && root.svc.customAvatarGif === false
        anchors.fill: parent
        visible: active && status === Image.Ready
        source: active ? root.customUrl : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: circleMask
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

      // Ring on top so it stays visible over opaque images; accent on hover
      // — the avatar is a button.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: avatarMa.containsMouse ? root.accent : root.fg
        opacity: 0.9
      }

      // Hover affordance: scrim + pencil over the image.
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
