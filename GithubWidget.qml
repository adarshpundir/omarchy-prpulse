import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "prpulse.bar"

  // --- settings ------------------------------------------------------------
  readonly property string tokenFile: expandTilde(setting("tokenFile", "~/.config/omarchy/github.token"))
  readonly property bool hideWhenZero: setting("hideWhenZero", true)
  readonly property string webUrl: setting("webUrl", "https://github.com/pulls")
  readonly property bool showReviews: setting("showReviews", true)
  readonly property bool showCi: setting("showCi", true)

  // --- state ---------------------------------------------------------------
  property int reviews: 0
  property int failing: 0
  property string lastError: ""
  property bool checked: false

  readonly property int attention: (showReviews ? reviews : 0) + (showCi ? failing : 0)
  readonly property bool configured: true
  readonly property bool hasError: lastError !== ""

  visible: hasError || attention > 0 || (!hideWhenZero && checked)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color foreground: bar ? bar.foreground : Color.foreground

  readonly property string tooltipText: {
    if (hasError) return "GitHub error: " + lastError
    if (!checked) return "Checking GitHub..."
    var parts = []
    if (showReviews) parts.push(reviews + " PR" + (reviews === 1 ? "" : "s") + " awaiting review")
    if (showCi) parts.push(failing + " CI failure" + (failing === 1 ? "" : "s"))
    var summary = parts.length > 0 ? parts.join(" · ") : "Nothing needs attention"
    return "GitHub — " + summary + " · right click to refresh"
  }

  function expandTilde(path) {
    var home = Quickshell.env("HOME")
    if (path === "~") return home
    if (path.indexOf("~/") === 0) return home + path.substring(1)
    return path
  }

  function refresh() {
    if (!checkProc.running) checkProc.running = true
  }

  function openGithub() {
    if (root.bar && webUrl !== "") root.bar.run("xdg-open \"" + webUrl + "\"")
  }

  IpcHandler {
    target: "prpulse.bar"

    function refresh(): void { root.broadcast("refresh") }
  }

  Process {
    id: checkProc
    command: [Qt.resolvedUrl("check.sh").toString().replace("file://", ""), root.tokenFile]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = text.trim().split(/\s+/)
        if (parts.length >= 2) {
          root.reviews = parseInt(parts[0], 10) || 0
          root.failing = parseInt(parts[1], 10) || 0
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = text.trim()
        if (message !== "") root.lastError = message.split("\n")[0]
      }
    }
    onExited: function(exitCode) {
      root.checked = true
      if (exitCode === 0) root.lastError = ""
    }
  }

  Timer {
    interval: Math.max(60, setting("pollIntervalSec", 300)) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf09b"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    active: root.hasError || root.failing > 0
    dimmed: !root.hasError && root.checked && root.attention === 0
    tooltipText: root.tooltipText

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.openGithub()
      else root.refresh()
    }

    Text {
      visible: root.attention > 0
      anchors.right: parent.right
      anchors.rightMargin: Style.space(1)
      anchors.top: parent.top
      anchors.topMargin: Style.space(3)
      text: root.attention > 99 ? "99+" : String(root.attention)
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
