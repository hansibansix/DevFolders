import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "devFolders"

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
        text: "↑/↓ Navigate  •  Enter Open  •  ⌘+Enter File manager  •  ⇧+Esc Clear  •  PgUp/PgDn Jump 5"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
