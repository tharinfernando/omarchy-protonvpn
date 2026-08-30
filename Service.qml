import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Uses Proton's official CLI as the connection owner. The CLI performs live
// server selection, DNS setup, NetworkManager integration, and firewall
// handling; this plugin only presents that state in the Omarchy bar.
Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool connected: false
  property string tunnelIp: ""
  property string tunnelDevice: ""
  property string rxRate: ""
  property string txRate: ""
  property string serverName: ""
  property string serverCity: ""
  property string serverCountry: ""
  property string serverLoad: ""
  property string protocol: ""
  property string backendState: "Unknown"
  property string statusText: "Checking\u2026"
  property string connectedUptime: ""
  property var connectedSince: 0
  property string actionStatus: ""
  property string lastError: ""
  property var freeCountries: []
  property bool refreshing: false
  property bool toggling: false

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool notificationsEnabled: boolSetting("notificationsEnabled", true)
  // Optimistic switch state: -1 follows the real `connected`, 0/1 is the
  // desired state set the instant a toggle is clicked. The panel switch binds
  // to this so its knob throws immediately instead of waiting for the next
  // status poll, then reconciles with reality in applyStatus.
  readonly property bool switchOn: _desiredConnected === -1 ? connected : (_desiredConnected === 1)
  readonly property bool busy: statusProcess.running || deviceProcess.running || deviceIpProcess.running || toggleProcess.running || whichProcess.running
  readonly property string serverListPath: (Quickshell.env("HOME") || "") + "/.cache/Proton/VPN/serverlist.json"

  property string _statusOutput: ""
  property string _statusError: ""
  property string _deviceOutput: ""
  property string _deviceIpOutput: ""
  property string _toggleOutput: ""
  property string _toggleError: ""
  property string _countryOutput: ""
  property var _countryNames: ({})
  property string _serverListText: ""
  property bool _stateKnown: false
  property bool _lastConnected: false
  property var _netBytes: null
  property var _netSampleAt: 0
  property string _netDevOutput: ""
  property int _desiredConnected: -1

  function intSetting(name, fallback, min, max) {
    var v = parseInt(settings ? settings[name] : undefined, 10)
    if (isNaN(v)) return fallback
    return Math.max(min, Math.min(max, v))
  }

  function boolSetting(name, fallback) {
    if (!settings || settings[name] === undefined || settings[name] === null) return fallback
    var v = String(settings[name]).toLowerCase()
    if (v === "true" || v === "1" || v === "on" || v === "yes") return true
    if (v === "false" || v === "0" || v === "off" || v === "no") return false
    return fallback
  }

  // Fires a desktop notification through the shell's notification daemon via
  // notify-send, so do-not-disturb and popup styling are handled centrally.
  function notify(summary, body, critical) {
    if (!notificationsEnabled) return
    var args = ["notify-send", "--app-name=Proton VPN", "--urgency=" + (critical ? "critical" : "normal")]
    args.push(String(summary || ""))
    if (body !== "") args.push(String(body))
    Quickshell.execDetached(args)
  }

  function refresh() {
    if (!installed) {
      if (!whichProcess.running) {
        whichProcess.command = ["which", "protonvpn"]
        whichProcess.running = true
      }
      return
    }
    if (!statusProcess.running) {
      refreshing = true
      _statusOutput = ""
      _statusError = ""
      statusProcess.command = ["protonvpn", "status"]
      statusProcess.running = true
    }
    if (connected) refreshDevice()
  }

  function refreshServerList() {
    if (!countryProcess.running) {
      _countryOutput = ""
      countryProcess.command = ["protonvpn", "countries", "list"]
      countryProcess.running = true
    }
    serverListFile.reload()
  }

  function applyServerList() {
    freeCountries = Model.freeCountryRows(_serverListText, _countryNames)
  }

  function connectCountry(code) {
    if (toggling || !code) return
    toggling = true
    lastError = ""
    actionStatus = "Connecting to fastest " + code + " server\u2026"
    toggleProcess.command = ["protonvpn", "connect", "--country", String(code)]
    toggleProcess.running = true
  }

  function refreshDevice() {
    if (!deviceProcess.running) {
      deviceProcess.command = ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "dev", "status"]
      deviceProcess.running = true
    }
  }

  function applyStatus(stdout) {
    var parsed = Model.parseCliStatus(stdout)
    var prevConnected = root._lastConnected
    connected = parsed.connected
    // Once the real state matches the optimistic value, drop back to tracking
    // reality so the knob always reflects the true connection.
    if (_desiredConnected !== -1 && connected === (_desiredConnected === 1)) _desiredConnected = -1
    serverName = parsed.serverName
    serverCity = parsed.serverCity
    serverCountry = parsed.serverCountry
    serverLoad = parsed.load
    protocol = parsed.protocol
    refreshing = false
    backendState = connected ? "Connected" : "Disconnected"
    statusText = connected ? "Connected" : "Disconnected"
    if (connected) {
      refreshDevice()
      if (!prevConnected && _stateKnown) connectedSince = Date.now()
    } else {
      tunnelIp = ""
      connectedSince = 0
    }
    connectedUptime = connected ? formatUptime() : ""
    _lastConnected = connected
    if (_stateKnown && prevConnected !== connected) {
      if (connected && Model.shouldNotifyTransition(true, Date.now())) {
        notify("Proton VPN connected", "Connected to " + Model.serverLabel(parsed.serverName, parsed.serverCity, parsed.serverCountry, ""), false)
      } else if (!connected && Model.shouldNotifyTransition(false, Date.now())) {
        notify("Proton VPN disconnected", "", false)
      }
    }
    _stateKnown = true
  }

  function applyDeviceList(stdout) {
    var device = Model.parseWireguardDevice(stdout)
    if (!device) {
      tunnelIp = ""
      tunnelDevice = ""
      rxRate = ""
      txRate = ""
      return
    }
    tunnelDevice = device
    deviceIpProcess.command = ["nmcli", "-g", "IP4.ADDRESS", "dev", "show", device]
    if (!deviceIpProcess.running) deviceIpProcess.running = true
  }

  function sampleTraffic() {
    if (!connected || !tunnelDevice || netProcess.running) return
    _netDevOutput = ""
    netProcess.command = ["cat", "/proc/net/dev"]
    netProcess.running = true
  }

  function applyNetDev(stdout) {
    var bytes = Model.parseNetDev(String(stdout), tunnelDevice)
    if (!bytes) return
    var now = Date.now()
    if (_netBytes) {
      var dt = Math.max(1, now - _netSampleAt) / 1000
      rxRate = Model.formatRate(Math.max(0, bytes.rx - _netBytes.rx), dt)
      txRate = Model.formatRate(Math.max(0, bytes.tx - _netBytes.tx), dt)
    }
    _netBytes = bytes
    _netSampleAt = now
  }

  function toggle() {
    if (toggling) return
    if (connected) disconnect()
    else connect()
  }

  function connect() {
    if (toggling || connected) return
    toggling = true
    lastError = ""
    _desiredConnected = 1
    actionStatus = "Connecting to fastest server\u2026"
    toggleProcess.command = ["protonvpn", "connect"]
    toggleProcess.running = true
  }

  function disconnect() {
    if (toggling || !connected) return
    toggling = true
    lastError = ""
    _desiredConnected = 0
    actionStatus = "Disconnecting\u2026"
    toggleProcess.command = ["protonvpn", "disconnect"]
    toggleProcess.running = true
  }

  function copyText(text) {
    if (text === "") return
    Quickshell.execDetached(["sh", "-c", "printf '%s' '" + String(text).replace(/'/g, "'\\''") + "' | wl-copy"])
    actionStatus = "Copied " + text
    actionStatusTimer.restart()
  }

  // Formats the elapsed wall-clock time of the current session uptime.
  function formatUptime() {
    if (!connectedSince) return ""
    return Model.formatUptime(Date.now() - connectedSince)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2600
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: uptimeTimer
    interval: 1000
    repeat: true
    running: root.connected
    onTriggered: root.connectedUptime = root.formatUptime()
  }

  Timer {
    id: trafficTimer
    interval: 1500
    repeat: true
    running: root.connected && root.tunnelDevice !== ""
    triggeredOnStart: true
    onTriggered: root.sampleTraffic()
  }

  Timer {
    id: pollWatchdog
    interval: 30000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (deviceProcess.running) deviceProcess.running = false
      if (deviceIpProcess.running) deviceIpProcess.running = false
      if (toggleProcess.running) toggleProcess.running = false
      root.refreshing = false
      root.toggling = false
    }
  }

  Process {
    id: whichProcess
    command: []
    onExited: function(exitCode) {
      installed = exitCode === 0
      if (installed) root.refresh()
      else {
        root.backendState = "Unavailable"
        root.statusText = "Proton CLI not found"
      }
    }
  }

  Process {
    id: countryProcess
    command: []
    stdout: StdioCollector { id: countryStdout; waitForEnd: true; onStreamFinished: root._countryOutput = text }
    onExited: function(exitCode) {
      if (exitCode === 0) root._countryNames = Model.parseCountriesOutput(String(countryStdout.text || root._countryOutput || ""))
      root.applyServerList()
    }
  }

  Process {
    id: statusProcess
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else {
        var wasConnected = root._lastConnected
        root.refreshing = false
        root.connected = false
        root._desiredConnected = -1
        root._lastConnected = false
        root.backendState = "Unavailable"
        root.statusText = "CLI status failed"
        root.lastError = Model.elideStatus(stderr || stdout || "Could not read Proton VPN status")
        if (root._stateKnown && wasConnected) {
          root.notify("Proton VPN connection lost", root.lastError, true)
        }
        root._stateKnown = true
      }
    }
  }

  Process {
    id: deviceProcess
    command: []
    stdout: StdioCollector { id: deviceStdout; waitForEnd: true; onStreamFinished: root._deviceOutput = text }
    onExited: function(exitCode) {
      var stdout = String(deviceStdout.text || root._deviceOutput || "")
      if (exitCode === 0) root.applyDeviceList(stdout)
    }
  }

  Process {
    id: deviceIpProcess
    command: []
    stdout: StdioCollector { id: deviceIpStdout; waitForEnd: true; onStreamFinished: root._deviceIpOutput = text }
    onExited: function() {
      root.tunnelIp = Model.parseDeviceIp(String(deviceIpStdout.text || root._deviceIpOutput || ""))
    }
  }

  Process {
    id: netProcess
    command: []
    stdout: StdioCollector { id: netStdout; waitForEnd: true; onStreamFinished: root._netDevOutput = text }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyNetDev(String(netStdout.text || root._netDevOutput || ""))
    }
  }

  Process {
    id: toggleProcess
    command: []
    stdout: StdioCollector { id: toggleStdout; waitForEnd: true; onStreamFinished: root._toggleOutput = text }
    stderr: StdioCollector { id: toggleStderr; waitForEnd: true; onStreamFinished: root._toggleError = text }
    onExited: function(exitCode) {
      root.toggling = false
      var stdout = String(toggleStdout.text || root._toggleOutput || "")
      var stderr = String(toggleStderr.text || root._toggleError || "")
      if (exitCode === 0) {
        root.lastError = ""
        root.actionStatus = ""
      } else {
        root.lastError = Model.elideStatus(stderr || stdout || "Proton VPN command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
        root.notify("Proton VPN action failed", root.lastError, true)
        // The toggle failed — drop any optimistic state so the switch snaps
        // back to the real connection state.
        root._desiredConnected = -1
      }
      delayedRefresh.restart()
    }
  }

  FileView {
    id: serverListFile
    path: root.serverListPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root._serverListText = text()
      root.applyServerList()
    }
    onFileChanged: reload()
  }
}
