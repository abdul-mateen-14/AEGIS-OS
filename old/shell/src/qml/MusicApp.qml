import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Qt.labs.folderlistmodel
import Aegis.Util
import Aegis.Files

// Aegis Music — M3 first-party app (proposal §8, plate 12).
//
// Library = whatever lives in ~/Music (FolderListModel, the same stack as
// Files — no indexer service in M3). Playback = Qt Multimedia over
// PipeWire (qml6-module-qtmultimedia ships in the ISO; the Qt FFmpeg
// backend decodes mp3/flac/ogg/wav/m4a/opus). Transport lives in the
// toolbar per the shared anatomy; the tape is the flat track list.
Window {
    id: win

    width: 780; height: 520
    minimumWidth: 560; minimumHeight: 420
    visible: true
    title: "Music"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    property string musicFolder: {
        const home = Files.homeUrl().toString()
        return (home.endsWith("/") ? home : home + "/") + "Music"
    }
    property int currentIndex: -1
    property bool shuffle: false
    property int repeatMode: 0          // 0 off · 1 all · 2 one

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {
            id: audioOut
            volume: 0.8
        }
        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.StoppedState
                    && player.mediaStatus === MediaPlayer.EndOfMedia)
                win.advance(1)
        }
        onErrorOccurred: function (error, errorString) {
            win.nowLine = errorString.length > 0 ? "Cannot play — " + errorString
                                                 : "Cannot play this file"
        }
    }

    property string nowLine: ""

    function trackTitle(fileName) {
        const base = fileName.replace(/\.[^.]+$/, "")
        return base.replace(/_/g, " ")
    }

    function extOf(fileName) {
        const i = fileName.lastIndexOf(".")
        return i > 0 ? fileName.slice(i + 1).toUpperCase() : "—"
    }

    function playAt(index) {
        if (index < 0 || index >= tracks.count) return
        currentIndex = index
        const name = tracks.get(index, "fileName")
        const folder = tracks.folder.toString()
        player.source = (folder.endsWith("/") ? folder : folder + "/") + encodeURIComponent(name)
        player.play()
        nowLine = ""
    }

    function advance(direction) {
        if (tracks.count === 0) return
        if (repeatMode === 2 && direction === 1) { playAt(currentIndex); return }
        let next
        if (shuffle) next = Math.floor(Math.random() * tracks.count)
        else next = currentIndex + direction
        if (next >= tracks.count) {
            if (repeatMode === 1) next = 0
            else { player.stop(); currentIndex = -1; return }
        }
        if (next < 0) next = tracks.count - 1
        playAt(next)
    }

    function togglePlay() {
        if (currentIndex < 0) {
            if (tracks.count > 0) playAt(0)
            return
        }
        if (player.playbackState === MediaPlayer.PlayingState) player.pause()
        else player.play()
    }

    function fmtTime(ms) {
        if (ms <= 0 || !isFinite(ms)) return "0:00"
        const s = Math.floor(ms / 1000)
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    FolderListModel {
        id: tracks
        folder: "file://" + win.musicFolder
        nameFilters: ["*.mp3", "*.flac", "*.ogg", "*.oga", "*.wav", "*.m4a", "*.opus"]
        showDirs: false
        showHidden: false
    }

    AppWindow {
        id: appBody
        anchors.fill: parent
        title: "Music"

        toolbar: [
            // transport
            AbstractButton {
                Layout.preferredHeight: 30; Layout.preferredWidth: 30
                contentItem: Text {
                    text: "\u23EE"
                    font.pixelSize: 13
                    color: Tokens.fg
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 15
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.06) : "#E8ECF4"
                }
                onClicked: win.advance(-1)
            },
            AbstractButton {
                Layout.preferredHeight: 34; Layout.preferredWidth: 44
                contentItem: Text {
                    text: player.playbackState === MediaPlayer.PlayingState ? "\u23F8" : "\u25B6"
                    font.pixelSize: 14
                    color: "#FFFFFF"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { radius: 17; color: Tokens.accent }
                onClicked: win.togglePlay()
            },
            AbstractButton {
                Layout.preferredHeight: 30; Layout.preferredWidth: 30
                contentItem: Text {
                    text: "\u23ED"
                    font.pixelSize: 13
                    color: Tokens.fg
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 15
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.06) : "#E8ECF4"
                }
                onClicked: win.advance(1)
            },

            // now playing + seek
            ColumnLayout {
                Layout.fillWidth: true
                Layout.maximumHeight: 40
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: win.currentIndex >= 0 && win.currentIndex < tracks.count
                          ? win.trackTitle(tracks.get(win.currentIndex, "fileName"))
                          : (win.nowLine.length > 0 ? win.nowLine : "Nothing playing — pick a track")
                    font { pixelSize: 11; weight: Font.DemiBold }
                    color: win.nowLine.length > 0 && win.currentIndex < 0 ? Tokens.danger : Tokens.fg
                    elide: Text.ElideMiddle
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: win.fmtTime(player.position)
                        font.pixelSize: 9
                        color: Tokens.fgMuted
                    }
                    Slider {
                        id: seekBar
                        Layout.fillWidth: true
                        from: 0
                        to: Math.max(1, player.duration)
                        value: player.position
                        enabled: player.duration > 0
                        onMoved: player.position = seekBar.value
                        // W60/§5.5 — the Basic-style 20 px knob read as an
                        // oversized black dot on the track: 4 px glass
                        // track with an accent fill, 12 px white knob with
                        // a 1 px shadow ring.
                        background: Rectangle {
                            x: seekBar.leftPadding
                            y: seekBar.topPadding
                               + seekBar.availableHeight / 2 - height / 2
                            width: seekBar.availableWidth
                            height: 4
                            radius: 2
                            color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.08)
                                                 : Qt.rgba(0, 0, 0, 0.08)
                            Rectangle {
                                width: seekBar.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: Tokens.accent
                            }
                        }
                        handle: Rectangle {
                            x: seekBar.leftPadding
                               + seekBar.visualPosition
                                 * (seekBar.availableWidth - width)
                            y: seekBar.topPadding
                               + seekBar.availableHeight / 2 - height / 2
                            width: 12; height: 12; radius: 6
                            color: "#FFFFFF"
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.25)
                        }
                    }
                    Text {
                        text: win.fmtTime(player.duration)
                        font.pixelSize: 9
                        color: Tokens.fgMuted
                    }
                }
            },

            // volume + shuffle + repeat
            Text {
                text: "Vol"
                font.pixelSize: 9
                color: Tokens.fgMuted
                Layout.alignment: Qt.AlignVCenter
            },
            Slider {
                id: volumeBar
                Layout.preferredWidth: 90
                Layout.alignment: Qt.AlignVCenter
                from: 0; to: 1
                value: audioOut.volume
                onMoved: audioOut.volume = volumeBar.value
                // W60/§5.5 — same glass slider contract as the seek bar.
                background: Rectangle {
                    x: volumeBar.leftPadding
                    y: volumeBar.topPadding
                       + volumeBar.availableHeight / 2 - height / 2
                    width: volumeBar.availableWidth
                    height: 4
                    radius: 2
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.08)
                                         : Qt.rgba(0, 0, 0, 0.08)
                    Rectangle {
                        width: volumeBar.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: Tokens.accent
                    }
                }
                handle: Rectangle {
                    x: volumeBar.leftPadding
                       + volumeBar.visualPosition
                         * (volumeBar.availableWidth - width)
                    y: volumeBar.topPadding
                       + volumeBar.availableHeight / 2 - height / 2
                    width: 12; height: 12; radius: 6
                    color: "#FFFFFF"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.25)
                }
            },
            AbstractButton {
                Layout.preferredHeight: 28; Layout.preferredWidth: 34
                contentItem: Text {
                    text: "\u21C4"
                    font.pixelSize: 12
                    color: win.shuffle ? Tokens.accent : Tokens.fgMuted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 8
                    border.color: win.shuffle ? Tokens.accent : Tokens.glassBorder
                    color: Util.darkMode ? "#262930" : "#E8ECF4"
                }
                onClicked: win.shuffle = !win.shuffle
            },
            AbstractButton {
                Layout.preferredHeight: 28; Layout.preferredWidth: 34
                contentItem: Text {
                    text: win.repeatMode === 2 ? "\u21BB" : (win.repeatMode === 1 ? "\u21BB\u2192" : "\u2192")
                    font.pixelSize: 12
                    color: win.repeatMode > 0 ? Tokens.accent : Tokens.fgMuted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 8
                    border.color: win.repeatMode > 0 ? Tokens.accent : Tokens.glassBorder
                    color: Util.darkMode ? "#262930" : "#E8ECF4"
                }
                onClicked: win.repeatMode = (win.repeatMode + 1) % 3
            }
        ]

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // library header
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                Layout.bottomMargin: 4
                spacing: 8
                Text {
                    text: "Library"
                    font { pixelSize: 13; weight: Font.DemiBold }
                    color: Tokens.fg
                }
                Text {
                    text: tracks.count === 1 ? "1 track" : tracks.count + " tracks"
                    font.pixelSize: 10
                    color: Tokens.fgMuted
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: win.musicFolder
                    font.pixelSize: 10
                    color: Tokens.fgMuted
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 300
                }
            }

            // empty state
            Rectangle {
                visible: tracks.count === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 14
                Layout.topMargin: 4
                radius: 16
                color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                border.color: Tokens.glassBorder
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: "No audio in ~/Music"
                        font { family: "Montserrat"; pixelSize: 15; weight: Font.DemiBold }
                        color: Tokens.fg
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: "Drop mp3, flac, ogg, wav, m4a or opus files there —\nthey appear the next time Music opens."
                        font.pixelSize: 11
                        color: Tokens.fgMuted
                        horizontalAlignment: Text.AlignHCenter
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // track tape
            ListView {
                visible: tracks.count > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.bottomMargin: 14
                clip: true
                model: tracks
                spacing: 2
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 40
                    radius: 10
                    color: win.currentIndex === index ? Tokens.accent
                                                      : (trackRow.containsMouse
                                                         ? (Util.darkMode ? Qt.rgba(1, 1, 1, 0.06) : "#EBEEF5")
                                                         : "transparent")
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 10
                        Text {
                            text: win.currentIndex === index && player.playbackState === MediaPlayer.PlayingState
                                  ? "\u25B6" : String(index + 1).padStart(2, "0")
                            font { pixelSize: 10; family: "Monospace"; bold: win.currentIndex === index }
                            color: win.currentIndex === index ? "#FFFFFF" : Tokens.fgMuted
                            Layout.preferredWidth: 24
                        }
                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            Text {
                                text: win.trackTitle(model.fileName)
                                font { pixelSize: 12; weight: win.currentIndex === index ? Font.DemiBold : Font.Normal }
                                color: win.currentIndex === index ? "#FFFFFF" : Tokens.fg
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                            Text {
                                text: model.fileName
                                font.pixelSize: 9
                                color: win.currentIndex === index ? Qt.rgba(1, 1, 1, 0.7) : Tokens.fgMuted
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                        }
                        Rectangle {
                            width: 34; height: 16; radius: 8
                            color: win.currentIndex === index ? Qt.rgba(1, 1, 1, 0.25)
                                                              : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.06) : "#E8ECF4")
                            Text {
                                anchors.centerIn: parent
                                text: win.extOf(model.fileName)
                                font { pixelSize: 8; bold: true }
                                color: win.currentIndex === index ? "#FFFFFF" : Tokens.fgMuted
                            }
                        }
                    }
                    MouseArea {
                        id: trackRow
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.playAt(index)
                    }
                }
            }
        }
    }
}
