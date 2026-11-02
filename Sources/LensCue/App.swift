import AppKit
import SwiftUI
import AVFoundation
import Speech
import Combine
import CueCore

@MainActor final class Model: ObservableObject {
    static let shared = Model()
    @Published var script: String { didSet { UserDefaults.standard.set(script, forKey: "script"); tracker = WordTracker(script: script); position = 0; onLayout?() } }
    @Published var fontSize: Double { didSet { save("font", fontSize); onLayout?() } }
    @Published var width: Double { didSet { save("width", width); onLayout?() } }
    @Published var height: Double { didSet { save("height", height); onLayout?() } }
    @Published var speed: Double { didSet { save("speed", speed) } }
    @Published var sensitivity: Double { didSet { save("sensitivity", sensitivity) } }
    @Published var mode: Int { didSet { UserDefaults.standard.set(mode, forKey: "mode"); if running { stop() } } }
    @Published var running = false
    @Published var status = "Ready when you are"
    @Published var level = 0.0
    @Published var speaking = false
    @Published var position = 0
    @Published var hovered = false
    var tracker: WordTracker
    var voice: VoiceService?
    var onLayout: (() -> Void)?
    var onSeek: (() -> Void)?
    var onFailure: (() -> Void)?
    init() {
        let d = UserDefaults.standard
        let text = d.string(forKey: "script") ?? "Welcome. Take a breath, and look toward the camera.\n\nThis is LensCue, your free voice-following teleprompter.\n\nPaste your own script in the editor, then press Start presenting. The words stay close to the camera, so you can read naturally.\n\nSpeak at your own pace. Pause whenever you need to. Your script waits for you."
        script = text; tracker = WordTracker(script: text)
        fontSize = d.object(forKey: "font") as? Double ?? 20
        width = d.object(forKey: "width") as? Double ?? 360
        height = d.object(forKey: "height") as? Double ?? 150
        speed = d.object(forKey: "speed") as? Double ?? 32
        sensitivity = d.object(forKey: "sensitivity") as? Double ?? 0.012
        mode = d.integer(forKey: "mode")
    }
    func save(_ key: String, _ value: Double) { UserDefaults.standard.set(value, forKey: key) }
    func toggle() { running ? stop() : start() }
    func start() {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "Paste a script first"; return }
        if position >= tracker.words.count { reset() }
        running = true
        if mode == 2 { status = "Auto-scroll"; return }
        status = "Preparing microphone…"
        let service = VoiceService(model: self)
        voice = service
        Task { await service.start() }
    }
    func stop() { running = false; voice?.stop(); voice = nil; speaking = false; level = 0; status = "Paused" }
    func reset() { tracker.seek(0); position = 0; onSeek?() }
    func seek(_ index: Int) { tracker.seek(index); position = tracker.position; onSeek?() }
    func heard(_ text: String) {
        guard running, !hovered else { return }
        position = tracker.follow(text)
        if position >= tracker.words.count { stop(); status = "Finished · Restart to read again" }
    }
    func failed(_ message: String) { stop(); status = message; onFailure?() }
}

@MainActor final class VoiceService {
    weak var model: Model?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var rotation: Timer?
    private var tapped = false
    private var generation = 0
    private var stopped = false
    init(model: Model) { self.model = model }
    func start() async {
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard !stopped, model?.running == true else { return }
        guard mic else { model?.failed("Allow Microphone in System Settings → Privacy & Security"); return }
        if model?.mode == 0 {
            let permission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard !stopped, model?.running == true else { return }
            guard permission == .authorized else { model?.failed("Allow Speech Recognition, or choose Voice activity"); return }
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            guard recognizer?.supportsOnDeviceRecognition == true else { model?.failed("Offline English recognition unavailable. Choose Voice activity."); return }
            beginRecognition()
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { model?.failed("No microphone found"); return }
        // Audio callback owns the gate; only scalar values cross to the main actor.
        var gate = VoiceGate()
        let threshold = model?.sensitivity ?? 0.012
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum = 0.0
            for i in 0..<count { sum += Double(samples[i] * samples[i]) }
            let rms = sqrt(sum / Double(count))
            let active = gate.update(rms: rms, time: ProcessInfo.processInfo.systemUptime, threshold: threshold)
            Task { @MainActor [weak self] in
                guard let self, self.model?.running == true else { return }
                self.request?.append(buffer)
                self.model?.level = min(1, rms * 12)
                self.model?.speaking = active
                self.model?.status = self.model?.hovered == true ? "Hover paused" : (active ? "Listening to you" : "Waiting for your voice")
            }
        }
        tapped = true
        do { engine.prepare(); try engine.start() }
        catch { model?.failed("Microphone could not start: \(error.localizedDescription)") }
    }
    private func beginRecognition() {
        generation += 1
        let token = generation
        task?.cancel(); request?.endAudio()
        model?.tracker.newUtterance()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.taskHint = .dictation
        req.contextualStrings = Array((model?.script.components(separatedBy: .newlines) ?? []).filter { !$0.isEmpty }.prefix(40))
        request = req
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.model?.running == true else { return }
                if let text { self.model?.heard(text) }
                if final { self.beginRecognition() }
                else if let message { self.model?.failed("Word tracking stopped: \(message). Try Voice activity.") }
            }
        }
        rotation?.invalidate()
        rotation = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
            Task { @MainActor in if self?.model?.running == true { self?.beginRecognition() } }
        }
    }
    func stop() {
        stopped = true
        generation += 1; rotation?.invalidate(); rotation = nil
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil
    }
}

