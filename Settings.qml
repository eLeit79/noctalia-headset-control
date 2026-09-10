import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null
  property ShellScreen screen

  property int pollIntervalSeconds: pluginApi?.pluginSettings?.pollIntervalSeconds || pluginApi?.manifest?.metadata?.defaultSettings?.pollIntervalSeconds || 60
  property int lowThreshold: pluginApi?.pluginSettings?.lowThreshold || pluginApi?.manifest?.metadata?.defaultSettings?.lowThreshold || 20
  property bool hideWhenOffline: pluginApi?.pluginSettings?.hideWhenOffline !== undefined ? pluginApi.pluginSettings.hideWhenOffline : true

  spacing: Style.marginL

  NToggle {
    label: "Hide when headset is off"
    description: "Remove the widget from the bar while the headset is powered down or disconnected."
    checked: root.hideWhenOffline
    onToggled: function (checked) {
      root.hideWhenOffline = checked;
    }
  }

  ColumnLayout {
    Layout.fillWidth: true

    RowLayout {
      spacing: Style.marginL

      NLabel {
        label: "Poll interval"
        description: "How often to ask the headset for its battery level."
      }

      NText {
        text: root.pollIntervalSeconds + " seconds"
        color: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mOnPrimary
      }
    }

    NSlider {
      Layout.fillWidth: true
      from: 15
      to: 600
      value: root.pollIntervalSeconds
      stepSize: 15
      onValueChanged: {
        root.pollIntervalSeconds = value;
      }
    }
  }

  ColumnLayout {
    Layout.fillWidth: true

    RowLayout {
      spacing: Style.marginL

      NLabel {
        label: "Low battery threshold"
        description: "Colour the widget as low battery at or below this level."
      }

      NText {
        text: root.lowThreshold + "%"
        color: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mOnPrimary
      }
    }

    NSlider {
      Layout.fillWidth: true
      from: 5
      to: 50
      value: root.lowThreshold
      stepSize: 5
      onValueChanged: {
        root.lowThreshold = value;
      }
    }
  }

  function saveSettings() {
    if (!pluginApi) {
      Logger.e("HeadsetControl", "Cannot save settings: pluginApi is null");
      return;
    }

    pluginApi.pluginSettings.pollIntervalSeconds = root.pollIntervalSeconds;
    pluginApi.pluginSettings.lowThreshold = root.lowThreshold;
    pluginApi.pluginSettings.hideWhenOffline = root.hideWhenOffline;

    pluginApi.saveSettings();
    pluginApi?.mainInstance?.refresh();

    Logger.i("HeadsetControl", "Settings saved");
    pluginApi.closePanel(root.screen);
  }
}
