import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 520

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
    property string pendingLayout: ""
    property string lastError: ""
    property int pendingRefreshes: 0

    readonly property var layouts: [
        { id: "adaptive", label: "Adaptive" },
        { id: "all", label: "All displays" },
        { id: "dual-tvs", label: "Both TVs" },
        { id: "primary-aux", label: "Primary + aux" },
        { id: "secondary-aux", label: "Secondary + aux" },
        { id: "solo-primary", label: "Primary only" },
        { id: "solo-secondary", label: "Secondary only" },
        { id: "solo-tertiary", label: "Aux only" }
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
        pendingLayout = layoutId
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
        var measured = Math.round(Math.sqrt(width * width + height * height) / 25.4)
        var commonSizes = [24, 27, 32, 40, 43, 48, 49, 50, 55, 58, 65, 75, 77, 85]
        for (var i = 0; i < commonSizes.length; i++) {
            if (Math.abs(commonSizes[i] - measured) <= 1)
                return commonSizes[i]
        }
        return measured
    }

    function monitorDetail(monitor) {
        var inches = monitorInches(monitor)
        var width = monitor.width || 0
        var height = monitor.height || 0
        var refresh = Math.round(monitor.refreshRate || 0)
        var parts = []
        if (inches > 0)
            parts.push(inches + "″")
        if (width > 0 && height > 0)
            parts.push(resolutionLabel(width, height))
        if (refresh > 0)
            parts.push(refresh + "Hz")
        return parts.join(" · ")
    }

    function resolutionLabel(width, height) {
        if (width === 1920 && height === 1080)
            return "1080p"
        if (width === 2560 && height === 1440)
            return "1440p"
        if (width === 3840 && height === 2160)
            return "4K"
        return width + "×" + height
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

    function mirrorAccent() {
        if (mirrorState !== "on")
            return Theme.surfaceVariantText
        return mirrorIsEffective() ? Theme.primary : Theme.tertiary
    }

    function mirrorDescription() {
        if (mirrorState !== "on")
            return "Off"
        return mirrorIsEffective() ? "Active on both TVs" : "Armed — waiting for another TV"
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
                if (value) {
                    root.layoutState = value
                    if (root.pendingLayout === value)
                        root.pendingLayout = ""
                }
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
                color: root.mirrorState === "on" ? root.mirrorAccent() : Theme.widgetIconColor
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
                color: root.mirrorState === "on" ? root.mirrorAccent() : Theme.widgetIconColor
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
                    buttonSize: 36
                    enabled: !root.isRefreshing
                    tooltipText: "Refresh display state"
                    tooltipSide: "bottom"
                    onClicked: root.refreshAll()
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingL

                SectionLabel {
                    text: "Now showing"
                }

                StyledRect {
                    width: parent.width
                    height: outputsColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: outputsColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        Repeater {
                            model: root.connectedExternalMonitors()

                            OutputRow {
                                required property var modelData
                                monitor: modelData
                            }
                        }

                        StyledText {
                            visible: root.connectedExternalMonitors().length === 0
                            width: parent.width
                            text: "No external display is currently reported by Hyprland"
                            wrapMode: Text.WordWrap
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                SectionLabel {
                    text: "Quick actions"
                }

                StyledRect {
                    width: parent.width
                    height: actionsColumn.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: actionsColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingXS

                        ControlRow {
                            width: parent.width
                            iconName: "screen_share"
                            title: "Mirror"
                            subtitle: root.mirrorDescription()
                            accentColor: root.mirrorAccent()
                            trailingLabel: root.mirrorLabel()
                            onActivated: root.toggleMirror()
                        }

                        ControlRow {
                            visible: root.showAudio
                            width: parent.width
                            height: visible ? implicitHeight : 0
                            iconName: "speaker"
                            title: "Audio output"
                            subtitle: root.audioState
                            trailingIcon: "skip_next"
                            onActivated: root.cycleAudio()
                        }
                    }
                }

                SectionLabel {
                    text: "Layout policy"
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
                        }
                    }
                }

                StyledRect {
                    visible: root.lastError !== ""
                    width: parent.width
                    height: visible ? errorRow.implicitHeight + Theme.spacingM * 2 : 0
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.error, 0.12)

                    Row {
                        id: errorRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "error"
                            size: Theme.iconSize
                            color: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            width: parent.width - Theme.iconSize - Theme.spacingS
                            text: root.lastError
                            wrapMode: Text.WordWrap
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }

    component SectionLabel: StyledText {
        width: parent.width
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceVariantText
    }

    component OutputRow: Column {
        id: outputRow

        property var monitor: null
        readonly property bool active: monitor?.dpmsStatus === true

        width: parent.width
        spacing: 2

        Item {
            width: parent.width
            height: Math.max(outputRole.implicitHeight, outputStatus.implicitHeight, Theme.iconSize)

            DankIcon {
                id: outputIcon
                name: root.monitorRole(outputRow.monitor) === "Auxiliary display" ? "desktop_windows" : "tv"
                size: Theme.iconSize
                color: outputRow.active ? Theme.surfaceText : Theme.surfaceVariantText
                opacity: outputRow.active ? 1 : 0.6
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                id: outputRole
                anchors.left: outputIcon.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: outputStatus.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: root.monitorRole(outputRow.monitor)
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
                opacity: outputRow.active ? 1 : 0.6
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledRect {
                id: outputStatus
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: outputStatusText.implicitWidth + Theme.spacingM * 2
                height: outputStatusText.implicitHeight + Theme.spacingXS * 2
                radius: height / 2
                color: outputRow.active
                    ? Theme.withAlpha(Theme.primary, 0.15)
                    : Theme.surfaceContainerHighest

                StyledText {
                    id: outputStatusText
                    anchors.centerIn: parent
                    text: outputRow.active ? "Active" : "Parked"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: outputRow.active ? Theme.primary : Theme.surfaceVariantText
                }
            }
        }

        StyledText {
            x: Theme.iconSize + Theme.spacingS
            width: parent.width - x
            text: root.monitorDetail(outputRow.monitor)
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            opacity: outputRow.active ? 1 : 0.6
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    component ControlRow: StyledRect {
        id: control

        property string iconName: ""
        property string title: ""
        property string subtitle: ""
        property color accentColor: Theme.surfaceVariantText
        property string trailingLabel: ""
        property string trailingIcon: ""
        signal activated

        readonly property real trailingWidth: trailingLabel !== ""
            ? controlStateText.implicitWidth + Theme.spacingM * 2
            : (trailingIcon !== "" ? Theme.iconSize + Theme.spacingM : 0)

        implicitHeight: Math.max(72, controlText.implicitHeight + Theme.spacingM * 2)
        height: visible ? implicitHeight : 0
        radius: Theme.cornerRadius
        color: controlMouse.pressed
            ? Theme.withAlpha(Theme.primary, 0.12)
            : (controlMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.withAlpha(Theme.surfaceContainerHighest, 0))
        opacity: root.actionRunning ? 0.6 : 1

        DankIcon {
            id: controlIcon
            name: control.iconName
            size: Theme.iconSize + 2
            color: control.accentColor
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            id: controlText
            anchors.left: controlIcon.right
            anchors.leftMargin: Theme.spacingM
            anchors.right: controlTrailing.left
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            StyledText {
                width: parent.width
                text: control.title
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                width: parent.width
                text: control.subtitle
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Item {
            id: controlTrailing
            width: control.trailingWidth
            height: parent.height
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            StyledRect {
                visible: control.trailingLabel !== ""
                anchors.centerIn: parent
                width: controlStateText.implicitWidth + Theme.spacingM * 2
                height: controlStateText.implicitHeight + Theme.spacingXS * 2
                radius: height / 2
                color: Theme.withAlpha(control.accentColor, 0.15)

                StyledText {
                    id: controlStateText
                    anchors.centerIn: parent
                    text: control.trailingLabel
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: control.accentColor
                }
            }

            DankIcon {
                visible: control.trailingLabel === "" && control.trailingIcon !== ""
                anchors.centerIn: parent
                name: control.trailingIcon
                size: Theme.iconSize
                color: Theme.surfaceVariantText
            }
        }

        MouseArea {
            id: controlMouse
            anchors.fill: parent
            enabled: !root.actionRunning
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: control.activated()
        }
    }

    component LayoutChoice: StyledRect {
        id: choice

        property string layoutId: ""
        property string label: ""
        readonly property bool selected: root.layoutState === layoutId
        readonly property bool pending: root.pendingLayout === layoutId
        readonly property bool emphasized: selected || pending

        height: 56
        radius: Theme.cornerRadius
        color: emphasized
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
            : (choiceMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
        border.width: emphasized ? 2 : 1
        border.color: emphasized ? Theme.primary : Theme.outlineVariant
        opacity: root.actionRunning && !pending ? 0.6 : 1

        Row {
            id: choiceRow
            anchors.centerIn: parent
            spacing: Theme.spacingS

            DankIcon {
                visible: choice.emphasized
                width: visible ? Theme.iconSize : 0
                name: choice.pending ? "sync" : "check_circle"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: choice.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: choice.emphasized ? Font.Bold : Font.Medium
                color: choice.emphasized ? Theme.primary : Theme.surfaceText
                wrapMode: Text.NoWrap
                maximumLineCount: 1
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
