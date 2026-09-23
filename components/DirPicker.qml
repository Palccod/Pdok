pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons

// In-drawer folder browser for picking the GIF deck directory. Layer-shell
// surfaces have no native dialogs, so this walks the tree with a fixed-argv
// `ls -1Ap` and offers the subdirectories of the current path. "Use this
// folder" hands the path to applyDir (a function set by the host) which
// validates, applies and persists the choice and returns a status line —
// a success reply closes the picker, a failure is shown in place.
Rectangle {
  id: root

  property var svc: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family
  property var applyDir: null

  visible: false
  z: 50
  clip: true

  property string currentDir: ""
  property var dirs: []
  property string statusText: ""

  readonly property var rows: {
    var r = []
    if (root.currentDir !== "/") r.push("..")
    for (var i = 0; i < root.dirs.length; i++) r.push(root.dirs[i])
    if (r.length === 0) r.push("")
    return r
  }

  function openFor(startDir) {
    var d = String(startDir === undefined || startDir === null ? "" : startDir)
    if (d.length === 0 && root.svc) d = root.svc.activeGifDir
    if (d.length === 0 && root.svc) d = root.svc.home
    root.currentDir = d
    root.statusText = ""
    root.visible = true
    root.refresh()
  }

  function close() {
    root.visible = false
  }

  function refresh() {
    if (listProc.running) return
    listProc.command = ["/usr/bin/ls", "-1Ap", "--", root.currentDir]
    listProc.running = true
  }

  function goUp() {
    var p = root.currentDir.replace(/\/+$/, "")
    var idx = p.lastIndexOf("/")
    root.currentDir = idx <= 0 ? "/" : p.slice(0, idx)
    root.refresh()
  }

  function enter(name) {
    var base = root.currentDir.replace(/\/+$/, "")
    root.currentDir = base === "" || base === "/" ? "/" + name : base + "/" + name
    root.refresh()
  }

  function goHome() {
    if (!root.svc) return
    root.currentDir = root.svc.home
    root.refresh()
  }

  function use() {
    var msg = root.applyDir ? String(root.applyDir(root.currentDir)) : "service unavailable"
    if (msg.indexOf("gifDir=") === 0) {
      root.close()
    } else {
      root.statusText = msg
    }
  }

  Process {
    id: listProc
    onExited: if (exitCode !== 0) root.statusText = "can't read that folder"
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          // `-p` appends "/" to directories, so only those survive the filter.
          var line = lines[i]
          if (!line.endsWith("/")) continue
          var name = line.slice(0, -1)
          if (name.length === 0) continue
          out.push(name)
        }
        out.sort(function(a, b) {
          var la = a.toLowerCase(), lb = b.toLowerCase()
          return la < lb ? -1 : (la > lb ? 1 : 0)
        })
        root.dirs = out
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: parent.width - Style.space(16)
    height: Math.min(parent.height - Style.space(16), Style.space(480))
    radius: Style.space(10)
    color: Color.popups.background
    border.width: 1
    border.color: Util.alpha(root.fg, 0.18)

    // Header
    Item {
      id: header
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Style.space(12)
      height: Style.space(24)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Choose GIF folder"
        textFormat: Text.PlainText
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Rectangle {
        id: closeBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(22)
        height: Style.space(22)
        radius: height / 2
        color: closeMa.containsMouse ? Style.hoverFill : "transparent"

        Text {
          anchors.centerIn: parent
          text: "✕"
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: closeMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.close()
        }
      }
    }

    // Path bar: home · current path · up
    Rectangle {
      id: pathBar
      anchors.top: header.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: Style.space(10)
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      height: Style.space(30)
      radius: Style.space(6)
      color: Util.alpha(root.fg, 0.05)

      Rectangle {
        id: homeBtn
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(3)
        width: Style.space(24)
        height: Style.space(24)
        radius: height / 2
        color: homeMa.containsMouse ? Style.hoverFill : "transparent"

        Text {
          anchors.centerIn: parent
          text: "󰋜"
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: homeMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.goHome()
        }
      }

      Text {
        anchors.left: homeBtn.right
        anchors.leftMargin: Style.space(8)
        anchors.right: upBtn.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: root.currentDir
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }

      Rectangle {
        id: upBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Style.space(3)
        width: Style.space(24)
        height: Style.space(24)
        radius: height / 2
        color: upMa.containsMouse ? Style.hoverFill : "transparent"

        Text {
          anchors.centerIn: parent
          text: "󰁔"
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: upMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.goUp()
        }
      }
    }

    // Directory list
    ListView {
      id: dirList
      anchors.top: pathBar.bottom
      anchors.bottom: statusText.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: Style.space(8)
      anchors.bottomMargin: Style.space(8)
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.rows

      delegate: Item {
        id: dirRow

        required property var modelData
        required property int index

        width: dirList.width
        height: Style.space(26)

        readonly property bool isUp: modelData === ".."
        readonly property bool isEmpty: modelData === ""

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          radius: Style.space(5)
          color: rowMa.pressed ? Style.pressedFill
            : rowMa.containsMouse ? Style.hoverFill : "transparent"
          visible: !dirRow.isEmpty
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: dirRow.isUp ? "󰁔" : "󰉋"
          textFormat: Text.PlainText
          color: root.fg
          opacity: dirRow.isUp ? 0.5 : 0.65
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          visible: !dirRow.isEmpty
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(34)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: dirRow.isEmpty ? "no subfolders here" : dirRow.modelData
          textFormat: Text.PlainText
          color: root.fg
          opacity: dirRow.isEmpty ? 0.35 : 0.9
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        MouseArea {
          id: rowMa
          anchors.fill: parent
          enabled: !dirRow.isEmpty
          hoverEnabled: true
          cursorShape: dirRow.isEmpty ? Qt.ArrowCursor : Qt.PointingHandCursor
          onClicked: dirRow.isUp ? root.goUp() : root.enter(dirRow.modelData)
        }
      }
    }

    // Status / error line
    Text {
      id: statusText
      anchors.bottom: footer.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottomMargin: Style.space(6)
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      height: text.length > 0 ? implicitHeight : 0
      text: root.statusText
      textFormat: Text.PlainText
      color: Color.urgent
      opacity: 0.9
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      visible: text.length > 0
    }

    // Footer: select / reset / cancel
    Row {
      id: footer
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottomMargin: Style.space(12)
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(8)

      Repeater {
        model: [
          { label: "Use this folder", action: "use", primary: true },
          { label: "Reset", action: "reset", primary: false },
          { label: "Cancel", action: "cancel", primary: false }
        ]

        delegate: Rectangle {
          id: footBtn

          required property var modelData

          width: footLabel.implicitWidth + Style.space(16)
          height: footLabel.implicitHeight + Style.space(9)
          radius: height / 2
          color: footMa.pressed ? Style.pressedFill
            : footMa.containsMouse ? Style.hoverFill : "transparent"
          border.width: 1
          border.color: footBtn.modelData.primary ? Color.accent : Util.alpha(root.fg, 0.4)
          opacity: 0.9

          Text {
            id: footLabel
            anchors.centerIn: parent
            text: footBtn.modelData.label
            textFormat: Text.PlainText
            color: footBtn.modelData.primary ? Color.accent : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: footBtn.modelData.primary
          }

          MouseArea {
            id: footMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (footBtn.modelData.action === "use") root.use()
              else if (footBtn.modelData.action === "reset") {
                var msg = root.applyDir ? String(root.applyDir("")) : "service unavailable"
                if (msg.indexOf("gifDir=") === 0) root.close()
                else root.statusText = msg
              } else root.close()
            }
          }
        }
      }
    }
  }
}
