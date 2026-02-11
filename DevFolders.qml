import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "KeybindDefaults.js" as KeybindDefaults

PluginComponent {
    id: root

    layerNamespacePlugin: "dev-folders"

    // Settings from pluginData
    property string watchDirectory: pluginData.watchDirectory ?? ""
    property bool showHiddenFolders: pluginData.showHiddenFolders ?? false
    property int refreshInterval: pluginData.refreshInterval ?? 30
    property int searchDepth: pluginData.searchDepth ?? 3
    property bool showFolderCount: pluginData.showFolderCount ?? true
    property color iconColor: pluginData.iconColor ?? Theme.primary
    property bool showGitStatus: pluginData.showGitStatus ?? true
    property bool enableGrouping: pluginData.enableGrouping ?? true
    property string defaultSortMode: pluginData.defaultSortMode ?? "name"

    // Editor settings
    property string editorPreset: pluginData.editorPreset ?? "phpstorm"
    property string customEditorCommand: pluginData.customEditorCommand ?? ""
    property bool editorInTerminal: pluginData.editorInTerminal ?? false
    property string terminalEmulator: pluginData.terminalEmulator ?? "kitty"
    property string customTerminalCommand: pluginData.customTerminalCommand ?? ""
    property string editorCommand: editorPreset === "custom" ? customEditorCommand : editorPreset
    property string kittySocketBase: pluginData.kittySocket ?? "unix:@mykitty"

    // Keybinding system
    readonly property var defaultBindings: KeybindDefaults.create()
    property var userBindings: pluginData.keybindings || {}

    function matchesAction(eventKey, eventMods, actionId) {
        var bindings = userBindings[actionId] || defaultBindings[actionId] || []
        // Mask out KeypadModifier to normalize numpad keys
        var mods = eventMods & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier)
        for (var i = 0; i < bindings.length; i++) {
            var b = bindings[i]
            if (typeof b === "object" && b.key === eventKey && (b.mods || 0) === mods) return true
            if (typeof b === "number" && b === eventKey && mods === 0) return true
        }
        return false
    }

    // Kitty tab support
    property var pendingKittyAction: null  // { path, name, cmd (optional) }

    // Internal state
    property var folderList: []
    property bool isLoading: false
    property string homeDir: Qt.getenv("HOME")
    property string cacheFilePath: homeDir + "/.cache/dms-devfolders-repos.json"

    // Sort, grouping state
    property string sortMode: defaultSortMode
    property var expandedGroups: ({})

    // Git status (separate from folderList to avoid full model rebuilds)
    property var dirtyStatusMap: ({})

    // Last scan
    property var lastScanTime: null
    property string lastScanText: ""

    // Stagger animation
    property bool staggerActive: false
    property bool hasLoadedOnce: false

    // ── Startup ──
    Component.onCompleted: {
        loadPersistedState()
        cacheLoadProcess.running = true
    }
    onWatchDirectoryChanged: refreshDebounce.restart()
    onShowHiddenFoldersChanged: refreshDebounce.restart()
    onSearchDepthChanged: refreshDebounce.restart()

    Timer {
        id: refreshDebounce
        interval: 50
        onTriggered: root.refreshFolders()
    }

    Timer {
        interval: root.refreshInterval * 1000
        running: root.watchDirectory !== ""
        repeat: true
        onTriggered: root.refreshFolders()  // Folder list only, not git status
    }

    Timer {
        id: lastScanTimer
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!root.lastScanTime) { root.lastScanText = ""; return }
            root.lastScanText = root.formatTimeSince(root.lastScanTime)
        }
    }

    // ── Cache Load ──
    Process {
        id: cacheLoadProcess
        property string output: ""
        command: ["cat", root.cacheFilePath]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { cacheLoadProcess.output += data }
        }
        onExited: (exitCode) => {
            if (exitCode === 0 && output) {
                try {
                    let cached = JSON.parse(output)
                    if (Array.isArray(cached) && cached.length > 0) {
                        root.folderList = cached
                    }
                } catch (e) {
                    console.warn("DevFolders: cache parse error:", e)
                }
            }
            output = ""
            root.refreshFolders()
        }
    }

    // ── Cache Save ──
    Process {
        id: cacheSaveProcess
        property string jsonData: ""
        command: ["tee", root.cacheFilePath]
        stdinEnabled: true
        onStarted: {
            write(jsonData + "\n")
            stdinClose()
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) console.warn("DevFolders: cache save failed")
        }
    }

    Timer {
        id: cacheSaveDebounce
        interval: 2000
        onTriggered: {
            if (root.folderList.length === 0) return
            if (cacheSaveProcess.running) return
            cacheSaveProcess.jsonData = JSON.stringify(root.folderList)
            cacheSaveProcess.running = true
        }
    }

    onFolderListChanged: {
        if (folderList.length > 0) cacheSaveDebounce.restart()
    }

    // ── Find git repos ──
    Process {
        id: folderListProcess
        property var collectedFolders: []

        command: ["bash", "-c",
            (root.showHiddenFolders
                ? 'find "$1" -mindepth 1 -maxdepth "$2" -type d -name ".git" -print -prune'
                : 'find "$1" -mindepth 1 -maxdepth "$2" \\( -name ".*" ! -name ".git" \\) -prune -o -type d -name ".git" -print -prune')
            + ' | while IFS= read -r g; do d="${g%/.git}"; r="${d#$1/}"; b=$(git -C "$d" branch --show-current 2>/dev/null); m=$(stat -c %Y "$d" 2>/dev/null || echo 0); printf "%s\\t%s\\t%s\\n" "$r" "$b" "$m"; done',
            "--", root.watchDirectory, (root.searchDepth + 1).toString()]

        stdout: SplitParser {
            onRead: line => {
                let trimmed = line.trim()
                if (!trimmed) return
                var parts = trimmed.split("\t")
                if (parts.length >= 1 && parts[0]) {
                    folderListProcess.collectedFolders.push({
                        relPath: parts[0],
                        name: parts[0].split("/").pop(),
                        branch: parts[1] || "",
                        mtime: parseInt(parts[2]) || 0
                    })
                }
            }
        }

        stderr: SplitParser {
            onRead: line => { if (line.trim()) console.warn("DevFolders:", line) }
        }

        onExited: (exitCode) => {
            if (exitCode === 0) {
                collectedFolders.sort((a, b) => a.relPath.localeCompare(b.relPath))
                // Only reassign folderList if data actually changed (avoids full model rebuild)
                let changed = collectedFolders.length !== root.folderList.length
                if (!changed) {
                    for (let i = 0; i < collectedFolders.length; i++) {
                        let o = root.folderList[i], n = collectedFolders[i]
                        if (o.relPath !== n.relPath || o.branch !== n.branch || o.mtime !== n.mtime) {
                            changed = true; break
                        }
                    }
                }
                let wasEmpty = root.folderList.length === 0
                if (changed) root.folderList = collectedFolders
                root.lastScanTime = new Date()
                lastScanTimer.restart()
                // Only stagger animation on first populate, not periodic refreshes
                if (wasEmpty && collectedFolders.length > 0 && !root.hasLoadedOnce) {
                    root.hasLoadedOnce = true
                    root.staggerActive = true
                    staggerResetTimer.restart()
                }
            } else {
                if (root.folderList.length === 0) root.folderList = []
            }
            root.isLoading = false
        }
    }

    Timer {
        id: staggerResetTimer
        interval: 500
        onTriggered: root.staggerActive = false
    }

    // ── Git Status Check (parallel, streaming results) ──
    Process {
        id: gitStatusProcess
        property var pendingResults: []

        stdout: SplitParser {
            onRead: line => {
                let trimmed = line.trim()
                if (!trimmed) return
                let tabIdx = trimmed.indexOf("\t")
                if (tabIdx < 0) return
                let status = trimmed.substring(0, tabIdx)
                let relPath = trimmed.substring(tabIdx + 1)
                gitStatusProcess.pendingResults.push({ relPath: relPath, dirty: status === "DIRTY" })
                gitStatusBatchTimer.restart()
            }
        }

        onExited: (exitCode) => {
            root.flushGitStatusResults()
        }
    }

    Timer {
        id: gitStatusBatchTimer
        interval: 200
        onTriggered: root.flushGitStatusResults()
    }

    function flushGitStatusResults() {
        if (gitStatusProcess.pendingResults.length === 0) return
        let map = Object.assign({}, dirtyStatusMap)
        for (let r of gitStatusProcess.pendingResults) {
            map[r.relPath] = { dirty: r.dirty, checked: true }
        }
        gitStatusProcess.pendingResults = []
        dirtyStatusMap = map
    }

    // ── Kitty Tab Launch Chain ──
    Process {
        id: kittyPidFinder
        property string kittyPid: ""
        command: ["pgrep", "-x", "kitty"]
        stdout: SplitParser {
            onRead: line => { if (line.trim()) kittyPidFinder.kittyPid = line.trim() }
        }
        onExited: (exitCode) => {
            if (exitCode === 0 && kittyPid) {
                kittyChecker.kittyPid = kittyPid
                kittyChecker.running = true
            } else {
                root.launchKittyWindow()
            }
            kittyPid = ""
        }
    }

    Process {
        id: kittyChecker
        property string kittyPid: ""
        command: ["kitty", "@", "--to", root.kittySocketBase + "-" + kittyPid, "ls"]
        onExited: (exitCode) => {
            if (exitCode === 0) {
                kittyLauncher.kittyPid = kittyPid
                kittyLauncher.running = true
            } else {
                root.launchKittyWindow()
            }
        }
    }

    Process {
        id: kittyLauncher
        property string kittyPid: ""
        command: {
            if (!root.pendingKittyAction) return ["true"]
            let a = root.pendingKittyAction
            let base = ["kitty", "@", "--to", root.kittySocketBase + "-" + kittyPid,
                        "launch", "--type=tab", "--tab-title", a.name, "--cwd", a.path]
            if (a.cmd) return base.concat(["sh", "-c", a.cmd])
            return base
        }
        onExited: (exitCode) => {
            if (exitCode === 0) {
                let a = root.pendingKittyAction
                ToastService.showInfo("Kitty", "Opened " + (a ? a.name : "") + " in tab")
                kittyFocuser.kittyPid = kittyPid
                kittyFocuser.running = true
            } else {
                root.launchKittyWindow()
            }
            root.pendingKittyAction = null
        }
    }

    Process {
        id: kittyFocuser
        property string kittyPid: ""
        command: ["kitty", "@", "--to", root.kittySocketBase + "-" + kittyPid, "focus-window"]
    }

    function launchKittyTab(path, name, cmd) {
        pendingKittyAction = { path: path, name: name, cmd: cmd || "" }
        kittyPidFinder.kittyPid = ""
        kittyPidFinder.running = true
    }

    function launchKittyWindow() {
        let a = pendingKittyAction
        if (!a) return
        if (a.cmd) {
            Quickshell.execDetached(["kitty", "sh", "-c", a.cmd])
        } else {
            Quickshell.execDetached(["kitty", "--directory", a.path])
        }
        ToastService.showInfo("Kitty", "Opening " + a.name)
        pendingKittyAction = null
    }

    // ── Functions ──

    function refreshFolders() {
        if (!watchDirectory || watchDirectory === "") {
            folderList = []
            return
        }
        if (folderListProcess.running) return
        isLoading = true
        folderListProcess.collectedFolders = []
        folderListProcess.running = true
    }

    function loadPersistedState() {
        if (!pluginService) return
        sortMode = pluginService.loadPluginData("devFolders", "sortMode", defaultSortMode)
    }

    function openFolder(relPath) {
        var fullPath = watchDirectory + "/" + relPath
        var displayName = relPath.split("/").pop()

        if (editorInTerminal) {
            var escapedPath = fullPath.replace(/'/g, "'\\''")
            var innerCmd = editorCommand + " '" + escapedPath + "'"
            if (terminalEmulator === "custom" && customTerminalCommand) {
                Quickshell.execDetached(["sh", "-c", customTerminalCommand.replace("{cmd}", innerCmd)])
            } else {
                switch (terminalEmulator) {
                    case "kitty": launchKittyTab(fullPath, displayName, innerCmd); return
                    case "alacritty": Quickshell.execDetached(["alacritty", "-e", "sh", "-c", innerCmd]); break
                    case "foot": Quickshell.execDetached(["foot", "sh", "-c", innerCmd]); break
                    case "wezterm": Quickshell.execDetached(["wezterm", "start", "--", "sh", "-c", innerCmd]); break
                    case "ghostty": Quickshell.execDetached(["ghostty", "-e", "sh", "-c", innerCmd]); break
                    case "gnome-terminal": Quickshell.execDetached(["gnome-terminal", "--", "sh", "-c", innerCmd]); break
                    case "konsole": Quickshell.execDetached(["konsole", "-e", "sh", "-c", innerCmd]); break
                    case "xterm": Quickshell.execDetached(["xterm", "-e", "sh", "-c", innerCmd]); break
                    default: Quickshell.execDetached([terminalEmulator, "-e", "sh", "-c", innerCmd])
                }
            }
        } else {
            Quickshell.execDetached([editorCommand, fullPath])
        }
        ToastService.showInfo(editorCommand, "Opening " + displayName)
    }

    function openInFileManager(relPath) {
        var fullPath = watchDirectory + "/" + relPath
        Quickshell.execDetached(["xdg-open", fullPath])
        ToastService.showInfo("File Manager", "Opening " + relPath.split("/").pop())
    }

    function openInTerminal(relPath) {
        var fullPath = watchDirectory + "/" + relPath
        var displayName = relPath.split("/").pop()
        switch (terminalEmulator) {
            case "kitty": launchKittyTab(fullPath, displayName); return
            case "alacritty": Quickshell.execDetached(["alacritty", "--working-directory", fullPath]); break
            case "foot": Quickshell.execDetached(["foot", "--app-id=devfolders", "-D", fullPath]); break
            case "wezterm": Quickshell.execDetached(["wezterm", "start", "--cwd", fullPath]); break
            case "ghostty": Quickshell.execDetached(["ghostty", "--working-directory=" + fullPath]); break
            case "gnome-terminal": Quickshell.execDetached(["gnome-terminal", "--working-directory=" + fullPath]); break
            case "konsole": Quickshell.execDetached(["konsole", "--workdir", fullPath]); break
            case "xterm": Quickshell.execDetached(["xterm", "-e", "cd '" + fullPath.replace(/'/g, "'\\''") + "' && $SHELL"]); break
            default:
                if (customTerminalCommand) {
                    Quickshell.execDetached(["sh", "-c", customTerminalCommand.replace("{cmd}", "cd '" + fullPath.replace(/'/g, "'\\''") + "' && $SHELL")])
                } else {
                    Quickshell.execDetached([terminalEmulator, "--working-directory", fullPath])
                }
        }
        ToastService.showInfo("Terminal", "Opening " + displayName)
    }

    function copyPath(relPath) {
        var fullPath = watchDirectory + "/" + relPath
        Quickshell.execDetached(["wl-copy", fullPath])
        ToastService.showInfo("Copied", fullPath)
    }

    function checkAllGitStatus() {
        if (!showGitStatus || gitStatusProcess.running || folderList.length === 0) return
        let paths = folderList.map(f => f.relPath)
        gitStatusProcess.pendingResults = []
        gitStatusProcess.command = ["bash", "-c",
            'base="$1"; shift; for d in "$@"; do ( if git -C "$base/$d" diff-index --quiet HEAD -- 2>/dev/null; then printf "CLEAN\\t%s\\n" "$d"; else printf "DIRTY\\t%s\\n" "$d"; fi ) & if (( $(jobs -r -p | wc -l) >= 16 )); then wait -n 2>/dev/null; fi; done; wait',
            "--", watchDirectory].concat(paths)
        gitStatusProcess.running = true
    }

    // ── Fuzzy Search ──
    function fuzzyMatch(pattern, text) {
        let pLower = pattern.toLowerCase()
        let tLower = text.toLowerCase()

        // Exact substring match
        let exactIdx = tLower.indexOf(pLower)
        if (exactIdx >= 0) {
            let indices = []
            for (let i = exactIdx; i < exactIdx + pLower.length; i++) indices.push(i)
            return { score: 10000 - exactIdx, indices: indices }
        }

        // Fuzzy character-by-character
        let pIdx = 0, indices = [], score = 0, lastMatchIdx = -1
        for (let tIdx = 0; tIdx < tLower.length && pIdx < pLower.length; tIdx++) {
            if (tLower[tIdx] === pLower[pIdx]) {
                indices.push(tIdx)
                if (lastMatchIdx === tIdx - 1) score += 5
                if (tIdx === 0 || "/\\-_ ".indexOf(text[tIdx - 1]) >= 0) score += 10
                if (text[tIdx] === pattern[pIdx]) score += 1
                lastMatchIdx = tIdx
                pIdx++
            }
        }
        if (pIdx < pLower.length) return null
        score += (pLower.length / tLower.length) * 50
        score -= (indices[indices.length - 1] - indices[0]) * 0.5
        return { score: score, indices: indices }
    }

    function highlightMatch(text, indices, color) {
        if (!indices || indices.length === 0) return text
        let indexSet = {}
        for (let i of indices) indexSet[i] = true
        let result = "", inH = false
        for (let i = 0; i < text.length; i++) {
            let ch = text[i].replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            if (indexSet[i]) {
                if (!inH) { result += '<b><font color="' + color + '">'; inH = true }
                result += ch
            } else {
                if (inH) { result += '</font></b>'; inH = false }
                result += ch
            }
        }
        if (inH) result += '</font></b>'
        return result
    }

    // ── Sort ──
    function sortRepos(repos, mode) {
        let sorted = repos.slice()
        switch (mode) {
            case "name": sorted.sort((a, b) => a.name.localeCompare(b.name)); break
            case "path": sorted.sort((a, b) => a.relPath.localeCompare(b.relPath)); break
            case "modified": sorted.sort((a, b) => (b.mtime || 0) - (a.mtime || 0)); break
            case "branch": sorted.sort((a, b) => (a.branch || "").localeCompare(b.branch || "") || a.name.localeCompare(b.name)); break
        }
        return sorted
    }

    // ── Grouping ──
    function buildGroupedList(repos) {
        let groups = {}, groupOrder = []
        for (let repo of repos) {
            let lastSlash = repo.relPath.lastIndexOf("/")
            let groupName = lastSlash >= 0 ? repo.relPath.substring(0, lastSlash) : ""
            if (!groups[groupName]) { groups[groupName] = []; groupOrder.push(groupName) }
            groups[groupName].push(repo)
        }
        let flat = []
        for (let gName of groupOrder) {
            let gRepos = groups[gName]
            let expanded = expandedGroups[gName] !== false
            flat.push({ type: "group", name: gName || "(root)", count: gRepos.length, expanded: expanded, groupKey: gName })
            if (expanded) {
                for (let repo of gRepos) flat.push({ type: "repo", repo: repo })
            }
        }
        return flat
    }

    function toggleGroup(groupKey) {
        let eg = Object.assign({}, expandedGroups)
        eg[groupKey] = !(eg[groupKey] !== false)
        expandedGroups = eg
    }

    // ── Formatting ──
    function formatTimeSince(date) {
        if (!date) return ""
        let secs = Math.floor((Date.now() - date.getTime()) / 1000)
        if (secs < 60) return "just now"
        let mins = Math.floor(secs / 60)
        if (mins < 60) return mins + "m ago"
        let hrs = Math.floor(mins / 60)
        return hrs + "h ago"
    }

    // ── Bar Pills ──
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

    // ── Popout ──
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "DevFolders"
            detailsText: {
                if (!root.watchDirectory) return "No directory configured"
                const home = Qt.getenv("HOME")
                if (home && root.watchDirectory.startsWith(home))
                    return "~" + root.watchDirectory.slice(home.length)
                return root.watchDirectory
            }
            showCloseButton: false

            property string searchQuery: ""
            property int selectedIndex: 0
            property bool isSearching: searchQuery.trim() !== ""

            property var displayList: {
                let base = root.sortRepos(root.folderList, root.sortMode)

                // Search filter
                if (isSearching) {
                    let q = searchQuery.trim()
                    let scored = []
                    for (let f of base) {
                        let match = root.fuzzyMatch(q, f.relPath)
                        if (match) {
                            scored.push({ type: "repo", repo: Object.assign({}, f, { matchScore: match.score, matchIndices: match.indices }) })
                        }
                    }
                    scored.sort((a, b) => b.repo.matchScore - a.repo.matchScore)
                    return scored
                }

                // Group when not searching
                if (root.enableGrouping) {
                    return root.buildGroupedList(base)
                }

                return base.map(f => ({ type: "repo", repo: f }))
            }

            property int repoCount: {
                let count = 0
                for (let item of displayList) {
                    if (item.type === "repo") count++
                }
                return count
            }

            onDisplayListChanged: {
                if (selectedIndex >= displayList.length) {
                    selectedIndex = Math.max(0, displayList.length - 1)
                }
            }

            function openSelected(fileManager) {
                if (displayList.length === 0 || selectedIndex < 0 || selectedIndex >= displayList.length) return
                var item = displayList[selectedIndex]
                if (item.type === "group") {
                    root.toggleGroup(item.groupKey)
                    return
                }
                if (!item.repo) return
                if (fileManager) {
                    root.openInFileManager(item.repo.relPath)
                } else {
                    root.openFolder(item.repo.relPath)
                }
                popout.closePopout()
            }

            function moveSelection(delta) {
                if (displayList.length === 0) return
                var newIdx = selectedIndex + delta
                if (newIdx < 0) newIdx = displayList.length - 1
                if (newIdx >= displayList.length) newIdx = 0
                selectedIndex = newIdx
                listView.positionViewAtIndex(selectedIndex, ListView.Contain)
                if (listView.contentHeight > listView.height) {
                    scrollBar.keyboardActive = true
                    scrollBarFlash.restart()
                }
            }

            function getSelectedRepo() {
                if (selectedIndex < 0 || selectedIndex >= displayList.length) return null
                let item = displayList[selectedIndex]
                return item.type === "repo" ? item.repo : null
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

            Timer {
                id: searchDebounce
                interval: 150
                onTriggered: {
                    popout.searchQuery = searchField.text
                    popout.selectedIndex = 0
                }
            }

            FocusScope {
                id: popoutFocus
                width: parent.width
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingM
                focus: true

                Keys.onPressed: event => {
                    if (searchField.activeFocus) return  // let search field handle it
                    if (event.key === Qt.Key_Escape) {
                        popout.closePopout(); event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        popout.moveSelection(1); event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        popout.moveSelection(-1); event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        popout.openSelected(event.modifiers & Qt.MetaModifier); event.accepted = true
                    } else if (event.key === Qt.Key_PageDown) {
                        popout.moveSelection(5); event.accepted = true
                    } else if (event.key === Qt.Key_PageUp) {
                        popout.moveSelection(-5); event.accepted = true
                    } else if (root.matchesAction(event.key, event.modifiers, "openTerminal")) {
                        let repo = popout.getSelectedRepo()
                        if (repo) { root.openInTerminal(repo.relPath); popout.closePopout() }
                        event.accepted = true
                    } else if (root.matchesAction(event.key, event.modifiers, "copyPath")) {
                        let repo = popout.getSelectedRepo()
                        if (repo) root.copyPath(repo.relPath)
                        event.accepted = true
                    } else if (root.matchesAction(event.key, event.modifiers, "refresh")) {
                        refreshPulse.restart(); root.refreshFolders()
                        event.accepted = true
                    } else {
                        // Any other key refocuses search
                        searchField.forceActiveFocus()
                    }
                }

                Column {
                    id: contentColumn
                    anchors.fill: parent
                    anchors.topMargin: Theme.spacingM
                    anchors.leftMargin: Theme.spacingM
                    anchors.bottomMargin: Theme.spacingM
                    spacing: Theme.spacingM

                    // ── Search Box ──
                    Rectangle {
                        width: parent.width - Theme.spacingM
                        height: 44
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        border.color: searchField.activeFocus ? Theme.primary : "transparent"
                        border.width: searchField.activeFocus ? 2 : 0

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
                                cursorVisible: activeFocus

                                Component.onCompleted: forceActiveFocus()

                                onTextChanged: searchDebounce.restart()

                                Keys.onPressed: event => {
                                    // Modifier keybinds work even during search (Ctrl+T won't type text)
                                    var hasActionMods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
                                    if (event.key === Qt.Key_Down) {
                                        popout.moveSelection(1); event.accepted = true
                                    } else if (event.key === Qt.Key_Up) {
                                        popout.moveSelection(-1); event.accepted = true
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        popout.openSelected(event.modifiers & Qt.MetaModifier); event.accepted = true
                                    } else if (event.key === Qt.Key_Escape) {
                                        if (event.modifiers & Qt.ShiftModifier) {
                                            searchField.text = ""; popout.selectedIndex = 0
                                        } else {
                                            searchField.focus = false
                                        }
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Tab) {
                                        popout.moveSelection(1); event.accepted = true
                                    } else if (event.key === Qt.Key_Backtab) {
                                        popout.moveSelection(-1); event.accepted = true
                                    } else if (event.key === Qt.Key_PageDown) {
                                        popout.moveSelection(5); event.accepted = true
                                    } else if (event.key === Qt.Key_PageUp) {
                                        popout.moveSelection(-5); event.accepted = true
                                    } else if ((hasActionMods || !searchField.text) && root.matchesAction(event.key, event.modifiers, "refresh")) {
                                        refreshPulse.restart(); root.refreshFolders(); event.accepted = true
                                    } else if ((hasActionMods || !searchField.text) && root.matchesAction(event.key, event.modifiers, "openTerminal")) {
                                        let repo = popout.getSelectedRepo()
                                        if (repo) { root.openInTerminal(repo.relPath); popout.closePopout() }
                                        event.accepted = true
                                    } else if ((hasActionMods || !searchField.text) && root.matchesAction(event.key, event.modifiers, "copyPath")) {
                                        let repo = popout.getSelectedRepo()
                                        if (repo) root.copyPath(repo.relPath)
                                        event.accepted = true
                                    }
                                }

                                StyledText {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Search repos..."
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeMedium
                                    visible: !searchField.text
                                    font.italic: true
                                }
                            }

                            Item {
                                id: clearBtn
                                width: searchField.text ? Theme.iconSize : 0
                                height: parent.height
                                opacity: searchField.text ? 1 : 0
                                Behavior on width { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

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
                                    enabled: searchField.text
                                    onClicked: {
                                        searchField.text = ""
                                        popout.selectedIndex = 0
                                        searchField.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }

                    // ── Toolbar ──
                    Item {
                        id: toolbar
                        width: parent.width - Theme.spacingM
                        height: Theme.iconSize + Theme.spacingS

                        // Left side: refresh + git status + count
                        Row {
                            id: toolbarLeft
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Rectangle {
                                id: refreshBtn
                                width: toolbar.height
                                height: toolbar.height
                                radius: Theme.cornerRadiusSmall
                                color: refreshArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                scale: 1.0

                                Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

                                SequentialAnimation {
                                    id: refreshPulse
                                    NumberAnimation { target: refreshBtn; property: "scale"; to: 0.8; duration: 100; easing.type: Easing.InQuad }
                                    NumberAnimation { target: refreshBtn; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                                }

                                DankIcon {
                                    name: "refresh"
                                    size: Theme.iconSizeSmall
                                    color: root.isLoading ? Theme.surfaceVariantText : Theme.primary
                                    anchors.centerIn: parent

                                    RotationAnimator on rotation {
                                        from: 0; to: 360; duration: 1000
                                        loops: Animation.Infinite
                                        running: root.isLoading
                                    }
                                }

                                StateLayer {
                                    id: refreshArea
                                    tooltipText: "Refresh repos"
                                    tooltipSide: "bottom"
                                    onClicked: {
                                        refreshPulse.restart()
                                        root.refreshFolders()
                                        searchField.forceActiveFocus()
                                    }
                                }
                            }

                            Rectangle {
                                id: gitStatusBtn
                                width: toolbar.height
                                height: toolbar.height
                                radius: Theme.cornerRadiusSmall
                                color: gitStatusArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                visible: root.showGitStatus
                                scale: 1.0

                                Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

                                SequentialAnimation {
                                    id: gitStatusPulse
                                    NumberAnimation { target: gitStatusBtn; property: "scale"; to: 0.8; duration: 100; easing.type: Easing.InQuad }
                                    NumberAnimation { target: gitStatusBtn; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                                }

                                DankIcon {
                                    name: "check_circle"
                                    size: Theme.iconSizeSmall
                                    color: gitStatusProcess.running ? Theme.surfaceVariantText : Theme.primary
                                    anchors.centerIn: parent

                                    RotationAnimator on rotation {
                                        from: 0; to: 360; duration: 1000
                                        loops: Animation.Infinite
                                        running: gitStatusProcess.running
                                    }
                                }

                                StateLayer {
                                    id: gitStatusArea
                                    tooltipText: "Check git status"
                                    tooltipSide: "bottom"
                                    onClicked: {
                                        root.dirtyStatusMap = ({})
                                        gitStatusPulse.restart()
                                        root.checkAllGitStatus()
                                        searchField.forceActiveFocus()
                                    }
                                }
                            }

                            StyledText {
                                id: countText
                                text: {
                                    let countStr = popout.isSearching
                                        ? popout.repoCount + "/" + root.folderList.length
                                        : popout.repoCount + " repos"
                                    if (root.lastScanText) countStr += " · " + root.lastScanText
                                    return countStr
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                                leftPadding: Theme.spacingXS
                            }
                        }

                        // Right side: sort buttons
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Repeater {
                                model: [
                                    { mode: "name", icon: "sort_by_alpha", tip: "Name" },
                                    { mode: "path", icon: "folder", tip: "Path" },
                                    { mode: "modified", icon: "schedule", tip: "Modified" },
                                    { mode: "branch", icon: "alt_route", tip: "Branch" }
                                ]

                                Rectangle {
                                    required property var modelData
                                    width: 28; height: 28
                                    radius: Theme.cornerRadiusSmall
                                    color: root.sortMode === modelData.mode
                                        ? Theme.primaryContainer
                                        : (sortBtnArea.containsMouse ? Theme.surfaceContainerHighest : "transparent")

                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: modelData.icon
                                        size: 16
                                        color: root.sortMode === modelData.mode ? Theme.primary : Theme.surfaceVariantText
                                    }

                                    StateLayer {
                                        id: sortBtnArea
                                        tooltipText: modelData.tip
                                        tooltipSide: "bottom"
                                        onClicked: {
                                            root.sortMode = modelData.mode
                                            if (root.pluginService) root.pluginService.savePluginData("devFolders", "sortMode", modelData.mode)
                                            searchField.forceActiveFocus()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── List ──
                    ListView {
                        id: listView
                        width: parent.width
                        height: parent.height - 44 - toolbar.height - Theme.spacingM * 3
                        clip: true
                        model: popout.displayList
                        currentIndex: popout.selectedIndex
                        spacing: Theme.spacingS
                        ScrollBar.vertical: ScrollBar {
                            id: scrollBar
                            property bool keyboardActive: false
                            contentItem: Rectangle {
                                implicitWidth: 4
                                radius: 2
                                color: scrollBar.pressed ? Theme.primary : Theme.outlineVariant
                                opacity: scrollBar.active || scrollBar.keyboardActive ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            }
                        }

                        Timer {
                            id: scrollBarFlash
                            interval: 800
                            onTriggered: scrollBar.keyboardActive = false
                        }

                        displaced: Transition {
                            NumberAnimation { properties: "y"; duration: Theme.shortDuration; easing.type: Theme.standardEasing }
                        }




                        delegate: Rectangle {
                            id: delegateItem
                            required property var modelData
                            required property int index

                            property bool isGroup: modelData.type === "group"
                            property bool isRepo: modelData.type === "repo"
                            property var repoData: isRepo ? modelData.repo : null
                            property bool isSelected: index === popout.selectedIndex

                            property string parentPath: {
                                if (!repoData) return ""
                                var idx = repoData.relPath.lastIndexOf("/")
                                return idx >= 0 ? repoData.relPath.substring(0, idx + 1) : ""
                            }
                            property string secondaryText: {
                                if (!repoData) return ""
                                var parts = []
                                if (parentPath) parts.push(parentPath)
                                if (repoData.branch) parts.push(repoData.branch)
                                return parts.join(" · ")
                            }

                            width: listView.width - (scrollBar.visible ? scrollBar.width + Theme.spacingXS : Theme.spacingM)
                            height: isGroup ? 40 : (secondaryText ? 64 : 52)
                            radius: Theme.cornerRadius

                            color: {
                                if (isGroup) return "transparent"
                                if (isSelected) return Theme.primaryContainer
                                if (delegateArea.containsMouse) return Theme.surfaceContainerHighest
                                return Theme.surfaceContainerHigh
                            }
                            border.width: isSelected && isRepo ? 2 : 0
                            border.color: Theme.primary

                            Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                            Behavior on border.width { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

                            // Stagger animation
                            opacity: root.staggerActive ? 0 : 1
                            transform: Translate { id: staggerTranslate; y: root.staggerActive ? 8 : 0 }

                            Timer {
                                id: staggerTimer
                                interval: root.staggerActive ? Math.min(delegateItem.index * 25, 300) : 0
                                running: root.staggerActive
                                onTriggered: {
                                    delegateItem.opacity = 1
                                    staggerTranslate.y = 0
                                }
                            }

                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                            // ── Group Header ──
                            Item {
                                visible: delegateItem.isGroup
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM

                                DankIcon {
                                    id: groupIcon
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: delegateItem.modelData.expanded ? "folder_open" : "folder"
                                    size: Theme.iconSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    anchors.left: groupIcon.right
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: delegateItem.modelData.name || "(root)"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.surfaceVariantText
                                }

                                // Count badge
                                Rectangle {
                                    anchors.right: groupChevron.left
                                    anchors.rightMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: groupCountLabel.contentWidth + Theme.spacingS
                                    height: 18
                                    radius: 9
                                    color: Theme.surfaceContainerHighest

                                    StyledText {
                                        id: groupCountLabel
                                        anchors.centerIn: parent
                                        text: delegateItem.modelData.count || ""
                                        font.pixelSize: Theme.fontSizeXSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                DankIcon {
                                    id: groupChevron
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "expand_more"
                                    size: Theme.iconSizeSmall
                                    color: Theme.surfaceVariantText
                                    rotation: delegateItem.modelData.expanded ? 0 : -90
                                    Behavior on rotation { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                }
                            }

                            // ── Repo Content ──
                            Item {
                                visible: delegateItem.isRepo
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM + 2
                                anchors.rightMargin: Theme.spacingM + 2
                                anchors.topMargin: Theme.spacingS
                                anchors.bottomMargin: Theme.spacingS

                                // Leading icon with status dot
                                Item {
                                    id: leadIconContainer
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.iconSize
                                    height: Theme.iconSize

                                    DankIcon {
                                        id: leadIcon
                                        anchors.centerIn: parent
                                        name: "code"
                                        size: Theme.iconSize
                                        color: Theme.primary
                                    }

                                    Rectangle {
                                        visible: root.showGitStatus && delegateItem.repoData && root.dirtyStatusMap[delegateItem.repoData.relPath] ? true : false
                                        width: 8; height: 8; radius: 4
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: -1
                                        color: delegateItem.repoData && root.dirtyStatusMap[delegateItem.repoData.relPath] && root.dirtyStatusMap[delegateItem.repoData.relPath].dirty ? Theme.error : "#4caf50"
                                        border.width: 1.5
                                        border.color: delegateItem.color
                                    }
                                }

                                // Trailing action icon
                                DankIcon {
                                    id: trailIcon
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "open_in_new"
                                    size: Theme.iconSize
                                    color: (delegateArea.containsMouse || delegateItem.isSelected) ? Theme.primary : Theme.outlineVariant
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                }

                                // Hover action buttons row
                                Row {
                                    id: actionBtnRow
                                    anchors.right: trailIcon.left
                                    anchors.rightMargin: Theme.spacingXS
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    clip: true

                                    property bool showActions: delegateArea.containsMouse
                                    width: showActions ? (26 * 3 + 2 * 2) : 0
                                    opacity: showActions ? 1 : 0

                                    Behavior on width { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

                                    // Terminal
                                    Item {
                                        width: 26; height: 26
                                        visible: actionBtnRow.showActions
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Theme.cornerRadiusSmall
                                            color: delegateArea.hoveringBtn === "term"
                                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: "terminal"
                                                size: Theme.iconSizeSmall
                                                color: delegateArea.hoveringBtn === "term" ? Theme.primary : Theme.surfaceVariantText
                                                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                            }
                                        }
                                    }
                                    // Copy path
                                    Item {
                                        width: 26; height: 26
                                        visible: actionBtnRow.showActions
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Theme.cornerRadiusSmall
                                            color: delegateArea.hoveringBtn === "copy"
                                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: "content_copy"
                                                size: Theme.iconSizeSmall
                                                color: delegateArea.hoveringBtn === "copy" ? Theme.primary : Theme.surfaceVariantText
                                                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                            }
                                        }
                                    }
                                    // File manager
                                    Item {
                                        width: 26; height: 26
                                        visible: actionBtnRow.showActions
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Theme.cornerRadiusSmall
                                            color: delegateArea.hoveringBtn === "fm"
                                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: "open_in_browser"
                                                size: Theme.iconSizeSmall
                                                color: delegateArea.hoveringBtn === "fm" ? Theme.primary : Theme.surfaceVariantText
                                                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                            }
                                        }
                                    }
                                }

                                // Content area
                                Column {
                                    clip: true
                                    anchors.left: leadIconContainer.right
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.right: actionBtnRow.left
                                    anchors.rightMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    Item {
                                        id: nameRow
                                        width: parent.width
                                        height: Math.max(nameLabel.implicitHeight, gitChip.height)

                                        Rectangle {
                                            id: gitChip
                                            width: gitChipLabel.contentWidth + Theme.spacingS * 2
                                            height: 20
                                            radius: 10
                                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                            border.width: 1
                                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter

                                            StyledText {
                                                id: gitChipLabel
                                                text: "git"
                                                font.pixelSize: Theme.fontSizeXSmall
                                                font.weight: Font.Medium
                                                color: Theme.primary
                                                anchors.centerIn: parent
                                            }
                                        }

                                        StyledText {
                                            id: nameLabel
                                            text: {
                                                if (!delegateItem.repoData) return ""
                                                if (popout.isSearching && delegateItem.repoData.matchIndices) {
                                                    return root.highlightMatch(delegateItem.repoData.name,
                                                        root.getNameIndices(delegateItem.repoData.relPath, delegateItem.repoData.matchIndices),
                                                        Theme.primary)
                                                }
                                                return delegateItem.repoData.name
                                            }
                                            textFormat: popout.isSearching ? Text.RichText : Text.PlainText
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: delegateItem.isSelected ? Font.Medium : Font.Normal
                                            color: Theme.surfaceText
                                            anchors.left: parent.left
                                            anchors.right: gitChip.left
                                            anchors.rightMargin: Theme.spacingS
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                        }
                                    }

                                    StyledText {
                                        visible: delegateItem.secondaryText !== ""
                                        text: delegateItem.secondaryText
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.italic: true
                                        color: Theme.surfaceVariantText
                                        width: parent.width
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Mouse area
                            MouseArea {
                                id: delegateArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton

                                property string hoveringBtn: ""

                                onPositionChanged: mouse => {
                                    if (!containsMouse || !delegateItem.isRepo) { hoveringBtn = ""; return }
                                    // Check each action button
                                    let btns = ["term", "copy", "fm"]
                                    for (let i = 0; i < actionBtnRow.children.length && i < btns.length; i++) {
                                        let btn = actionBtnRow.children[i]
                                        if (!btn || !btn.visible) continue
                                        let pos = btn.mapToItem(delegateArea, 0, 0)
                                        if (mouse.x >= pos.x && mouse.x <= pos.x + btn.width &&
                                            mouse.y >= pos.y && mouse.y <= pos.y + btn.height) {
                                            hoveringBtn = btns[i]; return
                                        }
                                    }
                                    hoveringBtn = ""
                                }

                                onExited: hoveringBtn = ""

                                onClicked: mouse => {
                                    if (delegateItem.isGroup) {
                                        root.toggleGroup(delegateItem.modelData.groupKey)
                                        return
                                    }
                                    if (!delegateItem.repoData) return

                                    if (hoveringBtn === "term") {
                                        root.openInTerminal(delegateItem.repoData.relPath)
                                        popout.closePopout()
                                    } else if (hoveringBtn === "copy") {
                                        root.copyPath(delegateItem.repoData.relPath)
                                    } else if (hoveringBtn === "fm" || mouse.button === Qt.RightButton || (mouse.modifiers & Qt.MetaModifier)) {
                                        root.openInFileManager(delegateItem.repoData.relPath)
                                        popout.closePopout()
                                    } else {
                                        root.openFolder(delegateItem.repoData.relPath)
                                        popout.closePopout()
                                    }
                                }
                                onEntered: popout.selectedIndex = delegateItem.index
                            }
                        }

                        // Loading indicator
                        Column {
                            visible: root.isLoading && popout.displayList.length === 0
                            anchors.centerIn: parent
                            spacing: Theme.spacingM
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.standardEasing } }

                            DankIcon {
                                name: "sync"
                                size: Theme.iconSize * 2
                                color: Theme.surfaceVariantText
                                opacity: 0.5
                                anchors.horizontalCenter: parent.horizontalCenter
                                RotationAnimator on rotation {
                                    from: 0; to: 360; duration: 1000
                                    loops: Animation.Infinite; running: root.isLoading
                                }
                            }

                            StyledText {
                                text: "Scanning for repos..."
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        // Empty state
                        Column {
                            visible: !root.isLoading && popout.displayList.length === 0
                            anchors.centerIn: parent
                            spacing: Theme.spacingM
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.standardEasing } }

                            DankIcon {
                                name: popout.isSearching ? "search_off" : "folder_off"
                                size: Theme.iconSize * 2
                                color: Theme.surfaceVariantText
                                opacity: 0.5
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            StyledText {
                                text: {
                                    if (root.watchDirectory === "") return "Configure directory in settings"
                                    if (popout.isSearching) return "No matches"
                                    return "No git repos found"
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

    // Helper: extract name-relative indices from relPath match indices
    function getNameIndices(relPath, matchIndices) {
        let nameStart = relPath.lastIndexOf("/") + 1
        let nameIndices = []
        for (let i of matchIndices) {
            if (i >= nameStart) nameIndices.push(i - nameStart)
        }
        return nameIndices
    }

    popoutWidth: 480
    popoutHeight: 700
}
