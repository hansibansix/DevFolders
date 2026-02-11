import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets
import "KeybindDefaults.js" as KeybindDefaults

PluginSettings {
    id: root
    pluginId: "devFolders"

    readonly property var defaultBindings: KeybindDefaults.create()
    property var keybindings: ({})
    property string recordingChip: ""

    readonly property var _keyNames: {
        var m = {}
        m[Qt.Key_Space] = "Space";   m[Qt.Key_Return] = "Enter";  m[Qt.Key_Enter] = "Enter"
        m[Qt.Key_Escape] = "Esc";    m[Qt.Key_Tab] = "Tab";       m[Qt.Key_Backspace] = "Backspace"
        m[Qt.Key_Delete] = "Delete";  m[Qt.Key_Up] = "Up";         m[Qt.Key_Down] = "Down"
        m[Qt.Key_Left] = "Left";     m[Qt.Key_Right] = "Right"
        m[Qt.Key_BracketLeft] = "["; m[Qt.Key_BracketRight] = "]"
        m[Qt.Key_Minus] = "-";       m[Qt.Key_Equal] = "="
        m[Qt.Key_Slash] = "/";       m[Qt.Key_Semicolon] = ";"
        m[Qt.Key_Apostrophe] = "'";  m[Qt.Key_Comma] = ",";       m[Qt.Key_Period] = "."
        return m
    }

    function loadKeybindings() {
        keybindings = root.loadValue("keybindings", {}) || {}
    }

    function getKeysForAction(actionId) {
        if (keybindings[actionId] !== undefined) return keybindings[actionId]
        return defaultBindings[actionId] || []
    }

    function saveKeysForAction(actionId, newKeys) {
        var updated = Object.assign({}, keybindings)
        var defaults = defaultBindings[actionId] || []
        var isDefault = newKeys.length === defaults.length
        if (isDefault) {
            for (var j = 0; j < newKeys.length; j++) {
                var nk = newKeys[j], dk = defaults[j]
                if (typeof nk === "object" && typeof dk === "object") {
                    if (nk.key !== dk.key || (nk.mods || 0) !== (dk.mods || 0)) { isDefault = false; break }
                } else {
                    if (nk !== dk) { isDefault = false; break }
                }
            }
        }
        if (isDefault) {
            delete updated[actionId]
        } else {
            updated[actionId] = newKeys
        }
        keybindings = updated
        root.saveValue("keybindings", updated)
    }

    function keyDisplayName(binding) {
        // Accept both plain keyCode (number) and {key, mods} object
        var keyCode, mods
        if (typeof binding === "object" && binding !== null) {
            keyCode = binding.key
            mods = binding.mods || 0
        } else {
            keyCode = binding
            mods = 0
        }

        var keyName
        if (_keyNames[keyCode] !== undefined) keyName = _keyNames[keyCode]
        else if (keyCode >= Qt.Key_A && keyCode <= Qt.Key_Z) keyName = String.fromCharCode(keyCode)
        else if (keyCode >= Qt.Key_0 && keyCode <= Qt.Key_9) keyName = String.fromCharCode(keyCode)
        else if (keyCode >= Qt.Key_F1 && keyCode <= Qt.Key_F12) keyName = "F" + (keyCode - Qt.Key_F1 + 1)
        else keyName = "Key " + keyCode

        if (mods === 0) return keyName

        var parts = []
        if (mods & Qt.ControlModifier) parts.push("Ctrl")
        if (mods & Qt.AltModifier) parts.push("Alt")
        if (mods & Qt.ShiftModifier) parts.push("Shift")
        if (mods & Qt.MetaModifier) parts.push("Super")
        parts.push(keyName)
        return parts.join("+")
    }

    function isModifierKey(keyCode) {
        return keyCode === Qt.Key_Shift || keyCode === Qt.Key_Control ||
               keyCode === Qt.Key_Alt || keyCode === Qt.Key_Meta ||
               keyCode === Qt.Key_Super_L || keyCode === Qt.Key_Super_R
    }

    function startKeyCapture() {
        keyCapture.forceActiveFocus()
    }

    onPluginServiceChanged: {
        if (pluginService) {
            Qt.callLater(loadKeybindings)
        }
    }

    // Section: Directory
    StyledText {
        width: parent.width
        text: "Directory"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StringSetting {
        settingKey: "watchDirectory"
        label: "Watch Directory"
        description: "Path to folder containing your projects"
        placeholder: "/home/user/Projects"
        defaultValue: ""
    }

    ToggleSetting {
        settingKey: "showHiddenFolders"
        label: "Show Hidden Folders"
        description: "Include folders starting with a dot"
        defaultValue: false
    }

    SliderSetting {
        settingKey: "searchDepth"
        label: "Search Depth"
        description: "How many levels deep to search for git repos"
        defaultValue: 3
        minimum: 1
        maximum: 10
        unit: "levels"
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Auto-Refresh Interval"
        description: "How often to scan for new folders"
        defaultValue: 30
        minimum: 5
        maximum: 300
        unit: "sec"
    }

    Item { width: 1; height: Theme.spacingL }

    // Section: Default Editor
    StyledText {
        width: parent.width
        text: "Default Editor"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Select which editor opens when pressing Enter. Use ⌘+Enter to always open in file manager."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Item { width: 1; height: Theme.spacingS }

    SelectionSetting {
        settingKey: "editorPreset"
        label: "Editor"
        description: "Application to open projects with"
        options: [
            { label: "PhpStorm", value: "phpstorm" },
            { label: "VS Code", value: "code" },
            { label: "VS Code Insiders", value: "code-insiders" },
            { label: "VSCodium", value: "codium" },
            { label: "Zed", value: "zed" },
            { label: "Cursor", value: "cursor" },
            { label: "IntelliJ IDEA", value: "idea" },
            { label: "WebStorm", value: "webstorm" },
            { label: "PyCharm", value: "pycharm" },
            { label: "CLion", value: "clion" },
            { label: "GoLand", value: "goland" },
            { label: "RustRover", value: "rustrover" },
            { label: "Sublime Text", value: "subl" },
            { label: "Emacs", value: "emacs" },
            { label: "Kate", value: "kate" },
            { label: "File Manager", value: "xdg-open" },
            { label: "Custom", value: "custom" }
        ]
        defaultValue: "phpstorm"
    }

    StringSetting {
        settingKey: "customEditorCommand"
        label: "Custom Editor Command"
        description: "Command to run when 'Custom' is selected above"
        placeholder: "nvim"
        defaultValue: ""
    }

    ToggleSetting {
        settingKey: "editorInTerminal"
        label: "Run in Terminal"
        description: "Launch editor in a terminal (for CLI editors like nvim, vim)"
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "terminalEmulator"
        label: "Terminal Emulator"
        description: "Terminal to use for CLI editors"
        options: [
            { label: "Kitty", value: "kitty" },
            { label: "Alacritty", value: "alacritty" },
            { label: "Foot", value: "foot" },
            { label: "WezTerm", value: "wezterm" },
            { label: "Ghostty", value: "ghostty" },
            { label: "GNOME Terminal", value: "gnome-terminal" },
            { label: "Konsole", value: "konsole" },
            { label: "xterm", value: "xterm" },
            { label: "Custom", value: "custom" }
        ]
        defaultValue: "kitty"
    }

    StringSetting {
        settingKey: "customTerminalCommand"
        label: "Custom Terminal Command"
        description: "Terminal command when 'Custom' is selected (use {cmd} as placeholder)"
        placeholder: "my-terminal -e {cmd}"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "kittySocket"
        label: "Kitty Socket"
        description: "Socket path for kitty remote control (from listen_on in kitty.conf)"
        placeholder: "unix:@mykitty"
        defaultValue: "unix:@mykitty"
    }

    Item { width: 1; height: Theme.spacingL }

    // Section: Appearance
    StyledText {
        width: parent.width
        text: "Appearance"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "showFolderCount"
        label: "Show Folder Count"
        description: "Display number of folders in the bar pill"
        defaultValue: true
    }

    ColorSetting {
        settingKey: "iconColor"
        label: "Icon Color"
        description: "Color of the folder icon in the bar"
        defaultValue: Theme.primary
    }

    Item { width: 1; height: Theme.spacingL }

    // Section: Features
    StyledText {
        width: parent.width
        text: "Features"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "showGitStatus"
        label: "Show Git Status"
        description: "Display dirty/clean indicators on repos (runs git status)"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "enableGrouping"
        label: "Group by Directory"
        description: "Group repos by their parent folder with collapsible headers"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "defaultSortMode"
        label: "Default Sort"
        description: "How repos are sorted when the popout opens"
        options: [
            { label: "Name (A-Z)", value: "name" },
            { label: "Path", value: "path" },
            { label: "Last Modified", value: "modified" },
            { label: "Branch", value: "branch" }
        ]
        defaultValue: "name"
    }

    Item { width: 1; height: Theme.spacingL }

    // Section: Keyboard Shortcuts
    StyledText {
        width: parent.width
        text: "Keyboard Shortcuts"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Click a key chip to rebind, press Escape to cancel. These shortcuts work when the search box is empty or unfocused."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
        bottomPadding: Theme.spacingS
    }

    // Hidden key capture item
    Item {
        id: keyCapture
        width: 0; height: 0

        Keys.onPressed: function(event) {
            if (root.recordingChip === "") return
            if (event.key === Qt.Key_Escape) {
                root.recordingChip = ""
                event.accepted = true
                return
            }
            if (root.isModifierKey(event.key)) {
                event.accepted = true
                return
            }
            var mods = event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier)
            var parts = root.recordingChip.split(":")
            var actionId = parts[0]
            var slotIndex = parseInt(parts[1])
            var currentKeys = root.getKeysForAction(actionId).slice()
            while (currentKeys.length <= slotIndex) currentKeys.push(null)
            currentKeys[slotIndex] = { key: event.key, mods: mods }
            while (currentKeys.length > 0 && currentKeys[currentKeys.length - 1] === null) currentKeys.pop()
            root.recordingChip = ""
            root.saveKeysForAction(actionId, currentKeys)
            event.accepted = true
        }
    }

    Repeater {
        model: [
            { actionId: "openTerminal", label: "Open Terminal", maxKeys: 1 },
            { actionId: "copyPath", label: "Copy Path", maxKeys: 1 },
            { actionId: "refresh", label: "Refresh Repos", maxKeys: 1 }
        ]
        KeybindRow {
            required property var modelData
            actionId: modelData.actionId
            label: modelData.label
            maxKeys: modelData.maxKeys
            settingsRoot: root
        }
    }

    Item { width: 1; height: Theme.spacingS }

    StyledText {
        width: parent.width
        text: "Fixed: ↑/↓ Navigate  •  ⏎ Open  •  ⌘+⏎ File manager  •  Esc Unfocus  •  ⇧+Esc Clear"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
