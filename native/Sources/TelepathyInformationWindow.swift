import AppKit

private final class TelepathyUtilityWindow: NSWindow {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown,
          event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command else {
      return super.performKeyEquivalent(with: event)
    }
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "c": return firstResponder?.tryToPerform(#selector(NSText.copy(_:)), with: nil) ?? false
    case "a": return firstResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: nil) ?? false
    case "w": performClose(nil); return true
    default: return super.performKeyEquivalent(with: event)
    }
  }
}

// A retained native window, independent of external editors and file associations.
final class TelepathyInformationWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTabViewDelegate {
  private struct License {
    let title: String
    let url: URL
  }
  private var licenses = [License]()
  private let licenseTable = NSTableView()
  private let licenseText = NSTextView()
  private let tabs = NSTabView()
  private var settingsView: TelepathySettingsView?

  init(bundle: Bundle = .main) {
    let window = TelepathyUtilityWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
    window.title = "Telepathy"
    window.minSize = NSSize(width: 620, height: 420)
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.setFrameAutosaveName("TelepathyInformationWindow")
    window.center()
    guard let content = window.contentView else { return }

    let title = NSTextField(labelWithString: "Project Telepathy")
    title.font = .systemFont(ofSize: 24, weight: .semibold)
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let subtitle = NSTextField(labelWithString: version.isEmpty ? "Settings, credits and open-source licenses" : "Version \(version)")
    subtitle.textColor = .secondaryLabelColor
    let header = NSStackView(views: [title, subtitle])
    header.orientation = .vertical
    header.alignment = .leading
    header.spacing = 4
    header.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(header)

    tabs.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(tabs)
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
      header.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
      header.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
      tabs.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
      tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
      tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
      tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
    ])

    let settings = TelepathySettingsView(bundle: bundle)
    settingsView = settings
    let settingsTab = NSTabViewItem(identifier: "settings")
    settingsTab.label = "Settings"; settingsTab.view = settings
    tabs.addTabViewItem(settingsTab)
    let creditsText = NSTextView()
    let creditsScroll = reader(creditsText)
    if let url = bundle.url(forResource: "CREDITS", withExtension: "md"),
       let markdown = try? String(contentsOf: url, encoding: .utf8) {
      creditsText.textStorage?.setAttributedString(Self.renderCredits(markdown))
    }
    let creditsTab = NSTabViewItem(identifier: "credits")
    creditsTab.label = "Credits"
    creditsTab.view = creditsScroll
    tabs.addTabViewItem(creditsTab)

    if let ownLicense = bundle.url(forResource: "LICENSE", withExtension: nil) {
      licenses.append(License(title: "Telepathy · GPL-3.0", url: ownLicense))
    }
    if let root = bundle.resourceURL?.appendingPathComponent("licenses"),
       let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
      var dependencies = [License]()
      for case let url as URL in files {
        if url.lastPathComponent == "__pycache__" {
          files.skipDescendants()
          continue
        }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              !["json", "pyc"].contains(url.pathExtension.lowercased()) else { continue }
        let relative = String(url.path.dropFirst(root.path.count + 1))
        dependencies.append(License(title: relative, url: url))
      }
      licenses += dependencies.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
    split.isVertical = true
    split.dividerStyle = .thin
    let sidebar = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 480))
    sidebar.hasVerticalScroller = true
    sidebar.autohidesScrollers = true
    let column = NSTableColumn(identifier: .init("license"))
    column.width = 240
    licenseTable.addTableColumn(column)
    licenseTable.headerView = nil
    licenseTable.rowHeight = 26
    licenseTable.dataSource = self
    licenseTable.delegate = self
    licenseTable.allowsEmptySelection = false
    licenseTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    sidebar.documentView = licenseTable
    split.addArrangedSubview(sidebar)
    split.addArrangedSubview(reader(licenseText))
    split.setPosition(240, ofDividerAt: 0)
    let licenseTab = NSTabViewItem(identifier: "licenses")
    licenseTab.label = "Licenses"
    licenseTab.view = split
    tabs.addTabViewItem(licenseTab)
    licenseTable.reloadData()
    if !licenses.isEmpty {
      licenseTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
      showLicense(0)
    }
    tabs.selectTabViewItem(creditsTab)
    tabs.delegate = self
  }

  required init?(coder: NSCoder) { nil }

  func selectTab(_ identifier: String) {
    if let tab = tabs.tabViewItems.first(where: { $0.identifier as? String == identifier }) {
      if tabs.selectedTabViewItem === tab { refreshSettings(ifSelected: tab) }
      else { tabs.selectTabViewItem(tab) }
    }
  }

  func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    if let tabViewItem { refreshSettings(ifSelected: tabViewItem) }
  }

  private func refreshSettings(ifSelected tab: NSTabViewItem) {
    if tab.identifier as? String == "settings" { settingsView?.reload(); settingsView?.refreshModelStatus() }
  }

  private func reader(_ text: NSTextView) -> NSScrollView {
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.autoresizingMask = [.width, .height]
    text.frame = scroll.bounds
    text.isEditable = false
    text.isSelectable = true
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = false
    text.autoresizingMask = [.width]
    text.minSize = NSSize(width: 0, height: 0)
    text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    text.textContainer?.widthTracksTextView = true
    text.textContainerInset = NSSize(width: 16, height: 16)
    text.font = .systemFont(ofSize: 13)
    text.backgroundColor = .textBackgroundColor
    text.textColor = .textColor
    scroll.documentView = text
    return scroll
  }

  // The bundled credits use headings, paragraphs, links and a three-column
  // component table. Present the table as readable component sections.
  private static func renderCredits(_ markdown: String) -> NSAttributedString {
    let result = NSMutableAttributedString()
    func append(_ text: String, heading: Bool = false) {
      let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
      let part = parsed.map { NSMutableAttributedString(attributedString: NSAttributedString($0)) } ?? NSMutableAttributedString(string: text)
      part.addAttributes([.font: NSFont.systemFont(ofSize: heading ? 16 : 13, weight: heading ? .semibold : .regular),
                          .foregroundColor: NSColor.labelColor], range: NSRange(location: 0, length: part.length))
      result.append(part)
    }
    for line in markdown.components(separatedBy: "\n") {
      if line.hasPrefix("| ") {
        let cells = line.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count == 3, cells[0] != "Component", !cells[0].hasPrefix("---") else { continue }
        append(cells[0] + "\n", heading: true)
        append(cells[1] + "\n" + cells[2] + "\n\n")
      } else if line.hasPrefix("# ") {
        continue
      } else if line.hasPrefix("## ") {
        append(String(line.dropFirst(3)) + "\n\n", heading: true)
      } else {
        append(line + "\n")
      }
    }
    return result
  }

  func numberOfRows(in tableView: NSTableView) -> Int { licenses.count }
  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    licenses.indices.contains(row) ? licenses[row].title : nil
  }
  func tableViewSelectionDidChange(_ notification: Notification) { showLicense(licenseTable.selectedRow) }
  private func showLicense(_ row: Int) {
    guard licenses.indices.contains(row) else { licenseText.string = ""; return }
    licenseText.string = (try? String(contentsOf: licenses[row].url, encoding: .utf8)) ?? "Unable to read this bundled license file."
    licenseText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    licenseText.scrollRangeToVisible(NSRange(location: 0, length: 0))
  }
}
