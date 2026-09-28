pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Daily tab: GIF deck on top, then the streak dashboard, today's recurring
// tasks, the scratchpad, and todos.
Rectangle {
  id: root

  color: "transparent"

  property var svc: null
  property color fg: Color.foreground
  property color accent: Color.accent
  property color danger: Color.urgent
  property string fontFamily: Style.font.family
  // Host function(path) -> status line; validates, applies and persists a
  // picked GIF directory (shared with the setGifDir IPC command).
  property var applyDir: null
  // Bumped by the host panel's requestPicker() (IPC pickGifDir) — opens the
  // folder picker. Only the panel on the focused monitor bumps it.
  property int pickerNonce: 0
  onPickerNonceChanged: if (pickerNonce > 0) picker.openFor(root.svc ? root.svc.activeGifDir : "")

  Timer {
    id: notesSaveTimer
    interval: 600
    onTriggered: if (root.svc) root.svc.setNotes(notesArea.text)
  }

  Flickable {
    id: scroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: contentCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: contentCol
      width: scroll.width
      spacing: Style.space(16)

      GifDeck {
        width: parent.width
        files: root.svc ? root.svc.gifFiles : []
        dirLabel: root.svc ? root.svc.activeGifDir : ""
        fg: root.fg
        fontFamily: root.fontFamily
        onPickRequested: picker.openFor(root.svc ? root.svc.activeGifDir : "")
      }

      // Streak dashboard
      Column {
        width: parent.width
        spacing: Style.space(8)

        SectionHeader {
          width: parent.width
          title: "STREAK"
          fg: root.fg
          fontFamily: root.fontFamily

          Text {
            text: {
              if (!root.svc || root.svc.daily.tasks.length === 0) return "no daily tasks yet"
              return root.svc.todayDoneIds().length + " / " + root.svc.daily.tasks.length + " today"
            }
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: 10
          }
        }

        StreakGrid {
          width: parent.width
          svc: root.svc
          fg: root.fg
          fontFamily: root.fontFamily
        }
      }

      // Daily tasks
      Column {
        width: parent.width
        spacing: Style.space(6)

        SectionHeader {
          width: parent.width
          title: "DAILY TASKS"
          fg: root.fg
          fontFamily: root.fontFamily
        }

        TaskList {
          width: parent.width
          daily: true
          svc: root.svc
          fg: root.fg
          fontFamily: root.fontFamily
        }
      }

      // Scratchpad
      Column {
        width: parent.width
        spacing: Style.space(6)

        SectionHeader {
          width: parent.width
          title: "QUICK NOTES"
          fg: root.fg
          fontFamily: root.fontFamily
        }

        Rectangle {
          id: notesBox
          width: parent.width
          height: Math.min(Math.max(notesArea.contentHeight + Style.space(20), Style.space(90)), Style.space(260))
          radius: Style.space(6)
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
          border.width: 1
          border.color: notesArea.activeFocus ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35) : "transparent"

          ScrollView {
            anchors.fill: parent
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }

            TextArea {
              id: notesArea
              padding: Style.space(10)
              wrapMode: TextArea.Wrap
              color: root.fg
              opacity: 0.9
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: TextEdit.PlainText
              persistentSelection: false

              // Init once, then sync only while unfocused — a binding here
              // would yank the cursor on every daily-state change.
              Component.onCompleted: if (root.svc) text = root.svc.daily.notes

              Connections {
                target: root.svc || null
                function onDailyChanged() {
                  if (!notesArea.activeFocus && notesArea.text !== root.svc.daily.notes)
                    notesArea.text = root.svc.daily.notes
                }
              }

              onTextChanged: {
                if (!root.svc) return
                if (text === root.svc.daily.notes) return
                notesSaveTimer.restart()
              }
            }
          }

          Text {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: Style.space(10)
            visible: notesArea.text.length === 0 && !notesArea.activeFocus
            text: "Jot anything — saved automatically."
            textFormat: Text.PlainText
            color: root.fg
            opacity: 0.3
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // Todos
      Column {
        width: parent.width
        spacing: Style.space(6)

        SectionHeader {
          width: parent.width
          title: "TODOS"
          fg: root.fg
          fontFamily: root.fontFamily
        }

        TaskList {
          width: parent.width
          daily: false
          svc: root.svc
          fg: root.fg
          fontFamily: root.fontFamily
        }
      }
    }
  }

  // Folder picker overlay — covers the tab, above the flickable content.
  DirPicker {
    id: picker
    anchors.fill: parent
    svc: root.svc
    fg: root.fg
    fontFamily: root.fontFamily
    applyDir: root.applyDir
  }
}
