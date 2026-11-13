import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "dartc.poker"
  ipcTarget: "dartc.poker"
  manageIpc: false

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color fainter: Qt.darker(fg, 2.1)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color accent: Commons.Color.accent
  readonly property string userName: (Quickshell.env("USER") || "Bạn")

  property var game: Model.newGame()
  property int revision: 0
  property bool aiThinking: false
  property bool showResult: false
  property string resultTitle: ""
  property string resultSub: ""
  property int resultWinner: -1

  // action effects
  property var fx: null
  property int fxSeen: 0
  property var chipBursts: []
  property int prevPChips: -1
  property int prevAChips: -1
  property int pDelta: 0
  property int aDelta: 0
  property bool chipFlash: false
  property int prevPot: -1
  property real potPulse: 1.0
  // roulette suspense
  property bool rouletteSpinning: false
  property int rouletteHighlight: 0
  property int rouletteSpinTick: 0
  property bool rouletteReveal: false

  // intro / scores / victory flow
  property var topScores: []
  property real introPulse: 0
  property bool victoryReady: false

  // persistence (game state + AI level)
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: root.home + "/.local/state/dartc.poker"
  readonly property string statePath: root.stateDir + "/state.json"
  readonly property string scoresPath: root.stateDir + "/scores.json"
  // Older builds kept scores inside the plugin folder. It is copied into the
  // state dir (and removed from the checkout) on startup so git updates stay clean.
  readonly property string legacyScoresPath: root.home + "/.config/omarchy/plugins/dartc.poker/scores.json"
  property bool stateLoaded: false

  function loadScores() {
    try {
      var raw = scoresFile.text()
      if (!raw) { topScores = []; return }
      var arr = JSON.parse(raw)
      if (arr && arr.length !== undefined) topScores = arr
      else topScores = []
    } catch(e) { topScores = [] }
  }

  function saveScores() {
    try {
      scoresFile.setText(JSON.stringify(topScores || []))
    } catch(e) {}
  }

  function recordScore(chips) {
    var c = chips || 0
    if (c <= 0) return
    var arr = (topScores || []).slice()
    arr.push({ name: root.userName || "Bạn", chips: c })
    arr.sort(function(a,b){ return (b.chips||0) - (a.chips||0) })
    var uniq = []
    var seen = {}
    // keep top 3 unique by name+chips entries? just top 3 values
    for (var i=0; i<arr.length && uniq.length < 3; i++) uniq.push(arr[i])
    topScores = uniq
    saveScores()
  }

  // ------------------------------------------------------------- persistence

  function save() {
    if (!root.stateLoaded) return
    saveTimer.restart()
  }

  // Debounced: several refreshes in quick succession would otherwise write
  // the same hand over itself several times.
  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: root.writeState()
  }

  function writeState() {
    if (!root.stateLoaded) return
    saveTimer.stop()
    var stg = (root.game && root.game.stage) ? root.game.stage : ""
    var live = (stg === "preflop" || stg === "flop" || stg === "turn" || stg === "river" || stg === "showdown")
    var payload = JSON.stringify({
      version: 1,
      game: live ? root.game : null
    }, null, 2) + "\n"
    stateFile.setText(payload)
  }

  function applyState(raw) {
    var st = null
    try { st = JSON.parse(String(raw || "").trim()) } catch (e) {}
    if (st && st.game && typeof st.game === "object") {
      root.game = st.game
      root.refresh()
      root.maybeAi()
    } else {
      root.startGame()
    }
    root.stateLoaded = true
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: function(err) { root.applyState("") }
  }

  // Make sure the state dir exists, then (re)load the state file.
  Process {
    id: mkStateDir
    command: ["sh", "-c",
      "mkdir -p \"$1\" || exit 1; " +
      "if [ -f \"$2\" ]; then " +
      "if [ ! -f \"$3\" ]; then cp \"$2\" \"$3\" || exit 1; fi; " +
      "rm -f \"$2\"; fi",
      "sh", root.stateDir, root.legacyScoresPath, root.scoresPath]
    onExited: {
      stateFile.reload()
      scoresFile.reload()
    }
  }

  Component.onCompleted: mkStateDir.running = true

  function setAiLevel(lvl) {
    if (root.game && root.game.ai && typeof root.game.ai === "object") root.game.ai.level = lvl || 0
    root.save()
  }

  function startGame() {
    victoryReady = false
    game = Model.newGame()
    // newGame starts in intro in model now? we changed to intro, but for starting play we want a hand
    game = Model.startHand(game)
    if (game.players && game.players[0]) game.players[0].name = root.userName
    prevPChips = -1; prevAChips = -1; prevPot = -1
    pDelta = 0; aDelta = 0; chipFlash = false
    showResult = false; resultWinner = -1; resultTitle = ""; resultSub = ""
    rouletteSpinning = false; rouletteReveal = false; rouletteHighlight = 0
    refresh()
    maybeAi()
    
  }

  FileView {
    id: scoresFile
    path: root.scoresPath
    blockLoading: true
    printErrors: false
    onLoaded: root.loadScores()
  }

  SequentialAnimation on introPulse {
    running: root.game && root.game.stage === "intro"
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0; duration: 900; easing.type: Easing.InOutSine }
  }

  Timer {
    id: victoryDelayTimer
    interval: 4500
    repeat: false
    onTriggered: {
      if (root.game.stage === "dead_wait") {
        root.game = Model.claimVictory(root.game)
        root.victoryReady = true
        root.refresh()
      }
    }
  }

  function refresh() { 
    revision++
    var pc = (game.players[0] && game.players[0].chips) || 0
    var ac = (game.players[1] && game.players[1].chips) || 0
    if (prevPChips !== -1) pDelta = pc - prevPChips
    if (prevAChips !== -1) aDelta = ac - prevAChips
    if ((prevPChips !== -1 && pDelta !== 0) || (prevAChips !== -1 && aDelta !== 0)) { chipFlash = true; chipFlashTimer.restart() }
    prevPChips = pc; prevAChips = ac
    var potNow = game.pot || 0
    if (prevPot !== -1 && potNow > prevPot) potPulseAnim.restart()
    prevPot = potNow
    // action effects
    if (game.lastFx && game.lastFx.id !== fxSeen) {
      fxSeen = game.lastFx.id
      fx = game.lastFx
      if (game.lastFx.amount > 0) spawnChips(game.lastFx)
    }

    // persist live game state (debounced write)
    if (game) {
      var stg = game.stage
      if (stg === "preflop" || stg === "flop" || stg === "turn" || stg === "river" || stg === "showdown") root.save()
    }

    // roulette: AI auto-fire (spin), player waits for click
    if (game.stage === "roulette" && game.roulette && !game.roulette.done) {
      autoReset.stop()
      showResult = false
      if (!rouletteSpinning) rouletteReveal = false
      if (!rouletteSpinning && !rouletteReveal) {
        rouletteTimer.restart()
      }
      return
    }

    // intro
    if (game.stage === "intro") {
      rouletteTimer.stop(); rouletteSpinTimer.stop(); autoReset.stop(); victoryDelayTimer.stop()
      showResult = false
      victoryReady = false
      return
    }

    // dead_wait: AI chết, chờ rồi hiện thắng
    if (game.stage === "dead_wait") {
      rouletteTimer.stop(); rouletteSpinTimer.stop(); autoReset.stop()
      rouletteSpinning = false; rouletteReveal = true
      showResult = false
      if (!victoryDelayTimer.running) victoryDelayTimer.restart()
      return
    }

    // game over (final)
    if (game.stage === "gameover") {
      rouletteTimer.stop(); rouletteSpinTimer.stop(); autoReset.stop(); victoryDelayTimer.stop()
      rouletteSpinning = false; rouletteReveal = true
      if (!showResult) {
        showResult = true
        if (game.winner === (game.players[0] && game.players[0].name)) resultWinner = 0
        else if (game.winner === (game.players[1] && game.players[1].name)) resultWinner = 1
        else resultWinner = -1
        if (resultWinner === 0) { resultTitle = "🏆 CHIẾN THẮNG!"; resultSub = game.message || "Bạn đã thắng!" }
        else { resultTitle = "THẤT BẠI"; resultSub = game.message || "Kết thúc!" }
        // record score on final game over (best effort: player's chips)
        var pc2 = (game.players[0] && game.players[0].chips) || 0
        if (pc2 > 0) recordScore(pc2)
      }
      return
    }

    // handle showdown results (normal or survived roulette)
    if (game.stage === "showdown" && !showResult) {
      var survived = (game.roulette && game.roulette.done && !game.roulette.dead) || game.winner === "Sống sót"
      if (!survived) { rouletteReveal = false }
      showResult = true
      resultWinner = -1
      if (game.winner === (game.players[0] && game.players[0].name)) resultWinner = 0
      else if (game.winner === (game.players[1] && game.players[1].name)) resultWinner = 1
      else if (game.winner === "Hòa") resultWinner = -2
      if (survived) { resultTitle = "SỐNG SÓT!"; resultSub = game.message || "Tiếp tục chơi..." ; resultWinner = -3 }
      else if (resultWinner === 0) { resultTitle = "BẠN THẮNG!"; resultSub = (game.players[0] && game.players[0].handName) ? game.players[0].handName : (game.message || "") }
      else if (resultWinner === 1) { resultTitle = "AI THẮNG"; resultSub = (game.players[1] && game.players[1].handName) ? game.players[1].handName : (game.message || "") }
      else if (resultWinner === -2) { resultTitle = "HÒA"; resultSub = (game.players[0] && game.players[0].handName) ? game.players[0].handName : (game.message || "") }
      else { resultTitle = "KẾT THÚC"; resultSub = game.message || "" }
      if (!survived && resultWinner === 0) spawnWinChips(resultWinner)
      autoReset.restart()
      
    }
  }

  function startRouletteSpin() {
    if (game.stage !== "roulette" || !game.roulette || game.roulette.done) return
    if (rouletteSpinning) return
    rouletteTimer.stop()
    rouletteSpinning = true
    rouletteReveal = false
    rouletteSpinTick = 0
    rouletteHighlight = 1
    rouletteSpinTimer.interval = 70
    rouletteSpinTimer.restart()
  }

  function fireRoulette() {
    // called when spin/reveal sequence completes
    if (game.stage !== "roulette" || !game.roulette || game.roulette.done) {
      rouletteSpinning = false
      return
    }
    rouletteSpinTimer.stop()
    rouletteSpinning = false
    rouletteReveal = true
    game = Model.fireRoulette(game)
    refresh()
    
  }

  function spawnChips(fxData) {
    var amt = fxData.amount || 0
    var count = Math.max(2, Math.min(12, Math.round(amt / 10)))
    var arr = chipBursts.slice()
    var now = Date.now()
    for (var i = 0; i < count; i++) {
      arr.push({ id: now + "-" + i + "-" + Math.random(), who: fxData.who, t: i, win: false })
    }
    chipBursts = arr
    chipGc.restart()
  }

  function spawnWinChips(who) {
    var arr = chipBursts.slice()
    var now = Date.now()
    var count = 10
    for (var i = 0; i < count; i++) {
      arr.push({ id: "win-" + now + "-" + i + "-" + Math.random(), who: who, t: i, win: true })
    }
    chipBursts = arr
    chipGc.restart()
  }

  function newHand() {
    aiThinking = false
    aiTimer.stop()
    autoReset.stop()
    rouletteTimer.stop()
    rouletteSpinTimer.stop()
    revealPause.stop()
    victoryDelayTimer.stop()
    rouletteSpinning = false
    rouletteReveal = false
    rouletteHighlight = 0
    showResult = false
    resultWinner = -1
    resultTitle = ""
    resultSub = ""
    fx = null
    chipBursts = []
    pDelta = 0; aDelta = 0; chipFlash = false
    prevPot = -1
    victoryReady = false
    // from intro: start fresh game; from gameover: play again
    if (game.stage === "intro" || game.stage === "gameover") {
      startGame()
      return
    }
    game = Model.startHand(game)
    if (game.players && game.players[0]) game.players[0].name = root.userName
    refresh()
    maybeAi()
  }

  function act(action, amount) {
    if (aiThinking) return
    if (game.stage === "idle" || game.stage === "showdown" || game.stage === "roulette" || game.stage === "gameover") return
    if (game.turn !== 0) return
    game = Model.doAction(game, action, amount || 0)
    refresh()
    maybeAi()
    
  }

  function maybeAi() {
    if (Model.needAi(game)) {
      aiThinking = true
      aiTimer.restart()
    } else {
      aiThinking = false
    }
  }

  readonly property bool myTurn: {
    var _r = revision
    return !aiThinking && game.stage !== "idle" && game.stage !== "showdown" && game.stage !== "roulette" && game.stage !== "gameover" && game.turn === 0
  }
  readonly property int toCallAmt: {
    var _r = revision
    return Math.max(0, (game.toCall || 0) - ((game.players[0] && game.players[0].bet) || 0))
  }
  readonly property bool canCheck: toCallAmt === 0

  Timer {
    id: autoReset
    interval: 2200
    repeat: false
    onTriggered: root.newHand()
  }

  Timer {
    id: chipGc
    interval: 900
    repeat: false
    onTriggered: root.chipBursts = []
  }

  Timer {
    id: chipFlashTimer
    interval: 1200
    repeat: false
    onTriggered: root.chipFlash = false
  }

  SequentialAnimation {
    id: potPulseAnim
    NumberAnimation { target: root; property: "potPulse"; to: 1.12; duration: 120; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "potPulse"; to: 1.0; duration: 220; easing.type: Easing.OutBack }
  }

  Timer {
    id: rouletteTimer
    interval: 900
    repeat: false
    onTriggered: root.startRouletteSpin()
  }

  Timer {
    id: rouletteSpinTimer
    interval: 50
    repeat: true
    onTriggered: {
      if (!root.rouletteSpinning || !root.game.roulette) { stop(); return }
      root.rouletteSpinTick += 1
      root.rouletteHighlight = (root.rouletteHighlight % 6) + 1
      // slow down progressively for suspense, then land on result (faster)
      if (root.rouletteSpinTick < 8) interval = 50
      else if (root.rouletteSpinTick < 14) interval = 75
      else if (root.rouletteSpinTick < 20) interval = 110
      else if (root.rouletteSpinTick < 26) interval = 170
      else if (root.rouletteSpinTick < 32) interval = 260
      else if (root.rouletteSpinTick < 36) interval = 380
      else interval = 500
      var target = root.game.roulette.chamber || 1
      if (root.rouletteSpinTick >= 36 && root.rouletteHighlight === target) {
        stop()
        revealPause.restart()
      } else if (root.rouletteSpinTick > 60) {
        // safety
        stop(); root.fireRoulette()
      }
    }
  }

  Timer {
    id: revealPause
    interval: 700
    repeat: false
    onTriggered: root.fireRoulette()
  }

  Timer {
    id: aiTimer
    interval: 700
    repeat: true
    onTriggered: {
      if (!Model.needAi(root.game)) { root.aiThinking = false; aiTimer.stop(); return }
      root.game = Model.stepAi(root.game)
      root.refresh()
      if (!Model.needAi(root.game)) { root.aiThinking = false; aiTimer.stop(); }
    }
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function setAiLevel(lvl: int): void { root.setAiLevel(lvl) }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    text: "♠"
    tooltipText: "Poker"
    onPressed: function(buttonCode) { if (buttonCode === Qt.RightButton) root.newHand(); else root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)
    onOpenChanged: if (open && panel.loadedContent) panel.loadedContent.forceActiveFocus()

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: mainColumn.implicitHeight
      MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.AllButtons
        onPressed: function(mouse) { keyCatcher.forceActiveFocus(); mouse.accepted = false }
      }
      onCloseRequested: root.close()
      onActivateRequested: {
        if (root.game.stage === "roulette" && root.game.roulette && root.game.roulette.who === 0 && !root.game.roulette.done && !root.rouletteSpinning) root.startRouletteSpin()
        else root.newHand()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        // j/down = call/check, k/up = raise (PanelKeyCatcher consumes j/k as move)
        if (root.myTurn) {
          if (dy > 0) root.act(root.canCheck ? "check" : "call")
          else if (dy < 0) root.act("raise", (root.game.toCall || 0) + 40)
        }
      }
      onTextKey: function(text) {
        var k = String(text || "").toLowerCase()
        if (k === "n") root.newHand()
        else if (root.game.stage === "roulette" && root.game.roulette && root.game.roulette.who === 0 && !root.game.roulette.done && !root.rouletteSpinning && (k === " " || k === "b")) { root.startRouletteSpin(); return }
        else if (k === "f" && root.myTurn) root.act("fold")
        else if (k === "j" && root.myTurn) root.act(root.canCheck ? "check" : "call")
        else if (k === "k" && root.myTurn) root.act("raise", (root.game.toCall || 0) + 40)
        else if (k === "a" && root.myTurn) root.act("allin")
      }

      Column {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(10)
          Rectangle {
            width: Style.space(36); height: Style.space(36); radius: Style.space(10)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
            border.width: 1; border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
            Text { anchors.centerIn: parent; textFormat: Text.PlainText; text: "♠"; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.space(20) }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter; spacing: 2
            Text { textFormat: Text.PlainText; text: "Poker • Texas Hold'em"; color: root.fg; font.family: root.fontFamily; font.pixelSize: 18; font.weight: Font.DemiBold }
            Text { textFormat: Text.PlainText; text: (root.userName || "Bạn") + " vs AI (heads-up)"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.small }
          }
        }

        Rectangle {
          width: parent.width; height: (root.game.stage === "roulette") ? Style.space(330) : ((root.showResult || root.game.stage === "dead_wait") ? Style.space(305) : Style.space(270)); radius: Style.space(18)
          readonly property bool winGold: root.game.stage === "gameover" && root.showResult && root.resultWinner === 0
          readonly property bool surviveGreen: root.showResult && root.resultWinner === -3
          color: winGold ? Qt.rgba(0.50, 0.38, 0.05, 0.82) : (surviveGreen ? Qt.rgba(0.08, 0.38, 0.22, 0.75) : Qt.rgba(0.10, 0.32, 0.18, 0.55))
          border.width: (winGold || surviveGreen) ? 2 : 1
          border.color: winGold ? "#ffd54f" : (surviveGreen ? "#66bb6a" : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12))

          Column {
            anchors.fill: parent; anchors.margins: Style.space(8); spacing: 4

            // Intro / start screen
            Item {
              visible: root.game.stage === "intro"
              width: parent.width
              height: parent.height
              Column {
                anchors.centerIn: parent
                spacing: 10
                width: parent.width - 20
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "♠ ♥ ♦ ♣"
                  color: Qt.rgba(1, 0.84, 0.4, 0.8 + root.introPulse * 0.2)
                  font.family: root.fontFamily
                  font.pixelSize: 28
                  scale: 1.0 + root.introPulse * 0.08
                  transformOrigin: Item.Center
                  textFormat: Text.PlainText
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "POKER ROULETTE"
                  color: "#fff7d6"
                  font.family: root.fontFamily
                  font.pixelSize: 18
                  font.weight: Font.Bold
                  textFormat: Text.PlainText
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Top 3 tiền cao nhất"
                  color: "#ffe082"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.small
                  font.weight: Font.Bold
                  textFormat: Text.PlainText
                }
                Column {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: 2
                  Repeater {
                    model: Math.max(1, (root.topScores || []).length)
                    delegate: Text {
                      required property int index
                      anchors.horizontalCenter: parent.horizontalCenter
                      textFormat: Text.PlainText
                      text: {
                        var arr = root.topScores || []
                        if (arr.length === 0) return "Chưa có kỷ lục"
                        if (index >= arr.length) return ""
                        var it = arr[index]
                        var medal = index === 0 ? "🥇" : (index === 1 ? "🥈" : "🥉")
                        return medal + " " + (it.name || "Bạn") + ": " + (it.chips || 0)
                      }
                      color: index === 0 ? "#ffd54f" : (index === 1 ? "#e0e0e0" : "#ffcc80")
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.small
                      font.weight: index === 0 ? Font.Bold : Font.Normal
                    }
                  }
                }
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: 140; height: 36; radius: 10
                  color: startMa.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30)
                  border.width: 1; border.color: Qt.rgba(1,1,1,0.35)
                  Text { anchors.centerIn: parent; text: "Bắt đầu chơi"; color: "#fff"; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Bold }
                  MouseArea { id: startMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.startGame() }
                }
              }
            }

            // Dead wait overlay message
            Rectangle {
              visible: root.game.stage === "dead_wait"
              width: parent.width
              height: deadCol.implicitHeight + 16
              radius: 10
              color: Qt.rgba(0.2, 0.0, 0.0, 0.75)
              border.width: 1; border.color: "#ff5252"
              Column {
                id: deadCol
                anchors.centerIn: parent
                spacing: 4
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "AI đã dính đạn..."; color: "#ff8a80"; font.family: root.fontFamily; font.pixelSize: Style.font.normal; font.weight: Font.Bold; textFormat: Text.PlainText }
                Text { anchors.horizontalCenter: parent.horizontalCenter; width: parent.parent.width - 20; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "Chuẩn bị tuyên bố chiến thắng..."; color: "#fff"; font.family: root.fontFamily; font.pixelSize: Style.font.small; textFormat: Text.PlainText }
              }
            }

            Row {
              visible: root.game.stage !== "intro"
              width: parent.width; spacing: Style.space(8)
              Column {
                width: parent.width - Style.space(110); spacing: 3
                Text { textFormat: Text.PlainText; text: "AI"; color: (root.showResult && root.resultWinner === 1) ? "#ffd54f" : "#f1f8e9"; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Medium }
                Rectangle {
                  width: chipRowAi.implicitWidth + 14; height: chipRowAi.implicitHeight + 8; radius: 8
                  color: Qt.rgba(0.85, 0.55, 0.15, root.chipFlash && root.aDelta !== 0 ? 0.45 : 0.28); border.width: 1; border.color: root.chipFlash && root.aDelta > 0 ? "#66bb6a" : (root.chipFlash && root.aDelta < 0 ? "#ff8a80" : Qt.rgba(1, 0.84, 0.45, 0.7))
                  Row {
                    id: chipRowAi
                    anchors.centerIn: parent; spacing: 5
                    Rectangle {
                      width: 14; height: 14; radius: 7
                      color: "#ffd54f"; border.width: 2; border.color: "#b8860b"
                      Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 2.5; color: Qt.rgba(1,1,1,0.55) }
                    }
                    Text { textFormat: Text.PlainText; text: (root.revision, String((root.game.players[1] && root.game.players[1].chips) || 0) + (root.chipFlash && root.aDelta !== 0 ? (root.aDelta > 0 ? " (+" + root.aDelta + ")" : " (" + root.aDelta + ")") : "")); color: root.chipFlash && root.aDelta > 0 ? "#b9f6ca" : (root.chipFlash && root.aDelta < 0 ? "#ff8a80" : "#fff8d6"); font.family: root.fontFamily; font.pixelSize: Style.font.normal; font.weight: Font.Bold }
                  }
                }
                Text { textFormat: Text.PlainText; text: (root.revision, root.aiThinking ? "Đang suy nghĩ…" : (root.game.players[1] && root.game.players[1].folded ? "Đã bỏ bài" : (root.game.stage === "showdown" ? ((root.game.players[1] && root.game.players[1].handName) || "") : ""))); color: Qt.rgba(1,1,1,0.7); font.family: root.fontFamily; font.pixelSize: Style.font.small; elide: Text.ElideRight; width: parent.width }
              }
              Row {
                spacing: 4
                Repeater {
                  model: 2
                  delegate: Item {
                    required property int index
                    width: Style.space(30); height: Style.space(42)
                    property var c: (root.revision, root.game.players[1] ? root.game.players[1].hole[index] : null)
                    property bool show: root.game.stage === "showdown"
                    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 7; visible: root.showResult && root.resultWinner === 1; color: "transparent"; border.width: 2; border.color: "#ffd54f"; opacity: 0.95 }
                    Rectangle { anchors.fill: parent; radius: 5; visible: !!c && show; color: "#fdfbf6"; border.width: 1; border.color: "#cfc7b8" }
                    Text { visible: !!c && show; anchors.centerIn: parent; textFormat: Text.PlainText; text: c ? ((Model.RANK_STR[c.r]||"?") + (Model.SUIT_SYM[c.s]||"")) : ""; color: c && (c.s==="h"||c.s==="d") ? "#c62828" : "#1e1e1e"; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Bold }
                    Rectangle { anchors.fill: parent; radius: 5; visible: !c || !show; color: "#2a4a7a"; border.width: 1; border.color: "#7aa2d6" }
                    Text { visible: !c || !show; anchors.centerIn: parent; textFormat: Text.PlainText; text: "♠"; color: Qt.rgba(1,1,1,0.35); font.family: root.fontFamily; font.pixelSize: Style.font.normal }
                  }
                }
              }
            }

            Column {
              visible: root.game.stage !== "intro"
              width: parent.width; spacing: 2
              Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 4
                Repeater {
                  model: 5
                  delegate: Item {
                    required property int index
                    width: Style.space(30); height: Style.space(42)
                    property var c: (root.revision, root.game.community[index])
                    Rectangle { anchors.fill: parent; radius: 5; visible: !c; color: Qt.rgba(1,1,1,0.06); border.width: 1; border.color: Qt.rgba(1,1,1,0.12) }
                    Rectangle { anchors.fill: parent; radius: 5; visible: !!c; color: "#fdfbf6"; border.width: 1; border.color: "#cfc7b8" }
                    Column {
                      visible: !!c; anchors.centerIn: parent; spacing: -2
                      Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: c ? (Model.RANK_STR[c.r]||"?") : ""; color: c && (c.s==="h"||c.s==="d") ? "#c62828" : "#1e1e1e"; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Bold }
                      Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: c ? (Model.SUIT_SYM[c.s]||"") : ""; color: c && (c.s==="h"||c.s==="d") ? "#c62828" : "#1e1e1e"; font.family: root.fontFamily; font.pixelSize: Style.font.small }
                    }
                  }
                }
              }
              Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2
                width: parent.width - 8

                Rectangle {
                  id: potBadge
                  anchors.horizontalCenter: parent.horizontalCenter
                  readonly property int pot: (root.revision, (root.game.pot || 0))
                  readonly property int chipCount: pot <= 0 ? 0 : Math.max(1, Math.min(10, Math.ceil(pot / 20)))
                  width: Math.min(parent.width, potCol.implicitWidth + 18)
                  height: potCol.implicitHeight + 8
                  radius: 10
                  scale: root.potPulse
                  transformOrigin: Item.Center
                  color: Qt.rgba(0.55, 0.42, 0.08, pot > 0 ? 0.55 : 0.25)
                  border.width: pot > 0 ? 2 : 1
                  border.color: pot > 0 ? (root.potPulse > 1.01 ? "#fff176" : "#ffd54f") : Qt.rgba(1,1,1,0.18)

                  Column {
                    id: potCol
                    anchors.centerIn: parent
                    spacing: 2

                    Row {
                      anchors.horizontalCenter: parent.horizontalCenter
                      spacing: 5

                      Text {
                        textFormat: Text.PlainText
                        text: "POT"
                        color: "#ffe082"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.small
                        font.weight: Font.Bold
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: (root.revision, String(root.game.pot || 0))
                        color: "#fff8e1"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.normal
                        font.weight: Font.Bold
                      }
                    }

                    Row {
                      anchors.horizontalCenter: parent.horizontalCenter
                      spacing: potBadge.chipCount > 7 ? 1 : 3
                      visible: potBadge.chipCount > 0
                      Repeater {
                        model: potBadge.chipCount
                        delegate: Rectangle {
                          required property int index
                          width: 11; height: 11; radius: 5.5
                          color: {
                            var colors = ["#e53935", "#1e88e5", "#43a047", "#fb8c00", "#8e24aa"]
                            var layer = Math.floor(index / 5)
                            return colors[(index + layer) % colors.length]
                          }
                          border.width: 2
                          border.color: Qt.rgba(1,1,1,0.55)
                          Rectangle {
                            anchors.centerIn: parent
                            width: 4; height: 4; radius: 2
                            color: Qt.rgba(1,1,1,0.45)
                          }
                        }
                      }
                    }
                  }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: (root.revision, root.game.message || "")
                  visible: (root.game.message || "").length > 0 && !root.showResult
                  color: "#fff7d6"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.small
                  font.weight: Font.Normal
                  elide: Text.ElideRight
                  maximumLineCount: 1
                }
              }

              Rectangle {
                id: roulettePanel
                visible: root.game.stage === "roulette"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 8, roulCol.implicitWidth + 24)
                height: roulCol.implicitHeight + 14
                radius: 12
                property real pulse: 0
                SequentialAnimation on pulse {
                  running: root.rouletteSpinning
                  loops: Animation.Infinite
                  NumberAnimation { to: 1; duration: 350; easing.type: Easing.InOutQuad }
                  NumberAnimation { to: 0; duration: 350; easing.type: Easing.InOutQuad }
                }
                color: root.rouletteSpinning ? Qt.rgba(0.18 + pulse*0.12, 0.02, 0.02, 0.98) : Qt.rgba(0.22, 0.06, 0.06, 0.96)
                border.width: root.rouletteSpinning ? 3 : 2
                border.color: root.rouletteSpinning ? Qt.rgba(1.0, 0.1 + pulse*0.4, 0.1, 1.0) : "#ff5252"
                MouseArea {
                  anchors.fill: parent
                  z: 10
                  enabled: root.game.roulette && root.game.roulette.who === 0 && !root.game.roulette.done && !root.rouletteSpinning
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.startRouletteSpin()
                }
                Column {
                  id: roulCol
                  anchors.centerIn: parent
                  spacing: 5
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: root.rouletteSpinning ? "☠  ROULETTE TỬ THẦN" : "🔫 ROULETTE SÚNG XOAY"
                    color: "#ffccbc"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.normal
                    font.weight: Font.Bold
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(roulCol.width, 260)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: (root.revision, (root.game.roulette && root.game.roulette.handMsg ? ("Kết quả ván: " + root.game.roulette.handMsg + "\n") : "") + (root.game.roulette ? ((root.game.roulette.who === 0 ? (root.userName || "Bạn") : "AI") + " hết tiền → Roulette " + (root.game.roulette.bulletCount || 1) + "/6") : ""))
                    color: "#ffffff"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.small
                  }
                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                      model: 6
                      delegate: Item {
                        required property int index
                        readonly property int chamberNo: index + 1
                        readonly property int bulletCount: (root.game.roulette && root.game.roulette.bulletCount) ? root.game.roulette.bulletCount : 1
                        readonly property bool isTarget: root.game.roulette && (chamberNo === (root.game.roulette.chamber || 0))
                        readonly property bool isLoaded: chamberNo <= bulletCount
                        readonly property bool done: root.game.roulette && root.game.roulette.done
                        readonly property bool spinning: root.rouletteSpinning
                        readonly property bool highlighted: spinning ? (root.rouletteHighlight === chamberNo) : (done && isTarget)
                        readonly property bool lethalHit: done && isTarget && isLoaded
                        readonly property bool safeHit: done && isTarget && !isLoaded
                        width: 24; height: 24
                        Rectangle {
                          anchors.fill: parent; radius: 12
                          color: highlighted ? (lethalHit ? "#d50000" : (safeHit ? "#2e7d32" : "#ff8f00"))
                               : (isLoaded ? Qt.rgba(0.45, 0.08, 0.08, 0.85) : Qt.rgba(0.2,0.2,0.2,0.7))
                          border.width: highlighted ? 2 : 1
                          border.color: highlighted ? "#fff" : (isLoaded ? "#ff5252" : Qt.rgba(1,1,1,0.25))
                          scale: highlighted ? 1.15 : 1.0
                          Behavior on scale { NumberAnimation { duration: 80 } }
                          Behavior on color { ColorAnimation { duration: 80 } }
                        }
                        Text {
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: {
                            if (done && isTarget) return lethalHit ? "✖" : "•"
                            if (isLoaded) return "●"
                            return String(chamberNo)
                          }
                          color: highlighted ? "#fff" : (isLoaded ? "#ff8a80" : Qt.rgba(1,1,1,0.7))
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.small
                          font.weight: Font.Bold
                        }
                      }
                    }
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: {
                      root.revision
                      if (!root.game.roulette) return ""
                      if (root.rouletteSpinning) {
                        if (root.rouletteSpinTick < 18) return "Đang quay buồng đạn..."
                        if (root.rouletteSpinTick < 34) return "Nòng súng đang chậm lại..."
                        if (root.rouletteSpinTick < 48) return "Đừng thở... sắp dừng..."
                        return "..."
                      }
                      if (root.game.roulette.done) return root.game.roulette.dead ? ("BANG!!! Dính đạn buồng " + root.game.roulette.chamber + " (" + (root.game.roulette.bulletCount||1) + "/6) — CHẾT!") : ("CLICK... An toàn buồng " + root.game.roulette.chamber + " (" + (root.game.roulette.bulletCount||1) + "/6) — Sống sót!")
                      if (root.game.roulette.who === 1) return "AI đang đặt súng lên thái dương..."
                      return "Bấm BẮN! ...và cầu nguyện"
                    }
                    color: root.game.roulette && root.game.roulette.done ? (root.game.roulette.dead ? "#ff1744" : "#b9f6ca") : (root.rouletteSpinning ? "#ff5252" : Qt.rgba(1,1,1,0.9))
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.small
                    font.weight: Font.Bold
                  }
                  Rectangle {
                    visible: root.game.roulette && root.game.roulette.who === 0 && !root.game.roulette.done && !root.rouletteSpinning
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 100; height: 32; radius: 8
                    color: fireMa.containsMouse ? Qt.rgba(0.95,0.2,0.2,0.95) : Qt.rgba(0.8,0.15,0.15,0.95)
                    border.width: 1; border.color: "#ff8a80"
                    Text { anchors.centerIn: parent; text: "🔫 BẮN!"; color: "#fff"; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Bold }
                    MouseArea { id: fireMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.startRouletteSpin() }
                  }
                }
              }

              Rectangle {
                visible: root.showResult && root.game.stage !== "roulette"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 16, bannerCol.implicitWidth + 24)
                height: bannerCol.implicitHeight + 8
                radius: 10
                color: root.resultWinner === 0 ? Qt.rgba(0.2, 0.55, 0.25, 0.92)
                     : root.resultWinner === 1 ? Qt.rgba(0.55, 0.22, 0.22, 0.92)
                     : root.resultWinner === -3 ? Qt.rgba(0.12, 0.45, 0.25, 0.94)
                     : Qt.rgba(0.35, 0.35, 0.4, 0.92)
                border.width: 1
                border.color: root.resultWinner === -3 ? "#66bb6a" : Qt.rgba(1,1,1,0.25)
                Column {
                  id: bannerCol
                  anchors.centerIn: parent
                  spacing: 1
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: root.resultTitle
                    color: "#ffffff"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.small
                    font.weight: Font.Bold
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(bannerCol.width - 4, 280)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    textFormat: Text.PlainText
                    text: root.resultSub + (root.game.stage === "gameover" ? "  •  Bấm Ván mới." : "  •  Tự động ván mới...")
                    color: Qt.rgba(1,1,1,0.9)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.small
                    elide: Text.ElideRight
                  }
                }
              }
            }

            Row {
              visible: root.game.stage !== "intro"
              width: parent.width; spacing: Style.space(8)
              Row {
                spacing: 4
                Repeater {
                  model: 2
                  delegate: Item {
                    required property int index
                    width: Style.space(30); height: Style.space(42)
                    property var c: (root.revision, root.game.players[0] ? root.game.players[0].hole[index] : null)
                    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 7; visible: root.showResult && root.resultWinner === 0; color: "transparent"; border.width: 2; border.color: "#66bb6a"; opacity: 0.95 }
                    Rectangle { anchors.fill: parent; radius: 5; visible: !!c; color: "#fdfbf6"; border.width: 1; border.color: "#cfc7b8" }
                    Text { visible: !!c; anchors.centerIn: parent; textFormat: Text.PlainText; text: c ? ((Model.RANK_STR[c.r]||"?") + (Model.SUIT_SYM[c.s]||"")) : ""; color: c && (c.s==="h"||c.s==="d") ? "#c62828" : "#1e1e1e"; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Bold }
                    Rectangle { anchors.fill: parent; radius: 5; visible: !c; color: "#2a4a7a"; border.width: 1; border.color: "#7aa2d6" }
                  }
                }
              }
              Column {
                width: parent.width - Style.space(110); spacing: 3
                Text { textFormat: Text.PlainText; text: (root.revision, root.userName || "Bạn"); color: (root.showResult && root.resultWinner === 0) ? "#a5d6a7" : "#e8f5e9"; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Medium; horizontalAlignment: Text.AlignRight; width: parent.width }
                Item {
                  width: parent.width; height: plChipBg.height
                  Rectangle {
                    id: plChipBg
                    anchors.right: parent.right
                    width: chipRowPl.implicitWidth + 14; height: chipRowPl.implicitHeight + 8; radius: 8
                    color: Qt.rgba(0.20, 0.60, 0.35, root.chipFlash && root.pDelta !== 0 ? 0.45 : 0.30); border.width: 1; border.color: root.chipFlash && root.pDelta > 0 ? "#66bb6a" : (root.chipFlash && root.pDelta < 0 ? "#ff8a80" : Qt.rgba(0.60, 0.95, 0.70, 0.75))
                    Row {
                      id: chipRowPl
                      anchors.centerIn: parent; spacing: 5
                      Rectangle {
                        width: 14; height: 14; radius: 7
                        color: "#66bb6a"; border.width: 2; border.color: "#2e7d32"
                        Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 2.5; color: Qt.rgba(1,1,1,0.55) }
                      }
                      Text { textFormat: Text.PlainText; text: (root.revision, String((root.game.players[0] && root.game.players[0].chips) || 0) + (root.chipFlash && root.pDelta !== 0 ? (root.pDelta > 0 ? " (+" + root.pDelta + ")" : " (" + root.pDelta + ")") : "")); color: root.chipFlash && root.pDelta > 0 ? "#b9f6ca" : (root.chipFlash && root.pDelta < 0 ? "#ff8a80" : "#eaffef"); font.family: root.fontFamily; font.pixelSize: Style.font.normal; font.weight: Font.Bold }
                    }
                  }
                }
                Text { textFormat: Text.PlainText; text: (root.revision, (function(){ var p=root.game.players[0]; return p && p.folded ? "Đã bỏ bài" : (root.game.stage === "showdown" ? ((p && p.handName) || "") : (root.myTurn ? "Tới lượt bạn" : "")) })()); color: Qt.rgba(1,1,1,0.75); font.family: root.fontFamily; font.pixelSize: Style.font.small; horizontalAlignment: Text.AlignRight; width: parent.width; elide: Text.ElideRight }
              }
            }
          }

          // Action effect popup
          Item {
            id: fxOverlay
            anchors.fill: parent
            z: 20

            property real pop: 0
            property real rise: 0

            Text {
              id: fxText
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: -fxOverlay.rise + (root.fx && root.fx.who === 1 ? -30 : (root.fx && root.fx.who === 0 ? 30 : 0))
              opacity: fxOverlay.pop
              scale: 0.8 + fxOverlay.pop * 0.3
              textFormat: Text.PlainText
              text: {
                if (!root.fx) return ""
                var t = root.fx.type
                if (t === "fold") return "FOLD"
                if (t === "check") return "CHECK"
                if (t === "call") return "CALL +" + (root.fx.amount || 0)
                if (t === "raise") return "RAISE +" + (root.fx.amount || 0)
                if (t === "allin") return "ALL-IN +" + (root.fx.amount || 0)
                if (t === "shot") return "BANG!"
                if (t === "survive") return "SỐNG! +" + (root.fx.amount || 0)
                return ""
              }
              color: {
                if (!root.fx) return "#fff"
                if (root.fx.type === "fold") return "#ff8a80"
                if (root.fx.type === "shot") return "#ff5252"
                if (root.fx.type === "survive") return "#69f0ae"
                if (root.fx.type === "allin") return "#ff80ab"
                if (root.fx.type === "raise") return "#ffd54f"
                if (root.fx.type === "call") return "#90caf9"
                return "#b9f6ca"
              }
              font.family: root.fontFamily
              font.pixelSize: 18
              font.weight: Font.Bold
              style: Text.Outline
              styleColor: Qt.rgba(0,0,0,0.6)
            }

            SequentialAnimation {
              id: actionFxAnim
              NumberAnimation { target: fxOverlay; property: "pop"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
              NumberAnimation { target: fxOverlay; property: "rise"; from: 0; to: 18; duration: 520; easing.type: Easing.OutCubic }
              PauseAnimation { duration: 120 }
              ParallelAnimation {
                NumberAnimation { target: fxOverlay; property: "pop"; to: 0; duration: 220 }
              }
              ScriptAction { script: { fxOverlay.rise = 0 } }
            }

            Connections {
              target: root
              function onFxChanged() { 
                if (root.fx) actionFxAnim.restart()
                if (root.fx && root.fx.type === "shot") shotFlashAnim.restart()
              }
            }

            // Tension overlay during spin
            Rectangle {
              anchors.fill: parent
              visible: root.rouletteSpinning
              z: 0
              property real t: 0
              SequentialAnimation on t {
                running: root.rouletteSpinning
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 400 }
                NumberAnimation { to: 0.2; duration: 400 }
              }
              color: Qt.rgba(0.15, 0.0, 0.0, 0.25 + t * 0.25)
            }

            // Shot flash
            Rectangle {
              id: shotFlash
              anchors.fill: parent
              visible: opacity > 0
              color: Qt.rgba(0.6, 0.0, 0.0, 0.7)
              opacity: 0
              z: 1
            }
            SequentialAnimation {
              id: shotFlashAnim
              NumberAnimation { target: shotFlash; property: "opacity"; to: 1.0; duration: 40 }
              PauseAnimation { duration: 120 }
              NumberAnimation { target: shotFlash; property: "opacity"; to: 0.2; duration: 80 }
              NumberAnimation { target: shotFlash; property: "opacity"; to: 0.95; duration: 60 }
              PauseAnimation { duration: 250 }
              NumberAnimation { target: shotFlash; property: "opacity"; to: 0.15; duration: 120 }
              NumberAnimation { target: shotFlash; property: "opacity"; to: 0.7; duration: 80 }
              NumberAnimation { target: shotFlash; property: "opacity"; to: 0.0; duration: 900 }
            }

            // Death/defeat effect (chỉ khi thua)
            Rectangle {
              anchors.fill: parent
              visible: root.game.stage === "gameover" && root.resultWinner === 1
              color: Qt.rgba(0.25, 0.0, 0.0, 0.55)
              z: 1
            }
            Column {
              anchors.centerIn: parent
              spacing: 0
              visible: root.game.stage === "gameover" && root.resultWinner === 1
              z: 2
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "💀"
                font.pixelSize: 52
                textFormat: Text.PlainText
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "THẤT BẠI!"
                color: "#ff1744"
                font.family: root.fontFamily
                font.pixelSize: 28
                font.weight: Font.ExtraBold
                style: Text.Outline
                styleColor: "#000000"
                textFormat: Text.PlainText
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Game Over"
                color: "#ff8a80"
                font.family: root.fontFamily
                font.pixelSize: Style.font.small
                font.weight: Font.Bold
                textFormat: Text.PlainText
              }
            }

            // Win cup effect
            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: 6
              spacing: 0
              visible: root.game.stage === "gameover" && root.showResult && root.resultWinner === 0
              z: 3
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🏆"
                font.pixelSize: 34
                textFormat: Text.PlainText
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "CHIẾN THẮNG"
                color: "#ffd54f"
                font.family: root.fontFamily
                font.pixelSize: Style.font.small
                font.weight: Font.Bold
                style: Text.Outline
                styleColor: Qt.rgba(0,0,0,0.7)
                textFormat: Text.PlainText
              }
            }

            // Chip bet effects
            Repeater {
              model: root.chipBursts
              delegate: Item {
                id: chip
                required property var modelData
                readonly property bool fromPlayer: modelData.who === 0
                width: 14; height: 14
                x: parent.width * 0.5 - 7 + (Math.sin((modelData.t || 0) * 1.7) * (20 + (modelData.t||0)*3))
                y: fromPlayer ? parent.height - 40 : 26
                opacity: 1
                scale: 0.6
                property real travel: 0

                Rectangle {
                  anchors.fill: parent
                  radius: width/2
                  color: Qt.rgba(0.95, 0.78, 0.25, 0.95)
                  border.width: 2
                  border.color: Qt.rgba(0.6, 0.45, 0.1, 0.9)
                }
                Rectangle {
                  anchors.centerIn: parent
                  width: parent.width * 0.45; height: width; radius: width/2
                  color: "transparent"; border.width: 1; border.color: Qt.rgba(1,1,1,0.5)
                }

                transform: Translate { y: fromPlayer ? -chip.travel : chip.travel }

                ParallelAnimation {
                  running: true
                  NumberAnimation { target: chip; property: "travel"; to: 55 + (modelData.t||0)*2; duration: 600; easing.type: Easing.OutCubic }
                  NumberAnimation { target: chip; property: "scale"; from: 0.4; to: 1.0; duration: 200 }
                  SequentialAnimation {
                    PauseAnimation { duration: 450 }
                    NumberAnimation { target: chip; property: "opacity"; to: 0; duration: 250 }
                  }
                }
              }
            }
          }
        }

        Row {
          width: parent.width; spacing: Style.space(4)

          Rectangle {
            id: newBtn
            readonly property bool canNew: root.game.stage === "idle" || root.game.stage === "showdown" || root.game.stage === "gameover"
            visible: root.game.stage !== "intro" && root.game.stage !== "dead_wait"
            width: (parent.width - Style.space(16)) / 5; height: Style.space(38); radius: 8
            opacity: newBtn.canNew ? 1.0 : 0.45
            color: !newBtn.canNew ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03) : (mNew.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28) : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18))
            border.width: 1; border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
            Column { anchors.centerIn: parent; spacing: 0
              Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: (root.game.stage === "gameover" ? "Chơi lại" : "Mới"); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Medium }
              Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: "N"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.small }
            }
            MouseArea { id: mNew; anchors.fill: parent; hoverEnabled: newBtn.canNew; enabled: newBtn.canNew; cursorShape: newBtn.canNew ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.newHand() }
          }

          Rectangle {
            id: foldBtn
            visible: root.game.stage !== "intro" && root.game.stage !== "dead_wait" && root.game.stage !== "gameover"
            readonly property bool ok: root.myTurn
            readonly property color base: Qt.rgba(0.85, 0.30, 0.30, 1)
            width: (parent.width - Style.space(16)) / 5; height: Style.space(40); radius: 8
            opacity: foldBtn.ok ? 1 : 0.45
            color: !foldBtn.ok ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03) : (mFold.containsMouse ? Qt.rgba(foldBtn.base.r, foldBtn.base.g, foldBtn.base.b, 0.28) : Qt.rgba(foldBtn.base.r, foldBtn.base.g, foldBtn.base.b, 0.18))
            border.width: 1; border.color: !foldBtn.ok ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : Qt.rgba(foldBtn.base.r, foldBtn.base.g, foldBtn.base.b, 0.45)
            Column { anchors.centerIn: parent; spacing: 1
              Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: "✕ Fold"; color: foldBtn.ok ? Qt.rgba(1,0.92,0.92,1) : root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Medium }
              Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: "F"; color: foldBtn.ok ? Qt.rgba(1,0.85,0.85,0.8) : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.small }
            }
            MouseArea { id: mFold; anchors.fill: parent; hoverEnabled: foldBtn.ok; enabled: foldBtn.ok; cursorShape: foldBtn.ok ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.act("fold") }
          }

          Rectangle {
            id: callBtn
            visible: root.game.stage !== "intro" && root.game.stage !== "dead_wait" && root.game.stage !== "gameover"
            readonly property bool ok: root.myTurn
            readonly property color base: root.canCheck ? Qt.rgba(0.25, 0.65, 0.45, 1) : Qt.rgba(0.25, 0.55, 0.85, 1)
            width: (parent.width - Style.space(16)) / 5; height: Style.space(40); radius: 8
            opacity: callBtn.ok ? 1 : 0.45
            color: !callBtn.ok ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03) : (mCall.containsMouse ? Qt.rgba(callBtn.base.r, callBtn.base.g, callBtn.base.b, 0.30) : Qt.rgba(callBtn.base.r, callBtn.base.g, callBtn.base.b, 0.20))
            border.width: 1; border.color: !callBtn.ok ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : Qt.rgba(callBtn.base.r, callBtn.base.g, callBtn.base.b, 0.5)
            Column { anchors.centerIn: parent; spacing: 1
              Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: root.canCheck ? "✓ Check" : ("➜ Call"); color: callBtn.ok ? "#eef8ff" : root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Medium }
              Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: "J"; color: callBtn.ok ? Qt.rgba(1,1,1,0.75) : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.small }
            }
            MouseArea { id: mCall; anchors.fill: parent; hoverEnabled: callBtn.ok; enabled: callBtn.ok; cursorShape: callBtn.ok ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.act(root.canCheck ? "check" : "call") }
          }

          Rectangle {
            id: raiseBtn
            visible: root.game.stage !== "intro" && root.game.stage !== "dead_wait" && root.game.stage !== "gameover"
            readonly property bool ok: root.myTurn
            readonly property color base: Qt.rgba(0.95, 0.70, 0.20, 1)
            width: (parent.width - Style.space(16)) / 5; height: Style.space(40); radius: 8
            opacity: raiseBtn.ok ? 1 : 0.45
            color: !raiseBtn.ok ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03) : (mRaise.containsMouse ? Qt.rgba(raiseBtn.base.r, raiseBtn.base.g, raiseBtn.base.b, 0.32) : Qt.rgba(raiseBtn.base.r, raiseBtn.base.g, raiseBtn.base.b, 0.20))
            border.width: 1; border.color: !raiseBtn.ok ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : Qt.rgba(raiseBtn.base.r, raiseBtn.base.g, raiseBtn.base.b, 0.55)
            Column { anchors.centerIn: parent; spacing: 1
              Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: "▲ Raise"; color: raiseBtn.ok ? "#fff7e0" : root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Medium }
              Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: "K"; color: raiseBtn.ok ? Qt.rgba(1,0.95,0.85,0.8) : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.small }
            }
            MouseArea { id: mRaise; anchors.fill: parent; hoverEnabled: raiseBtn.ok; enabled: raiseBtn.ok; cursorShape: raiseBtn.ok ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.act("raise", (root.game.toCall || 0) + 40) }
          }

          Rectangle {
            id: allinBtn
            visible: root.game.stage !== "intro" && root.game.stage !== "dead_wait" && root.game.stage !== "gameover"
            readonly property bool ok: root.myTurn
            readonly property color base: Qt.rgba(0.85, 0.25, 0.55, 1)
            width: (parent.width - Style.space(16)) / 5; height: Style.space(40); radius: 8
            opacity: allinBtn.ok ? 1 : 0.45
            color: !allinBtn.ok ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03) : (mAllin.containsMouse ? Qt.rgba(allinBtn.base.r, allinBtn.base.g, allinBtn.base.b, 0.32) : Qt.rgba(allinBtn.base.r, allinBtn.base.g, allinBtn.base.b, 0.20))
            border.width: 1; border.color: !allinBtn.ok ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : Qt.rgba(allinBtn.base.r, allinBtn.base.g, allinBtn.base.b, 0.55)
            Column { anchors.centerIn: parent; spacing: 1
              Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: "★ All-in"; color: allinBtn.ok ? "#ffe8f3" : root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.small; font.weight: Font.Medium }
              Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: "A"; color: allinBtn.ok ? Qt.rgba(1,0.9,0.95,0.8) : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.small }
            }
            MouseArea { id: mAllin; anchors.fill: parent; hoverEnabled: allinBtn.ok; enabled: allinBtn.ok; cursorShape: allinBtn.ok ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.act("allin") }
          }
        }

        Rectangle {
          visible: {
            root.revision
            var p = root.game.players[0]
            return !!(p && p.hole && p.hole.length >= 2 && !p.folded && root.game.stage !== "idle" && root.game.stage !== "intro")
          }
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(parent.width, handLabel.implicitWidth + Style.space(20))
          height: handLabel.implicitHeight + Style.space(10)
          radius: height / 2
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          border.width: 1
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
          Text {
            id: handLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: {
              root.revision
              var p = root.game.players[0]
              if (!p || !p.hole) return ""
              var cards = p.hole.concat(root.game.community || [])
              var name = Model.currentHandName ? Model.currentHandName(cards) : ""
              return "Bài của bạn: " + (name || "—")
            }
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.small
            font.weight: Font.Medium
          }
        }

        Text {
          width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; textFormat: Text.PlainText
          text: {
            if (root.game.stage === "intro") return "Bấm Bắt đầu chơi để vào bàn."
            if (root.game.stage === "dead_wait") return "AI đã gục ngã... chuẩn bị tuyên bố chiến thắng."
            if (root.game.stage === "gameover") return "Trận đấu kết thúc."
            if (root.game.stage === "showdown") return "Ván kết thúc — sẽ tự động ván mới."
            return "F: fold, J: check/call, K: raise, A: all-in."
          }
          color: root.fainter; font.family: root.fontFamily; font.pixelSize: Style.font.small
        }
      }
    }
  }
}
