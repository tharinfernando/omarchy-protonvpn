import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Proton VPN details panel: hero with connection state + on/off switch,
// tunnel info rows, and quick actions. Keyboard-cursor navigable like the
// other bar panels (j/k move, enter activates, t toggles, esc closes).
Panel {
  id: root
  moduleName: "tharin.protonvpn"
  ipcTarget: "tharin.protonvpn"
  manageIpc: false // BarWidget.qml owns the single IpcHandler this target permits

  property var service: null
  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so the popout coordinator compares against the host widget.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  readonly property bool hasError: service && service.lastError !== ""
  readonly property string heroMeta: service ? (service.connected ? "Connected" : "Disconnected") : "Proton VPN"
  readonly property bool vpnOn: service && service.connected
  readonly property string statusText: {
    if (!service) return ""
    if (service.actionStatus !== "") return service.actionStatus
    if (service.busy) return "Working\u2026"
    return ""
  }
  readonly property string serverLabel: service
    ? Model.serverLabel(service.serverName, service.serverCity, service.serverCountry, "")
    : ""

  // ---- cursor model ------------------------------------------------------

  property string focusSection: "header"
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool freeServersExpanded: false

  readonly property bool headerHasCursor: cursorActive && focusSection === "header"

  function buildRows() {
    var info = []
    var countries = []
    var actions = []
    if (serverLabel !== "") info.push({ action: "copyServer", label: "Server", hint: serverLabel })
    if (service && service.tunnelIp !== "") info.push({ action: "copyIp", label: "Tunnel IP", hint: service.tunnelIp })
    if (service && service.protocol !== "") info.push({ action: "none", label: "Protocol", hint: service.protocol })
    if (service && service.serverLoad !== "") info.push({ action: "none", label: "Server load", hint: service.serverLoad })
    if (service && service.connectedUptime !== "") info.push({ action: "none", label: "Connected for", hint: service.connectedUptime })
    if (service && service.freeCountries) {
      for (var i = 0; i < service.freeCountries.length; i++) {
        var country = service.freeCountries[i]
        countries.push({ action: "connectCountry", value: country.code, label: country.name, hint: country.hint })
      }
    }
    actions.push({ action: "refresh", label: "Refresh", hint: "" })
    return { info: info, countries: countries, actions: actions }
  }

  readonly property var infoRows: buildRows().info
  readonly property var countryRows: buildRows().countries
  readonly property var actionRows: buildRows().actions
  readonly property int visibleCountryCount: root.freeServersExpanded ? countryRows.length : 0
  readonly property var cursorRows: {
    var rows = []
    for (var c = 0; c < root.visibleCountryCount; c++) rows.push(countryRows[c])
    for (var i = 0; i < infoRows.length; i++) rows.push(infoRows[i])
    for (var j = 0; j < actionRows.length; j++) rows.push(actionRows[j])
    return rows
  }
  readonly property int cursorRowCount: cursorRows.length

  function rowSelected(rowIndex) {
    return cursorActive && focusSection === "rows" && selectedIndex === rowIndex
  }

  function focusHeader() {
    cursorActive = true
    focusSection = "header"
    selectedIndex = 0
  }

  function moveCursor(delta) {
    if (!cursorActive) { cursorActive = true; return }
    if (focusSection === "header") {
      if (delta > 0 && cursorRowCount > 0) {
        focusSection = "rows"
        selectedIndex = 0
      }
      return
    }
    if (cursorRowCount === 0) { focusSection = "header"; return }
    var idx = selectedIndex + (delta > 0 ? 1 : -1)
    if (idx < 0) { focusSection = "header"; selectedIndex = 0; return }
    if (idx >= cursorRowCount) { selectedIndex = cursorRowCount - 1; return }
    selectedIndex = idx
  }

  function activateCursor() {
    if (!cursorActive) return
    if (focusSection === "header") {
      if (service) service.toggle()
      return
    }
    var row = cursorRows[selectedIndex]
    if (row) runAction(row.action, row.value)
  }

  function runAction(action, value) {
    if (!service) return
    if (action === "refresh") { service.refresh(); service.refreshServerList() }
    else if (action === "copyIp") service.copyText(service.tunnelIp)
    else if (action === "copyServer") service.copyText(serverLabel)
    else if (action === "connectCountry") service.connectCountry(value)
  }

  function toggleFreeServers() {
    freeServersExpanded = !freeServersExpanded
  }

  onFreeServersExpandedChanged: {
    if (focusSection === "rows" && selectedIndex >= cursorRowCount)
      selectedIndex = Math.max(0, cursorRowCount - 1)
  }

  onOpenedChanged: {
    if (opened) {
      focusSection = "header"
      selectedIndex = 0
      cursorActive = false
      freeServersExpanded = false
      if (service) service.refreshServerList()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") { if (root.service) root.service.toggle() }
        else if (t === "c" || t === "C") { if (root.service) root.service.copyText(root.service.tunnelIp) }
        else if (t === "s" || t === "S") root.toggleFreeServers()
        else if (t === "r" || t === "R") {
          if (root.service) { root.service.refresh(); root.service.refreshServerList() }
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.focusHeader() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Proton VPN"
              meta: root.heroMeta
              detail: root.vpnOn && root.service && root.service.serverName ? root.service.serverName : ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.vpnOn ? 1.0 : 0.5
              iconComponent: Component {
                ProtonIcon {
                  iconSize: Style.font.display
                  color: root.vpnOn ? root.foreground : root.dim
                  badgeColor: root.urgent
                  crossed: !root.vpnOn
                  warning: root.hasError
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  checked: root.vpnOn
                  busy: root.service ? root.service.busy : false
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: { if (root.service) root.service.toggle() }
                }
              }
            }
          }

          Text {
            id: statusLine
            width: parent.width
            visible: root.statusText !== ""
            text: root.statusText
            color: root.hasError ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(2)

            visible: root.countryRows.length > 0

            Item {
              id: freeHeader
              width: parent.width
              implicitHeight: Math.max(freeChevron.implicitHeight, freeLabel.implicitHeight, freeCount.implicitHeight) + Style.space(4)

              Text {
                id: freeChevron
                anchors.left: parent.left
                anchors.leftMargin: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter
                text: root.freeServersExpanded ? "\u25be" : "\u25b8"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                id: freeLabel
                anchors.left: freeChevron.right
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: "SERVERS LIST"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                topPadding: Math.ceil(Style.font.caption * 0.15)
              }

              Text {
                id: freeCount
                anchors.right: parent.right
                anchors.rightMargin: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter
                text: root.countryRows.length + " countries"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                id: freeHeaderMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleFreeServers()
              }
            }

            Repeater {
              model: root.freeServersExpanded ? root.countryRows : []

              delegate: Item {
                required property var modelData
                required property int index
                width: parent.width
                height: cursorRow.implicitHeight

                CursorRow {
                  id: cursorRow
                  width: parent.width
                  label: modelData.label
                  hint: modelData.hint
                  rowIndex: index
                  actionName: modelData.action
                  actionValue: modelData.value
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: root.infoRows.length > 0
            PanelSectionHeader {
              text: "TUNNEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.infoRows

              delegate: Item {
                required property var modelData
                required property int index
                width: parent.width
                height: cursorRow.implicitHeight

                CursorRow {
                  id: cursorRow
                  width: parent.width
                  label: modelData.label
                  hint: modelData.hint
                  rowIndex: root.visibleCountryCount + index
                  actionName: modelData.action
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(2)

            PanelSectionHeader {
              text: "ACTIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.actionRows

              delegate: Item {
                required property var modelData
                required property int index
                width: parent.width
                height: cursorRow.implicitHeight

                CursorRow {
                  id: cursorRow
                  width: parent.width
                  label: modelData.label
                  hint: modelData.hint
                  rowIndex: root.visibleCountryCount + root.infoRows.length + index
                  actionName: modelData.action
                  actionValue: modelData.value
                }
              }
            }
          }
        }
      }
    }
  }

  component CursorRow: CursorSurface {
    id: row
    required property string label
    required property string hint
    required property int rowIndex
    required property string actionName
    property var actionValue: undefined

    readonly property bool rowSelected: root.rowSelected(rowIndex)

    hasCursor: rowSelected
    foreground: root.foreground
    accent: Color.accent
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: Math.max(Style.spacing.popupRowHeight + Style.space(8), rowContent.implicitHeight + Style.spacing.rowPaddingX)

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "rows"
        root.selectedIndex = row.rowIndex
      }
      onClicked: root.runAction(row.actionName, row.actionValue)
    }

    Row {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Text {
        id: rowLabel
        text: row.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Item {
        width: Math.max(1, rowContent.width - rowLabel.implicitWidth - (rowHint.visible ? rowHint.implicitWidth + rowContent.spacing : 0) - rowContent.spacing)
        height: 1
      }

      Text {
        id: rowHint
        visible: row.hint !== ""
        text: row.hint
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
      }
    }
  }
}
