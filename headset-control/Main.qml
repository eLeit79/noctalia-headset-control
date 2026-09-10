import QtQuick
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi: null

  readonly property int pollIntervalSeconds: root.setting("pollIntervalSeconds", 60)

  // Control values are remembered here: headsetcontrol can set sidetone, voice
  // prompts and inactive time on this device but cannot read them back, so the
  // last applied value is the only state available.
  readonly property int sidetone: root.setting("sidetone", 0)
  // The level sent when enabling sidetone on a device that ignores levels. A constant,
  // not a setting: nothing has ever written it, so a persisted copy could only drift.
  readonly property int sidetoneOnLevel: 64
  readonly property bool sidetoneEnabled: root.sidetone > 0
  readonly property int inactiveTime: root.setting("inactiveTime", 0)
  readonly property bool voicePrompts: root.setting("voicePrompts", true) === true

  // Capabilities reported by headsetcontrol for the connected device. Kept from
  // the last successful read so the panel does not empty out when the headset
  // sleeps.
  property var capabilities: []
  property string productId: ""

  // False once a poll comes back with nothing on stdout, which is what a missing or
  // broken headsetcontrol looks like. A working one always prints JSON, even with no
  // device attached (it exits non-zero, which is why the exit code alone proves nothing).
  property bool toolAvailable: true

  // Whether any control has ever been applied from here. Until one has, the values shown
  // are the plugin's defaults and may not match the headset at all, which the panel has
  // to say rather than implying they were read back.
  readonly property bool controlsApplied: root.setting("controlsApplied", false) === true

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

  // pluginSettings arrives with the manifest defaults already merged in (PluginService
  // does that before handing the api to a plugin), so this only needs a literal fallback.
  function setting(key, fallback) {
    const v = pluginApi?.pluginSettings ? pluginApi.pluginSettings[key] : undefined;
    return (v !== undefined && v !== null) ? v : fallback;
  }

  function persist(values) {
    if (!pluginApi)
      return;
    for (var key in values)
      pluginApi.pluginSettings[key] = values[key];
    pluginApi.saveSettings();
  }

  function run(proc, cmd) {
    if (proc.running) {
      // Killing an in-flight command makes it exit non-zero (SIGTERM reports 15), which
      // must not be read as "this value failed": the replacement started just below is
      // about to apply the newer one. Without this flag, double-clicking a toggle let the
      // dying command's revert overwrite the value its successor applied successfully,
      // leaving the panel asserting the opposite of what the headset was told.
      proc.superseded = true;
      proc.running = false;
    }
    proc.command = cmd;
    proc.running = true;
    proc.pending = true;
    startCheck.restart();
  }

  //
  // ------ Did the command start at all? ------
  //
  // Quickshell's Process emits neither exited nor stdout.onStreamFinished when the binary
  // cannot be found: running simply goes back to false, silently. Every other failure path
  // in this file hangs off one of those two signals, so without this check a missing
  // headsetcontrol is indistinguishable from a headset that has not reported yet, and a
  // setter persists a value that reached nothing. running still reads true synchronously
  // after the assignment even for a command that cannot start, so the check has to be
  // deferred rather than made inline.
  readonly property var watchedProcs: [poll, sidetoneProc, voiceProc, inactiveProc]

  Timer {
    id: startCheck
    interval: 3000
    repeat: false
    onTriggered: {
      for (var i = 0; i < root.watchedProcs.length; i++) {
        const proc = root.watchedProcs[i];
        if (proc.pending && !proc.running)
          root.startFailed(proc);
      }
    }
  }

  function startFailed(proc) {
    proc.pending = false;
    if (root.toolAvailable)
      Logger.w("HeadsetControl", "headsetcontrol could not be started - is it installed?");
    root.toolAvailable = false;
    if (proc === poll) {
      pollWatchdog.stop();
      root.clear();
      root.logState("start-failed");
    } else {
      root.revertControl(proc, "headsetcontrol could not be started");
    }
  }

  //
  // ------ Battery polling ------
  //
  Timer {
    interval: Math.max(15, root.pollIntervalSeconds) * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  function refresh() {
    // The guard stops overlapping polls, so it must never latch: if headsetcontrol hangs
    // (a wedged dongle will do it), every later refresh, the timer and the IPC would all
    // become silent no-ops until the shell restarted. The watchdog below breaks that.
    if (poll.running)
      return;
    poll.timedOut = false;
    poll.command = ["headsetcontrol", "-b", "-o", "json"];
    poll.running = true;
    poll.pending = true;
    pollWatchdog.restart();
    startCheck.restart();
  }

  Timer {
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (!poll.running)
        return;
      Logger.w("HeadsetControl", "headsetcontrol did not finish within", interval / 1000, "s - killing it");
      // Marks the output that follows as unusable: a killed poll still delivers whatever
      // it had collected, and empty output from it would otherwise be misread as "the
      // tool is missing" when the tool is merely slow.
      poll.timedOut = true;
      poll.running = false;
      pollKill.restart();
      root.clear();
      root.logState("poll-timeout");
    }
  }

  // running = false only asks politely. A process wedged in a USB ioctl can ignore that,
  // and while it lives refresh()'s guard keeps every later poll a no-op - the exact latch
  // the watchdog exists to break. So the request is escalated.
  Timer {
    id: pollKill
    interval: 2000
    repeat: false
    onTriggered: {
      if (!poll.running)
        return;
      Logger.w("HeadsetControl", "headsetcontrol ignored SIGTERM - sending SIGKILL");
      poll.signal(9);
    }
  }

  // Debug-level, so it is silent in normal use and visible with NOCTALIA_DEBUG=1. The
  // capability tests in test/ read these lines to check gating without a UI.
  function logState(tag) {
    Logger.d("HeadsetControl", "state " + tag + " found=" + root.deviceFound + " name='" + root.deviceName + "' level=" + root.batteryLevel + " status=" + root.batteryStatus + " online=" + root.online + " pid=" + root.productId + " caps=[" + root.capabilities.join(",") + "] hasBattery=" + root.hasBattery + " hasSidetone=" + root.hasSidetone + " hasInactive=" + root.hasInactiveTime + " hasVoice=" + root.hasVoicePrompts + " hasAny=" + root.hasAnyControl + " levelIgnored=" + root.sidetoneLevelIgnored);
  }

  function clear() {
    root.deviceFound = false;
    root.batteryLevel = -1;
    root.batteryStatus = "BATTERY_UNAVAILABLE";
    // Capabilities and productId are deliberately kept so the panel does not empty out
    // while the headset sleeps, but the name must go: clear() only runs when nothing is
    // enumerated at all, and naming a device that is not there is simply wrong.
    root.deviceName = "";
  }

  Process {
    id: poll

    // Set from the moment a poll is started until one of the completion paths is reached;
    // startCheck reads it to tell "never started" from "finished".
    property bool pending: false
    // Set when the watchdog killed this poll, so its truncated output is discarded.
    property bool timedOut: false

    onExited: (exitCode, exitStatus) => {
      // A non-zero code is normal — headsetcontrol exits 1 when no device is attached
      // while still printing valid JSON — so the code is only used to stop the watchdog.
      pollWatchdog.stop();
      pollKill.stop();
      poll.pending = false;
    }

    stdout: StdioCollector {
      onStreamFinished: {
        pollWatchdog.stop();
        poll.pending = false;
        if (poll.timedOut) {
          poll.timedOut = false;
          return;
        }
        if (!text || text.trim() === "") {
          // A working headsetcontrol always prints JSON. Nothing on stdout means it is
          // missing or broken, which the panel says outright instead of pretending to
          // still be waiting for a device to appear.
          if (root.toolAvailable)
            Logger.w("HeadsetControl", "headsetcontrol produced no output - is it installed?");
          root.toolAvailable = false;
          root.clear();
          root.logState("no-output");
          return;
        }
        root.toolAvailable = true;
        try {
          const data = JSON.parse(text);
          const dev = (data.devices && data.devices.length > 0) ? data.devices[0] : null;
          if (!dev) {
            root.clear();
            root.logState("no-device");
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
            // Clamped: a device reporting a bogus level would otherwise render as "255%".
            root.batteryLevel = (typeof dev.battery.level === "number") ? Math.max(-1, Math.min(100, Math.round(dev.battery.level))) : -1;
          } else {
            root.batteryStatus = "BATTERY_UNAVAILABLE";
            root.batteryLevel = -1;
          }
          root.logState("parsed");
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
  // Applies a control and remembers what to put back if headsetcontrol rejects it. The
  // value is persisted up front so the UI responds immediately; controlFinished() undoes
  // that if the command fails, rather than leaving the panel asserting a setting the
  // headset never received.
  function applyControl(proc, key, value, cmd, label) {
    proc.revertKey = key;
    proc.revertValue = root.setting(key, value);
    // controlsApplied is part of what a failed apply has to undo: a first-ever apply that
    // never reached the headset must not leave the panel claiming these values came from
    // here, which is what its footnote says once the flag is set.
    proc.revertApplied = root.controlsApplied;
    root.persist({
      [key]: value,
      "controlsApplied": true
    });
    root.run(proc, cmd);
    Logger.i("HeadsetControl", label, value);
  }

  function controlFinished(proc, exitCode) {
    if (proc.superseded) {
      // This exit belongs to a command we killed ourselves; its successor owns the state.
      proc.superseded = false;
      return;
    }
    proc.pending = false;
    if (exitCode === 0) {
      proc.revertKey = "";
      return;
    }
    root.revertControl(proc, "headsetcontrol exited " + exitCode);
  }

  function revertControl(proc, why) {
    if (proc.revertKey === "")
      return;
    Logger.w("HeadsetControl", why, "applying", proc.revertKey, "- reverting to", proc.revertValue);
    root.persist({
      [proc.revertKey]: proc.revertValue,
      "controlsApplied": proc.revertApplied
    });
    proc.revertKey = "";
  }

  function applySidetone(value) {
    if (!isFinite(value))
      return;
    const v = Math.round(Math.max(0, Math.min(128, value)));
    root.applyControl(sidetoneProc, "sidetone", v, ["headsetcontrol", "-s", String(v)], "Sidetone set to");
  }

  // Verified by sweeping levels 1..127 on a Cloud Alpha Wireless: the level byte
  // headsetcontrol sends after the enable command has no audible effect, and 128
  // (0x80) silences sidetone entirely. So this is driven as on/off.
  function applySidetoneEnabled(enabled) {
    root.applySidetone(enabled === true ? root.sidetoneOnLevel : 0);
  }

  function applyVoicePrompts(enabled) {
    const on = enabled === true;
    root.applyControl(voiceProc, "voicePrompts", on, ["headsetcontrol", "-v", on ? "1" : "0"], "Voice prompts set to");
  }

  function applyInactiveTime(minutes) {
    if (!isFinite(minutes))
      return;
    const v = Math.round(Math.max(0, Math.min(90, minutes)));
    root.applyControl(inactiveProc, "inactiveTime", v, ["headsetcontrol", "-i", String(v)], "Auto power-off set to");
  }

  Process {
    id: sidetoneProc
    property string revertKey: ""
    property var revertValue: null
    property bool revertApplied: false
    property bool pending: false
    property bool superseded: false
    onExited: (exitCode, exitStatus) => root.controlFinished(sidetoneProc, exitCode)
  }

  Process {
    id: voiceProc
    property string revertKey: ""
    property var revertValue: null
    property bool revertApplied: false
    property bool pending: false
    property bool superseded: false
    onExited: (exitCode, exitStatus) => root.controlFinished(voiceProc, exitCode)
  }

  Process {
    id: inactiveProc
    property string revertKey: ""
    property var revertValue: null
    property bool revertApplied: false
    property bool pending: false
    property bool superseded: false
    onExited: (exitCode, exitStatus) => root.controlFinished(inactiveProc, exitCode)
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
      // Unvalidated input used to reach both settings.json and the command line: a
      // non-numeric argument became NaN, persisted as null, and ran "headsetcontrol -s NaN".
      const v = parseInt(level);
      if (isNaN(v)) {
        Logger.w("HeadsetControl", "ipc sidetone: not a number:", level);
        return;
      }
      root.applySidetone(v);
    }

    function voicePrompts(enabled: string): void {
      // Anything unrecognised used to fall through to false, so "voicePrompts yes" quietly
      // turned them off and persisted that. Only the documented spellings are accepted.
      const on = ["1", "true", "on", "yes"].indexOf(String(enabled).toLowerCase()) !== -1;
      const off = ["0", "false", "off", "no"].indexOf(String(enabled).toLowerCase()) !== -1;
      if (!on && !off) {
        Logger.w("HeadsetControl", "ipc voicePrompts: not a boolean:", enabled);
        return;
      }
      root.applyVoicePrompts(on);
    }

    function inactiveTime(minutes: string): void {
      const v = parseInt(minutes);
      if (isNaN(v)) {
        Logger.w("HeadsetControl", "ipc inactiveTime: not a number:", minutes);
        return;
      }
      root.applyInactiveTime(v);
    }
  }
}
