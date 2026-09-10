import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  readonly property var main: pluginApi?.mainInstance

  readonly property var geometryPlaceholder: panelContainer
  property real contentPreferredWidth: 340 * Style.uiScaleRatio
  property real contentPreferredHeight: panelContent.implicitHeight + Style.marginL * 2
  readonly property bool allowAttach: true

  anchors.fill: parent

  Component.onCompleted: root.main?.refresh()

  function batteryText() {
    if (!root.main || !root.main.hasBattery)
      return "";
    if (!root.main.online)
      return "Off or disconnected";
    if (root.main.charging)
      return "Charging - " + root.main.batteryLevel + "%";
    return "Battery " + root.main.batteryLevel + "%";
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      id: panelContent
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      //
      // ------ Header ------
      //
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        NText {
          text: root.main?.deviceName || "Headset"
          pointSize: Style.fontSizeL
          font.weight: Font.DemiBold
          color: Color.mOnSurface
        }

        NText {
          visible: text !== ""
          text: root.batteryText()
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
        }
      }

      NDivider {
        Layout.fillWidth: true
        visible: root.main?.hasAnyControl === true
      }

      //
      // ------ Sidetone: toggle where the device ignores levels ------
      //
      NToggle {
        Layout.fillWidth: true
        visible: root.main?.hasSidetone === true && root.main?.sidetoneLevelIgnored === true
        label: "Hear yourself"
        description: "Sidetone: feeds your mic back into the earcups. This headset supports on/off only, not a level."
        checked: root.main ? root.main.sidetoneEnabled : false
        onToggled: function (checked) {
          root.main?.applySidetoneEnabled(checked);
        }
      }

      //
      // ------ Sidetone: level slider where the device honours levels ------
      //
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        visible: root.main?.hasSidetone === true && root.main?.sidetoneLevelIgnored !== true

        RowLayout {
          Layout.fillWidth: true

          NLabel {
            Layout.fillWidth: true
            label: "Hear yourself"
            description: "Sidetone: feeds your mic back into the earcups. 0 turns it off."
          }

          NText {
            text: sidetoneSlider.value <= 0 ? "Off" : Math.round(sidetoneSlider.value).toString()
            color: Color.mOnSurfaceVariant
          }
        }

        NSlider {
          id: sidetoneSlider
          Layout.fillWidth: true
          from: 0
          to: 127
          stepSize: 1
          value: root.main ? root.main.sidetone : 0
          onPressedChanged: {
            if (!pressed)
              root.main?.applySidetone(value);
          }
        }
      }

      //
      // ------ Auto power-off ------
      //
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        visible: root.main?.hasInactiveTime === true

        RowLayout {
          Layout.fillWidth: true

          NLabel {
            Layout.fillWidth: true
            label: "Auto power-off"
            description: "Switch the headset off after this long with no audio, to save battery."
          }

          NText {
            text: inactiveSlider.value <= 0 ? "Never" : Math.round(inactiveSlider.value) + " min"
            color: Color.mOnSurfaceVariant
          }
        }

        NSlider {
          id: inactiveSlider
          Layout.fillWidth: true
          from: 0
          to: 90
          stepSize: 5
          value: root.main ? root.main.inactiveTime : 0
          onPressedChanged: {
            if (!pressed)
              root.main?.applyInactiveTime(value);
          }
        }
      }

      //
      // ------ Voice prompts ------
      //
      NToggle {
        Layout.fillWidth: true
        visible: root.main?.hasVoicePrompts === true
        label: "Voice prompts"
        description: "Spoken announcements from the headset."
        checked: root.main ? root.main.voicePrompts : true
        onToggled: function (checked) {
          root.main?.applyVoicePrompts(checked);
        }
      }

      //
      // ------ Nothing to adjust ------
      //
      NText {
        Layout.fillWidth: true
        visible: root.main !== null && root.main !== undefined && !root.main.hasAnyControl
        text: root.main && root.main.capabilities.length > 0 ? "This headset reports no adjustable settings." : "Waiting for headsetcontrol to report the device..."
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
      }

      NDivider {
        Layout.fillWidth: true
        visible: root.main?.hasAnyControl === true
      }

      NText {
        Layout.fillWidth: true
        visible: root.main?.hasAnyControl === true
        text: "The headset cannot report these settings back, so the values shown are the last ones applied from here."
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
      }
    }
  }
}
