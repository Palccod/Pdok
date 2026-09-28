pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Drawer footer, pinned under every tab: the user's avatar and name.
// Avatar preference order: the GitHub profile picture the service caches
// under the state dir, then ~/.face, then the AccountsService icon, then a
// plain initial-on-circle. Name: GitHub display name, then login, then $USER.
Rectangle {
  id: root

  property var svc: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string userName: {
    var n = svc ? String(svc.ghName || "") : ""
    if (n.length > 0) return n
    var login = svc ? String(svc.ghLogin || "") : ""
    if (login.length > 0) return login
    return Quickshell.env("USER") || ""
  }
  readonly property string userLogin: svc ? String(svc.ghLogin || "") : ""

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

    Rectangle {
      width: Style.space(38)
      height: Style.space(38)
      radius: width / 2
      color: Util.alpha(root.fg, 0.08)
      clip: true
      border.width: 1
      border.color: root.fg
      opacity: 0.9
      anchors.verticalCenter: parent.verticalCenter

      // GitHub avatar (service bumps avatarVersion after a download so the
      // Image cache busts via the ?v query — toLocalFile() drops the query).
      Image {
        id: ghAvatar
        anchors.fill: parent
        source: root.svc && String(root.svc.avatarPath || "").length > 0
          ? "file://" + root.svc.avatarPath + "?v=" + (root.svc.avatarVersion || 0) : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        visible: status === Image.Ready
        asynchronous: true
      }

      Image {
        id: faceAvatar
        anchors.fill: parent
        source: root.home.length > 0 ? "file://" + root.home + "/.face" : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        visible: !ghAvatar.visible && status === Image.Ready
        asynchronous: true
      }

      Image {
        id: acctAvatar
        anchors.fill: parent
        source: "file:///var/lib/AccountsService/icons/" + (Quickshell.env("USER") || "")
        fillMode: Image.PreserveAspectCrop
        smooth: true
        visible: !ghAvatar.visible && !faceAvatar.visible && status === Image.Ready
        asynchronous: true
      }

      Text {
        anchors.centerIn: parent
        visible: !ghAvatar.visible && !faceAvatar.visible && !acctAvatar.visible
        text: root.userName.length > 0 ? root.userName.charAt(0).toUpperCase() : "?"
        textFormat: Text.PlainText
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
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
