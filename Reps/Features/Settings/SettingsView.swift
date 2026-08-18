import SwiftUI
import UniformTypeIdentifiers
import RepsKit

struct SettingsView: View {
    @Environment(RepsStore.self) private var store
    @Environment(PurchaseStore.self) private var purchases
    @Environment(TabRouter.self) private var router

    @State private var showEraseConfirm = false
    @State private var showEraseSecondConfirm = false
    #if DEBUG
    @State private var showDebugEraseConfirm = false
    #endif
    @State private var exportDocument: ExportDocument?
    @State private var showExporter = false

    var body: some View {
        Form {
            sessionSection
            countingSection
            restSection
            remindersSection
            healthSection
            proSection
            dataSection
            aboutSection
            #if DEBUG
            debugSection
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(Color.rBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.rPrimary)
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "reps-export"
        ) { _ in }
        .confirmationDialog("Erase all data?", isPresented: $showEraseConfirm, titleVisibility: .visible) {
            Button("Continue", role: .destructive) { showEraseSecondConfirm = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every session, record and streak will be deleted from this iPhone.")
        }
        .confirmationDialog(
            "This cannot be undone.",
            isPresented: $showEraseSecondConfirm,
            titleVisibility: .visible
        ) {
            // Two differently worded confirmations, on purpose. There is no account and no
            // sync, so this is genuinely irreversible.
            Button("Erase everything and start over", role: .destructive) { store.eraseAllData() }
            Button("Keep my data", role: .cancel) {}
        }
        #if DEBUG
        .confirmationDialog(
            "Erase and show onboarding?",
            isPresented: $showDebugEraseConfirm,
            titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) { store.eraseAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Debug tool. Deletes every session on this device and returns to first run.")
        }
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var sessionSection: some View {
        Section {
            if store.planHonoursSetCount {
                Picker("Sets per session", selection: setCountBinding) {
                    Text("One set").tag(1)
                    ForEach(2...PlanState.maxSetCount, id: \.self) { count in
                        Text("\(count) sets").tag(count)
                    }
                }
            } else {
                LabeledContent("Sets per session", value: "Set by the program")
            }
        } header: {
            Text("Session")
        } footer: {
            Text(store.planHonoursSetCount
                 ? "One set is about two minutes. Splitting it into sets adds volume and rest, and takes longer."
                 : "A published program prescribes its own sets and runs exactly as written.")
        }
    }

    private var countingSection: some View {
        Section {
            Picker("Engine", selection: engineBinding) {
                ForEach(RepDetectorFactory.availableEngines(), id: \.self) { engine in
                    Text(engine.label).tag(engine)
                }
            }
            Picker("Count out loud", selection: voiceBinding) {
                ForEach(CountingVoice.allCases, id: \.self) { voice in
                    Text(voice.label).tag(voice)
                }
            }
            Toggle("Haptics", isOn: hapticsBinding)
            if DepthProbe.isSupported {
                NavigationLink { CameraCheckView() } label: {
                    Label("Camera check", systemImage: "faceid")
                }
            }
            NavigationLink { SensorCheckView() } label: {
                Label("Sensor check", systemImage: "dot.radiowaves.up.forward")
            }
        } header: {
            Text("Counting")
        } footer: {
            Text(store.state.settings.engine.explanation)
        }
    }

    private var restSection: some View {
        Section {
            Stepper(
                "Rest between sets: \(store.state.settings.restSeconds)s",
                value: restBinding, in: 0...300, step: 15
            )
            Stepper(
                "Countdown: \(store.state.settings.countdownSeconds)s",
                value: countdownBinding, in: 1...10
            )
        } header: {
            Text("Timing")
        } footer: {
            Text("The countdown is also when Precision mode measures your starting distance, so it cannot be zero.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Daily reminder", isOn: reminderBinding)
            if store.state.settings.reminder.isEnabled {
                DatePicker("Time", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("One reminder, and only on days you have training left to do.")
        }
    }

    private var healthSection: some View {
        Section {
            Toggle("Save sessions to Health", isOn: healthBinding)
                .disabled(!HealthSync.isAvailable || !purchases.isPro)
            if store.state.settings.syncToHealth {
                Stepper(
                    bodyWeightLabel,
                    value: weightBinding, in: 30...200, step: 1
                )
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text(purchases.isPro
                 ? "Sessions are written as functional strength training. Body weight is used only to estimate calories and is never stored anywhere else."
                 : "Health sync is part of Reps Pro.")
        }
    }

    private var proSection: some View {
        Section {
            if purchases.isPro {
                Label("Reps Pro is active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color.rAccent)
            } else {
                Button("Get Reps Pro") { router.showPaywall = true }
                Button("Restore purchases") { Task { await purchases.restore() } }
            }
        } header: {
            Text("Subscription")
        }
    }

    private var dataSection: some View {
        Section {
            Button("Export as CSV") { exportCSV() }
            Button("Erase all data and start over", role: .destructive) { showEraseConfirm = true }
        } header: {
            Text("Data")
        } footer: {
            Text("Everything lives on this iPhone. There is no account, no server and no sync, so an export is the only backup.")
        }
    }

    /// Screenshot tooling. `#if DEBUG` so it is compiled out of the archive entirely —
    /// there is no runtime flag to get this wrong.
    #if DEBUG
    private var debugSection: some View {
        Section {
            Button("Fill with demo data") {
                store.installDemoData()
                Haptics.celebrate()
            }
            // One confirmation, not the two the shipping button carries: this is a tool
            // used dozens of times in a screenshot session, and a second tap that stops
            // an accidental wipe is worth it while a third would just be friction.
            Button("Erase and show onboarding", role: .destructive) {
                showDebugEraseConfirm = true
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Debug builds only. Nine months of generated history, for App Store screenshots.")
        }
    }
    #endif

    private var aboutSection: some View {
        Section {
            LabeledContent("Sessions", value: "\(store.state.workouts.count)")
            LabeledContent("All-time push-ups", value: Format.reps(store.records.totalReps))
            LabeledContent("Version", value: appVersion)
        } header: {
            Text("About")
        }
    }

    // MARK: - Bindings
    //
    // Written out rather than using @Bindable on the store: every write has to go through
    // `update`, which persists before the value is observable. A direct binding would let
    // the UI show a preference that never made it to disk.

    /// Writes the plan, not the preferences — the shape lives on `PlanState` so that every
    /// prescription call site reads it without a signature change.
    private var setCountBinding: Binding<Int> {
        Binding(get: { store.setCount }, set: { store.setSetCount($0) })
    }
    private var engineBinding: Binding<CountingEngine> {
        Binding(get: { store.state.settings.engine }, set: { value in store.update { $0.engine = value } })
    }
    private var voiceBinding: Binding<CountingVoice> {
        Binding(get: { store.state.settings.voice }, set: { value in store.update { $0.voice = value } })
    }
    private var hapticsBinding: Binding<Bool> {
        Binding(get: { store.state.settings.hapticsEnabled }, set: { value in store.update { $0.hapticsEnabled = value } })
    }
    private var restBinding: Binding<Int> {
        Binding(get: { store.state.settings.restSeconds }, set: { value in store.update { $0.restSeconds = value } })
    }
    private var countdownBinding: Binding<Int> {
        Binding(get: { store.state.settings.countdownSeconds }, set: { value in store.update { $0.countdownSeconds = value } })
    }
    private var healthBinding: Binding<Bool> {
        Binding(
            get: { store.state.settings.syncToHealth },
            set: { value in
                store.update { $0.syncToHealth = value }
                if value { Task { _ = await HealthSync.requestAuthorization() } }
            }
        )
    }
    private var weightBinding: Binding<Double> {
        Binding(
            get: { store.state.settings.bodyWeightKg ?? 80 },
            set: { value in store.update { $0.bodyWeightKg = value } }
        )
    }
    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { store.state.settings.reminder.isEnabled },
            set: { value in
                store.update { $0.reminder.isEnabled = value }
                Task {
                    if value { _ = await ReminderScheduler.requestAuthorization() }
                    await ReminderScheduler.rearm(state: store.state)
                }
            }
        )
    }
    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = store.state.settings.reminder.minuteOfDay
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
                ) ?? Date()
            },
            set: { value in
                let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                store.update { $0.reminder.minuteOfDay = (components.hour ?? 18) * 60 + (components.minute ?? 0) }
                Task { await ReminderScheduler.rearm(state: store.state) }
            }
        )
    }

    // MARK: - Helpers

    private var bodyWeightLabel: String {
        let kg = store.state.settings.bodyWeightKg ?? 80
        return "Body weight: \(Int(kg)) kg"
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func exportCSV() {
        guard let repository = try? RepsRepository.make() else { return }
        exportDocument = ExportDocument(text: repository.exportCSV(store.state))
        showExporter = true
    }
}

/// Minimal `FileDocument` so `.fileExporter` can hand the CSV to Files, Mail, or anywhere
/// else the user wants it.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
