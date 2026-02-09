import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "project-folders"

    // Settings from pluginData
    property string watchDirectory: pluginData.watchDirectory ?? ""
    property bool showHiddenFolders: pluginData.showHiddenFolders ?? false
    property int refreshInterval: pluginData.refreshInterval ?? 30
    property bool showFolderCount: pluginData.showFolderCount ?? true
    property color iconColor: pluginData.iconColor ?? Theme.primary
    
    // Editor settings
    property string editorPreset: pluginData.editorPreset ?? "phpstorm"
    property string customEditorCommand: pluginData.customEditorCommand ?? ""
    property bool editorInTerminal: pluginData.editorInTerminal ?? false
    property string terminalEmulator: pluginData.terminalEmulator ?? "kitty"
    property string customTerminalCommand: pluginData.customTerminalCommand ?? ""
    
    // Computed editor command
    property string editorCommand: editorPreset === "custom" ? customEditorCommand : editorPreset

    // Internal state
    property var folderList: []
    property bool isLoading: false

    // Debounce refresh on settings changes to avoid multiple concurrent runs on startup
    Component.onCompleted: refreshDebounce.restart()
    onWatchDirectoryChanged: refreshDebounce.restart()
    onShowHiddenFoldersChanged: refreshDebounce.restart()

    Timer {
        id: refreshDebounce
        interval: 50
        onTriggered: root.refreshFolders()
    }

    // Timer for periodic refresh
    Timer {
        interval: root.refreshInterval * 1000
        running: root.watchDirectory !== ""
        repeat: true
        onTriggered: root.refreshFolders()
    }

    // Single persistent process for listing folders
    Process {
        id: folderListProcess
        property var collectedFolders: []

        command: root.showHiddenFolders
            ? ["find", root.watchDirectory, "-maxdepth", "1", "-mindepth", "1", "-type", "d", "-printf", "%f\n"]
            : ["find", root.watchDirectory, "-maxdepth", "1", "-mindepth", "1", "-type", "d", "-not", "-name", ".*", "-printf", "%f\n"]

        stdout: SplitParser {
            onRead: line => {
                if (line.trim()) {
                    folderListProcess.collectedFolders.push(line.trim())
                }
            }
        }

        stderr: SplitParser {
            onRead: line => {
                if (line.trim()) {
                    console.warn("ProjectFolders:", line)
                }
            }
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                collectedFolders.sort((a, b) => a.localeCompare(b))
                root.folderList = collectedFolders
            } else {
                root.folderList = []
            }
            root.isLoading = false
        }
    }

    function refreshFolders() {
        if (!watchDirectory || watchDirectory === "") {
            folderList = []
            return
        }
        // Guard against concurrent runs
        if (folderListProcess.running) return

        isLoading = true
        folderListProcess.collectedFolders = []
        folderListProcess.running = true
    }

    function openFolder(folderName) {
        var fullPath = watchDirectory + "/" + folderName

        if (editorInTerminal) {
            // Escape single quotes for safe shell interpolation
            var escapedPath = fullPath.replace(/'/g, "'\\''")
            var innerCmd = editorCommand + " '" + escapedPath + "'"
            
            if (terminalEmulator === "custom" && customTerminalCommand) {
                // Custom terminal: replace {cmd} placeholder
                var termCmd = customTerminalCommand.replace("{cmd}", innerCmd)
                Quickshell.execDetached(["sh", "-c", termCmd])
            } else {
                // Standard terminals with their -e flag variations
                switch (terminalEmulator) {
                    case "kitty":
                        Quickshell.execDetached(["kitty", "sh", "-c", innerCmd])
                        break
                    case "alacritty":
                        Quickshell.execDetached(["alacritty", "-e", "sh", "-c", innerCmd])
                        break
                    case "foot":
                        Quickshell.execDetached(["foot", "sh", "-c", innerCmd])
                        break
                    case "wezterm":
                        Quickshell.execDetached(["wezterm", "start", "--", "sh", "-c", innerCmd])
                        break
                    case "ghostty":
                        Quickshell.execDetached(["ghostty", "-e", "sh", "-c", innerCmd])
                        break
                    case "gnome-terminal":
                        Quickshell.execDetached(["gnome-terminal", "--", "sh", "-c", innerCmd])
                        break
                    case "konsole":
                        Quickshell.execDetached(["konsole", "-e", "sh", "-c", innerCmd])
                        break
                    case "xterm":
                        Quickshell.execDetached(["xterm", "-e", "sh", "-c", innerCmd])
                        break
                    default:
                        // Fallback: try with -e flag
                        Quickshell.execDetached([terminalEmulator, "-e", "sh", "-c", innerCmd])
                }
            }
        } else {
            Quickshell.execDetached([editorCommand, fullPath])
        }
        ToastService.showInfo(editorCommand, "Opening " + folderName)
    }

    function openInFileManager(folderName) {
        var fullPath = watchDirectory + "/" + folderName
        Quickshell.execDetached(["xdg-open", fullPath])
        ToastService.showInfo("File Manager", "Opening " + folderName)
    }

    // Horizontal bar pill
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: "folder_code"
                size: root.iconSize
                color: root.iconColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.showFolderCount && root.folderList.length > 0
                text: root.folderList.length.toString()
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Vertical bar pill
    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: "folder_code"
                size: root.iconSize
                color: root.iconColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: root.showFolderCount && root.folderList.length > 0
                text: root.folderList.length.toString()
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // Popout content
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Project Folders"
            detailsText: root.watchDirectory || "No directory configured"
            showCloseButton: true

            property string searchQuery: ""
            property int selectedIndex: 0
            property var filteredFolders: {
                if (!searchQuery || searchQuery.trim() === "") {
                    return root.folderList
                }
                var q = searchQuery.toLowerCase().trim()
                return root.folderList.filter(f => f.toLowerCase().includes(q))
            }

            onFilteredFoldersChanged: {
                if (selectedIndex >= filteredFolders.length) {
                    selectedIndex = Math.max(0, filteredFolders.length - 1)
                }
            }

            function openSelected(fileManager) {
                if (filteredFolders.length > 0 && selectedIndex >= 0 && selectedIndex < filteredFolders.length) {
                    var folderName = filteredFolders[selectedIndex]
                    if (fileManager) {
                        root.openInFileManager(folderName)
                    } else {
                        root.openFolder(folderName)
                    }
                    popout.closePopout()
                }
            }

            function moveSelection(delta) {
                if (filteredFolders.length === 0) return
                var newIdx = selectedIndex + delta
                if (newIdx < 0) newIdx = filteredFolders.length - 1
                if (newIdx >= filteredFolders.length) newIdx = 0
                selectedIndex = newIdx
                listView.positionViewAtIndex(selectedIndex, ListView.Contain)
            }

            onVisibleChanged: {
                if (visible) {
                    searchField.text = ""
                    searchQuery = ""
                    selectedIndex = 0
                    root.refreshFolders()
                    focusTimer.start()
                }
            }

            Timer {
                id: focusTimer
                interval: 50
                onTriggered: searchField.forceActiveFocus()
            }

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingM

                Column {
                    id: contentColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    // Search box
                    Rectangle {
                        width: parent.width
                        height: 44
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        border.color: searchField.activeFocus ? Theme.primary : Theme.outlineVariant
                        border.width: searchField.activeFocus ? 2 : 1

                        Behavior on border.color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                        Behavior on border.width { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "search"
                                size: Theme.iconSize
                                color: searchField.activeFocus ? Theme.primary : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter

                                Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                            }

                            TextInput {
                                id: searchField
                                width: parent.width - Theme.iconSize - clearBtn.width - Theme.spacingS * 2
                                height: parent.height
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                clip: true
                                selectByMouse: true

                                Component.onCompleted: forceActiveFocus()

                                onTextChanged: {
                                    popout.searchQuery = text
                                    popout.selectedIndex = 0
                                }

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Down) {
                                        popout.moveSelection(1)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Up) {
                                        popout.moveSelection(-1)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        popout.openSelected(event.modifiers & Qt.MetaModifier)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Escape) {
                                        if (event.modifiers & Qt.ShiftModifier) {
                                            // Shift+Escape: clear search and show full list
                                            searchField.text = ""
                                            popout.selectedIndex = 0
                                        } else if (searchField.text) {
                                            // Escape with text: clear search
                                            searchField.text = ""
                                            popout.selectedIndex = 0
                                        } else {
                                            // Escape without text: close popout
                                            popout.closePopout()
                                        }
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Tab) {
                                        popout.moveSelection(1)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Backtab) {
                                        popout.moveSelection(-1)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_PageDown) {
                                        popout.moveSelection(5)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_PageUp) {
                                        popout.moveSelection(-5)
                                        event.accepted = true
                                    }
                                }

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Search folders..."
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeMedium
                                    visible: !searchField.text
                                }
                            }

                            Item {
                                id: clearBtn
                                width: searchField.text ? Theme.iconSize : 0
                                height: parent.height
                                visible: searchField.text

                                DankIcon {
                                    name: "close"
                                    size: Theme.iconSize
                                    color: clearArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                    anchors.centerIn: parent

                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                }

                                MouseArea {
                                    id: clearArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchField.text = ""
                                        popout.selectedIndex = 0
                                        searchField.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }

                    // Toolbar
                    Row {
                        id: toolbar
                        width: parent.width
                        height: Theme.iconSize + Theme.spacingS
                        spacing: Theme.spacingS

                        Rectangle {
                            width: toolbar.height
                            height: toolbar.height
                            radius: Theme.cornerRadiusSmall
                            color: refreshArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                            Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

                            DankIcon {
                                name: "refresh"
                                size: Theme.iconSizeSmall
                                color: Theme.primary
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: refreshArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.refreshFolders()
                                    searchField.forceActiveFocus()
                                }
                            }
                        }

                        StyledText {
                            text: popout.searchQuery 
                                ? popout.filteredFolders.length + "/" + root.folderList.length
                                : root.folderList.length + " folders"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Item { width: 1; height: 1 }

                        StyledText {
                            text: "↑↓ ⇥ ⏎ ⌘⏎"
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.outlineVariant
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // List
                    ListView {
                        id: listView
                        width: parent.width
                        height: parent.height - 44 - toolbar.height - Theme.spacingM * 2
                        clip: true
                        model: popout.filteredFolders
                        currentIndex: popout.selectedIndex
                        spacing: Theme.spacingXS

                        delegate: Rectangle {
                            id: delegateItem
                            required property string modelData
                            required property int index

                            width: listView.width
                            height: 44
                            radius: Theme.cornerRadius
                            color: {
                                if (index === popout.selectedIndex) return Theme.primaryContainer
                                if (delegateArea.containsMouse) return Theme.surfaceContainerHighest
                                return "transparent"
                            }

                            Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingS

                                DankIcon {
                                    name: "folder"
                                    size: Theme.iconSize
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter

                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                }

                                StyledText {
                                    text: delegateItem.modelData
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideMiddle
                                    width: parent.width - Theme.iconSize * 2 - Theme.spacingS * 3

                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                }

                                DankIcon {
                                    name: "chevron_right"
                                    size: Theme.iconSize
                                    color: {
                                        if (delegateArea.containsMouse || delegateItem.index === popout.selectedIndex) return Theme.primary
                                        return Theme.outlineVariant
                                    }
                                    anchors.verticalCenter: parent.verticalCenter

                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                }
                            }

                            MouseArea {
                                id: delegateArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        root.openInFileManager(delegateItem.modelData)
                                    } else if (mouse.modifiers & Qt.MetaModifier) {
                                        root.openInFileManager(delegateItem.modelData)
                                    } else {
                                        root.openFolder(delegateItem.modelData)
                                    }
                                    popout.closePopout()
                                }
                                onEntered: popout.selectedIndex = delegateItem.index
                            }
                        }

                        // Loading indicator
                        Column {
                            visible: root.isLoading && popout.filteredFolders.length === 0
                            anchors.centerIn: parent
                            spacing: Theme.spacingM

                            DankIcon {
                                name: "sync"
                                size: 48
                                color: Theme.surfaceVariantText
                                opacity: 0.5
                                anchors.horizontalCenter: parent.horizontalCenter

                                RotationAnimator on rotation {
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                    running: root.isLoading
                                }
                            }

                            StyledText {
                                text: "Loading folders..."
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        // Empty state
                        Column {
                            visible: !root.isLoading && popout.filteredFolders.length === 0
                            anchors.centerIn: parent
                            spacing: Theme.spacingM

                            DankIcon {
                                name: popout.searchQuery ? "search_off" : "folder_off"
                                size: 48
                                color: Theme.surfaceVariantText
                                opacity: 0.5
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            StyledText {
                                text: {
                                    if (root.watchDirectory === "") return "Configure directory in settings"
                                    if (popout.searchQuery) return "No matches"
                                    return "No folders found"
                                }
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 360
    popoutHeight: 420
}
