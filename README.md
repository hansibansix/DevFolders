# DevFolders

A DankMaterialShell widget plugin that displays folders from a specified directory and opens them in your preferred editor (PhpStorm, VS Code, Neovim, etc.).

## Features

- **Quick Access**: Click the widget to browse project folders
- **Search**: Filter folders instantly with the search box
- **Multi-Editor Support**: Configure multiple editors (VS Code, Neovim, Vim, etc.)
- **One-Click Open**: Click any folder to open it in your default editor
- **Auto-Refresh**: Folders are automatically refreshed every 30 seconds

## Installation

```bash
cp -r DevFolders ~/.config/DankMaterialShell/plugins/
dms restart
```

Then enable in Settings → Plugins and add to your DankBar layout.

## Configuration

### Directory Settings
- **Watch Directory**: Path to your projects folder (e.g., `~/Projects`)
- **Show Hidden Folders**: Include dot-folders

### Editor Configuration

The plugin supports multiple editors. Configure them in `~/.config/DankMaterialShell/settings.json`:

```json
{
  "devFolders": {
    "watchDirectory": "/home/user/Projects",
    "defaultEditorIndex": 0,
    "editors": [
      {"name": "VS Code", "command": "code", "icon": "code", "terminal": false},
      {"name": "Neovim", "command": "nvim", "icon": "terminal", "terminal": true},
      {"name": "Files", "command": "xdg-open", "icon": "folder_open", "terminal": false}
    ]
  }
}
```

**Common editor commands:**

| Editor | Command | Terminal |
|--------|---------|----------|
| PhpStorm | `phpstorm` | no |
| VS Code | `code` | no |
| Neovim | `nvim` | yes |
| Vim | `vim` | yes |
| IntelliJ IDEA | `idea` | no |
| WebStorm | `webstorm` | no |
| Sublime Text | `subl` | no |
| Zed | `zed` | no |
| Emacs | `emacs` | no |

Set `terminal: true` for terminal-based editors like Neovim or Vim.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate folders |
| `Enter` | Open in default editor |
| `Super+Enter` | Open in file manager |
| `Shift+Escape` | Clear search |
| `PageUp/Down` | Jump 5 items |

## License

MIT
