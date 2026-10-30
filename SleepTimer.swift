import SwiftUI
import AppKit

enum EndAction: String, CaseIterable, Identifiable {
    case shutdown, sleep
    var id: Self { self }
    var title: String { self == .shutdown ? "Shut Down" : "Sleep" }
}

// Palette taken from "Images and Words": night window, crimson canopy, gilded trim.
enum Theme {
    static let night = Color(red: 0.06, green: 0.08, blue: 0.16)
    static let wine = Color(red: 0.29, green: 0.05, blue: 0.07)
    static let crimson = Color(red: 0.56, green: 0.11, blue: 0.12)
    static let gold = Color(red: 0.85, green: 0.66, blue: 0.27)
    static let paleGold = Color(red: 0.95, green: 0.83, blue: 0.54)
    static let ivory = Color(red: 0.95, green: 0.90, blue: 0.78)
    static let flame = Color(red: 1.0, green: 0.62, blue: 0.22)

    static func title(_ size: CGFloat) -> Font { .custom("Copperplate", size: size) }
    static func serif(_ size: CGFloat) -> Font { .custom("Didot", size: size) }
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
            errorText = "Permission needed: System Settings › Privacy & Security › Automation › The Miracle and the Sleeper. (\(error[NSAppleScript.errorNumber] ?? "?"))"
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

struct GildedButtonStyle: ButtonStyle {
    enum Kind { case primary, outline, selected }
    var kind: Kind = .outline

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.title(kind == .primary ? 15 : 12))
            .tracking(1)
            .foregroundStyle(kind == .selected ? Theme.night : (kind == .primary ? Theme.ivory : Theme.paleGold))
            .padding(.vertical, kind == .primary ? 9 : 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(
                    kind == .primary
                        ? AnyShapeStyle(LinearGradient(colors: [Theme.crimson, Theme.wine], startPoint: .top, endPoint: .bottom))
                        : kind == .selected ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Color.black.opacity(0.25))
                )
            )
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.gold.opacity(kind == .outline ? 0.55 : 0.9), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

struct Ornament: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(LinearGradient(colors: [.clear, Theme.gold], startPoint: .leading, endPoint: .trailing)).frame(height: 0.8)
            Image(systemName: "moon.fill").font(.system(size: 9)).foregroundStyle(Theme.gold)
            Rectangle().fill(LinearGradient(colors: [Theme.gold, .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 0.8)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: TimerModel
    private let presets = [15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("THE MIRACLE")
                Text("AND THE SLEEPER")
            }
            .font(Theme.title(17))
            .tracking(2)
            .foregroundStyle(LinearGradient(colors: [Theme.paleGold, Theme.gold], startPoint: .top, endPoint: .bottom))
            .shadow(color: Theme.flame.opacity(0.4), radius: 6)

            Ornament()

            if let r = model.remaining {
                running(r)
            } else {
                setup
            }

            if let e = model.errorText {
                Text(e).font(.caption).foregroundStyle(Theme.flame).fixedSize(horizontal: false, vertical: true)
            }

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(Theme.serif(12).italic())
                .foregroundStyle(Theme.gold.opacity(0.7))
        }
        .padding(18)
        .frame(width: 280)
        .background(background)
        .tint(Theme.gold)
        .environment(\.colorScheme, .dark)
    }

    private func running(_ r: TimeInterval) -> some View {
        VStack(spacing: 10) {
            Text(format(r))
                .font(Theme.serif(52).monospacedDigit())
                .foregroundStyle(Theme.ivory)
                .shadow(color: Theme.flame.opacity(0.5), radius: 10)
            Text(model.action == .shutdown ? "until the Mac shuts down" : "until the Mac sleeps")
                .font(Theme.serif(13).italic()).foregroundStyle(Theme.paleGold.opacity(0.85))
            if let w = model.scheduledWake {
                Label("Wakes \(w.formatted(date: .abbreviated, time: .shortened))", systemImage: "sun.horizon")
                    .font(Theme.serif(13)).foregroundStyle(Theme.paleGold.opacity(0.85))
            }
            HStack(spacing: 8) {
                Button("+5 MIN") { model.extend(by: 5) }.buttonStyle(GildedButtonStyle())
                Button("+15 MIN") { model.extend(by: 15) }.buttonStyle(GildedButtonStyle())
            }
            Button("CANCEL") { model.cancel() }
                .buttonStyle(GildedButtonStyle(kind: .primary))
                .keyboardShortcut(.cancelAction)
        }
    }

    private var setup: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(presets, id: \.self) { p in
                    Button("\(p) MIN") { model.minutes = p }
                        .buttonStyle(GildedButtonStyle(kind: model.minutes == p ? .selected : .outline))
                }
            }
            HStack {
                Text("Duration").font(Theme.serif(14))
                Spacer()
                TextField("", value: $model.minutes, format: .number)
                    .textFieldStyle(.plain)
                    .font(Theme.serif(16).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                Text("min").font(Theme.serif(14).italic())
                Stepper("", value: $model.minutes, in: 1...600, step: 5).labelsHidden()
            }
            .foregroundStyle(Theme.ivory)

            HStack(spacing: 8) {
                ForEach(EndAction.allCases) { a in
                    Button(a.title.uppercased()) { model.action = a }
                        .buttonStyle(GildedButtonStyle(kind: model.action == a ? .selected : .outline))
                }
            }

            HStack {
                Toggle(isOn: $model.wakeEnabled) {
                    Text("Wake me at").font(Theme.serif(14))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                DatePicker("", selection: $model.wakeTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!model.wakeEnabled)
            }
            .foregroundStyle(Theme.ivory)

            Button("BEGIN") { model.start() }
                .buttonStyle(GildedButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Theme.night, Theme.wine], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.flame.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.gold.opacity(0.5), lineWidth: 1)
                .padding(5)
        }
    }
}

@main
struct MiracleSleeperApp: App {
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
