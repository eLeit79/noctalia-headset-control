import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property bool hovered: false

  // Bar positioning properties
  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: Style.getBarHeightForScreen(screenName)
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

  // Headset state, published by Main.qml
  readonly property int level: root.pluginApi?.mainInstance?.batteryLevel !== undefined ? root.pluginApi.mainInstance.batteryLevel : -1
  readonly property bool online: root.pluginApi?.mainInstance?.online === true
  readonly property bool charging: root.pluginApi?.mainInstance?.charging === true
  readonly property string deviceName: root.pluginApi?.mainInstance?.deviceName || root.tr("device.fallback-name")

  readonly property bool hideWhenOffline: root.pluginApi?.pluginSettings?.hideWhenOffline !== undefined ? root.pluginApi.pluginSettings.hideWhenOffline : (root.pluginApi?.manifest?.metadata?.defaultSettings?.hideWhenOffline !== false)
  readonly property int lowThreshold: root.pluginApi?.pluginSettings?.lowThreshold || root.pluginApi?.manifest?.metadata?.defaultSettings?.lowThreshold || 20

  readonly property bool isLow: root.online && !root.charging && root.level >= 0 && root.level <= root.lowThreshold
  readonly property bool isVisible: root.online || !root.hideWhenOffline

  visible: root.isVisible
  opacity: root.isVisible ? 1.0 : 0.0

  readonly property real contentWidth: isVertical ? root.capsuleHeight : layout.implicitWidth + Style.marginS * 2
  readonly property real contentHeight: isVertical ? layout.implicitHeight + Style.marginS * 2 : root.capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight

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

  function iconName() {
    if (!root.online)
      return "battery-off";
    if (root.charging)
      return "battery-charging";
    return "bt-device-headset";
  }

  function labelText() {
    if (!root.online)
      return "--";
    if (root.level < 0)
      return "?";
    return root.level + "%";
  }

  function contentColor() {
    if (root.hovered)
      return Color.mOnHover;
    if (root.isLow)
      return Color.mError;
    return Color.mOnSurface;
  }

  //
  // ------ Widget ------
  //
  Rectangle {
    id: visualCapsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.contentWidth
    height: root.contentHeight
    color: root.hovered ? Color.mHover : Style.capsuleColor
    radius: Style.radiusM
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Item {
      id: layout
      anchors.centerIn: parent

      implicitWidth: grid.implicitWidth
      implicitHeight: grid.implicitHeight

      GridLayout {
        id: grid
        columns: root.isVertical ? 1 : 2
        rowSpacing: Style.marginS
        columnSpacing: Style.marginS

        NIcon {
          Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
          icon: root.iconName()
          color: root.contentColor()
        }

        NText {
          Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
          text: root.labelText()
          color: root.contentColor()
          pointSize: root.barFontSize
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onEntered: {
      root.hovered = true;
      root.buildTooltip();
    }

    onExited: {
      root.hovered = false;
      TooltipService.hide();
    }

    onPressed: mouse => {
      TooltipService.hide();

      if (mouse.button == Qt.LeftButton)
        root.pluginApi?.openPanel(root.screen, root);
      else if (mouse.button == Qt.RightButton)
        PanelService.showContextMenu(contextMenu, root, screen);
    }

    NPopupContextMenu {
      id: contextMenu

      model: [
        {
          "label": root.tr("bar.menu.refresh"),
          "action": "refresh",
          "icon": "refresh"
        },
        {
          "label": I18n.tr("actions.widget-settings"),
          "action": "widget-settings",
          "icon": "settings"
        },
      ]

      onTriggered: action => {
        contextMenu.close();
        PanelService.closeContextMenu(screen);

        if (action === "refresh")
          root.pluginApi?.mainInstance?.refresh();
        else if (action === "widget-settings")
          BarService.openPluginSettings(screen, pluginApi.manifest);
      }
    }
  }

  function buildTooltip() {
    var msg;
    if (!root.online)
      msg = root.tr("bar.tooltip.offline", {
        "device": root.deviceName
      });
    else if (root.charging)
      msg = root.tr("bar.tooltip.charging", {
        "device": root.deviceName,
        "level": root.level
      });
    else
      msg = root.tr("bar.tooltip.level", {
        "device": root.deviceName,
        "level": root.level
      });

    TooltipService.show(root, msg, BarService.getTooltipDirection(root.screenName));
  }
}
