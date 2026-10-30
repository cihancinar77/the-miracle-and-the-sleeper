import SwiftUI
import AppKit

enum EndAction: String, CaseIterable, Identifiable {
    case shutdown, sleep
    var id: Self { self }
    var title: String { self == .shutdown ? "Shut Down" : "Sleep" }
}

// Accent taken from the "Parasomnia" cover: cold moonlight on teal-grey walls.
extension Color {
    static let moonlight = Color(red: 0.33, green: 0.56, blue: 0.60)
}

@MainActor
final class TimerModel: ObservableObject {
    @Published var minutes: Int = UserDefaults.standard.object(forKey: "minutes") as? Int ?? 45 {
        didSet { UserDefaults.standard.set(minutes, forKey: "minutes") }
    }
    @Published var action: EndAction = EndAction(rawValue: UserDefaults.standard.string(forKey: "action") ?? "") ?? .shutdown {
        didSet { UserDefaults.standard.set(action.rawValue, forKey: "action") }
    }
    @Published var wakeEnabled: Bool = UserDefaults.standard.bool(forKey: "wakeEnabled") {
        didSet { UserDefaults.standard.set(wakeEnabled, forKey: "wakeEnabled") }
    }
    @Published var wakeTime: Date = UserDefaults.standard.object(forKey: "wakeTime") as? Date
        ?? Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())! {
        didSet { UserDefaults.standard.set(wakeTime, forKey: "wakeTime") }
    }
    @Published private(set) var scheduledWake: Date?
    @Published private(set) var endDate: Date?
    @Published private(set) var now = Date()
    @Published var errorText: String?

    private var ticker: Timer?

    init() {
        // If the deadline passed while the Mac was asleep, don't shut down on wake — just drop the timer.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let end = self.endDate, end <= Date() else { return }
                self.stopTicker()
                self.scheduledWake = nil
            }
        }
    }

    var isRunning: Bool { endDate != nil }

    var remaining: TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSince(now)) }
    }

    func start() {
        errorText = nil
        // Ask for Automation permission now, not at 3 AM.
        if action == .shutdown, !runAppleScript("tell application \"System Events\" to get name") {
            return
        }
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        if wakeEnabled {
            let wake = nextWake(after: end)
            guard runAdminShell("pmset schedule wakeorpoweron '\(pmsetString(wake))'") else { return }
            scheduledWake = wake
        }
        endDate = end
        now = Date()
        ticker?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func extend(by mins: Int) {
        guard let end = endDate else { return }
        endDate = end.addingTimeInterval(Double(mins) * 60)
    }

    func cancel() {
        stopTicker()
        if let wake = scheduledWake {
            runAdminShell("pmset schedule cancel wakeorpoweron '\(pmsetString(wake))'")
            scheduledWake = nil
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }

    /// First occurrence of wakeTime's hour/minute after the timer ends.
    private func nextWake(after date: Date) -> Date {
        let c = Calendar.current.dateComponents([.hour, .minute], from: wakeTime)
        return Calendar.current.nextDate(after: date, matching: c, matchingPolicy: .nextTime)!
    }

    private func pmsetString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM/dd/yy HH:mm:ss"
        return f.string(from: date)
    }

    /// pmset schedule needs root; macOS shows its password dialog.
    @discardableResult
    private func runAdminShell(_ cmd: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(cmd)\" with administrator privileges")?.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) != -128 {
                errorText = "Couldn't schedule wake: \(error[NSAppleScript.errorMessage] ?? "?")"
            }
            return false
        }
        return true
    }

    private func tick() {
        now = Date()
        if let r = remaining, r <= 0 { fire() }
    }

    private func fire() {
        let action = self.action
        stopTicker()
        scheduledWake = nil  // keep the pmset entry so the Mac wakes in the morning
        switch action {
        case .shutdown:
            _ = runAppleScript("tell application \"System Events\" to shut down")
        case .sleep:
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["sleepnow"]
            try? p.run()
        }
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            errorText = "Permission needed: System Settings › Privacy & Security › Automation › Parasomnia. (\(error[NSAppleScript.errorNumber] ?? "?"))"
            return false
        }
        return true
    }
}

func format(_ t: TimeInterval) -> String {
    let s = Int(t.rounded(.up))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
}

extension View {
    /// Liquid Glass on macOS 26+, bordered buttons before that.
    @ViewBuilder func glassButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glass) } else { buttonStyle(.bordered) }
    }

    /// Control Center-style module background.
    @ViewBuilder func tile(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.thinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.08)))
        }
    }
}

