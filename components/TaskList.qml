pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// Editable checklist. Two modes: daily=true toggles today's completion of a
// recurring daily task (streak feed); daily=false is a plain persistent todo.
Rectangle {
  id: root

  color: "transparent"

  property bool daily: true
  property var svc: null
  property color fg: Color.foreground
  property color accent: Color.accent
  property color danger: Color.urgent
  property string fontFamily: Style.font.family

  readonly property var items: {
    if (!svc) return []
    return daily ? svc.daily.tasks : svc.daily.todos
  }
  readonly property var doneIds: {
    if (!svc) return []
    if (daily) return svc.todayDoneIds()
    var d = []
    for (var i = 0; i < svc.daily.todos.length; i++)
      if (svc.daily.todos[i].done === true) d.push(svc.daily.todos[i].id)
    return d
  }
  readonly property int doneCount: {
    var n = 0
    for (var i = 0; i < items.length; i++)
      if (doneIds.indexOf(items[i].id) >= 0) n++
    return n
  }

  height: listCol.implicitHeight

  function isDone(id) {
    return doneIds.indexOf(id) >= 0
  }

  function submitAdd() {
    if (!svc || addInput.text.trim().length === 0) return
    if (daily) svc.addTask(addInput.text)
    else svc.addTodo(addInput.text)
    addInput.text = ""
  }

  Column {
    id: listCol
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: root.items

      delegate: Rectangle {
        id: rowRoot

        required property int index
        required property var modelData

        readonly property bool done: root.isDone(modelData.id)

        width: parent.width
        height: Math.max(checkBox.height, rowText.implicitHeight) + Style.space(12)
        radius: Style.space(6)
        color: rowMa.containsMouse ? Style.hoverFill : "transparent"

        Row {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(10)

          // Checkbox
          Rectangle {
            id: checkBox
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            height: Style.space(16)
            radius: Style.space(4)
            color: rowRoot.done ? root.accent : "transparent"
            border.width: 1
            border.color: rowRoot.done ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45)

            Text {
              anchors.centerIn: parent
              text: "✓"
              textFormat: Text.PlainText
              color: Color.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              visible: rowRoot.done
            }

            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (!root.svc) return
                if (root.daily) root.svc.toggleTask(rowRoot.modelData.id)
                else root.svc.toggleTodo(rowRoot.modelData.id)
              }
            }
          }

          // Text
          Text {
            id: rowText
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - checkBox.width - Style.space(10) - delText.width - Style.space(8)
            text: rowRoot.modelData.text
            textFormat: Text.PlainText
            color: root.fg
            opacity: rowRoot.done ? 0.4 : 0.9
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.strikeout: rowRoot.done
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
          }

          // Delete (hover)
          Text {
            id: delText
            anchors.verticalCenter: parent.verticalCenter
            text: "✕"
            textFormat: Text.PlainText
            color: root.danger
            opacity: rowMa.containsMouse ? 0.8 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (!root.svc) return
                if (root.daily) root.svc.removeTask(rowRoot.modelData.id)
                else root.svc.removeTodo(rowRoot.modelData.id)
              }
            }
          }
        }

        MouseArea {
          id: rowMa
          anchors.fill: parent
          hoverEnabled: true
          // Hover-only: NoButton lets clicks fall through to the checkbox
          // and delete areas above.
          acceptedButtons: Qt.NoButton
        }
      }
    }

    // Add row
    Rectangle {
      width: parent.width
      height: Style.space(30)
      radius: Style.space(6)
      color: addInput.activeFocus ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
      border.width: 1
      border.color: addInput.activeFocus ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35) : "transparent"

      TextInput {
        id: addInput
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(34)
        anchors.verticalCenter: parent.verticalCenter
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        clip: true
        verticalAlignment: TextInput.AlignVCenter
        selectByMouse: true

        Keys.onReturnPressed: root.submitAdd()
        Keys.onEnterPressed: root.submitAdd()
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        visible: addInput.text.length === 0 && !addInput.activeFocus
        text: root.daily ? "Add a daily task…" : "Add a todo…"
        textFormat: Text.PlainText
        color: root.fg
        opacity: 0.3
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(22)
        height: Style.space(22)
        radius: height / 2
        color: addBtn.containsMouse ? Style.hoverFill : "transparent"
        visible: addInput.text.trim().length > 0

        Text {
          anchors.centerIn: parent
          text: "+"
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          id: addBtn
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (addInput.text.trim().length === 0) return
            if (root.daily) root.svc.addTask(addInput.text)
            else root.svc.addTodo(addInput.text)
            addInput.text = ""
          }
        }
      }
    }
  }
}
