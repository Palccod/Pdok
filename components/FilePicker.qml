pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Io
import qs.Commons

// In-drawer file browser for picking a profile picture. Same layer-shell
// constraint as DirPicker — no native dialogs — so this walks the tree with
// a fixed-argv `ls -1Ap` and offers subdirectories plus image files.
// Clicking a file selects it (live preview in the footer, animated for
// GIFs); "Use this image" hands the path to applyFile, set by the host,
// which validates, copies and returns a status line — a reply starting
// "avatar=" closes the picker, anything else is shown in place.
// applyFile("") resets to the GitHub avatar.
Rectangle {
  id: root

  property var svc: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family
  property var applyFile: null

  visible: false
  z: 50
  clip: true

  property string currentDir: ""
  property var dirs: []
  property var files: []
  property string selectedFile: ""
  property string statusText: ""
  // Pictures is the natural start point but may not exist — the first
  // failed listing there falls back to home, once.
  property bool _triedPictures: false

  readonly property bool selectedIsGif: selectedFile.toLowerCase().endsWith(".gif")

  readonly property var rows: {
    var r = []
    if (root.currentDir !== "/") r.push({ name: "..", isDir: true })
    for (var i = 0; i < root.dirs.length; i++) r.push({ name: root.dirs[i], isDir: true })
    for (var j = 0; j < root.files.length; j++) r.push({ name: root.files[j], isDir: false })
    if (root.dirs.length === 0 && root.files.length === 0)
      r.push({ name: "", isDir: false })
    return r
  }

  function openFor(startDir) {
    var d = String(startDir === undefined || startDir === null ? "" : startDir)
    if (d.length === 0 && root.svc) d = root.svc.home + "/Pictures"
    if (d.length === 0 && root.svc) d = root.svc.home
    root._triedPictures = false
    root.selectedFile = ""
    root.statusText = ""
    root.currentDir = d
    root.visible = true
    root.refresh()
    // Preselect the already-applied avatar (with its saved framing) so it
    // can be adjusted without re-finding the file.
    if (root.svc && root.svc.customAvatarActive === true
        && String(root.svc.customAvatarPath || "").length > 0) {
      root.selectedFile = String(root.svc.customAvatarPath)
      previewItem.zoom = root.svc.avatarZoom
      previewItem.ox = root.svc.avatarOx
      previewItem.oy = root.svc.avatarOy
    }
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
    root.selectedFile = ""
    root.refresh()
  }

  function enter(name) {
    var base = root.currentDir.replace(/\/+$/, "")
    root.currentDir = base === "" || base === "/" ? "/" + name : base + "/" + name
    root.selectedFile = ""
    root.refresh()
  }

  function goHome() {
    if (!root.svc) return
    root.currentDir = root.svc.home
    root.selectedFile = ""
    root.refresh()
  }

  function pick(name) {
    var base = root.currentDir.replace(/\/+$/, "")
    root.selectedFile = (base === "" || base === "/") ? "/" + name : base + "/" + name
    // A fresh file starts whole-image; the user adjusts from there.
    previewItem.resetFraming()
  }

  function use() {
    if (root.selectedFile === "") return
    var msg = root.applyFile
      ? String(root.applyFile(root.selectedFile, previewItem.zoom, previewItem.ox, previewItem.oy))
      : "service unavailable"
    if (msg.indexOf("avatar=") === 0) root.close()
    else root.statusText = msg
  }

  function reset() {
    var msg = root.applyFile ? String(root.applyFile("")) : "service unavailable"
    if (msg.indexOf("avatar=") === 0) root.close()
    else root.statusText = msg
  }

  Process {
    id: listProc
    onExited: function(exitCode) {
      if (exitCode === 0) return
      if (!root._triedPictures && root.svc
          && root.currentDir === root.svc.home + "/Pictures") {
        root._triedPictures = true
        root.currentDir = root.svc.home
        root.refresh()
        return
      }
      root.statusText = "can't read that folder"
    }
    stdout: StdioCollector {
      onStreamFinished: {
        var outDirs = []
        var outFiles = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i]
          if (line.length === 0) continue
          if (line.endsWith("/")) {
            var dn = line.slice(0, -1)
            if (dn.length > 0 && dn !== "." && dn !== "..") outDirs.push(dn)
          } else if (!root.svc || root.svc.isImageName(line)) {
            outFiles.push(line)
          }
        }
        var cmp = function(a, b) {
          var la = a.toLowerCase(), lb = b.toLowerCase()
          return la < lb ? -1 : (la > lb ? 1 : 0)
        }
        outDirs.sort(cmp)
        outFiles.sort(cmp)
        root.dirs = outDirs
        root.files = outFiles
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

    component PickButton: Rectangle {
      id: pickBtn

      property string label: ""
      property bool primary: false
      property bool enabled2: true
      signal clicked()

      width: pickLabel.implicitWidth + Style.space(16)
      height: pickLabel.implicitHeight + Style.space(9)
      radius: height / 2
      color: !pickBtn.enabled2 ? "transparent"
        : pickMa.pressed ? Style.pressedFill
        : pickMa.containsMouse ? Style.hoverFill : "transparent"
      border.width: 1
      border.color: !pickBtn.enabled2 ? Util.alpha(root.fg, 0.15)
        : pickBtn.primary ? Color.accent : Util.alpha(root.fg, 0.4)
      opacity: pickBtn.enabled2 ? 0.9 : 0.4

      Text {
        id: pickLabel
        anchors.centerIn: parent
        text: pickBtn.label
        textFormat: Text.PlainText
        color: pickBtn.primary ? Color.accent : root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: pickBtn.primary
      }

      MouseArea {
        id: pickMa
        anchors.fill: parent
        enabled: pickBtn.enabled2
        hoverEnabled: true
        cursorShape: pickBtn.enabled2 ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: pickBtn.clicked()
      }
    }

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
        text: "Choose profile picture"
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

    // Folder + image list
    ListView {
      id: fileList
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
        id: fileRow

        required property var modelData
        required property int index

        readonly property bool isUp: modelData.name === ".."
        readonly property bool isEmpty: modelData.name === ""
        readonly property bool isSelected: !modelData.isDir
          && root.selectedFile !== ""
          && root.currentDir.replace(/\/+$/, "") + "/" + modelData.name === root.selectedFile

        width: fileList.width
        height: Style.space(26)

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          radius: Style.space(5)
          color: fileRow.isEmpty ? "transparent"
            : fileRow.isSelected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
            : rowMa.pressed ? Style.pressedFill
            : rowMa.containsMouse ? Style.hoverFill : "transparent"
          border.width: fileRow.isSelected ? 1 : 0
          border.color: Util.alpha(Color.accent, 0.5)
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: fileRow.isUp ? "󰁔" : (fileRow.modelData.isDir ? "󰉋" : "󰉍")
          textFormat: Text.PlainText
          color: fileRow.isSelected ? Color.accent : root.fg
          opacity: fileRow.isUp ? 0.5 : (fileRow.modelData.isDir ? 0.65 : 0.9)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          visible: !fileRow.isEmpty
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(34)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: fileRow.isEmpty ? "no images here" : fileRow.modelData.name
          textFormat: Text.PlainText
          color: root.fg
          opacity: fileRow.isEmpty ? 0.35 : (fileRow.modelData.isDir ? 0.9 : 1.0)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        MouseArea {
          id: rowMa
          anchors.fill: parent
          enabled: !fileRow.isEmpty
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (fileRow.isUp) root.goUp()
            else if (fileRow.modelData.isDir) root.enter(fileRow.modelData.name)
            else root.pick(fileRow.modelData.name)
          }
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

    // Footer: cropper preview of the selected file + actions. Grows when a
    // file is selected so the preview is big enough to frame on.
    Item {
      id: footer
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottomMargin: Style.space(12)
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      height: root.selectedFile !== "" ? Style.space(114) : Style.space(34)
      Behavior on height { NumberAnimation { duration: 120 } }

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "pick an image"
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        visible: root.selectedFile === ""
      }

      Column {
        id: cropColumn
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        visible: root.selectedFile !== ""

        // Cropper preview: the image fits whole inside the circle at zoom 1;
        // drag pans, wheel zooms, the −/1:1/+ buttons do the same (wheel and
        // drag can be finicky on some setups, the buttons never are). This
        // exact framing is what "Use this image" saves with the avatar.
        Item {
          id: previewItem
          width: Style.space(84)
          height: Style.space(84)
          clip: true

          property real zoom: 1.0
          property real ox: 0.0
          property real oy: 0.0

          // The visible image drives the pan bounds (gif or still).
          readonly property var visImg: root.selectedIsGif ? pvGif : pvStill

          function resetFraming() {
            zoom = 1.0
            ox = 0.0
            oy = 0.0
          }

          function zoomBy(f) {
            zoom = Math.min(8, Math.max(1, zoom * f))
          }

          Item {
            id: previewMask
            anchors.fill: parent
            visible: false
            layer.enabled: true

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: "black"
            }
          }

          // The layer+mask lives on a circle-sized wrapper — MultiEffect
          // stretches maskSource over the source item's own bounds, so
          // masking the oversized image directly would square the circle.
          // Wrappers stay always-visible; the child's own visible gates.
          Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: previewMask
            }

            AnimatedImage {
              id: pvGif
              visible: root.selectedIsGif && status === AnimatedImage.Ready
              source: root.selectedIsGif ? "file://" + root.selectedFile : ""
              asynchronous: false
              smooth: true
              playing: previewItem.visible
              cache: false
              readonly property real natW: implicitWidth || 1
              readonly property real natH: implicitHeight || 1
              readonly property real fit: Math.min(previewItem.width / natW, previewItem.height / natH)
              readonly property real sc: fit * previewItem.zoom
              width: natW * sc
              height: natH * sc
              x: (previewItem.width - width) / 2 + previewItem.ox * Math.max(0, (width - previewItem.width) / 2)
              y: (previewItem.height - height) / 2 + previewItem.oy * Math.max(0, (height - previewItem.height) / 2)
            }
          }

          Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: previewMask
            }

            Image {
              id: pvStill
              visible: !root.selectedIsGif && status === Image.Ready
              source: !root.selectedIsGif && root.selectedFile !== "" ? "file://" + root.selectedFile : ""
              smooth: true
              asynchronous: true
              readonly property real natW: implicitWidth || 1
              readonly property real natH: implicitHeight || 1
              readonly property real fit: Math.min(previewItem.width / natW, previewItem.height / natH)
              readonly property real sc: fit * previewItem.zoom
              width: natW * sc
              height: natH * sc
              x: (previewItem.width - width) / 2 + previewItem.ox * Math.max(0, (width - previewItem.width) / 2)
              y: (previewItem.height - height) / 2 + previewItem.oy * Math.max(0, (height - previewItem.height) / 2)
            }
          }

          MouseArea {
            id: panMa
            anchors.fill: parent
            cursorShape: panMa.pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real lastX: 0
            property real lastY: 0
            onPressed: function(mouse) {
              lastX = mouse.x
              lastY = mouse.y
            }
            onPositionChanged: function(mouse) {
              if (!pressed) return
              var maxX = Math.max(0, (previewItem.visImg.width - previewItem.width) / 2)
              var maxY = Math.max(0, (previewItem.visImg.height - previewItem.height) / 2)
              if (maxX > 0)
                previewItem.ox = Math.min(1, Math.max(-1, previewItem.ox + (mouse.x - lastX) / maxX))
              if (maxY > 0)
                previewItem.oy = Math.min(1, Math.max(-1, previewItem.oy + (mouse.y - lastY) / maxY))
              lastX = mouse.x
              lastY = mouse.y
            }
            onDoubleClicked: previewItem.resetFraming()
          }

          WheelHandler {
            onWheel: function(ev) {
              previewItem.zoomBy(ev.angleDelta.y > 0 ? 1.12 : 0.89)
            }
          }
        }

        // Zoom controls under the preview.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(4)

          Repeater {
            model: [
              { label: "−", title: "zoom out", act: function() { previewItem.zoomBy(1 / 1.2) } },
              { label: "1:1", title: "reset framing", act: function() { previewItem.resetFraming() } },
              { label: "+", title: "zoom in", act: function() { previewItem.zoomBy(1.2) } }
            ]

            delegate: Rectangle {
              id: zoomBtn

              required property var modelData
              required property int index

              width: Style.space(26)
              height: Style.space(20)
              radius: Style.space(5)
              color: zoomMa.pressed ? Style.pressedFill
                : zoomMa.containsMouse ? Style.hoverFill : Util.alpha(root.fg, 0.06)
              border.width: 1
              border.color: Util.alpha(root.fg, 0.18)

              Text {
                anchors.centerIn: parent
                text: zoomBtn.modelData.label
                textFormat: Text.PlainText
                color: root.fg
                opacity: 0.85
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: zoomBtn.modelData.label !== "−" && zoomBtn.modelData.label !== "+"
              }

              MouseArea {
                id: zoomMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: zoomBtn.modelData.act()
              }
            }
          }
        }
      }

      Column {
        id: applyColumn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(5)
        visible: root.selectedFile !== ""

        Text {
          anchors.right: parent.right
          text: root.selectedFile === (root.svc ? String(root.svc.customAvatarPath || "") : "")
            ? "(current)" : root.selectedFile.split("/").pop()
          textFormat: Text.PlainText
          color: root.fg
          opacity: 0.75
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
          width: Math.min(implicitWidth, footerButtons.width)
        }

        Row {
          id: footerButtons
          anchors.right: parent.right
          spacing: Style.space(6)

          PickButton {
            label: "Use this image"
            primary: true
            enabled2: root.selectedFile !== ""
            onClicked: root.use()
          }

          PickButton {
            label: "Reset"
            onClicked: root.reset()
          }

          PickButton {
            label: "Cancel"
            onClicked: root.close()
          }
        }
      }
    }
  }
}
