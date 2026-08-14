import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Proton VPN bar widget entry point. Owns the data source (Service) and the
// bar button; the details panel loads via Loader, matching the clock
// plugin's bar-widget contract so shell summon/hide/toggle routes work.
BarWidget {
  id: root
  moduleName: "tharin.protonvpn"

  Service {
    id: vpn
    settings: root.settings
  }

  readonly property bool vpnConnected: vpn.connected
  readonly property bool vpnBusy: vpn.busy
  readonly property bool vpnWarning: vpn.lastError !== ""

  // ---- Panel lifecycle, forwarded for shell.summon/hide/toggle routing.
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  function refresh() { vpn.refresh(true) }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("service" in target) target.service = vpn
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "tharin.protonvpn"

    function refresh() { root.refresh() }
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.togglePanel() }
    function status(): string { return vpn.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        ProtonIcon {
          anchors.centerIn: parent
          iconSize: Style.bar.iconCanvas
          color: root.vpnConnected ? button.foreground : Qt.darker(button.foreground, 1.55)
          crossed: !root.vpnConnected
          warning: root.vpnWarning
          badgeColor: root.bar ? root.bar.urgent : Color.urgent
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) vpn.toggle()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
