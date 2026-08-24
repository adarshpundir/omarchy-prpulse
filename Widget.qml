import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "prpulse.bar"

  // --- settings ------------------------------------------------------------
  readonly property string githubTokenFile: expandTilde(setting("tokenFile", "~/.config/omarchy/github.token"))
  readonly property string forgesCsv: setting("forges", "github")
  readonly property string secretsDir: expandTilde(setting("secretsDir", "~/.config/omarchy/prpulse"))
  readonly property string gitlabHost: setting("gitlabHost", "https://gitlab.com")
  readonly property string gitlabUser: setting("gitlabUser", "")
  readonly property string webUrl: setting("webUrl", "https://github.com/pulls")
  readonly property bool hideWhenZero: asBool(setting("hideWhenZero", true))
  readonly property bool showReviews: asBool(setting("showReviews", true))
  readonly property bool showCi: asBool(setting("showCi", true))

  function asBool(value) {
    if (value === true) return true
    if (value === false) return false
    if (typeof value === "string") return value.trim().toLowerCase() === "true"
    return Boolean(value)
  }

  // --- state ---------------------------------------------------------------
  property int reviews: 0
  property int failing: 0
  property var perForge: ({})
  property bool allFailed: false
  property bool checked: false

  readonly property int attention: (showReviews ? reviews : 0) + (showCi ? failing : 0)

  visible: allFailed || attention > 0 || (!hideWhenZero && checked)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color foreground: bar ? bar.foreground : Color.foreground

  readonly property var forgeLabels: ({ github: "GH", gitlab: "GL", bitbucket: "BB" })

  readonly property string tooltipText: {
    if (!checked) return "PR Pulse is checking..."
    var parts = []
    var problems = []
    for (var i = 0; i < forgeOrder.length; i++) {
      var forge = forgeOrder[i]
      var entry = perForge[forge]
      if (!entry) continue
      var label = forgeLabels[forge] || forge
      if (entry.error !== undefined && entry.error !== "") {
        problems.push(label + ": " + entry.error)
      } else {
        var bits = []
        if (showReviews) bits.push(entry.reviews + "R")
        if (showCi) bits.push(entry.failing + "F")
        parts.push(label + " " + bits.join("+"))
      }
    }
    if (problems.length > 0) parts = parts.concat(problems)
    return parts.length === 0 ? "Nothing configured" : parts.join(" · ")
  }
  readonly property var forgeOrder: {
    var out = []
    var list = forgesCsv.split(",")
    for (var i = 0; i < list.length; i++) {
      var name = list[i].trim()
      if (name !== "") out.push(name)
    }
    return out
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

  function openForge() {
    if (root.bar && webUrl !== "") root.bar.run("xdg-open \"" + webUrl + "\"")
  }

  IpcHandler {
    target: "prpulse.bar"

    function refresh(): void { root.broadcast("refresh") }
  }

  Process {
    id: checkProc
    command: [Qt.resolvedUrl("check.sh").toString().replace("file://", ""),
              root.githubTokenFile, root.forgesCsv, root.secretsDir,
              root.gitlabHost, root.gitlabUser]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = text.trim()
        if (raw === "") return
        try {
          var data = JSON.parse(raw)
          root.reviews = data.total.reviews
          root.failing = data.total.failing
          root.perForge = data.forges
        } catch (e) {
          root.allFailed = true
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: { /* per-forge errors arrive via stdout JSON */ }
    }
    onExited: function(exitCode) {
      root.checked = true
      root.allFailed = exitCode === 3
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
    active: root.allFailed || root.failing > 0
    dimmed: !root.allFailed && root.checked && root.attention === 0
    tooltipText: root.tooltipText

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.openForge()
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
