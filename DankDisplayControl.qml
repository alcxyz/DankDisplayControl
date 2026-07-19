import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var pluginService: null
    property int refreshInterval: 2
    property int televisionWidthThreshold: 1000
    property bool showAudio: true

    property string layoutState: "adaptive"
    property string mirrorState: "off"
    property string audioState: "Unknown"
    property var monitors: []
    property var clients: []
    property bool isRefreshing: false
    property bool actionRunning: false
    property string lastError: ""
    property int pendingRefreshes: 0

    readonly property var layouts: [
        { id: "adaptive", label: "Adaptive", icon: "auto_awesome" },
        { id: "all", label: "All available", icon: "select_all" },
        { id: "dual-tvs", label: "Both TVs", icon: "video_settings" },
        { id: "primary-aux", label: "Primary + aux", icon: "view_sidebar" },
        { id: "secondary-aux", label: "Secondary + aux", icon: "view_sidebar" },
        { id: "solo-primary", label: "Primary TV", icon: "tv" },
        { id: "solo-secondary", label: "Secondary TV", icon: "tv" },
        { id: "solo-tertiary", label: "Auxiliary", icon: "desktop_windows" }
    ]

    function loadSettings() {
        if (!pluginService || !pluginService.loadPluginData)
            return
        refreshInterval = pluginService.loadPluginData("dankDisplayControl", "refreshInterval", 2) || 2
        televisionWidthThreshold = pluginService.loadPluginData("dankDisplayControl", "televisionWidthThreshold", 1000) || 1000
        showAudio = pluginService.loadPluginData("dankDisplayControl", "showAudio", true) !== false
    }

    Component.onCompleted: {
        loadSettings()
        refreshAll()
    }

    onPluginServiceChanged: loadSettings()

    Timer {
        id: settingsTimer
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.loadSettings()
    }

    Timer {
        id: refreshTimer
        interval: Math.max(1, root.refreshInterval) * 1000
        running: true
        repeat: true
        onTriggered: root.refreshAll()
    }

    Timer {
        id: actionRefreshTimer
        interval: 900
        repeat: false
        onTriggered: root.refreshAll()
    }

    function beginRefresh(process) {
        if (process.running)
            return
        pendingRefreshes++
        isRefreshing = true
        process.running = true
    }

    function finishRefresh() {
        pendingRefreshes = Math.max(0, pendingRefreshes - 1)
        isRefreshing = pendingRefreshes > 0
    }

    function refreshAll() {
        beginRefresh(layoutProcess)
        beginRefresh(mirrorProcess)
        if (showAudio)
            beginRefresh(audioProcess)
        beginRefresh(monitorsProcess)
        beginRefresh(clientsProcess)
    }

    function runAction(command) {
        if (actionRunning || !command || command.length === 0)
            return
        actionRunning = true
        lastError = ""
        actionProcess.command = command
        actionProcess.running = true
    }

    function selectLayout(layoutId) {
        runAction(["couch-display-layout", layoutId])
    }

    function toggleMirror() {
        runAction(["couch-display-mirror", "toggle"])
    }

    function cycleAudio() {
        runAction(["couch-audio-output", "cycle"])
    }

    function parseJson(text, fallback) {
        try {
            var parsed = JSON.parse(text.trim())
            return parsed
        } catch (error) {
            return fallback
        }
    }

    function isInternal(monitor) {
        if (!monitor || !monitor.name)
            return false
        return monitor.name.indexOf("eDP-") === 0 || monitor.name.indexOf("LVDS-") === 0
    }

    function connectedExternalMonitors() {
        var result = []
        for (var i = 0; i < monitors.length; i++) {
            var monitor = monitors[i]
            if (!isInternal(monitor) && monitor.disabled !== true)
                result.push(monitor)
        }
        result.sort(function(a, b) {
            return ((b.physicalWidth || 0) * (b.physicalHeight || 0))
                - ((a.physicalWidth || 0) * (a.physicalHeight || 0))
        })
        return result
    }

    function activeExternalMonitors() {
        return connectedExternalMonitors().filter(function(monitor) {
            return monitor.dpmsStatus === true
        })
    }

    function televisionMonitors() {
        return connectedExternalMonitors().filter(function(monitor) {
            return (monitor.physicalWidth || 0) >= televisionWidthThreshold
        })
    }

    function monitorRole(monitor) {
        if ((monitor.physicalWidth || 0) < televisionWidthThreshold)
            return "Auxiliary display"
        var televisions = televisionMonitors()
        for (var i = 0; i < televisions.length; i++) {
            if (televisions[i].name === monitor.name)
                return i === 0 ? "Primary TV" : (i === 1 ? "Secondary TV" : "TV")
        }
        return "TV"
    }

    function monitorInches(monitor) {
        var width = monitor.physicalWidth || 0
        var height = monitor.physicalHeight || 0
        if (width <= 0 || height <= 0)
            return 0
        return Math.round(Math.sqrt(width * width + height * height) / 25.4)
    }

    function monitorDetail(monitor) {
        var inches = monitorInches(monitor)
        var width = monitor.width || 0
        var height = monitor.height || 0
        var refresh = Math.round(monitor.refreshRate || 0)
        var parts = []
        if (inches > 0)
            parts.push(inches + " inch")
        if (width > 0 && height > 0)
            parts.push(width + "x" + height + (refresh > 0 ? " @ " + refresh + " Hz" : ""))
        return parts.join(" · ")
    }

    function layoutLabel(layoutId) {
        for (var i = 0; i < layouts.length; i++) {
            if (layouts[i].id === layoutId)
                return layouts[i].label
        }
        return layoutId || "Unknown"
    }

    function hasSoftwareMirror() {
        for (var i = 0; i < clients.length; i++) {
            var title = clients[i].title || ""
            if (title.indexOf("Couch mirror ") === 0)
                return true
        }
        return false
    }

    function hasNativeMirror() {
        var active = activeExternalMonitors()
        for (var i = 0; i < active.length; i++) {
            var mirrorOf = active[i].mirrorOf
            if (mirrorOf && mirrorOf !== "none")
                return true
        }
        return false
    }

    function mirrorIsEffective() {
        return hasSoftwareMirror() || hasNativeMirror()
    }

    function mirrorLabel() {
        if (mirrorState !== "on")
            return "Off"
        return mirrorIsEffective() ? "Active" : "Armed"
    }

    function displayCountLabel() {
        var count = activeExternalMonitors().length
        return count + (count === 1 ? " display" : " displays")
    }

    function pillLabel() {
        var text = layoutLabel(layoutState) + " · " + activeExternalMonitors().length
        if (mirrorState === "on")
            text += mirrorIsEffective() ? " · Mirror" : " · Armed"
        return text
    }

    Process {
        id: layoutProcess
        command: ["couch-display-layout", "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var value = text.trim().split("\n")[0]
                if (value)
                    root.layoutState = value
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.lastError = "Display layout command is unavailable"
            root.finishRefresh()
        }
    }

    Process {
        id: mirrorProcess
        command: ["couch-display-mirror", "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var value = text.trim().split("\n")[0]
                if (value)
                    root.mirrorState = value
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.lastError = "Display mirror command is unavailable"
            root.finishRefresh()
        }
    }

    Process {
        id: audioProcess
        command: ["couch-audio-output", "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var value = text.trim().split("\n")[0]
                if (value)
                    root.audioState = value
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.lastError = "Audio output command is unavailable"
            root.finishRefresh()
        }
    }

    Process {
        id: monitorsProcess
        command: ["hyprctl", "-j", "monitors", "all"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.monitors = root.parseJson(text, [])
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.lastError = "Hyprland display state is unavailable"
            root.finishRefresh()
        }
    }

    Process {
        id: clientsProcess
        command: ["hyprctl", "-j", "clients"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.clients = root.parseJson(text, [])
        }
        onExited: (exitCode, exitStatus) => root.finishRefresh()
    }

    Process {
        id: actionProcess
        command: ["true"]
        running: false
        onExited: (exitCode, exitStatus) => {
            root.actionRunning = false
            if (exitCode !== 0)
                root.lastError = "The requested display action failed"
            actionRefreshTimer.restart()
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.mirrorIsEffective() ? "screen_share" : "display_settings"
                size: Theme.barIconSize(root.barThickness, -4)
                color: root.mirrorState === "on" ? Theme.primary : Theme.widgetIconColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.pillLabel()
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                color: Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 1

            DankIcon {
                name: root.mirrorIsEffective() ? "screen_share" : "display_settings"
                size: Theme.barIconSize(root.barThickness)
                color: root.mirrorState === "on" ? Theme.primary : Theme.widgetIconColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.activeExternalMonitors().length.toString()
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                color: Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: "Display control"
            detailsText: root.layoutLabel(root.layoutState) + " · " + root.displayCountLabel()
            showCloseButton: true

            headerActions: Component {
                DankActionButton {
                    iconName: root.isRefreshing ? "sync" : "refresh"
                    iconColor: Theme.surfaceVariantText
                    buttonSize: 28
                    enabled: !root.isRefreshing
                    tooltipText: "Refresh display state"
                    tooltipSide: "bottom"
                    onClicked: root.refreshAll()
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledRect {
                    width: parent.width
                    height: statusContent.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: statusContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Item {
                            width: parent.width
                            height: Math.max(selectedLayout.implicitHeight, mirrorButton.implicitHeight)

                            Column {
                                anchors.left: parent.left
                                anchors.right: mirrorButton.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    text: "Selected policy"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    id: selectedLayout
                                    width: parent.width
                                    text: root.layoutLabel(root.layoutState)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            DankButton {
                                id: mirrorButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Mirror: " + root.mirrorLabel()
                                iconName: root.mirrorIsEffective() ? "screen_share" : "mobile_screen_share"
                                enabled: !root.actionRunning
                                onClicked: root.toggleMirror()
                            }
                        }

                        Item {
                            visible: root.showAudio
                            width: parent.width
                            height: visible ? Math.max(audioText.implicitHeight, audioButton.implicitHeight) : 0

                            StyledText {
                                id: audioText
                                anchors.left: parent.left
                                anchors.right: audioButton.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Audio: " + root.audioState
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            DankButton {
                                id: audioButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Next audio"
                                iconName: "speaker_group"
                                enabled: !root.actionRunning
                                onClicked: root.cycleAudio()
                            }
                        }
                    }
                }

                StyledText {
                    text: "Effective outputs"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: root.connectedExternalMonitors()

                        Item {
                            required property var modelData
                            width: parent.width
                            height: Math.max(outputRole.implicitHeight + outputDetail.implicitHeight + 2, 36)

                            StyledRect {
                                width: 8
                                height: 8
                                radius: 4
                                color: modelData.dpmsStatus === true ? Theme.primary : Theme.surfaceVariantText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 8 + Theme.spacingS
                                anchors.right: outputState.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    id: outputRole
                                    width: parent.width
                                    text: root.monitorRole(modelData)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                StyledText {
                                    id: outputDetail
                                    width: parent.width
                                    text: root.monitorDetail(modelData)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            StyledText {
                                id: outputState
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.dpmsStatus === true ? "Active" : "Parked"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: modelData.dpmsStatus === true ? Theme.primary : Theme.surfaceVariantText
                            }
                        }
                    }

                    StyledText {
                        visible: root.connectedExternalMonitors().length === 0
                        text: "No external display is currently reported by Hyprland"
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                StyledText {
                    text: "Choose a layout"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                }

                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: Theme.spacingS
                    rowSpacing: Theme.spacingS

                    Repeater {
                        model: root.layouts

                        LayoutChoice {
                            required property var modelData
                            width: (parent.width - parent.columnSpacing) / 2
                            layoutId: modelData.id
                            label: modelData.label
                            iconName: modelData.icon
                        }
                    }
                }

                StyledText {
                    visible: root.lastError !== ""
                    width: parent.width
                    text: root.lastError
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                }
            }
        }
    }

    component LayoutChoice: StyledRect {
        id: choice

        property string layoutId: ""
        property string label: ""
        property string iconName: "display_settings"
        readonly property bool selected: root.layoutState === layoutId

        height: Math.max(52, choiceRow.implicitHeight + Theme.spacingM * 2)
        radius: Theme.cornerRadius
        color: selected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
            : (choiceMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
        border.width: selected ? 2 : 1
        border.color: selected ? Theme.primary : Theme.outlineVariant
        opacity: root.actionRunning ? 0.6 : 1

        Row {
            id: choiceRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            DankIcon {
                name: choice.selected ? "check_circle" : choice.iconName
                size: Theme.iconSize
                color: choice.selected ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                width: parent.width - Theme.iconSize - Theme.spacingS
                text: choice.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: choice.selected ? Font.Bold : Font.Medium
                color: choice.selected ? Theme.primary : Theme.surfaceText
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: choiceMouse
            anchors.fill: parent
            enabled: !root.actionRunning
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectLayout(choice.layoutId)
        }
    }
}
