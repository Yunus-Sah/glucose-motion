import SwiftUI
import Charts
import UniformTypeIdentifiers
import UIKit

// Explicit wrapper alias also supports SDKs that expose a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

struct Reading: Codable, Identifiable, Sendable { var id: Date { time }; var time: Date; var value: Double }
struct Session: Codable, Identifiable, Sendable {
    var librePatientID: String? = nil
    var libreSyncEnabled: Bool? = nil
    var mealKnown: Bool? = nil
    var id = UUID(); var meal = Date(); var start = Date(); var end = Date().addingTimeInterval(1800)
    var type = ""; var notes = ""; var rpe: Int? = nil; // Legacy backup field; no longer collected.
     var readings: [Reading] = []; var demo = false
    var window: [Reading] { readings.filter { $0.time >= start && $0.time <= end }.sorted { $0.time < $1.time } }
    var stats: [Double]? {
        let p = window; guard end > start, let first = p.first, let last = p.last else { return nil }
        let v = p.map(\.value)
        return [first.value,last.value,v.min()!,v.max()!,last.value-first.value,v.reduce(0,+)/Double(v.count)]
    }
    var feedback: String {
        guard let m = stats, window.count > 1 else { return "Add glucose readings to see your session trend." }
        let trend = abs(m[4]) < 0.05 ? "was unchanged" : m[4] < 0 ? "decreased" : "increased"
        return "Glucose \(trend) by \(String(format: "%.1f", abs(m[4]))) mmol/L during this session."
    }
}
@MainActor final class Study: ObservableObject {
    @Published var sessions: [Session] = [] { didSet { persist() } }
    @Published var message = ""
    static let file = URL.documentsDirectory.appending(path: "study.json")
    init() {
        if let data = try? Data(contentsOf: Self.file), let s = try? JSONDecoder().decode([Session].self, from: data) { sessions = s }
    }
    func persist() { do { try JSONEncoder().encode(sessions).write(to: Self.file, options: .atomic) } catch { message = "Could not save. Please export a backup." } }
    func add(_ p: [Reading], to i: Int) {
        guard !sessions[i].demo else { message = "Use a real session to add your readings."; return }
        var map = Dictionary(sessions[i].readings.map { ($0.time,$0) }, uniquingKeysWith: { _,b in b })
        p.forEach { map[$0.time] = $0 }; sessions[i].readings = map.values.sorted { $0.time < $1.time }
    }
}
enum Importer {
    static func rows(_ text: String) -> [[String]] {
        let sample = text.components(separatedBy: .newlines).prefix(10).joined(separator: "\n")
        let sep: Character = [Character(","),Character(";"),Character("\t")].max { a,b in (sample.filter { $0 == a }.count * 10 + (a == ";" ? 2 : a == "\t" ? 3 : 0)) < (sample.filter { $0 == b }.count * 10 + (b == ";" ? 2 : b == "\t" ? 3 : 0)) } ?? ","
        let chars = Array(text); var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false, i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" { if quoted && i+1 < chars.count && chars[i+1] == "\"" { cell.append(c); i += 1 } else { quoted.toggle() } }
            else if c == sep && !quoted { row.append(cell.trimmingCharacters(in: .whitespaces)); cell = "" }
            else if (c == "\n" || c == "\r") && !quoted {
                if c == "\r" && i+1 < chars.count && chars[i+1] == "\n" { i += 1 }
                row.append(cell.trimmingCharacters(in: .whitespaces)); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = []; cell = ""
            } else { cell.append(c) }; i += 1
        }
        row.append(cell.trimmingCharacters(in: .whitespaces)); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; return rows
    }
    static func parse(_ text: String, mg: Bool, monthFirst: Bool) -> ([Reading],Int) {
        var data = rows(text); var ti = 0, vi = [1], sourceMG = mg
        if let h = data.firstIndex(where: { $0.contains { $0.lowercased().contains("timestamp") } && $0.contains { $0.lowercased().contains("glucose") } }) {
            let header = data[h].map { $0.lowercased() }; ti = header.firstIndex { $0.contains("timestamp") } ?? 0
            vi = header.indices.filter { header[$0].contains("historic") && header[$0].contains("glucose") }
            vi += header.indices.filter { header[$0].contains("scan") && header[$0].contains("glucose") }
            if vi.isEmpty { vi = header.indices.filter { header[$0].contains("glucose") } }
            if header.contains(where: { $0.contains("mg/dl") }) { sourceMG = true }
            else if header.contains(where: { $0.contains("mmol") }) { sourceMG = false }
            data = Array(data.dropFirst(h+1))
        }
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.isLenient = false
        let numeric = monthFirst ? "MM/dd/yyyy" : "dd/MM/yyyy"
        let formats = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", numeric+" HH:mm", numeric+" HH:mm:ss", (monthFirst ? "MM.dd.yyyy" : "dd.MM.yyyy")+" HH:mm"]
        var result: [Reading] = []; var skipped = 0
        for row in data {
            guard row.indices.contains(ti), let cell = vi.compactMap({ row.indices.contains($0) ? row[$0] : nil }).first(where: { !$0.isEmpty }), let v = Double(cell.replacingOccurrences(of: ",", with: ".")), v.isFinite, v > 0 else { skipped += 1; continue }
            var date = ISO8601DateFormatter().date(from: row[ti])
            for format in formats where date == nil { df.dateFormat = format; date = df.date(from: row[ti]) }
            if let date { result.append(Reading(time: date, value: sourceMG ? v/18.0182 : v)) } else { skipped += 1 }
        }
        return (result,skipped)
    }
}
@main struct GlucoseMotionApp: App {
    @StateObject var study = Study()
    @StateObject var libre = LibreSync()
    @StateObject var journal = ContextJournal()
    var body: some Scene { WindowGroup { ContentView().environmentObject(study).environmentObject(libre).environmentObject(journal).tint(.blue) } }
}
private let canvas = Color(.systemGroupedBackground)
extension Session {
    var title: String { type.isEmpty ? "Activity" : type }
    var symbol: String {
        switch type { case "Running": return "figure.run"; case "Cycling": return "figure.outdoor.cycle"; case "Walking": return "figure.walk"; case "Strength": return "dumbbell.fill"; default: return "figure.mixed.cardio" }
    }
    var duration: String { "\(max(0,Int(end.timeIntervalSince(start)/60))) min" }
}
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading,spacing: 16) { content }.padding(20).frame(maxWidth: .infinity,alignment: .leading).background(Color(.secondarySystemGroupedBackground),in: RoundedRectangle(cornerRadius: 24)) }
}
struct SessionRow: View {
    let s: Session
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: s.symbol).font(.title2).foregroundStyle(.blue).frame(width: 50,height: 50).background(.blue.opacity(0.08),in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading,spacing: 5) { Text(s.title).font(.headline); Text(s.start.formatted(date: .abbreviated,time: .shortened)+" · "+s.duration).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if s.demo { Text("DEMO").font(.caption2.bold()).foregroundStyle(.orange) }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }.padding(16).background(Color(.secondarySystemGroupedBackground),in: RoundedRectangle(cornerRadius: 22))
    }
}
struct ContentView: View {
    @EnvironmentObject var journal: ContextJournal
    @EnvironmentObject var study: Study
    @EnvironmentObject var libre: LibreSync
    @Environment(\.scenePhase) private var phase
    var sessionContext: [String] { study.sessions.map { "\($0.id)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)|\($0.meal.timeIntervalSince1970)|\($0.mealKnown != false)|\($0.librePatientID ?? "")|\($0.libreSyncEnabled != false)" } }
    var body: some View {
        TabView {
            LiveDashboard().tabItem { Label("Live",systemImage: "waveform.path.ecg") }
            HomeView().tabItem { Label("Journal",systemImage: "square.grid.2x2.fill") }
            SessionsView().tabItem { Label("Sessions",systemImage: "figure.run") }
            InsightsView().tabItem { Label("Compare",systemImage: "chart.xyaxis.line") }
            SettingsView().tabItem { Label("Settings",systemImage: "gearshape") }
        }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await libre.sync(study: study)
                journal.refresh(cache: libre.cache.byPatient,study: study)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onChange(of: sessionContext) { _,_ in libre.apply(to: study) }
        .onChange(of: libre.lastSync) { _,_ in journal.refresh(cache: libre.cache.byPatient,study: study) }
        .alert("Glucose Motion",isPresented: Binding(get: { !study.message.isEmpty },set: { if !$0 { study.message = "" } })) { Button("OK") { study.message = "" } } message: { Text(study.message) }
    }
}
struct HomeView: View {
    @EnvironmentObject var study: Study
    @ViewState<Bool> private var adding = false
    var latest: Session? { study.sessions.filter { !$0.demo }.sorted { $0.start > $1.start }.first }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: 20) {
                    HStack { VStack(alignment: .leading,spacing: 5) { Text("YOUR ACTIVITY JOURNAL").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary); Text("Glucose in motion.").font(.largeTitle.bold()).tracking(-1) }; Spacer(); Image(systemName: "waveform.path.ecg").font(.title).foregroundStyle(.blue) }.padding(.top,12)
                    Button { adding = true } label: { Label("Log an activity",systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(18) }.buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 18))
                    LibreHomeCard()
                    if let s = latest {
                        Panel {
                            HStack { Text("LATEST SESSION").font(.caption.bold()).foregroundStyle(.secondary); Spacer(); Text(s.start,format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary) }
                            Text(s.title).font(.title2.bold())
                            if let m = s.stats { HStack(alignment: .firstTextBaseline) { Text(m[4],format: .number.sign(strategy: .always()).precision(.fractionLength(1))).font(.system(size: 48,weight: .semibold,design: .rounded)); Text("mmol/L change").font(.subheadline).foregroundStyle(.secondary) } }
                            Curve(s: s)
                            NavigationLink { SessionDetail(id: s.id) } label: { Text("View session").font(.subheadline.bold()) }
                        }
                    } else {
                        Panel { Image(systemName: "waveform.path.ecg").font(.system(size: 40)).foregroundStyle(.blue).padding(.bottom,8); Text("Your activity. Your patterns.").font(.title2.bold()); Text("Log a workout, add glucose, and explore what changed.").foregroundStyle(.secondary); Text("Connect LibreLinkUp or add readings").font(.caption).foregroundStyle(.secondary) }
                    }
                    HStack { Text("Recent sessions").font(.title3.bold()); Spacer(); Text("\(study.sessions.filter { !$0.demo }.count) total").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(study.sessions.sorted { $0.start > $1.start }.prefix(3))) { s in NavigationLink { SessionDetail(id: s.id) } label: { SessionRow(s: s) }.buttonStyle(.plain) }
                }.padding(20)
            }.background(canvas).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $adding) { ActivityEditor(existing: nil) }
        }
    }
}
struct SessionsView: View {
    @EnvironmentObject var study: Study
    @ViewState<Bool> private var adding = false
    var body: some View {
        NavigationStack {
            ScrollView { LazyVStack(spacing: 12) {
                if study.sessions.isEmpty { ContentUnavailableView("Your sessions live here",systemImage: "figure.run",description: Text("Tap + to log your first activity.")) }
                ForEach(study.sessions.sorted { $0.start > $1.start }) { s in NavigationLink { SessionDetail(id: s.id) } label: { SessionRow(s: s) }.buttonStyle(.plain) }
            }.padding(20) }.background(canvas).navigationTitle("Sessions")
            .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Log activity") }
            .sheet(isPresented: $adding) { ActivityEditor(existing: nil) }
        }
    }
}
struct ActivityEditor: View {
    @EnvironmentObject var study: Study
    @EnvironmentObject var libre: LibreSync
    @Environment(\.dismiss) var dismiss
    let existing: Session?
    @ViewState<Bool> private var syncNew = true
    @ViewState<Session> private var draft: Session
    init(existing: Session?) { self.existing = existing; _draft = ViewState(initialValue: existing ?? Session()) }
    let types = ["Running","Cycling","Strength","Walking","Other"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    Picker("Type",selection: $draft.type) { Text("Choose activity").tag(""); ForEach(Array(Set(types+[draft.type]).filter { !$0.isEmpty }).sorted(),id: \.self) { Text($0).tag($0) } }
                    DatePicker("Start",selection: $draft.start)
                    DatePicker("End",selection: $draft.end)
                    if draft.end <= draft.start { Text("End must be after start.").font(.caption).foregroundStyle(.red) }
                }
                if existing == nil && libre.connected && libre.selectedID != nil { Section { Toggle("Sync glucose from LibreLinkUp",isOn: $syncNew) } footer: { Text(libre.profileName) } }
                Section("Meal & notes") { Toggle("Meal recorded",isOn: Binding(get: { draft.mealKnown != false },set: { draft.mealKnown = $0 })); if draft.mealKnown != false { DatePicker("Meal time",selection: $draft.meal) }; TextField("Add a note…",text: $draft.notes,axis: .vertical).lineLimit(3...5) }
            }.navigationTitle(existing == nil ? "New activity" : "Edit activity").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { if existing == nil { draft.librePatientID = libre.connected && syncNew ? libre.selectedID : nil }; if let i = study.sessions.firstIndex(where: { $0.id == draft.id }) { study.sessions[i] = draft } else { study.sessions.append(draft) }; dismiss() }.bold().disabled(draft.type.isEmpty || draft.end <= draft.start) } }
        }
    }
}
struct Curve: View {
    let s: Session
    var body: some View {
        if s.readings.isEmpty { VStack(spacing: 10) { Image(systemName: "waveform.path.ecg").font(.largeTitle).foregroundStyle(.blue.opacity(0.4)); Text("Add glucose to see your curve").font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).frame(height: 170) }
        else {
            Chart {
                if s.end > s.start { RectangleMark(xStart: .value("Start",s.start),xEnd: .value("End",s.end)).foregroundStyle(.teal.opacity(0.08)) }
                ForEach(s.readings.sorted { $0.time < $1.time }) { p in LineMark(x: .value("Time",p.time),y: .value("Glucose",p.value)).foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 2.5)) }
                if s.mealKnown != false { RuleMark(x: .value("Meal",s.meal)).foregroundStyle(.orange).lineStyle(StrokeStyle(dash: [4,4])) }
                RuleMark(x: .value("Start",s.start)).foregroundStyle(.teal).lineStyle(StrokeStyle(dash: [3,3]))
                RuleMark(x: .value("End",s.end)).foregroundStyle(.teal).lineStyle(StrokeStyle(dash: [3,3]))
            }.chartYAxisLabel("mmol/L").chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisValueLabel(format: .dateTime.hour().minute()) } }.frame(height: 190).padding(.top,8)
        }
    }
}
struct SessionDetail: View {
    let id: UUID
    @EnvironmentObject var study: Study
    @EnvironmentObject var libre: LibreSync
    @Environment(\.dismiss) var dismiss
    @ViewState<Bool> private var editing = false
    @ViewState<Bool> private var adding = false
    @ViewState<Bool> private var deleting = false
    @ViewState<Bool> private var details = false
    @ViewState<Bool> private var linking = false
    var s: Session? { study.sessions.first { $0.id == id } }
    var body: some View {
        ScrollView {
            if let s {
                VStack(alignment: .leading,spacing: 20) {
                    HStack { Label(s.duration,systemImage: "clock"); Spacer() }.font(.subheadline).foregroundStyle(.secondary)
                    if s.demo { Text("DEMO SESSION").font(.caption.bold()).foregroundStyle(.orange) }
                    Panel {
                        HStack { Text("Glucose").font(.title3.bold()); Spacer(); Text("\(s.readings.count) readings").font(.caption).foregroundStyle(.secondary) }
                        Curve(s: s)
                        HStack(spacing: 18) { if s.mealKnown != false { Label("Meal",systemImage: "circle.fill").foregroundStyle(.orange) }; Label("Activity",systemImage: "circle.fill").foregroundStyle(.teal) }.font(.caption2)
                        if let m = s.stats { MetricGrid(values: m) }
                        Text("Experimental · not medically validated").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if s.window.count > 1 { Panel { Label("Session trend",systemImage: "chart.line.uptrend.xyaxis").font(.headline); Text(s.feedback).foregroundStyle(.secondary) } }
                    if !s.demo {
                        Panel {
                            HStack { Label("LibreLinkUp",systemImage: "antenna.radiowaves.left.and.right").font(.headline); Spacer(); if s.librePatientID != nil { Text(s.libreSyncEnabled == false ? "Paused" : "Linked").font(.caption).foregroundStyle(.teal) } }
                            if let patient = s.librePatientID {
                                Text(patient == libre.selectedID ? libre.profileName : "Previously linked profile").font(.subheadline).foregroundStyle(.secondary)
                                if s.libreSyncEnabled == false {
                                    if patient == libre.selectedID { Button("Resume syncing") { libre.link(sessionID: id,study: study) } }
                                    else { Text("Choose this activity’s original shared profile to resume syncing.").font(.caption).foregroundStyle(.secondary) }
                                } else { Button("Pause syncing this activity") { libre.unlink(sessionID: id,study: study) }.font(.subheadline) }
                            } else if libre.connected && libre.selectedID != nil {
                                Button("Use \(libre.profileName)’s readings") { linking = true }
                            } else { NavigationLink("Connect glucose data") { LibreConnectionView() } }
                        }
                    }
                    if !s.demo { Button { adding = true } label: { Label(s.readings.isEmpty ? "Add glucose" : "Add more readings",systemImage: "plus").frame(maxWidth: .infinity).padding(10) }.buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 16)) }
                    Panel {
                        Text("Activity details").font(.headline)
                        LabeledContent("Date",value: s.start.formatted(date: .abbreviated,time: .omitted))
                        LabeledContent("Workout",value: s.start.formatted(date: .omitted,time: .shortened)+" – "+s.end.formatted(date: .omitted,time: .shortened))
                        if s.mealKnown != false { LabeledContent("Meal",value: s.meal.formatted(date: .abbreviated,time: .shortened)) }
                        if !s.notes.isEmpty { Text(s.notes).foregroundStyle(.secondary) }
                        DisclosureGroup("About these numbers",isExpanded: $details) { Text("First and last readings inside the activity window define start, end, and change. Mean is an arithmetic average. Lines connect gaps; times are local. Glucose observations alone do not explain causes or performance.").font(.caption).foregroundStyle(.secondary).padding(.top,8) }
                    }.font(.subheadline)
                }.padding(20)
            }
        }.background(canvas).navigationTitle(s?.title ?? "Session").navigationBarTitleDisplayMode(.inline)
        .toolbar { Menu { Button("Edit activity",systemImage: "pencil") { editing = true }; Button("Delete session",systemImage: "trash",role: .destructive) { deleting = true } } label: { Image(systemName: "ellipsis.circle") } }
        .sheet(isPresented: $editing) { if let s { ActivityEditor(existing: s) } }
        .sheet(isPresented: $adding) { AddGlucose(id: id) }
        .confirmationDialog("Link this activity to \(libre.profileName)?",isPresented: $linking,titleVisibility: .visible) { Button("Link and import readings") { libre.link(sessionID: id,study: study) } } message: { Text("Readings around this activity will be merged with its existing data. The activity stays linked to this profile.") }
        .confirmationDialog("Delete this session?",isPresented: $deleting,titleVisibility: .visible) { Button("Delete session",role: .destructive) { study.sessions.removeAll { $0.id == id }; dismiss() } }
    }
}
struct MetricGrid: View {
    let values: [Double]
    let names = ["Start","End","Change","Lowest","Highest","Average"]
    let positions = [0,1,4,2,3,5]
    var body: some View { LazyVGrid(columns: Array(repeating: GridItem(.flexible(),alignment: .leading),count: 3),alignment: .leading,spacing: 22) { ForEach(0..<6) { i in VStack(alignment: .leading,spacing: 5) { Text(names[i]).font(.caption).foregroundStyle(.secondary); Text(values[positions[i]],format: .number.precision(.fractionLength(1))).font(.title2.weight(.semibold)).monospacedDigit() } } }.padding(.vertical,8) }
}
struct AddGlucose: View {
    let id: UUID
    @EnvironmentObject var study: Study
    @Environment(\.dismiss) var dismiss
    @ViewState<Int> private var method = 0
    @ViewState<String> private var text = ""
    @ViewState<String> private var value = ""
    @ViewState<Date> private var time = Date()
    @ViewState<Bool> private var mg = false
    @ViewState<Bool> private var monthFirst = false
    @ViewState<Bool> private var file = false
    @ViewState<String> private var error = ""
    @ViewState<String> private var preview = ""
    @ViewState<[Reading]> private var pending = []
    var body: some View {
        NavigationStack {
            Form {
                Section { Picker("Method",selection: $method) { Text("File").tag(0); Text("Paste").tag(1); Text("Manual").tag(2) }.pickerStyle(.segmented) }
                if pending.isEmpty {
                    Section {
                        if method == 0 { Button { file = true } label: { Label("Choose LibreView CSV",systemImage: "doc.badge.plus") }; Text("Select an export from Files.").font(.caption).foregroundStyle(.secondary) }
                        if method == 1 { TextEditor(text: $text).frame(height: 150).font(.system(.subheadline,design: .monospaced)); Text("One timestamp and value per line.\n2026-10-20 14:00,5.4").font(.caption).foregroundStyle(.secondary); Button("Preview readings") { parse(text) }.disabled(text.isEmpty) }
                        if method == 2 { DatePicker("Time",selection: $time); TextField("Glucose",text: $value).keyboardType(.decimalPad); Button("Save reading") { guard let v = Double(value.replacingOccurrences(of: ",",with: ".")),v.isFinite,v > 0 else { error = "Enter a positive glucose value."; return }; commit([Reading(time: time,value: mg ? v/18.0182 : v)]) } }
                    }
                    Section { Picker("Input unit",selection: $mg) { Text("mmol/L").tag(false); Text("mg/dL").tag(true) }; if method != 2 { DisclosureGroup("Date options") { Toggle("Month / day / year",isOn: $monthFirst) } } }
                } else {
                    Section("Import preview") { Text(preview); Text("Display unit: mmol/L").font(.caption).foregroundStyle(.secondary); Button("Add \(pending.count) readings") { commit(pending) }.bold(); Button("Choose again") { pending = []; preview = "" } }
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red).font(.subheadline) } }
            }.navigationTitle("Add glucose").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
            .fileImporter(isPresented: $file,allowedContentTypes: [.commaSeparatedText,.plainText,.text]) { result in do { let url = try result.get(); let allowed = url.startAccessingSecurityScopedResource(); defer { if allowed { url.stopAccessingSecurityScopedResource() } }; parse(try String(contentsOf: url,encoding: .utf8)) } catch { self.error = "Couldn’t read this file. Try pasting the readings." } }
        }
    }
    func parse(_ raw: String) {
        let (points,skipped) = Importer.parse(raw,mg: mg,monthFirst: monthFirst)
        guard let first = points.min(by: { $0.time < $1.time }),let last = points.max(by: { $0.time < $1.time }) else { error = "No readings found. Check the format, units, and date options."; return }
        pending = points; error = ""; preview = "\(points.count) readings\n\(first.time.formatted())\n→ \(last.time.formatted())\n\(skipped) rows skipped\nRange: \(String(format: "%.1f",points.map(\.value).min()!))–\(String(format: "%.1f",points.map(\.value).max()!)) mmol/L"
    }
    func commit(_ points: [Reading]) { guard let i = study.sessions.firstIndex(where: { $0.id == id }) else { error = "This session no longer exists."; return }; study.add(points,to: i); dismiss() }
}
struct InsightsView: View {
    @EnvironmentObject var study: Study
    @EnvironmentObject var journal: ContextJournal
    @ViewState<UUID?> private var first = nil
    @ViewState<UUID?> private var second = nil
    @ViewState<Bool> private var poster = false
    var eligible: [Session] { study.sessions.filter { $0.window.count > 1 && $0.stats != nil }.sorted { $0.start < $1.start } }
    var data: ComparisonData? {
        guard let a = eligible.first(where: { $0.id == first }),let b = eligible.first(where: { $0.id == second }),a.id != b.id else { return nil }
        return ComparisonData(a:ComparedSession(a,events:journal.events),b:ComparedSession(b,events:journal.events))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:14) {
                    if eligible.count < 2 { ContentUnavailableView("Compare your sessions",systemImage:"chart.xyaxis.line",description:Text("Add two activities with glucose readings.")) }
                    else {
                        VStack(spacing:10) { selection("A",value:$first); selection("B",value:$second) }.padding(14).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:18))
                        if let data,data.compatible {
                            Button { poster = true } label: { Label("Poster view / export image",systemImage:"arrow.up.left.and.arrow.down.right").font(.subheadline.bold()).frame(maxWidth:.infinity).padding(10) }.buttonStyle(.borderedProminent)
                            GeometryReader { proxy in ComparisonReport(data:data).scaleEffect(proxy.size.width/390,anchor:.topLeading) }.frame(height:ComparisonReport.canvasHeight * (UIScreen.main.bounds.width-32)/390).clipShape(RoundedRectangle(cornerRadius:18))
                        } else { Text(data == nil ? "Choose two different sessions." : "Choose sessions from the same shared profile.").foregroundStyle(.secondary) }
                    }
                }.padding(16)
            }.background(Color(.systemGroupedBackground)).navigationTitle("Compare").navigationBarTitleDisplayMode(.inline)
            .onAppear { resetSelection() }.onChange(of:eligible.map(\.id)) { _,_ in resetSelection() }
            .fullScreenCover(isPresented:$poster) { if let data { ComparisonPosterView(data:data) } }
        }
    }
    func resetSelection() {
        guard !eligible.isEmpty else { first = nil; second = nil; return }
        if first == nil && second == nil {
            for s in eligible.reversed() {
                let same = eligible.filter { $0.type == s.type && $0.librePatientID == s.librePatientID }
                if same.count >= 2 { first = same[same.count-2].id; second = same.last?.id; return }
            }
        }
        if !eligible.contains(where: { $0.id == first }) { first = eligible.first?.id }
        if !eligible.contains(where: { $0.id == second }) || first == second { second = eligible.first { $0.id != first }?.id }
    }
    func selection(_ title:String,value:Binding<UUID?>) -> some View {
        HStack { Text(title).font(.headline).frame(width:18); Spacer(); Picker(title,selection:value) { Text("Choose session").tag(nil as UUID?); ForEach(eligible) { s in let item = ComparedSession(s,events:journal.events); Text("\(item.day) · \(s.title) · \(item.delayLabel)").tag(Optional(s.id)) } }.labelsHidden() }
    }
}
struct SettingsView: View {
    @EnvironmentObject var study: Study
    @ViewState<Bool> private var restoring = false
    @ViewState<Bool> private var confirm = false
    @ViewState<[Session]> private var pending = []
    var body: some View {
        NavigationStack {
            List {
                Section("Connections") { NavigationLink { LibreConnectionView() } label: { Label("LibreLinkUp",systemImage: "antenna.radiowaves.left.and.right") } }
                Section("Events") { NavigationLink("Exercise, meals & fasting") { ContextHistory() }; ShareLink(item: ContextJournal.file) { Label("Export event history",systemImage: "square.and.arrow.up") } }
                Section("Your data") {
                    ShareLink(item: Study.file) { Label("Export backup",systemImage: "square.and.arrow.up") }
                    Button { restoring = true } label: { Label("Restore backup",systemImage: "arrow.counterclockwise") }
                    LabeledContent("Storage",value: "On this iPhone")
                    LabeledContent("Glucose unit",value: "mmol/L")
                }
                Section { NavigationLink("About Glucose Motion") { List { Section { Text("A personal journal for glucose and activity.") }; Section("Prototype") { Text("Experimental. Not medically validated. Context feedback describes interstitial glucose during and after logged exercise, meals, and fasting. It does not judge meal quality, assess fasting safety or performance, diagnose carbohydrate deficiency, or prescribe fueling. Sensor and cloud readings can lag.") }; Section("Data") { Text("Optional unofficial LibreLinkUp cloud sync, CSV import, or manual entry. Sync runs while the app is open. No direct sensor connection. Login is stored in the iPhone Keychain; the password is not saved. Cloud readings are cached for 30 days, separately by shared profile. Session readings remain until deleted. Deleting the app removes local data.") }; Section("Calculations") { Text("Start and end use the first and last readings inside the activity window. Change = end − start. Average is the arithmetic mean. Chart lines connect gaps. Check imported dates and units.") } }.navigationTitle("About") } }
                Section("Try it out") { Button("Add a demo session") { var s = Session(); let base = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12*3600); s.type = "Running"; s.demo = true; s.meal = base; s.start = base.addingTimeInterval(3600); s.end = base.addingTimeInterval(5400);  s.readings = (0..<25).map { i in Reading(time: base.addingTimeInterval(Double(i)*300),value: 5.5+0.8*sin(Double(i)/5)-0.015*Double(i)) }; study.sessions.append(s) } }
            }.navigationTitle("Settings").onAppear { study.persist() }
            .fileImporter(isPresented: $restoring,allowedContentTypes: [.json]) { result in do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let restored = try JSONDecoder().decode([Session].self,from: Data(contentsOf: url)); guard Set(restored.map(\.id)).count == restored.count,restored.allSatisfy({ $0.readings.allSatisfy { $0.value.isFinite && $0.value > 0 } }) else { study.message = "This backup contains invalid values."; return }; pending = restored; confirm = true } catch { study.message = "Couldn’t open this backup." } }
            .confirmationDialog("Replace all sessions with this backup?",isPresented: $confirm,titleVisibility: .visible) { Button("Restore \(pending.count) sessions",role: .destructive) { study.sessions = pending; pending = [] } }
        }
    }
}
