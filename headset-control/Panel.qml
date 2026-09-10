import QtQuick
import QtQuick.Layouts
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

  function batteryText() {
    if (!root.main || !root.main.hasBattery)
      return "";
    if (!root.main.online)
      return root.tr("panel.status.offline");
    if (root.main.charging)
      return root.tr("panel.status.charging", {
        "level": root.main.batteryLevel
      });
    return root.tr("panel.status.battery", {
      "level": root.main.batteryLevel
    });
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
          text: root.main?.deviceName || root.tr("device.fallback-name")
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
        enabled: root.main?.deviceFound === true
        label: root.tr("panel.sidetone.label")
        description: root.tr("panel.sidetone.desc-toggle")
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
        // Capabilities are kept when the device disappears so the panel does not empty
        // out, but a control that can only fail should not look operable.
        enabled: root.main?.deviceFound === true

        RowLayout {
          Layout.fillWidth: true

          NLabel {
            Layout.fillWidth: true
            label: root.tr("panel.sidetone.label")
            description: root.tr("panel.sidetone.desc-slider")
          }

          NText {
            text: sidetoneSlider.value <= 0 ? root.tr("panel.sidetone.off") : Math.round(sidetoneSlider.value).toString()
            color: Color.mOnSurfaceVariant
          }
        }

        NSlider {
          id: sidetoneSlider
          Layout.fillWidth: true
          from: 0
          to: 128
          stepSize: 1
          value: root.main ? root.main.sidetone : 0

          // Dragging commits on release. Arrow keys and the wheel move the value without
          // pressed ever becoming true, so those commit on a short pause instead —
          // otherwise a keyboard change was shown but never sent to the headset.
          onPressedChanged: {
            if (!pressed) {
              sidetoneCommit.stop();
              root.main?.applySidetone(value);
            }
          }
          onMoved: {
            if (!pressed)
              sidetoneCommit.restart();
          }
        }

        Timer {
          id: sidetoneCommit
          interval: 400
          repeat: false
          onTriggered: root.main?.applySidetone(sidetoneSlider.value)
        }
      }

      //
      // ------ Auto power-off ------
      //
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        visible: root.main?.hasInactiveTime === true
        enabled: root.main?.deviceFound === true

        RowLayout {
          Layout.fillWidth: true

          NLabel {
            Layout.fillWidth: true
            label: root.tr("panel.inactive-time.label")
            description: root.tr("panel.inactive-time.desc")
          }

          NText {
            text: inactiveSlider.value <= 0 ? root.tr("panel.inactive-time.never") : root.tr("panel.inactive-time.value", {
              "count": Math.round(inactiveSlider.value)
            })
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
            if (!pressed) {
              inactiveCommit.stop();
              root.main?.applyInactiveTime(value);
            }
          }
          onMoved: {
            if (!pressed)
              inactiveCommit.restart();
          }
        }

        Timer {
          id: inactiveCommit
          interval: 400
          repeat: false
          onTriggered: root.main?.applyInactiveTime(inactiveSlider.value)
        }
      }

      //
      // ------ Voice prompts ------
      //
      NToggle {
        Layout.fillWidth: true
        visible: root.main?.hasVoicePrompts === true
        enabled: root.main?.deviceFound === true
        label: root.tr("panel.voice-prompts.label")
        description: root.tr("panel.voice-prompts.desc")
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
        // "Have we heard from a device yet?" is deviceFound, not the capability count:
        // a device that reports zero capabilities has still reported, and used to be
        // told the plugin was waiting for it.
        text: root.main?.toolAvailable === false ? root.tr("panel.tool-missing") : (root.main?.deviceFound === true ? root.tr("panel.no-controls") : root.tr("panel.waiting"))
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
      }

      NText {
        Layout.fillWidth: true
        visible: root.main?.hasAnyControl === true && root.main?.deviceFound !== true
        text: root.tr("panel.device-absent")
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
        // Before anything has been applied, the values on show are manifest defaults that
        // may not match the headset; claiming they are "the last ones applied from here"
        // would be untrue on a fresh install.
        text: root.main?.controlsApplied === true ? root.tr("panel.write-only-note") : root.tr("panel.defaults-note")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
      }
    }
  }
}
