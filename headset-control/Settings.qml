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

  //
  // ------ i18n ------
  //
  // pluginApi.tr() is a plain function, so a binding that calls it has nothing to
  // re-evaluate on when the language changes. noctalia increments translationVersion on
  // every translation reload, so reading it here gives those bindings a dependency —
  // which is exactly what the plugin API's own comment asks plugins to do.
  readonly property int trVersion: root.pluginApi?.translationVersion || 0

  function tr(key, interpolations) {
    return (root.trVersion >= 0 && root.pluginApi) ? root.pluginApi.tr(key, interpolations) : "";
  }

  NToggle {
    label: root.tr("settings.hide-when-offline.label")
    description: root.tr("settings.hide-when-offline.desc")
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
        label: root.tr("settings.poll-interval.label")
        description: root.tr("settings.poll-interval.desc")
      }

      NText {
        text: root.tr("settings.poll-interval.value", {
          "count": root.pollIntervalSeconds
        })
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
        label: root.tr("settings.low-threshold.label")
        description: root.tr("settings.low-threshold.desc")
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
