import SwiftUI
import AppKit

enum EndAction: String, CaseIterable, Identifiable {
    case shutdown, sleep
    var id: Self { self }
    var title: String { self == .shutdown ? "Shut Down" : "Sleep" }
}

// Accent taken from the "Images and Words" canopy.
extension Color {
    static let canopy = Color(red: 0.66, green: 0.12, blue: 0.14)
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

struct ContentView: View {
    @EnvironmentObject var model: TimerModel
    private let presets = [15, 30, 45, 60, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("The Miracle and the Sleeper").font(.headline)
                    Text(model.isRunning ? "Timer running" : "Sleep timer")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Divider()

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

            Divider()

            Button("Quit The Miracle and the Sleeper") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 300)
        .tint(.canopy)
    }

    private func running(_ r: TimeInterval) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(format(r))
                    .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: Int(r))
                Text(model.action == .shutdown ? "until your Mac shuts down" : "until your Mac sleeps")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let w = model.scheduledWake {
                    Label("Wakes \(w.formatted(date: .abbreviated, time: .shortened))", systemImage: "sunrise")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)

            HStack {
                Button("+5 min") { model.extend(by: 5) }.buttonStyle(.bordered)
                Button("+15 min") { model.extend(by: 15) }.buttonStyle(.bordered)
                Spacer()
                Button("Cancel") { model.cancel() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Duration", selection: $model.minutes) {
                ForEach(presets, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Duration").gridColumnAlignment(.trailing)
                    HStack(spacing: 4) {
                        TextField("", value: $model.minutes, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                        Stepper("", value: $model.minutes, in: 1...600, step: 5).labelsHidden()
                        Text("min").foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("When done")
                    Picker("", selection: $model.action) {
                        ForEach(EndAction.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text("Wake me at")
                    HStack {
                        DatePicker("", selection: $model.wakeTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .disabled(!model.wakeEnabled)
                        Spacer()
                        Toggle("", isOn: $model.wakeEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }

            Button {
                model.start()
            } label: {
                Text("Start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
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
