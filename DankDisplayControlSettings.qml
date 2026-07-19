import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "dankDisplayControl"

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh interval (seconds)"
        description: "How often to refresh layout and effective output state"
        minimum: 1
        maximum: 30
        defaultValue: 2
    }

    SliderSetting {
        settingKey: "televisionWidthThreshold"
        label: "TV width threshold (millimetres)"
        description: "Displays at least this physically wide are classified as TVs"
        minimum: 500
        maximum: 2000
        defaultValue: 1000
    }

    ToggleSetting {
        settingKey: "showAudio"
        label: "Show audio output"
        description: "Show the selected couch audio output and its cycle action"
        defaultValue: true
    }

    StyledText {
        width: parent.width
        text: "This widget is a frontend for the couch-display-layout, couch-display-mirror, and couch-audio-output command contract. It reads effective output state directly from Hyprland."
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
