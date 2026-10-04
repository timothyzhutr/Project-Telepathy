//
//  SquirrelInputController.swift
//  Squirrel
//
//  Created by Leo Liu on 5/7/24.
//

import InputMethodKit

final class SquirrelInputController: IMKInputController {
  private static let keyRollOver = 50
  private static var unknownAppCnt: UInt = 0

  private weak var client: IMKTextInput?
  private let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
  private var preedit: String = ""
  private var selRange: NSRange = .empty
  private var caretPos: Int = 0
  private var lastModifiers: NSEvent.ModifierFlags = .init()
  private var session: RimeSessionId = 0
  private var schemaId: String = ""
  private var inlinePreedit = false
  private var inlineCandidate = false
  private var chordKeyCodes: [UInt32] = .init(repeating: 0, count: SquirrelInputController.keyRollOver)
  private var chordModifiers: [UInt32] = .init(repeating: 0, count: SquirrelInputController.keyRollOver)
  private var chordKeyCount: Int = 0
  private var chordTimer: Timer?
  private var chordDuration: TimeInterval = 0
  private var currentApp: String = ""
  private var ranking = RankingState()
  private var intent = InputIntentState()
  private var rankingDelay: DispatchWorkItem?
  private var rankingNote = ""
  private var compositionPrefix = ""
  private var fallbackHistory = ""
  private var displayedHighlight = 0
  private var rankingEnabled: Bool { TelepathyPreferences.shared.enabled(.kev) }
  private var automaticLanguageEnabled: Bool { rankingEnabled && TelepathyPreferences.shared.enabled(.autoLanguage) }

  func freezeRanking() { ranking.freeze(); intent.forceChinese() }

  private func invalidateRanking(resetIntent: Bool = true) {
    rankingDelay?.cancel()
    rankingDelay = nil
    ranking.invalidate()
    rankingNote = ""
    if resetIntent { intent.invalidate(revision: ranking.revision) }
  }

  // swiftlint:disable:next cyclomatic_complexity
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    guard let event = event else { return false }
    let modifiers = event.modifierFlags
    let changes = lastModifiers.symmetricDifference(modifiers)

    // Return true to consume the key event; return false to pass it to the client app.
    var handled = false

    if session == 0 || !rimeAPI.find_session(session) {
      createSession()
      if session == 0 {
        return false
      }
    }

    self.client ?= sender as? IMKTextInput
    if let app = client?.bundleIdentifier(), currentApp != app {
      currentApp = app
      updateAppOptions()
    }

    switch event.type {
    case .flagsChanged:
      if lastModifiers == modifiers {
        handled = true
        break
      }
      if automaticLanguageEnabled && changes == .shift {
        lastModifiers = modifiers
        return true
      }
      var rimeModifiers: UInt32 = SquirrelKeycode.osxModifiersToRime(modifiers: modifiers)
      // Some remote desktop tools send flagsChanged with keyCode 0; infer the real modifier key when needed.
      var keyCode = event.keyCode
      if !SquirrelKeycode.modifierKeycodes.contains(keyCode) {
        guard let inferred = SquirrelKeycode.inferModifierKeycode(from: changes) else {
          lastModifiers = modifiers
          rimeUpdate()
          handled = true
          break
        }
        keyCode = inferred
      }
      let rimeKeycode: UInt32 = SquirrelKeycode.osxKeycodeToRime(keycode: keyCode, keychar: nil, shift: false, caps: false)

      if changes.contains(.capsLock) {
        // Rime expects XK_Caps_Lock before the lock mask changes; NSFlagsChanged has already applied it.
        rimeModifiers ^= kLockMask.rawValue
        _ = processKey(rimeKeycode, modifiers: rimeModifiers)
      }

      // Process releases first because some modifier releases arrive with the next keydown.
      var buffer = [(keycode: UInt32, modifier: UInt32)]()
      for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] where changes.contains(flag) {
        // In Auto mode Shift changes character case. It must not trigger
        // Rime's commit_code switch and leave subsequent words in ASCII mode.
        if automaticLanguageEnabled && flag == .shift { continue }
        if modifiers.contains(flag) {
          buffer.append((keycode: rimeKeycode, modifier: rimeModifiers))
        } else {
          buffer.insert((keycode: rimeKeycode, modifier: rimeModifiers | kReleaseMask.rawValue), at: 0)
        }
      }
      for (keycode, modifier) in buffer {
        _ = processKey(keycode, modifiers: modifier)
      }

      lastModifiers = modifiers
      rimeUpdate()

