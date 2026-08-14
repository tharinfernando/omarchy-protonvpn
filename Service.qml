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
  property string serverName: ""
  property string serverCity: ""
  property string serverCountry: ""
  property string serverLoad: ""
  property string protocol: ""
  property string backendState: "Unknown"
  property string statusText: "Checking\u2026"
  property string actionStatus: ""
  property string lastError: ""
  property var freeCountries: []
  property bool refreshing: false
  property bool toggling: false

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
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

  function intSetting(name, fallback, min, max) {
    var v = parseInt(settings ? settings[name] : undefined, 10)
    if (isNaN(v)) return fallback
    return Math.max(min, Math.min(max, v))
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
    connected = parsed.connected
    serverName = parsed.serverName
    serverCity = parsed.serverCity
    serverCountry = parsed.serverCountry
    serverLoad = parsed.load
    protocol = parsed.protocol
    refreshing = false
    backendState = connected ? "Connected" : "Disconnected"
    statusText = connected ? "Connected" : "Disconnected"
    if (connected) refreshDevice()
    else tunnelIp = ""
  }

  function applyDeviceList(stdout) {
    var device = Model.parseWireguardDevice(stdout)
    if (!device) {
      tunnelIp = ""
      return
    }
    deviceIpProcess.command = ["nmcli", "-g", "IP4.ADDRESS", "dev", "show", device]
    if (!deviceIpProcess.running) deviceIpProcess.running = true
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
    actionStatus = "Connecting to fastest server\u2026"
    toggleProcess.command = ["protonvpn", "connect"]
    toggleProcess.running = true
  }

  function disconnect() {
    if (toggling || !connected) return
    toggling = true
    lastError = ""
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
        root.refreshing = false
        root.connected = false
        root.backendState = "Unavailable"
        root.statusText = "CLI status failed"
        root.lastError = Model.elideStatus(stderr || stdout || "Could not read Proton VPN status")
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
