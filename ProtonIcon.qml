import QtQuick
import qs.Commons

// Native rendering of the Proton VPN mark (the "sign" banner) as a single
// canvas path, theme-colored. The path data comes from the official
// proton-vpn-sign.svg; drawing it ourselves keeps it crisp at tiny bar sizes
// and lets the theme own the color. The banner points up-right; a diagonal
// strike-through reads "off" the way the tailscale widget marks disconnection.
Item {
  id: root

  property real iconSize: 24
  property color color: "#cacccc"
  property color badgeColor: "#a55555"
  property bool crossed: false
  property bool warning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Path bounds from proton-vpn-sign.svg, computed across its cubic
  // segments: x 12.2..41.8, y 12.3..39.2 (viewBox-independent, so the
  // whole banner fits without cropping).
  readonly property real pathMinX: 12.2
  readonly property real pathMinY: 12.3
  readonly property real pathW: 29.6
  readonly property real pathH: 26.9

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var sx = root.iconSize / root.pathW
      var sy = sx
      var offX = 0
      var offY = (root.iconSize - root.pathH * sx) / 2
      ctx.translate(offX, offY)
      ctx.scale(sx, sy)
      ctx.translate(-root.pathMinX, -root.pathMinY)

      ctx.beginPath()
      ctx.moveTo(22.2, 35.5)
      ctx.bezierCurveTo(23.1, 37.2, 26.4, 39.0, 30.8, 39.2)
      ctx.lineTo(40.7, 24.1)
      ctx.bezierCurveTo(41.8, 22.5, 41.8, 18.7, 39.9, 14.7)
      ctx.lineTo(20.4, 12.5)
      ctx.bezierCurveTo(18.3, 12.3, 14.7, 14.3, 12.2, 18.1)
      ctx.closePath()
      ctx.fillStyle = root.color
      ctx.fill()
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.22
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  Rectangle {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