final class CuePanel: NSPanel { override var canBecomeKey: Bool { false } }
@MainActor final class CueView: NSView {
    let model: Model
    var timer: Timer?
    var offset = 0.0
    var target = 0.0
    var textHeight = 0.0
    var notchInset: CGFloat = 0
    var bodyHeight: CGFloat { bounds.height - notchInset }
    var wordRects: [(Int, NSRect)] = []
    var cachedKey = ""
    var cachedStorage: NSTextStorage?
    var cachedLayout: NSLayoutManager?
    var cachedContainer: NSTextContainer?
    var cachedRects: [(Int, NSRect)] = []
    var lastTick = ProcessInfo.processInfo.systemUptime
    var lastPosition = -1
    var lastRunning = false
    var lastHover = false
    var lastOffset = -1.0
    override var isFlipped: Bool { true }
    init(model: Model) {
        self.model = model
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("LensCue teleprompter. Hover to pause, scroll to navigate, double click to edit.")
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { model.hovered = true }
    override func mouseExited(with event: NSEvent) { model.hovered = false }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { (NSApp.delegate as? AppDelegate)?.showEditor(); return }
        let point = convert(event.locationInWindow, from: nil)
        if let hit = wordRects.first(where: { $0.1.contains(point) }) { model.seek(hit.0) }
    }
    override func scrollWheel(with event: NSEvent) {
        offset = max(0, min(max(0, textHeight - bodyHeight + 30), offset - event.scrollingDeltaY * 2))
        target = offset
        // In word mode, align the recognizer's search window with the manually chosen line.
        if model.mode == 0, let nearest = wordRects.min(by: { abs($0.1.midY - notchInset - 20) < abs($1.1.midY - notchInset - 20) }) {
            model.tracker.seek(nearest.0); model.position = nearest.0
        }
        needsDisplay = true
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, now - lastTick); lastTick = now
        if model.running && !model.hovered {
            if model.mode == 0 {
                offset += (target - offset) * min(1, dt * 10)
            } else if model.mode == 2 || model.speaking {
                offset += model.speed * dt; target = offset
                let end = max(0, textHeight - bodyHeight + 30)
                if offset >= end && end > 0 { offset = end; model.stop(); model.status = "Finished · Restart to read again" }
            }
        }
        if model.position != lastPosition || model.running != lastRunning || model.hovered != lastHover || abs(offset - lastOffset) > 0.1 {
            lastPosition = model.position; lastRunning = model.running; lastHover = model.hovered; lastOffset = offset
            needsDisplay = true
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 22, yRadius: 22)
        shape.appendRect(NSRect(x: 0, y: 0, width: bounds.width, height: 24))
        NSColor.black.setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        let key = "\(model.script)|\(model.fontSize)|\(bounds.width)"
        if key != cachedKey {
            cachedKey = key
            let style = NSMutableParagraphStyle()
            style.alignment = .center; style.lineSpacing = 7; style.paragraphSpacing = 14
            let font = NSFont.monospacedSystemFont(ofSize: model.fontSize, weight: .medium)
            let storage = NSTextStorage(string: model.script, attributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.82), .paragraphStyle: style])
            let layout = NSLayoutManager()
            let container = NSTextContainer(containerSize: NSSize(width: bounds.width - 36, height: 100000))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container); storage.addLayoutManager(layout); layout.ensureLayout(for: container)
            cachedStorage = storage; cachedLayout = layout; cachedContainer = container
            cachedRects = model.tracker.words.enumerated().map { i, word in
                let range = layout.glyphRange(forCharacterRange: word.range, actualCharacterRange: nil)
                return (i, layout.boundingRect(forGlyphRange: range, in: container))
            }
        }
        guard let storage = cachedStorage, let layout = cachedLayout, let container = cachedContainer else { return }
        storage.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.82), range: NSRange(location: 0, length: storage.length))
        textHeight = layout.usedRect(for: container).height + 28
        let words = model.tracker.words
        if model.mode == 0 && model.position > 0 {
            let end = words[min(model.position, words.count)-1].range.upperBound
            storage.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.32), range: NSRange(location: 0, length: end))
        }
        if model.mode == 0 && model.position < words.count {
            let range = words[model.position].range
            storage.addAttribute(.foregroundColor, value: NSColor.white, range: range)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let box = layout.boundingRect(forGlyphRange: glyphs, in: container)
            target = max(0, box.minY)
        }
        // The background reaches the display edge; words stay below the camera.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: notchInset + 4, width: bounds.width, height: bodyHeight - 18)).addClip()
        let origin = NSPoint(x: 18, y: notchInset + 6 - offset)
        let glyphs = layout.glyphRange(for: container)
        layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
        wordRects = cachedRects.map { ($0.0, $0.1.offsetBy(dx: origin.x, dy: origin.y)) }
        NSGraphicsContext.restoreGraphicsState()
        // Tiny status indicator leaves the text and camera area uncluttered.
        let color: NSColor = model.running ? (model.hovered ? .systemOrange : .systemGreen) : .darkGray
        color.setFill(); NSBezierPath(ovalIn: NSRect(x: bounds.midX - 2, y: bounds.height - 10, width: 4, height: 4)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

struct Editor: View {
    @ObservedObject var model: Model
    let present: () -> Void
    let preview: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "viewfinder").font(.system(size: 25, weight: .medium)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("LensCue").font(.system(size: 22, weight: .semibold))
                    Text("Your words. Right by the camera.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: preview) { Image(systemName: "rectangle.topthird.inset.filled") }.help("Show or hide the camera overlay")
                Button(action: present) { Label(model.running ? "Pause" : "Start presenting", systemImage: model.running ? "pause.fill" : "mic.fill") }
                    .buttonStyle(.borderedProminent).tint(.mint).keyboardShortcut(.return, modifiers: .command)
            }.padding(24)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("SCRIPT").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Import…", action: importText).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    TextEditor(text: $model.script).font(.system(size: 19)).lineSpacing(7)
                        .scrollContentBackground(.hidden).padding(10)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Text("\(model.tracker.words.count) words · Saved on this Mac").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart", action: model.reset).buttonStyle(.plain).font(.system(size: 12))
                    }
                }.padding(24)
                Divider()
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        caption("VOICE & PACE")
                        Picker("Scrolling", selection: $model.mode) {
                            Text("Follow my words").tag(0)
                            Text("Voice activity").tag(1)
                            Text("Auto-scroll").tag(2)
                        }.labelsHidden()
                        Text(model.mode == 0 ? "Recognizes English on this Mac and follows your place in the script." : model.mode == 1 ? "Scrolls while you speak. Pauses when you stop. Adjust sensitivity before starting." : "Scrolls at a steady pace. Hover over the overlay to pause.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        caption("CAMERA OVERLAY")
                        control("Text size", value: $model.fontSize, range: 14...32, unit: "pt")
                        control("Width", value: $model.width, range: 260...560, unit: "pt")
                        control("Height", value: $model.height, range: 90...260, unit: "pt")
                        if model.mode != 0 { control("Speed", value: $model.speed, range: 10...90, unit: "pt/s") }
                        if model.mode == 1 {
                            Text("Mic threshold").font(.system(size: 12))
                            Slider(value: $model.sensitivity, in: 0.002...0.06)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            Circle().fill(model.running ? Color.mint : Color.gray).frame(width: 6, height: 6)
                            Text(model.status).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                        }
                        ProgressView(value: model.level).tint(.mint)
                    }
                    Spacer(minLength: 0)
                    Text("Hover to pause · Scroll to move\nClick a word to resume there\nDouble-click the overlay to edit\n⌘⇧L to show or hide")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
                    Text("Free. Local. No account.").font(.system(size: 11)).foregroundStyle(.tertiary)
                }.padding(24).frame(width: 265)
            }
        }.frame(minWidth: 800, minHeight: 570).background(Color(nsColor: NSColor(calibratedWhite: 0.085, alpha: 1))).preferredColorScheme(.dark)
    }
    func caption(_ text: String) -> some View { Text(text).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary) }
    func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue)) \(unit)").foregroundStyle(.secondary).monospacedDigit() }.font(.system(size: 12))
            Slider(value: value, in: range)
        }
    }
    func importText() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) { model.stop(); model.script = text }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = Model.shared
    var editor: NSWindow!
    var overlay: CuePanel!
    var cue: CueView!
    var statusItem: NSStatusItem!
    var monitors: [Any] = []
    var verificationTask: SFSpeechRecognitionTask?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenus()
        editor = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        editor.title = "LensCue"; editor.isReleasedWhenClosed = false; editor.delegate = self
        editor.contentView = NSHostingView(rootView: Editor(model: model, present: { [weak self] in self?.present() }, preview: { [weak self] in self?.toggleOverlay() }))
        editor.minSize = NSSize(width: 800, height: 570); editor.center()
        overlay = CuePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.title = "LensCue Camera Overlay"; overlay.isOpaque = false; overlay.backgroundColor = .clear
        overlay.level = .statusBar; overlay.hasShadow = false; overlay.hidesOnDeactivate = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        cue = CueView(model: model); overlay.contentView = cue
        model.onLayout = { [weak self] in self?.positionOverlay() }
        model.onSeek = { [weak self] in self?.cue.offset = 0; self?.cue.target = 0 }
        model.onFailure = { [weak self] in self?.showEditor() }
        positionOverlay(); overlay.orderFrontRegardless(); showEditor()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.positionOverlay() } }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in self?.shortcut(event) }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in self?.shortcut(event); return event }) { monitors.append(monitor) }
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--verify-speech"), args.count > flag + 2 {
            verifySpeech(audio: args[flag + 1], report: args[flag + 2])
        }
    }
    // Developer verification exercises the same on-device recognizer with a deterministic audio fixture.
    func verifySpeech(audio: String, report: String) {
        Task {
            let permission = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
            guard permission == .authorized, let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.supportsOnDeviceRecognition else {
                try? "Recognition permission or offline model unavailable".write(toFile: report, atomically: true, encoding: .utf8); return
            }
            let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: audio))
            request.requiresOnDeviceRecognition = true
            verificationTask = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let transcript = result.bestTranscription.formattedString
                    var tracker = WordTracker(script: "Welcome to my presentation. Today we will explore the ocean and discover a whole new world together. Thank you for listening.")
                    // Feed successive partials as the live recognizer does.
                    let words = transcript.split(separator: " ")
                    for i in 1...max(1, words.count) { tracker.follow(words.prefix(i).joined(separator: " ")) }
                    let json: [String: Any] = ["transcript": transcript, "matchedWords": tracker.position, "scriptWords": tracker.words.count, "onDevice": true]
                    if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: report)) }
                } else if let error { try? error.localizedDescription.write(toFile: report, atomically: true, encoding: .utf8) }
            }
        }
    }
    func positionOverlay() {
        // Prefer the notched display even when an external monitor is primary.
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else { return }
        let inset = screen.safeAreaInsets.top
        let w = min(model.width, screen.frame.width - 30)
        cue.notchInset = inset
        overlay.setFrame(NSRect(x: screen.frame.midX - w/2, y: screen.frame.maxY - inset - model.height, width: w, height: model.height + inset), display: true)
        cue.needsDisplay = true
    }
    func present() {
        model.toggle(); overlay.orderFrontRegardless()
        if model.running { editor.orderOut(nil) }
    }
    @objc func showEditor() { editor.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggleOverlay() { if overlay.isVisible { overlay.orderOut(nil) } else { overlay.orderFrontRegardless() } }
    @objc func togglePlayback() { present() }
    @objc func restart() { model.reset() }
    @objc func quit() { model.stop(); NSApp.terminate(nil) }
    func shortcut(_ event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains([.command, .shift]), event.charactersIgnoringModifiers?.lowercased() == "l" { toggleOverlay() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showEditor(); return true }
    func buildMenus() {
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let app = NSMenu(); item.submenu = app
        app.addItem(withTitle: "Edit script", action: #selector(showEditor), keyEquivalent: "e").target = self
        app.addItem(withTitle: "Show / hide overlay", action: #selector(toggleOverlay), keyEquivalent: "").target = self
        app.addItem(withTitle: "Start / pause", action: #selector(togglePlayback), keyEquivalent: "").target = self
        app.addItem(withTitle: "Restart script", action: #selector(restart), keyEquivalent: "0").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit LensCue", action: #selector(quit), keyEquivalent: "q").target = self
        let editRoot = NSMenuItem(); menu.addItem(editRoot)
        let edit = NSMenu(title: "Edit"); editRoot.submenu = edit
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "LensCue")
        statusItem.menu = app.copy() as? NSMenu
    }
}
@main struct LensCueMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
