import QtQuick
import QtQuick.Effects

Item {
  id: root

  property real iconSize: 16
  property color color: "white"

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Keep the downloaded mark only as an alpha mask. Coloring an opaque black
  // source leaves it black; masking a theme-colored texture is deterministic.
  Image {
    id: maskImage
    anchors.fill: parent
    source: Qt.resolvedUrl("anki.svg")
    fillMode: Image.PreserveAspectFit
    visible: false
    layer.enabled: true
  }

  Rectangle {
    id: colorLayer
    anchors.fill: parent
    color: root.color
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: colorLayer
    source: colorLayer
    maskEnabled: true
    maskSource: maskImage
    maskThresholdMin: 0.5
  }
}
