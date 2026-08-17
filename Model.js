// Proton VPN CLI output parsing helpers.

.pragma library

// Last transition that has already produced a desktop notification. The bar
// mounts one Service per monitor, and every instance polls the same CLI;
// deduping here keeps a connect/disconnect from notifying once per monitor.
var _lastNotifiedTransition = { connected: false, at: 0 }
var _notifyDedupeWindowMs = 45000

function shouldNotifyTransition(connected, now) {
  if (_lastNotifiedTransition.connected === connected && now - _lastNotifiedTransition.at < _notifyDedupeWindowMs) return false
  _lastNotifiedTransition.connected = connected
  _lastNotifiedTransition.at = now
  return true
}

// Parses the official `protonvpn status` output:
//
//   Status: Connected
//   Server: US-FREE#38 in New York, US
//   Load: 42%
//   Protocol: wireguard
function parseCliStatus(text) {
  var result = {
    connected: false,
    serverName: "",
    serverCity: "",
    serverCountry: "",
    load: "",
    protocol: ""
  }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    var status = line.match(/^status\s*:\s*(.+)$/i)
    if (status) {
      result.connected = /^connected$/i.test(status[1].trim())
      continue
    }
    var server = line.match(/^server\s*:\s*(.+?)\s+in\s+(.+)$/i)
    if (server) {
      result.serverName = server[1].trim()
      var location = server[2].trim().split(/\s*,\s*/)
      result.serverCountry = location.length > 1 ? location[location.length - 1] : ""
      result.serverCity = location.length > 1 ? location.slice(0, -1).join(", ") : location[0]
      continue
    }
    var load = line.match(/^load\s*:\s*(.+)$/i)
    if (load) {
      result.load = load[1].trim()
      continue
    }
    var protocol = line.match(/^protocol\s*:\s*(.+)$/i)
    if (protocol) result.protocol = protocol[1].trim()
  }
  return result
}

// `nmcli -g IP4.ADDRESS dev show <device>` may print several addresses.
function parseDeviceIp(text) {
  var s = String(text || "").trim()
  var ipv4 = s.match(/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/)
  return ipv4 ? ipv4[1] : ""
}

// Parses `nmcli -t -f DEVICE,TYPE,STATE dev status` and returns the active
// WireGuard device used by the CLI. The app commonly names it proton0, but
// the device name is intentionally discovered instead of hard-coded.
function parseWireguardDevice(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(":")
    if (parts.length >= 3 && parts[1] === "wireguard" && /connected/.test(parts[2])) return parts[0]
  }
  return ""
}

function serverLabel(serverName, serverCity, serverCountry, fallback) {
  var parts = []
  if (serverName) parts.push(serverName)
  if (serverCity) parts.push(serverCity)
  if (serverCountry && serverCountry !== serverCity) parts.push(serverCountry)
  if (parts.length === 0 && fallback) parts.push(fallback)
  return parts.join(" \u00b7 ")
}

function parseCountriesOutput(text) {
  var names = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*(.+?)\s{2,}([A-Z]{2})\s*$/)
    if (match && match[2] !== "CO") names[match[2]] = match[1].trim()
  }
  return names
}

// Projects Proton's cached logical server list into a compact country list.
// Tier 0 is Proton's Free tier; offline logical servers are omitted.
function freeCountryRows(raw, countryNames) {
  var result = {}
  try {
    var logicals = JSON.parse(String(raw || "")).LogicalServers || []
    for (var i = 0; i < logicals.length; i++) {
      var server = logicals[i]
      if (!server || Number(server.Tier) !== 0 || Number(server.Status) !== 1) continue
      var code = String(server.ExitCountry || "").toUpperCase()
      if (!code) continue
      if (!result[code]) {
        result[code] = {
          code: code,
          name: countryNames && countryNames[code] ? countryNames[code] : code,
          count: 0,
          bestLoad: Number(server.Load)
        }
      }
      result[code].count += 1
      var load = Number(server.Load)
      if (isFinite(load) && load < result[code].bestLoad) result[code].bestLoad = load
    }
  } catch (e) {
    return []
  }
  var rows = []
  for (var code in result) {
    var row = result[code]
    row.hint = row.count + " server" + (row.count === 1 ? "" : "s") + " \u00b7 " + row.bestLoad + "% best load"
    rows.push(row)
  }
  rows.sort(function(a, b) {
    if (a.bestLoad !== b.bestLoad) return a.bestLoad - b.bestLoad
    return a.name.localeCompare(b.name)
  })
  return rows
}

function elideStatus(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > 140 ? value.substring(0, 137) + "\u2026" : value
}
