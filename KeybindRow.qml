import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Row {
    id: row

    required property string actionId
    required property string label
    required property int maxKeys

    // Provided by parent settings page
    required property var settingsRoot

    width: parent ? parent.width : 0
    spacing: Theme.spacingM
    height: 36

    StyledText {
        width: parent.width * 0.4
        text: row.label
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceText
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
    }

    Row {
        spacing: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            model: row.maxKeys
            delegate: StyledRect {
                required property int index
                property string chipId: row.actionId + ":" + index
                property bool isRecording: settingsRoot.recordingChip === chipId
                property var currentKeys: settingsRoot.getKeysForAction(row.actionId)
                property var binding: index < currentKeys.length ? currentKeys[index] : null
                property bool hasBinding: binding !== null && binding !== undefined && (typeof binding === "object" ? binding.key !== undefined : binding >= 0)

                width: Math.max(chipLabel.implicitWidth + Theme.spacingM * 2, 56)
                height: 30
                radius: Theme.cornerRadiusSmall
                color: isRecording ? Theme.primary : (hasBinding ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                border.color: isRecording ? Theme.primary : Theme.outline
                border.width: 1

                StyledText {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: parent.isRecording ? "Press key..." : (parent.hasBinding ? settingsRoot.keyDisplayName(parent.binding) : "---")
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: parent.isRecording ? Font.Medium : Font.Normal
                    color: parent.isRecording ? Theme.surfaceText : (parent.hasBinding ? Theme.surfaceText : Theme.surfaceTextMedium)
                    font.italic: parent.isRecording
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (settingsRoot.recordingChip === parent.chipId) {
                            settingsRoot.recordingChip = ""
                        } else {
                            settingsRoot.recordingChip = parent.chipId
                            settingsRoot.startKeyCapture()
                        }
                    }
                }
            }
        }

        StyledRect {
            width: 28
            height: 28
            radius: Theme.cornerRadiusSmall
            color: resetMa.containsMouse ? Theme.surfaceContainerHighest : "transparent"
            visible: settingsRoot.keybindings[row.actionId] !== undefined

            DankIcon {
                anchors.centerIn: parent
                name: "restart_alt"
                size: 16
                color: Theme.surfaceTextMedium
            }

            MouseArea {
                id: resetMa
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    settingsRoot.recordingChip = ""
                    settingsRoot.saveKeysForAction(row.actionId, settingsRoot.defaultBindings[row.actionId].slice())
                }
            }
        }
    }
}