    case .keyDown:
      // Let client apps handle Command shortcuts.
      if modifiers.contains(.command) {
        if intent.english { commitPendingLiteral() }
        invalidateRanking()
        fallbackHistory = ""
        break
      }

      let keyCode = event.keyCode
      var keyChars = event.charactersIgnoringModifiers
      let capitalModifiers = modifiers.isSubset(of: [.shift, .capsLock])
      if let code = keyChars?.first,
         (capitalModifiers && !code.isLetter) || (!capitalModifiers && !code.isASCII) {
        keyChars = event.characters
      }
      if let char = keyChars?.first {
        let rimeKeycode = SquirrelKeycode.osxKeycodeToRime(keycode: keyCode, keychar: char,
                                                           shift: modifiers.contains(.shift),
                                                           caps: modifiers.contains(.capsLock))
        if rimeKeycode != 0 {
          if let result = handleAutoKey(rimeKeycode, modifiers: modifiers) { return result }
          let rimeModifiers = SquirrelKeycode.osxModifiersToRime(modifiers: modifiers)
          handled = processKey(rimeKeycode, modifiers: rimeModifiers)
          rimeUpdate()
        }
      }

    default:
      break
    }

    return handled
  }

  func selectCandidate(_ index: Int) -> Bool {
    freezeRanking()
    let native = ranking.nativeIndex(index) ?? index
    let success = rimeAPI.select_candidate_on_current_page(session, native)
    if success {
      rimeUpdate()
    }
    return success
  }

  // swiftlint:disable:next identifier_name
  func page(up: Bool) -> Bool {
    intent.forceChinese()
    var handled = false
    handled = rimeAPI.change_page(session, up)
    if handled {
      rimeUpdate()
    }
    return handled
  }

  func moveCaret(forward: Bool) -> Bool {
    intent.forceChinese()
    let currentCaretPos = rimeAPI.get_caret_pos(session)
    guard let input = rimeAPI.get_input(session) else { return false }
    if forward {
      if currentCaretPos <= 0 {
        return false
      }
      rimeAPI.set_caret_pos(session, currentCaretPos - 1)
    } else {
      let inputStr = String(cString: input)
      if currentCaretPos >= inputStr.utf8.count {
        return false
      }
      rimeAPI.set_caret_pos(session, currentCaretPos + 1)
    }
    rimeUpdate()
    return true
  }

  override func recognizedEvents(_ sender: Any!) -> Int {
    return Int(NSEvent.EventTypeMask.Element(arrayLiteral: .keyDown, .flagsChanged).rawValue)
  }

  override func activateServer(_ sender: Any!) {
    invalidateRanking()
    compositionPrefix = ""
    fallbackHistory = ""
    self.client ?= sender as? IMKTextInput
    applyTypingPreferences()
    var keyboardLayout = NSApp.squirrelAppDelegate.config?.getString("keyboard_layout") ?? ""
    if keyboardLayout == "last" || keyboardLayout == "" {
      keyboardLayout = ""
    } else if keyboardLayout == "default" {
      keyboardLayout = "com.apple.keylayout.ABC"
    } else if !keyboardLayout.hasPrefix("com.apple.keylayout.") {
      keyboardLayout = "com.apple.keylayout.\(keyboardLayout)"
    }
    if keyboardLayout != "" {
      client?.overrideKeyboard(withKeyboardNamed: keyboardLayout)
    }
    // Activation delivers no flagsChanged event, and NSEvent.modifierFlags
    // only reflects this process's own event stream, so lastModifiers may
    // disagree with the actual Caps Lock state by now. Seed it from the
    // session-wide hardware state; otherwise the next Caps Lock press can
    // compare equal to the stale lastModifiers and be dropped by the
    // early-return in handle().
    if CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) {
      lastModifiers.insert(.capsLock)
    } else {
      lastModifiers.remove(.capsLock)
    }
    preedit = ""
    if session != 0 {
      let state = rimeAPI.get_option(session, "ascii_mode")
      let label = rimeAPI.get_state_label_abbreviated(session, "ascii_mode", state, true).asString
      NSApp.squirrelAppDelegate.updateStatusIcon(asciiMode: state, schemaLabel: label)
    }
  }

  override init!(server: IMKServer!, delegate: Any!, client: Any!) {
    self.client = client as? IMKTextInput
    super.init(server: server, delegate: delegate, client: client)
    createSession()

    NotificationCenter.default.addObserver(
      forName: .init("TelepathySetASCIIModeNotification"),
      object: nil,
      queue: nil
    ) { [weak self] notification in
      self?.handleASCIIModeToggle(notification)
    }

    NotificationCenter.default.addObserver(
      forName: .init("TelepathyReportASCIIModeNotification"),
      object: nil,
      queue: nil
    ) { [weak self] notification in
      self?.reportASCIIMode(notification)
    }
  }

  override func deactivateServer(_ sender: Any!) {
    hidePalettes()
    commitComposition(sender)
    fallbackHistory = ""
    client = nil
  }

  override func hidePalettes() {
    NSApp.squirrelAppDelegate.panel?.hide()
    super.hidePalettes()
  }

  override func commitComposition(_ sender: Any!) {
    self.client ?= sender as? IMKTextInput
    if intent.english { commitPendingLiteral(); return }
    invalidateRanking()
    fallbackHistory = ""
    if session != 0 {
      _ = tp_commit_composition(session)
      rimeConsumeCommittedText()
      rimeAPI.clear_composition(session)
    }
  }

  override func menu() -> NSMenu! {
    let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
    settings.target = self
    let logDir = NSMenuItem(title: NSLocalizedString("Logs...", comment: "Menu item"), action: #selector(openLogFolder), keyEquivalent: "")
    logDir.target = self
    let wiki = NSMenuItem(title: "Credits and licenses…", action: #selector(openWiki), keyEquivalent: "")
    wiki.target = self

    let kev = NSMenuItem(title: "Kev assistance", action: #selector(toggleKev), keyEquivalent: "")
    kev.target = self
    kev.state = rankingEnabled ? .on : .off
    let menu = NSMenu()
    menu.addItem(settings)
    menu.addItem(kev)
    menu.addItem(.separator())
    menu.addItem(logDir)
    menu.addItem(wiki)


    return menu
  }

  @objc func toggleKev() {
    TelepathyPreferences.shared.set(!rankingEnabled, for: .kev)
    invalidateRanking()
    rimeUpdate()
  }

  @objc func deploy() {
    NSApp.squirrelAppDelegate.deploy()
  }

  @objc func syncUserData() {
    NSApp.squirrelAppDelegate.syncUserData()
  }

  @objc func openLogFolder() {
    NSApp.squirrelAppDelegate.openLogFolder()
  }

  @objc func openRimeFolder() {
    NSApp.squirrelAppDelegate.openRimeFolder()
  }

  @objc func checkForUpdates() {
    NSApp.squirrelAppDelegate.checkForUpdates()
  }

  @objc func openWiki() {
    NSApp.squirrelAppDelegate.openWiki()
  }

  @objc func openSettings() { NSApp.squirrelAppDelegate.openSettings() }

  func preferencesDidChange() {
    invalidateRanking()
    applyTypingPreferences()
    rimeUpdate()
  }

  private func applyTypingPreferences() {
    guard session != 0 else { return }
    rimeAPI.set_option(session, "ascii_punct", !TelepathyPreferences.shared.enabled(.punctuation))
    if let panel = NSApp.squirrelAppDelegate.panel {
      inlinePreedit = (panel.inlinePreedit && !rimeAPI.get_option(session, "no_inline")) || rimeAPI.get_option(session, "inline")
      inlineCandidate = panel.inlineCandidate && !rimeAPI.get_option(session, "no_inline")
      rimeAPI.set_option(session, "soft_cursor", !inlinePreedit)
    }
  }

  private(set) var specialCommentIndices: [ReservedPropertyKey: Set<Int>] = [:]

  func handleReservedProperty(key rawKey: String, value rawValue: String, for sessionId: RimeSessionId) throws(ReservedPropertyError) {
    guard session == sessionId, session != 0, rimeAPI.find_session(session) else { return }
    guard let key = ReservedPropertyKey(rawValue: rawKey) else { throw .unknownInput(rawKey) }
    let parsed = try ReservedPropertyValue.parse(rawValue)
    switch key {
    case .commentHighlight:
      specialCommentIndices[.commentHighlight] = try parsed.indices()
    case .commentWarning:
      specialCommentIndices[.commentWarning] = try parsed.indices()
    case .refreshUI:
      rimeUpdate(clearReservedComments: false)
    }
  }

  deinit {
    destroySession()
  }
}

private extension SquirrelInputController {

  func commitPendingLiteral(separator: String = "") {
    let raw = rimeAPI.get_input(session).map { String(cString: $0) } ?? ""
    rimeAPI.clear_composition(session)
    if !raw.isEmpty { commit(string: raw + separator) }
    else { invalidateRanking() }
  }

  // nil means use the ordinary Rime key path; false passes the original key
  // to the host. Nothing waits for a model on the input event thread.
  func handleAutoKey(_ key: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool? {
    guard automaticLanguageEnabled, !rimeAPI.get_option(session, "ascii_mode") else { return nil }
    if modifiers.contains(.control) || modifiers.contains(.option) {
      guard intent.english || intent.literalRun else { return nil }
      if intent.english { commitPendingLiteral() }
      invalidateRanking(); fallbackHistory = ""
      return false
    }
    func recordPassedKey() {
      if (32...126).contains(key), let scalar = UnicodeScalar(key) {
        fallbackHistory = String((fallbackHistory + String(scalar)).suffix(512))
      } else { fallbackHistory = "" }
    }
    if TelepathyPreferences.shared.enabled(.autoPunctuation),
       TelepathyPreferences.shared.enabled(.punctuation),
       !rimeAPI.get_option(session, "ascii_punct"),
       let scalar = UnicodeScalar(key), PunctuationPolicy.supports(Character(String(scalar))) {
      let char = Character(String(scalar))
      let raw = rimeAPI.get_input(session).map { String(cString: $0) } ?? ""
      let prefix = precedingText()
      let addressStart = PunctuationPolicy.beginsAddress(key: char, context: prefix + raw)
      // Apostrophes inside Chinese composition are pinyin syllable separators.
      if char != "'" || raw.isEmpty || intent.english {
        var context = prefix
        if intent.english || addressStart { context += raw }
        else if !raw.isEmpty {
          var ctx = RimeContext_stdbool.rimeStructInit()
          if rimeAPI.get_context(session, &ctx) {
            context += ctx.commit_text_preview.map { String(cString: $0) } ?? ""
            _ = rimeAPI.free_context(&ctx)
          }
        }
        if let decision = PunctuationPolicy.decide(key: char, context: context, defaultChinese: true) {
          if intent.english || addressStart { commitPendingLiteral() }
          else {
            // Commit the current native highlight (including Kev's ordering)
            // before inserting the mark; never replace committed host text.
            _ = tp_commit_composition(session)
            rimeConsumeCommittedText()
            rimeAPI.clear_composition(session)
          }
          commit(string: decision.text)
          rimeUpdate()
          if decision.continueLiteral { intent.startLiteralRun() }
          return true
        }
      }
    }
    if intent.passLiteralKey(key) { recordPassedKey(); return false }
    if (65...90).contains(key) {
      commitPendingLiteral()
      intent.startLiteralRun()
      recordPassedKey()
      return false
    }
    switch intent.action(for: key) {
    case .none: return nil
    case .space:
      commitPendingLiteral(separator: " ")
      return true
    case .commitAndPass:
      commitPendingLiteral()
      if (33...126).contains(key) { intent.startLiteralRun() }
      recordPassedKey()
      return false
    case .chinese:
      freezeRanking()
      rimeUpdate(clearReservedComments: false)
      return true
    }
  }

  func onChordTimer(_: Timer) {
    var processedKeys = false
    if chordKeyCount > 0 && session != 0 {
      // Chord typing releases are synthesized after the configured timeout.
      for i in 0..<chordKeyCount {
        let handled = rimeAPI.process_key(session, Int32(chordKeyCodes[i]), Int32(chordModifiers[i] | kReleaseMask.rawValue))
        if handled {
          processedKeys = true
        }
      }
    }
    clearChord()
    if processedKeys {
      rimeUpdate()
    }
  }

  func updateChord(keycode: UInt32, modifiers: UInt32) {
    for i in 0..<chordKeyCount where chordKeyCodes[i] == keycode {
      return
    }
    if chordKeyCount >= Self.keyRollOver {
      return
    }
    chordKeyCodes[chordKeyCount] = keycode
    chordModifiers[chordKeyCount] = modifiers
    chordKeyCount += 1
    if let timer = chordTimer, timer.isValid {
      timer.invalidate()
    }
    chordDuration = 0.1
    if let duration = NSApp.squirrelAppDelegate.config?.getDouble("chord_duration"), duration > 0 {
      chordDuration = duration
    }
    chordTimer = Timer.scheduledTimer(withTimeInterval: chordDuration, repeats: false, block: onChordTimer)
  }

  func clearChord() {
    chordKeyCount = 0
    if let timer = chordTimer {
      if timer.isValid {
        timer.invalidate()
      }
      chordTimer = nil
    }
  }

  func createSession() {
    let app = client?.bundleIdentifier() ?? {
      SquirrelInputController.unknownAppCnt &+= 1
      return "UnknownApp\(SquirrelInputController.unknownAppCnt)"
    }()
    print("createSession: \(app)")
    currentApp = app
    session = rimeAPI.create_session()
    schemaId = ""

    if session != 0 {
      _ = rimeAPI.select_schema(session, "wanxiang")
      updateAppOptions()
      rimeAPI.set_option(session, "ascii_mode", false)
      for option in ["context_reorder", "s2t", "s2hk", "s2tw"] { rimeAPI.set_option(session, option, false) }
      applyTypingPreferences()
    }
  }

  func updateAppOptions() {
    if currentApp == "" {
      return
    }
    if let appOptions = NSApp.squirrelAppDelegate.config?.getAppOptions(currentApp) {
      for (key, value) in appOptions {
        print("set app option: \(key) = \(value)")
        rimeAPI.set_option(session, key, value)
      }
    }
    if let reportBundleID = NSApp.squirrelAppDelegate.config?.getBool("unsafe/report_bundleid"), reportBundleID {
      currentApp.withCString { name in
        rimeAPI.set_property(session, "client_app", name)
      }
    }
  }

  func destroySession() {
    if session != 0 {
      _ = rimeAPI.destroy_session(session)
      session = 0
    }
    clearChord()
  }

  func processKey(_ rimeKeycode: UInt32, modifiers rimeModifiers: UInt32) -> Bool {
    if let panel = NSApp.squirrelAppDelegate.panel {
      if panel.linear != rimeAPI.get_option(session, "_linear") {
        rimeAPI.set_option(session, "_linear", panel.linear)
      }
      if panel.vertical != rimeAPI.get_option(session, "_vertical") {
        rimeAPI.set_option(session, "_vertical", panel.vertical)
      }
    }

    if rimeModifiers == 0, !ranking.order.isEmpty {
      if rimeKeycode >= 49 && rimeKeycode <= 57 || rimeKeycode == 48 {
        let displayed = rimeKeycode == 48 ? 9 : Int(rimeKeycode - 49)
        if let native = ranking.nativeIndex(displayed) {
          freezeRanking()
          return rimeAPI.select_candidate_on_current_page(session, native)
        }
      }
      if rimeKeycode == UInt32(XK_Up) || rimeKeycode == UInt32(XK_Down) {
        freezeRanking()
        let step = rimeKeycode == UInt32(XK_Up) ? -1 : 1
        displayedHighlight = max(0, min(ranking.order.count - 1, displayedHighlight + step))
        if let native = ranking.nativeIndex(displayedHighlight) {
          return rimeAPI.highlight_candidate_on_current_page(session, native)
        }
      }
    }
    if (rimeAPI.get_input(session).map { String(cString: $0).isEmpty } ?? true),
       rimeKeycode == UInt32(XK_BackSpace) || rimeKeycode == UInt32(XK_Left) || rimeKeycode == UInt32(XK_Right) {
      fallbackHistory = ""
    }
    let handled = rimeAPI.process_key(session, Int32(rimeKeycode), Int32(rimeModifiers))

    if !handled {
      let isVimBackInCommandMode = rimeKeycode == XK_Escape || ((rimeModifiers & kControlMask.rawValue != 0) && (rimeKeycode == XK_c || rimeKeycode == XK_C || rimeKeycode == XK_bracketleft))
      if isVimBackInCommandMode && rimeAPI.get_option(session, "vim_mode") &&
          !rimeAPI.get_option(session, "ascii_mode") {
        rimeAPI.set_option(session, "ascii_mode", true)
      }
    } else {
      let isChordingKey = switch Int32(rimeKeycode) {
      case XK_space...XK_asciitilde, XK_Control_L, XK_Control_R, XK_Alt_L, XK_Alt_R, XK_Shift_L, XK_Shift_R:
        true
      default:
        false
      }
      if isChordingKey && rimeAPI.get_option(session, "_chord_typing") {
        updateChord(keycode: rimeKeycode, modifiers: rimeModifiers)
      } else if (rimeModifiers & kReleaseMask.rawValue) == 0 {
        clearChord()
      }
    }

    return handled
  }

  func rimeConsumeCommittedText() {
    var commitText = RimeCommit.rimeStructInit()
    if rimeAPI.get_commit(session, &commitText) {
      if let text = commitText.text {
        commit(string: String(cString: text))
      }
      _ = rimeAPI.free_commit(&commitText)
    }
  }

  func submitRanking(_ data: Data, revision: Int) {
    guard rankingEnabled, ranking.revision == revision, !ranking.frozen, !intent.english else { return }
    DecisionTransport.shared.submit(data) { [weak self] result in
      guard let self, !self.intent.english, let result, result["status"] as? String == "ok",
            let order = result["order"] as? [Int], self.ranking.apply(order, revision: revision) else { return }
      self.displayedHighlight = 0
      _ = self.rimeAPI.highlight_candidate_on_current_page(self.session, order[0])
      if result["ranked"] as? Bool == true {
        let name = result["strategy"] as? String == "continuation" ? "Context" : "Kev"
        self.rankingNote = "\(name) \(Int((result["request_ms"] as? Double) ?? 0)) ms"
      } else { self.rankingNote = "Full phrase" }
      self.rimeUpdate(clearReservedComments: false)
    }
  }

  func scheduleRanking(_ data: Data, revision: Int, deadline: DispatchTime) {
    rankingDelay?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.submitRanking(data, revision: revision) }
    rankingDelay = work
    DispatchQueue.main.asyncAfter(deadline: deadline, execute: work)
  }

  // Preserve reserved comment marks when librime requests a UI-only refresh.
  func rimeUpdate(clearReservedComments: Bool = true) {
    if clearReservedComments {
      specialCommentIndices = [:]
    }
    rimeConsumeCommittedText()

    var status = RimeStatus_stdbool.rimeStructInit()
    if rimeAPI.get_status(session, &status) {
      // swiftlint:disable:next identifier_name
      if let schema_id = status.schema_id, schemaId == "" || schemaId != String(cString: schema_id) {
        schemaId = String(cString: schema_id)
        NSApp.squirrelAppDelegate.loadSettings(for: schemaId)
        applyTypingPreferences()
      }
      _ = rimeAPI.free_status(&status)
    }

    var ctx = RimeContext_stdbool.rimeStructInit()
    if rimeAPI.get_context(session, &ctx) {
      let preedit = ctx.composition.preedit.map({ String(cString: $0) }) ?? ""

      let start = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_start)), within: preedit) ?? preedit.startIndex
      let end = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_end)), within: preedit) ?? preedit.startIndex
      let caretPos = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.cursor_pos)), within: preedit) ?? preedit.startIndex

      if inlineCandidate {
        var candidatePreview = ctx.commit_text_preview.map { String(cString: $0) } ?? ""
        let endOfCandidatePreview = candidatePreview.endIndex
        if inlinePreedit {
          // 左移光標後的情形：
          // preedit:             ^已選某些字[xiang zuo yi dong]|guangbiao$
          // commit_text_preview: ^已選某些字向左移動$
          // candidate_preview:   ^已選某些字[向左移動]|guangbiao$
          // 繼續翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字[xiang zuo]yidong|guangbiao$
          // commit_text_preview: ^已選某些字向左yidong$
          // candidate_preview:   ^已選某些字[向左]yidong|guangbiao$
          // 光標移至當前段落最左端的情形：
          // preedit:             ^已選某些字|[xiang zuo yi dong guang biao]$
          // commit_text_preview: ^已選某些字向左移動光標$
          // candidate_preview:   ^已選某些字|[向左移動光標]$
          // 討論：
          // preedit 與 commit_text_preview 中“已選某些字”部分一致
          // 因此，選中範圍即正在翻譯的碼段“向左移動”中，兩者的 start 值一致
          // 光標位置的範圍是 start ..= endOfCandidatePreview
          if caretPos >= end && caretPos < preedit.endIndex {
            // 從 preedit 截取光標後未翻譯的編碼“guangbiao”
            candidatePreview += preedit[caretPos...]
          }
        } else {
          // 翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字[xiang zuo]yidong|guangbiao$
          // commit_text_preview: ^已選某些字向左yidongguangbiao$
          // candidate_preview:   ^已選某些字[向左???]|$
          // 光標移至當前段落最左端，繼續翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字|[xiang zuo]yidongguangbiao$
          // commit_text_preview: ^已選某些字向左yidongguangbiao$
          // candidate_preview:   ^已選某些字|[向左]???$
          // FIXME: add librime APIs to support preview candidate without remaining code.
        }
        // preedit can contain additional prompt text before start:
        // ^(prompt)[selection]$
        let start = min(start, candidatePreview.endIndex)
        let caretPos = caretPos <= start ? caretPos : endOfCandidatePreview
        show(preedit: candidatePreview,
             selRange: NSRange(location: start.utf16Offset(in: candidatePreview),
                               length: candidatePreview.utf16.distance(from: start, to: candidatePreview.endIndex)),
             caretPos: caretPos.utf16Offset(in: candidatePreview))
      } else {
        if inlinePreedit {
          show(preedit: preedit, selRange: NSRange(location: start.utf16Offset(in: preedit), length: preedit.utf16.distance(from: start, to: end)), caretPos: caretPos.utf16Offset(in: preedit))
        } else {
          // Use a full-width space placeholder to prevent iTerm2 from echoing raw preedit;
          // half-width placeholders make the Chinese composition baseline unstable.
          show(preedit: preedit.isEmpty ? "" : "　", selRange: NSRange(location: 0, length: 0), caretPos: 0)
        }
      }

      let numCandidates = Int(ctx.menu.num_candidates)
      var candidates = [String]()
      var comments = [String]()
      for i in 0..<numCandidates {
        let candidate = ctx.menu.candidates[i]
        candidates.append(candidate.text.map { String(cString: $0) } ?? "")
        comments.append(candidate.comment.map { String(cString: $0) } ?? "")
      }
      if !TelepathyPreferences.shared.enabled(.annotations) { comments = Array(repeating: "", count: numCandidates) }
      var labels = [String]()
      // swiftlint:disable identifier_name
      if let select_keys = ctx.menu.select_keys {
        labels = String(cString: select_keys).map { String($0) }
      } else if let select_labels = ctx.select_labels {
        let pageSize = Int(ctx.menu.page_size)
        for i in 0..<pageSize {
          labels.append(select_labels[i].map { String(cString: $0) } ?? "")
        }
      }
      // swiftlint:enable identifier_name
      let page = Int(ctx.menu.page_no)
      let lastPage = ctx.menu.is_last_page

      let raw = rimeAPI.get_input(session).map { String(cString: $0) } ?? ""
      let confirmed = String(preedit[..<start])
      let pending = String(preedit[start..<end]).replacingOccurrences(of: " ", with: "")
      let caret = Int(rimeAPI.get_caret_pos(session))
      let nativeHighlight = Int(ctx.menu.highlighted_candidate_index)
      let signature = "\(raw)|\(confirmed)|\(caret)|\(page)|" + candidates.joined(separator: "\u{1f}")
      if raw.isEmpty || candidates.isEmpty || !rankingEnabled {
        invalidateRanking()
        compositionPrefix = ""
      } else if page != 0 {
        invalidateRanking(resetIntent: false)
        intent.update(raw: raw, revision: ranking.revision)
        intent.forceChinese()
      } else if signature != ranking.key {
        let wasEmpty = ranking.key.isEmpty
        invalidateRanking(resetIntent: false)
        if wasEmpty { compositionPrefix = precedingText() }
        let revision = ranking.reset(key: signature, count: candidates.count)
        intent.update(raw: raw, revision: revision)
        let snapshotWords = candidates
        var ends = [Int32](repeating: -1, count: candidates.count)
        ends.withUnsafeMutableBufferPointer { tp_candidate_ends(session, Int32(candidates.count), $0.baseAddress) }
        let prefix = String((compositionPrefix + confirmed).suffix(512))
        let payload: [String: Any] = ["revision": revision, "prefix": prefix, "pinyin": raw, "pending": pending,
                                    "candidates": snapshotWords, "candidate_ends": ends.map(Int.init),
                                    "strategy": TelepathyPreferences.shared.rankingStrategy]
        let data = try? JSONSerialization.data(withJSONObject: payload)
        let deadline = DispatchTime.now() + 0.085
        if automaticLanguageEnabled && confirmed.isEmpty && caret == raw.utf8.count, let data {
          // Start during the existing ranking debounce. Replies can only change
          // the current uncommitted snapshot and cannot override manual choices.
          DecisionTransport.language.submit(data) { [weak self] result in
            guard let self, self.automaticLanguageEnabled, !self.ranking.frozen,
                  self.ranking.revision == revision else { return }
            let language = result?["status"] as? String == "ok" ? result?["language"] as? String ?? "uncertain" : "uncertain"
            // A manual language override rejects the judgment, while an edited
            // Chinese snapshot can still use ordinary candidate ranking.
            _ = self.intent.apply(language, revision: revision)
            if self.intent.english { self.rankingDelay?.cancel(); self.rankingDelay = nil }
            else { self.scheduleRanking(data, revision: revision, deadline: deadline) }
            self.rimeUpdate(clearReservedComments: false)
          }
        } else {
          if automaticLanguageEnabled { intent.forceChinese() }
          else { intent.invalidate(revision: revision) }
          if let data { scheduleRanking(data, revision: revision, deadline: deadline) }
        }
      }
      if intent.english {
        show(preedit: raw, selRange: NSRange(location: 0, length: raw.utf16.count), caretPos: raw.utf16.count)
        hidePalettes()
        _ = rimeAPI.free_context(&ctx)
        return
      }
      var shownHighlight = nativeHighlight
      if ranking.order.count == candidates.count {
        let nativeWords = candidates, nativeComments = comments
        candidates = ranking.order.map { nativeWords[$0] }
        comments = ranking.order.map { nativeComments[$0] }
        shownHighlight = ranking.displayIndex(nativeHighlight) ?? 0
        if TelepathyPreferences.shared.enabled(.timing), !rankingNote.isEmpty && !comments.isEmpty { comments[0] = rankingNote }
      }
      displayedHighlight = shownHighlight
      let selRange = NSRange(location: start.utf16Offset(in: preedit), length: preedit.utf16.distance(from: start, to: end))
      showPanel(preedit: inlinePreedit ? "" : preedit, selRange: selRange, caretPos: caretPos.utf16Offset(in: preedit),
                candidates: candidates, comments: comments, labels: labels, highlighted: shownHighlight,
                page: page, lastPage: lastPage)
      _ = rimeAPI.free_context(&ctx)
    } else {
      hidePalettes()
    }
  }

  func commit(string: String) {
    guard let client = client else { return }

    let forceMarkedText =
      session != 0 &&
      rimeAPI.get_option(session, "force_marked_text_for_direct_commit")

    // Direct commits such as full-width punctuation do not necessarily have an
    // active marked-text phase. Some NSTextInputClient implementations require
    // one before accepting insertText.
    if forceMarkedText && preedit.isEmpty && !string.isEmpty {
      let markedText = NSMutableAttributedString(string: string)
      client.setMarkedText(
        markedText,
        selectionRange: NSRange(location: markedText.length, length: 0),
        replacementRange: .empty
      )
    }

    fallbackHistory = String((fallbackHistory + string).suffix(512))
    invalidateRanking()
    client.insertText(string, replacementRange: .empty)
    preedit = ""
    hidePalettes()
  }

  func show(preedit: String, selRange: NSRange, caretPos: Int) {
    guard let client = client else { return }
    if self.preedit == preedit && self.caretPos == caretPos && self.selRange == selRange {
      return
    }

    self.preedit = preedit
    self.caretPos = caretPos
    self.selRange = selRange

    let start = selRange.location
    let attrString = NSMutableAttributedString(string: preedit)
    if start > 0 {
      let attrs = mark(forStyle: kTSMHiliteConvertedText, at: NSRange(location: 0, length: start))! as! [NSAttributedString.Key: Any]
      attrString.setAttributes(attrs, range: NSRange(location: 0, length: start))
    }
    let remainingRange = NSRange(location: start, length: preedit.utf16.count - start)
    let attrs = mark(forStyle: kTSMHiliteSelectedRawText, at: remainingRange)! as! [NSAttributedString.Key: Any]
    attrString.setAttributes(attrs, range: remainingRange)
    client.setMarkedText(attrString, selectionRange: NSRange(location: caretPos, length: 0), replacementRange: .empty)
  }

  // swiftlint:disable:next function_parameter_count
  func showPanel(preedit: String, selRange: NSRange, caretPos: Int, candidates: [String], comments: [String], labels: [String], highlighted: Int, page: Int, lastPage: Bool) {
    guard let client = client else { return }
    var inputPos = NSRect()
    client.attributes(forCharacterIndex: 0, lineHeightRectangle: &inputPos)
    if let panel = NSApp.squirrelAppDelegate.panel {
      panel.position = inputPos
      panel.inputController = self
      panel.update(preedit: preedit, selRange: selRange, caretPos: caretPos, candidates: candidates, comments: comments, labels: labels,
                   highlighted: highlighted, page: page, lastPage: lastPage, update: true)
    }
  }

  private func handleASCIIModeToggle(_ notification: Notification) {
    guard let enableASCII = notification.object as? Bool else { return }
    guard session != 0 && rimeAPI.find_session(session) else { return }

    rimeAPI.set_option(session, "ascii_mode", enableASCII)
    rimeUpdate()
  }

  private func reportASCIIMode(_: Notification) {
    guard client != nil else { return }
    guard session != 0 && rimeAPI.find_session(session) else { return }

    let isASCIIMode = rimeAPI.get_option(session, "ascii_mode")
    let status = isASCIIMode ? "ascii" : "nascii"

    DistributedNotificationCenter.default().postNotificationName(
      .init("TelepathyASCIIModeResponse"),
      object: status
    )
  }

}

private extension SquirrelInputController {
  func precedingText() -> String {
    guard let client = client else { return "" }
    let marked = client.markedRange()
    let selected = client.selectedRange()
    let position = marked.location != NSNotFound ? marked.location : selected.location
    guard position != NSNotFound, position >= 0 else { return fallbackHistory }
    if position == 0 { return "" }
    let length = min(512, position)
    let range = NSRange(location: position - length, length: length)
    guard let text = client.attributedSubstring(from: range)?.string else { return fallbackHistory }
    return String(text.suffix(512))
  }
}
