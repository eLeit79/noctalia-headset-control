import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi: null

  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings

  readonly property int pollIntervalSeconds: root.setting("pollIntervalSeconds", 60)

  // Control values are remembered here: headsetcontrol can set sidetone, voice
  // prompts and inactive time on this device but cannot read them back, so the
  // last applied value is the only state available.
  readonly property int sidetone: root.setting("sidetone", 0)
  readonly property int sidetoneOnLevel: root.setting("sidetoneOnLevel", 64)
  readonly property bool sidetoneEnabled: root.sidetone > 0
  readonly property int inactiveTime: root.setting("inactiveTime", 0)
  readonly property bool voicePrompts: root.setting("voicePrompts", true) === true

  // Capabilities reported by headsetcontrol for the connected device. Kept from
  // the last successful read so the panel does not empty out when the headset
  // sleeps.
  property var capabilities: []
  property string productId: ""

  readonly property bool hasBattery: root.capabilities.indexOf("CAP_BATTERY_STATUS") !== -1
  readonly property bool hasSidetone: root.capabilities.indexOf("CAP_SIDETONE") !== -1
  readonly property bool hasInactiveTime: root.capabilities.indexOf("CAP_INACTIVE_TIME") !== -1
  readonly property bool hasVoicePrompts: root.capabilities.indexOf("CAP_VOICE_PROMPTS") !== -1
  readonly property bool hasAnyControl: root.hasSidetone || root.hasInactiveTime || root.hasVoicePrompts

  // The Cloud Alpha Wireless ignores the level byte sent after the sidetone
  // enable command (measured by sweeping 1..127), so it gets a toggle. Other
  // devices are assumed to honour levels until shown otherwise.
  readonly property bool sidetoneLevelIgnored: root.productId === "0x098d"

  property int batteryLevel: -1
  property string batteryStatus: "BATTERY_UNAVAILABLE"
  property string deviceName: ""
  property bool deviceFound: false

  readonly property bool charging: root.batteryStatus === "BATTERY_CHARGING"
  readonly property bool online: root.deviceFound && (root.batteryStatus === "BATTERY_AVAILABLE" || root.charging)

  Component.onCompleted: root.refresh()

  function setting(key, fallback) {
    const v = pluginApi?.pluginSettings ? pluginApi.pluginSettings[key] : undefined;
    if (v !== undefined && v !== null)
      return v;
    const d = root.defaults ? root.defaults[key] : undefined;
    return (d !== undefined && d !== null) ? d : fallback;
  }

  function persist(key, value) {
    if (!pluginApi)
      return;
    pluginApi.pluginSettings[key] = value;
    pluginApi.saveSettings();
  }

  function run(proc, cmd) {
    if (proc.running)
      proc.running = false;
    proc.command = cmd;
    proc.running = true;
  }

  //
  // ------ Battery polling ------
  //
  Timer {
    interval: Math.max(10, root.pollIntervalSeconds) * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  function refresh() {
    if (poll.running)
      return;
    poll.command = ["headsetcontrol", "-b", "-o", "json"];
    poll.running = true;
  }

  function clear() {
    root.deviceFound = false;
    root.batteryLevel = -1;
    root.batteryStatus = "BATTERY_UNAVAILABLE";
  }

  Process {
    id: poll

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text);
          const dev = (data.devices && data.devices.length > 0) ? data.devices[0] : null;
          if (!dev) {
            root.clear();
            return;
          }
          root.deviceFound = true;
          root.deviceName = dev.device || "";
          root.capabilities = dev.capabilities || [];
          root.productId = dev.id_product || "";
          // A device that reports no battery is still a device: its identity and
          // capabilities must be read so the panel can offer the controls it does
          // support. Only the battery fields go unavailable. Treating a missing
          // battery as a missing device hid every control on such a headset, and
          // left the previous device's name and capabilities on display.
          if (dev.battery) {
            root.batteryStatus = dev.battery.status || "BATTERY_UNAVAILABLE";
            root.batteryLevel = (typeof dev.battery.level === "number") ? dev.battery.level : -1;
          } else {
            root.batteryStatus = "BATTERY_UNAVAILABLE";
            root.batteryLevel = -1;
          }
        } catch (e) {
          root.clear();
          Logger.w("HeadsetControl", "Cannot parse headsetcontrol output:", e);
        }
      }
    }
  }

  //
  // ------ Controls ------
  //
  function applySidetone(value) {
    const v = Math.round(Math.max(0, Math.min(127, value)));
    root.persist("sidetone", v);
    root.run(sidetoneProc, ["headsetcontrol", "-s", String(v)]);
    Logger.i("HeadsetControl", "Sidetone set to", v);
  }

  // Verified by sweeping levels 1..127 on a Cloud Alpha Wireless: the level byte
  // headsetcontrol sends after the enable command has no audible effect, and 128
  // (0x80) silences sidetone entirely. So this is driven as on/off.
  function applySidetoneEnabled(enabled) {
    root.applySidetone(enabled === true ? root.sidetoneOnLevel : 0);
  }

  function applyVoicePrompts(enabled) {
    const on = enabled === true;
    root.persist("voicePrompts", on);
    root.run(voiceProc, ["headsetcontrol", "-v", on ? "1" : "0"]);
    Logger.i("HeadsetControl", "Voice prompts set to", on);
  }

  function applyInactiveTime(minutes) {
    const v = Math.round(Math.max(0, Math.min(90, minutes)));
    root.persist("inactiveTime", v);
    root.run(inactiveProc, ["headsetcontrol", "-i", String(v)]);
    Logger.i("HeadsetControl", "Auto power-off set to", v, "minutes");
  }

  Process {
    id: sidetoneProc
  }

  Process {
    id: voiceProc
  }

  Process {
    id: inactiveProc
  }

  //
  // ------ IPC ------
  //
  IpcHandler {
    target: "plugin:headset-control"

    function refresh(): void {
      root.refresh();
    }

    function sidetone(level: string): void {
      root.applySidetone(parseInt(level));
    }

    function voicePrompts(enabled: string): void {
      root.applyVoicePrompts(enabled === "1" || enabled === "true");
    }

    function inactiveTime(minutes: string): void {
      root.applyInactiveTime(parseInt(minutes));
    }
  }
}
