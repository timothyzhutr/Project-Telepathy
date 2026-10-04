import AppKit

private final class TelepathySettingsDocument: NSView {
  override var isFlipped: Bool { true }
}

final class TelepathySettingsView: NSView {
  private let preferences: TelepathyPreferences
  private let bundle: Bundle
  private let rows = NSPopUpButton()
  private let rankCount = NSPopUpButton()
  private let shownCount = NSPopUpButton()
  private let font = NSSlider(value: 16, minValue: 12, maxValue: 28, target: nil, action: nil)
  private let fontLabel = NSTextField(labelWithString: "16 pt")
  private let appearancePopup = NSPopUpButton()
  private let rankingPopup = NSPopUpButton()
  private let preview = NSTextField(wrappingLabelWithString: "")
  private let modelStatus = NSTextField(wrappingLabelWithString: "Checking model status…")
  private var toggles = [TelepathyPreferences.Key: NSButton]()
  private var observer: NSObjectProtocol?
  private var assistanceEnabled: Bool?
  private var download: Process?
  private let downloadButton = NSButton(title: "Download / repair model", target: nil, action: nil)

  init(preferences: TelepathyPreferences = .shared, bundle: Bundle = .main) {
    self.preferences = preferences
    self.bundle = bundle
    super.init(frame: .zero)
    let scroll = NSScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
    let document = TelepathySettingsDocument()
    scroll.documentView = document
    document.translatesAutoresizingMaskIntoConstraints = false
    let stack = NSStackView()
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(stack)
    NSLayoutConstraint.activate([
      document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
      stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
      stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)
    ])
    func add(_ view: NSView) {
      stack.addArrangedSubview(view)
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    func heading(_ title: String) {
      let label = NSTextField(labelWithString: title)
      label.font = .systemFont(ofSize: 15, weight: .semibold)
      add(label)
    }
    func note(_ text: String) {
      let label = NSTextField(wrappingLabelWithString: text)
      label.textColor = .secondaryLabelColor; label.font = .systemFont(ofSize: 12)
      add(label)
    }
    func row(_ title: String, _ control: NSView) {
      let label = NSTextField(labelWithString: title)
      label.widthAnchor.constraint(equalToConstant: 185).isActive = true
      let line = NSStackView(views: [label, control, NSView()])
      line.alignment = .centerY; line.spacing = 16
      add(line)
    }
    func checkbox(_ title: String, _ key: TelepathyPreferences.Key) {
      let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggle(_:)))
      button.identifier = .init("settings." + key.rawValue)
      if key == .kev { button.identifier = .init("settings.kev") }
      if key == .autoLanguage { button.identifier = .init("settings.autoLanguage") }
      toggles[key] = button
      add(button)
    }
    heading("Candidate window")
    for count in TelepathyPreferences.countOptions {
      for popup in [shownCount, rankCount] {
        popup.addItem(withTitle: "\(count)"); popup.lastItem?.tag = count
      }
    }
    shownCount.identifier = .init("settings.shownCount"); shownCount.target = self; shownCount.action = #selector(changeShownCount(_:))
    row("Candidates to show", shownCount)
    note("Maximum candidates on each displayed page. Page Down or = reveals more; Page Up or − goes back.")
    for value in TelepathyPreferences.rowOptions {
      rows.addItem(withTitle: value == 0 ? "Automatic" : "\(value)")
      rows.lastItem?.tag = value
    }
    rows.identifier = .init("settings.rows"); rows.target = self; rows.action = #selector(changeRows(_:))
    row("Candidates per row", rows)
    note("Controls the layout of the visible candidates. Long phrases may wrap when they need more room.")
    font.identifier = .init("settings.font"); font.target = self; font.action = #selector(changeFont(_:))
    font.isContinuous = true; font.numberOfTickMarks = 9
    font.widthAnchor.constraint(equalToConstant: 220).isActive = true
    row("Text size", NSStackView(views: [font, fontLabel]))
    appearancePopup.addItems(withTitles: ["Follow system", "Light", "Dark"])
    appearancePopup.identifier = .init("settings.appearance"); appearancePopup.target = self; appearancePopup.action = #selector(changeAppearance(_:))
    row("Appearance", appearancePopup)
    let previewBox = NSBox()
    previewBox.title = "Preview"
    preview.translatesAutoresizingMaskIntoConstraints = false
    previewBox.contentView?.addSubview(preview)
    if let content = previewBox.contentView {
      NSLayoutConstraint.activate([
        preview.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
        preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
        preview.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
        preview.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
      ])
    }
    add(previewBox)
    checkbox("Show pinyin in the text field", .inlinePinyin)
    checkbox("Show candidate annotations", .annotations)
    checkbox("Show model timing on the chosen candidate", .timing)
    checkbox("Show the Chinese / English status icon in the menu bar", .statusIcon)
    heading("Typing")
    checkbox("Enable Kev assistance", .kev)
    note("Kev ranks candidates locally using preceding text. Turning assistance off stops the helper to free memory. Turning it on reloads the model while ordinary pinyin typing remains available.")
    rankCount.identifier = .init("settings.rankCount"); rankCount.target = self; rankCount.action = #selector(changeRankCount(_:))
    row("Candidates to rank", rankCount)
    note("Ranks up to this many candidates from Rime's first page, then shows the best ones. Remaining candidates keep their original order. A smaller pool can reduce scoring work but may miss a better word. With 1, there is no choice to rerank.")
    rankingPopup.addItems(withTitles: ["Context prediction (default)", "Kev decision ranking"])
    rankingPopup.identifier = .init("settings.rankingStrategy"); rankingPopup.target = self; rankingPopup.action = #selector(changeRanking(_:))
    row("Ranking method", rankingPopup)
    note("Context prediction uses the same local model to score which candidate naturally follows your text. It can be faster, but may still choose a poor match when all candidates are unsuitable.")
    checkbox("Automatic Chinese / English (experimental)", .autoLanguage)
    note("Uses context to keep English words literal. Requires Kev assistance. Space adds a space after English; ↓ or Tab restores Chinese choices. Shift + a letter starts literal English until the next space.")
    checkbox("Use Chinese punctuation", .punctuation)
    checkbox("Automatic punctuation in Auto mode", .autoPunctuation)
    note("Chooses Chinese or English forms from the current sentence, without waiting for Kev. Keeps decimals, URLs, email and backtick code ASCII. Turn off Use Chinese punctuation to always use ASCII forms.")
    note("Space chooses the highlighted candidate; 1–9 select candidates; Esc cancels composition. Personal dictionary learning is disabled in this prototype.")
    heading("Local model")
    add(modelStatus)
    let refresh = NSButton(title: "Refresh status", target: self, action: #selector(refreshModelStatus))
    let folder = NSButton(title: "Open model folder", target: self, action: #selector(openModelFolder))
    downloadButton.target = self; downloadButton.action = #selector(downloadModel)
    add(NSStackView(views: [refresh, folder, downloadButton, NSView()]))
    note("Model files are downloaded separately. Download / repair checks existing files and fetches any that are missing or damaged.")
    let reset = NSButton(title: "Restore default settings", target: self, action: #selector(resetSettings))
    add(NSStackView(views: [reset, NSView()]))
    note("Changes save automatically and apply to the next composition. Restoring defaults only resets these preferences.")
    observer = NotificationCenter.default.addObserver(forName: .telepathyPreferencesChanged, object: preferences, queue: .main) { [weak self] _ in
      guard let self else { return }
      let assistanceChanged = self.assistanceEnabled != self.preferences.enabled(.kev)
      self.reload()
      if assistanceChanged { self.refreshModelStatus() }
    }
    reload()
  }
  required init?(coder: NSCoder) { nil }
  deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

  func reload() {
    rows.selectItem(withTag: preferences.candidatesPerRow)
    rankCount.selectItem(withTag: preferences.candidatesToRank)
    shownCount.selectItem(withTag: preferences.candidatesToShow)
    rankCount.isEnabled = preferences.enabled(.kev)
    font.doubleValue = Double(preferences.fontSize); fontLabel.stringValue = "\(preferences.fontSize) pt"
    appearancePopup.selectItem(at: ["system", "light", "dark"].firstIndex(of: preferences.appearance) ?? 0)
    rankingPopup.selectItem(at: preferences.rankingStrategy == "kev" ? 1 : 0)
    rankingPopup.isEnabled = preferences.enabled(.kev)
    assistanceEnabled = preferences.enabled(.kev)
    toggles.forEach { $0.value.state = preferences.enabled($0.key) ? .on : .off }
    let samples = ["你好", "拟好", "你号", "倪好", "泥好", "你好啊", "您好", "你好呀", "你好吗", "你好吧", "你好哦", "你好呢"].prefix(preferences.candidatesToShow)
    preview.font = .systemFont(ofSize: CGFloat(preferences.fontSize))
    preview.stringValue = samples.enumerated().map { preferences.separator(before: $0.offset, linear: true) + "\($0.offset + 1). \($0.element)" }.joined()
  }
  @objc private func changeRows(_ sender: NSPopUpButton) { preferences.set(sender.selectedTag(), for: .rows) }
  @objc private func changeRankCount(_ sender: NSPopUpButton) { preferences.set(sender.selectedTag(), for: .rankCount) }
  @objc private func changeShownCount(_ sender: NSPopUpButton) { preferences.set(sender.selectedTag(), for: .shownCount) }
  @objc private func changeFont(_ sender: NSSlider) { preferences.set(Int(sender.doubleValue.rounded()), for: .font) }
  @objc private func changeAppearance(_ sender: NSPopUpButton) { preferences.set(["system", "light", "dark"][sender.indexOfSelectedItem], for: .appearance) }
  @objc private func changeRanking(_ sender: NSPopUpButton) { preferences.set(sender.indexOfSelectedItem == 1 ? "kev" : "continuation", for: .rankingStrategy) }
  @objc private func toggle(_ sender: NSButton) {
    if let key = toggles.first(where: { $0.value === sender })?.key { preferences.set(sender.state == .on, for: key) }
  }
  @objc private func resetSettings() { preferences.reset() }
  @objc private func openModelFolder() {
    let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Telepathy/models")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    NSWorkspace.shared.open(folder)
  }
  @objc func refreshModelStatus() {
    if download != nil { return }
    guard preferences.enabled(.kev) else {
      modelStatus.stringValue = "Kev assistance is off. The model helper stops to free memory."
      return
    }
    modelStatus.stringValue = "Checking model status…"
    var request = URLRequest(url: URL(string: "http://127.0.0.1:18765/api/health")!)
    request.timeoutInterval = 3
    URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
      let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      let valid = (response as? HTTPURLResponse)?.statusCode == 200 && json?["app"] as? String == "Telepathy"
      let status = valid ? json?["status"] as? String : nil
      DispatchQueue.main.async {
        guard let self, self.download == nil, self.preferences.enabled(.kev) else { return }
        self.modelStatus.stringValue = switch status {
        case "ready": "Kev is ready · Runs on this Mac"
        case "loading": "Kev is loading… Refresh in a moment."
        case "model_missing": "Model files are missing. Use Download / repair model to set up Kev."
        case "error": "Kev could not load. Try Download / repair model."
        default: "The local worker is not responding. Typing can continue with Rime candidates."
        }
      }
    }.resume()
  }
  @objc private func downloadModel() {
    guard download == nil else { return }
    let process = Process()
    process.executableURL = bundle.bundleURL.appendingPathComponent("Contents/Helpers/TelepathyWorker.app/Contents/MacOS/TelepathyWorker")
    process.arguments = ["--download-model"]
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    process.terminationHandler = { [weak self] process in
      DispatchQueue.main.async {
        guard let self else { return }
        self.download = nil; self.downloadButton.isEnabled = true
        if process.terminationStatus == 0 { self.reloadModel() }
        else { self.modelStatus.stringValue = "Model setup failed. Check the internet connection and available disk space, then try again." }
      }
    }
    do {
      try process.run(); download = process; downloadButton.isEnabled = false
      modelStatus.stringValue = "Checking / downloading model files… Keep Telepathy running until this finishes."
    } catch { modelStatus.stringValue = "The bundled model installer could not start." }
  }

  private func reloadModel() {
    guard preferences.enabled(.kev) else {
      modelStatus.stringValue = "Model files installed. Enable Kev assistance to load them."
      return
    }
    modelStatus.stringValue = "Model files verified. Loading Kev…"
    var request = URLRequest(url: URL(string: "http://127.0.0.1:18765/api/reload")!)
    request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 3
    URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        if (response as? HTTPURLResponse)?.statusCode == 202 { self.refreshModelStatus() }
        else { self.modelStatus.stringValue = "Model files verified. Reopen Telepathy to start the local worker." }
      }
    }.resume()
  }
}