/// Round icon like the ones in Control Center modules; filled with the accent when on.
struct Badge: View {
    let symbol: String
    var on = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? Color.white : Color.primary)
            .frame(width: 30, height: 30)
            .background(Circle().fill(on ? Color.moonlight : Color.primary.opacity(0.12)))
    }
}

/// A tappable module: badge + title + subtitle.
struct ModuleButton: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Badge(symbol: symbol, on: on)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tile(interactive: true)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: TimerModel
    private let presets = [15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("PARASOMNIA")
                        .font(.system(size: 14, weight: .light))
                        .tracking(4)
                    Text(model.isRunning ? "Timer running" : "Sleep timer")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .glassButton()
                    .buttonBorderShape(.circle)
                    .help("Quit Parasomnia")
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)

            if let r = model.remaining {
                running(r)
            } else {
                setup
            }

            if let e = model.errorText {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 300)
        .tint(.moonlight)
    }

    private func running(_ r: TimeInterval) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(format(r))
                    .font(.system(size: 50, weight: .thin, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: Int(r))
                Text(model.action == .shutdown ? "until your Mac shuts down" : "until your Mac sleeps")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let w = model.scheduledWake {
                    Label("Wakes \(w.formatted(date: .abbreviated, time: .shortened))", systemImage: "sunrise")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .tile()

            HStack(spacing: 10) {
                ModuleButton(symbol: "plus", title: "5 min", subtitle: "Extend") { model.extend(by: 5) }
                ModuleButton(symbol: "plus", title: "15 min", subtitle: "Extend") { model.extend(by: 15) }
            }

            ModuleButton(symbol: "stop.fill", title: "Cancel", subtitle: "Keep your Mac on", on: true) { model.cancel() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var setup: some View {
        VStack(spacing: 10) {
            HStack {
                Button { model.minutes = max(5, model.minutes - 5) } label: {
                    Image(systemName: "minus").frame(width: 18, height: 18)
                }
                .glassButton()
                .buttonBorderShape(.circle)
                Spacer()
                VStack(spacing: 0) {
                    Text("\(model.minutes)")
                        .font(.system(size: 50, weight: .thin, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.snappy, value: model.minutes)
                    Text("minutes").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.minutes = min(600, model.minutes + 5) } label: {
                    Image(systemName: "plus").frame(width: 18, height: 18)
                }
                .glassButton()
                .buttonBorderShape(.circle)
            }
            .controlSize(.large)
            .padding(12)
            .tile()

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<2) { row in
                    GridRow {
                        ForEach(presets[row * 3 ..< row * 3 + 3], id: \.self) { p in
                            presetButton(p)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                ModuleButton(symbol: "power", title: "Shut Down", subtitle: "Power off",
                             on: model.action == .shutdown) { model.action = .shutdown }
                ModuleButton(symbol: "moon.zzz.fill", title: "Sleep", subtitle: "Keep apps",
                             on: model.action == .sleep) { model.action = .sleep }
            }

            HStack(spacing: 8) {
                Button { model.wakeEnabled.toggle() } label: {
                    Badge(symbol: "sunrise.fill", on: model.wakeEnabled)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wake Me").font(.system(size: 12, weight: .semibold))
                    Text(model.wakeEnabled ? "In the morning" : "Off")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                DatePicker("", selection: $model.wakeTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!model.wakeEnabled)
            }
            .padding(10)
            .tile()

            ModuleButton(symbol: "play.fill", title: "Start",
                         subtitle: "\(model.minutes) min, then \(model.action == .shutdown ? "shut down" : "sleep")",
                         on: true) { model.start() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func presetButton(_ p: Int) -> some View {
        let selected = model.minutes == p
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button { model.minutes = p } label: {
            Text(p < 60 ? "\(p) min" : p % 60 == 0 ? "\(p / 60) h" : "\(p / 60) h \(p % 60)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background { if selected { shape.fill(.white) } }
        .modifier(PresetGlass(selected: selected))
    }
}

/// Unselected presets are glass; the selected one is solid white, like an "on" Control Center toggle.
struct PresetGlass: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        if selected { content } else { content.tile(cornerRadius: 12, interactive: true) }
    }
}

@main
struct ParasomniaApp: App {
    @StateObject private var model = TimerModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(model)
        } label: {
            if let r = model.remaining {
                Text("\(Image(systemName: "moon.fill")) \(format(r))").monospacedDigit()
            } else {
                Image(systemName: "moon")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
