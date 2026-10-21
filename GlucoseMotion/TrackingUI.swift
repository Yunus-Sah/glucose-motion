import SwiftUI
import Charts

@MainActor final class ContextJournal: ObservableObject {
    @Published private(set) var events: [ContextEvent] = []
    @Published var notice = ""
    static let file = URL.documentsDirectory.appending(path: "context-events.json")
    private let fileURL: URL
    init(file: URL? = nil) {
        let file = file ?? Self.file
        fileURL = file
        if FileManager.default.fileExists(atPath: file.path) {
            do { events = try JSONDecoder().decode([ContextEvent].self,from: Data(contentsOf: file)) }
            catch { notice = "Couldn’t read your event history. Export the existing file before recording new events." }
        } else { persist() }
    }
    @discardableResult func start(kind: EventKind,patientID: String,profileName: String,title: String,notes: String,time: Date,cache: [String:[Reading]],study: Study) -> Bool {
        guard time <= Date(),!patientID.isEmpty else { return false }
        guard notice.isEmpty else { return false }
        guard !events.contains(where: { $0.patientID == patientID && $0.kind == kind && $0.end == nil }) else { notice = "This type of event is already running for this profile."; return false }
        var e = ContextEvent(kind: kind,patientID: patientID,profileName: profileName,start: time)
        e.title = title; e.notes = notes
        events.append(e); refresh(cache: cache,study: study); persist(); return true
    }
    func finish(id: UUID,time: Date,cache: [String:[Reading]],study: Study) {
        guard let i = events.firstIndex(where: { $0.id == id }),events[i].end == nil,time > events[i].start else { return }
        events[i].end = time
        refresh(cache: cache,study: study)
        let e = events[i]
        if e.kind == .exercise,!study.sessions.contains(where: { $0.id == e.id }) {
            var s = Session(); s.id = e.id; s.start = e.start; s.end = time; s.type = e.displayTitle; s.notes = e.notes
            s.librePatientID = e.patientID; s.libreSyncEnabled = true; s.readings = e.readings
            let priorMeal = events.filter { $0.kind == .meal && $0.patientID == e.patientID && $0.start <= e.start && e.start.timeIntervalSince($0.start) <= 6*3600 }.max { $0.start < $1.start }
            s.meal = priorMeal?.start ?? e.start; s.mealKnown = priorMeal != nil
            study.sessions.append(s)
        }
        persist()
    }
    func refresh(cache: [String:[Reading]],study: Study,now: Date = Date()) {
        let next = ContextFeedback.merge(events,cache: cache,now: now)
        let changed = zip(next,events).contains { a,b in a.readings.count != b.readings.count || zip(a.readings,b.readings).contains { $0.time != $1.time || $0.value != $1.value } }
        if changed { events = next; persist() }
        var sessions = study.sessions; var update = false
        for e in events where e.kind == .exercise && e.end != nil {
            guard let i = sessions.firstIndex(where: { $0.id == e.id }),sessions[i].librePatientID == e.patientID,sessions[i].libreSyncEnabled != false else { continue }
            let merged = ContextFeedback.readings(sessions[i].readings+e.readings,from: .distantPast,through: now)
            if merged.count != sessions[i].readings.count || zip(merged,sessions[i].readings).contains(where: { $0.time != $1.time || $0.value != $1.value }) { sessions[i].readings = merged; update = true }
        }
        if update { study.sessions = sessions }
    }
    func delete(id: UUID) { events.removeAll { $0.id == id }; persist() }
    func persist() {
        do { try JSONEncoder().encode(events).write(to: fileURL,options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication]) }
        catch { notice = "Couldn’t save event history. Please export a backup." }
    }
}
extension EventKind {
    var tint: Color { switch self { case .exercise: return .teal; case .meal: return .orange; case .fasting: return .indigo } }
}
struct LiveDashboard: View {
    @EnvironmentObject var libre: LibreSync
    @EnvironmentObject var study: Study
    @EnvironmentObject var journal: ContextJournal
    @ViewState<Int> private var rangeMinutes = 30
    @ViewState<EventKind?> private var starting = nil
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now,by: 30)) { clock in
                ScrollView {
                    VStack(alignment: .leading,spacing: 20) {
                        liveCard(now: clock.date)
                        HStack(spacing: 10) {
                            ForEach(EventKind.allCases) { kind in
                                Button { starting = kind } label: { VStack(spacing: 10) { Image(systemName: kind.symbol).font(.title2); Text(kind == .exercise ? "Exercise" : kind == .meal ? "Meal" : "Fast").font(.subheadline.weight(.semibold)) }.frame(maxWidth: .infinity).padding(.vertical,18).background(kind.tint.opacity(0.1),in: RoundedRectangle(cornerRadius: 20)).foregroundStyle(kind.tint) }.disabled(!libre.connected || libre.selectedID == nil)
                            }
                        }
                        let relevant = journal.events.filter { $0.patientID == libre.selectedID }.sorted { $0.start > $1.start }
                        let ongoing = relevant.filter { $0.end == nil || ($0.observationEnd ?? .distantPast) > clock.date }
                        if !ongoing.isEmpty { Text("Happening now").font(.title3.bold()); ForEach(ongoing) { e in NavigationLink { ContextDetail(id: e.id) } label: { ContextRow(e: e,now: clock.date) }.buttonStyle(.plain) } }
                        HStack { Text("Your events").font(.title3.bold()); Spacer(); NavigationLink("See all") { ContextHistory() }.font(.subheadline) }
                        if relevant.isEmpty { Text("Mark an exercise, meal, or fast to add context to your readings.").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(Array(relevant.filter { $0.end != nil }.prefix(3))) { e in NavigationLink { ContextDetail(id: e.id) } label: { ContextRow(e: e,now: clock.date) }.buttonStyle(.plain) }
                    }.padding(20)
                }.background(Color(.systemGroupedBackground))
                .refreshable { await libre.sync(study: study); journal.refresh(cache: libre.cache.byPatient,study: study) }
            }.navigationTitle("Live glucose").navigationBarTitleDisplayMode(.inline)
            .toolbar { NavigationLink { LibreConnectionView() } label: { Image(systemName: "antenna.radiowaves.left.and.right") }.accessibilityLabel("LibreLinkUp connection") }
            .sheet(item: $starting) { kind in StartContext(kind: kind) }
        }
    }
    @ViewBuilder func liveCard(now: Date) -> some View {
        Panel {
            HStack { Label(libre.connected ? "LibreLinkUp" : "Not connected",systemImage: "waveform.path.ecg").font(.subheadline.weight(.semibold)); Spacer(); if libre.busy { ProgressView() } else { Button { Task { await libre.sync(study: study); journal.refresh(cache: libre.cache.byPatient,study: study) } } label: { Image(systemName: "arrow.clockwise") }.disabled(!libre.connected || !libre.canRequest).accessibilityLabel("Refresh glucose") } }
            let p = (libre.selectedID.flatMap { libre.cache.byPatient[$0] } ?? []).filter { $0.time <= now }
            if let latest = p.last,libre.connected {
                HStack(alignment: .firstTextBaseline,spacing: 10) { Text(latest.value,format: .number.precision(.fractionLength(1))).font(.system(size: 64,weight: .semibold,design: .rounded)).minimumScaleFactor(0.7); Text("mmol/L").foregroundStyle(.secondary) }
                HStack { Text("Measured \(latest.time.formatted(date: Calendar.current.isDateInToday(latest.time) ? .omitted : .abbreviated,time: .shortened))"); Spacer(); Text(now.timeIntervalSince(latest.time) > 300 ? "Older data" : "Recent reading").foregroundStyle(now.timeIntervalSince(latest.time) > 300 ? .orange : .secondary) }.font(.caption)
                ScrollView(.horizontal,showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([15,30,60,120,180,360,720,1440],id: \.self) { minutes in
                            Button { rangeMinutes = minutes } label: {
                                Text(minutes < 60 ? "\(minutes)m" : "\(minutes/60)h")
                                    .font(.subheadline.weight(.semibold)).fixedSize()
                                    .frame(minWidth: 28).padding(.horizontal,12).padding(.vertical,10)
                                    .foregroundStyle(rangeMinutes == minutes ? Color.white : Color.primary)
                                    .background(rangeMinutes == minutes ? Color.blue : Color(.tertiarySystemGroupedBackground),in: Capsule())
                            }.buttonStyle(.plain)
                            .accessibilityLabel("Show last \(minutes) minutes")
                            .accessibilityValue(rangeMinutes == minutes ? "Selected" : "")
                        }
                    }
                }
                let from = now.addingTimeInterval(-Double(rangeMinutes)*60)
                TimelineCurve(points: p,events: journal.events.filter { $0.patientID == libre.selectedID },from: from,through: now)
                Text(ContextFeedback.recent(p,now: now)).font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("—").font(.system(size: 64,weight: .semibold,design: .rounded))
                Text(libre.connected ? "Waiting for sensor readings" : "Connect LibreLinkUp to see your glucose").foregroundStyle(.secondary)
                if !libre.connected || libre.selectedID == nil { NavigationLink("Open connection") { LibreConnectionView() }.font(.subheadline.bold()) }
            }
            if !libre.notice.isEmpty { Text(libre.notice).font(.caption).foregroundStyle(.secondary) }
            if let last = libre.lastSync { Text("Cloud checked \(last.formatted(date: .omitted,time: .shortened))").font(.caption2).foregroundStyle(.tertiary) }
            Text("Experimental · Cloud updates while open · Not medically validated").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
private struct CurvePoint: Identifiable {
    let reading: Reading
    let segment: Int
    var id: Date { reading.time }
}
struct TimelineCurve: View {
    let points: [Reading]
    let events: [ContextEvent]
    let from: Date
    let through: Date
    private var segments: [CurvePoint] {
        let p = ContextFeedback.readings(points,from: from,through: through); var segment = 0
        return p.enumerated().map { i,r in if i > 0 && r.time.timeIntervalSince(p[i-1].time) > 600 { segment += 1 }; return CurvePoint(reading: r,segment: segment) }
    }
    var body: some View {
        if segments.isEmpty { Text("No readings in this time window").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 170) }
        else {
            Chart {
                ForEach(segments) { p in
                    LineMark(x: .value("Time",p.reading.time),y: .value("Glucose",p.reading.value),series: .value("Segment",p.segment)).foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("Time",p.reading.time),y: .value("Glucose",p.reading.value)).symbolSize(5).foregroundStyle(.blue)
                }
                ForEach(Array(events.filter { $0.start >= from && $0.start <= through }.sorted { $0.start < $1.start }.suffix(8))) { e in
                    RuleMark(x: .value("Event",e.start)).foregroundStyle(e.kind.tint.opacity(0.6)).lineStyle(StrokeStyle(dash: [3,4])).annotation(position: .top) { Image(systemName: e.kind.symbol).font(.caption2).foregroundStyle(e.kind.tint) }
                }
            }.chartXScale(domain: from...max(through,from.addingTimeInterval(1))).chartYAxisLabel("mmol/L").chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.hour().minute()) } }.frame(height: 200).padding(.top,10).accessibilityLabel("Interstitial glucose over time with exercise, meal, and fasting markers")
        }
    }
}
struct StartContext: View {
    let kind: EventKind
    @EnvironmentObject var libre: LibreSync
    @EnvironmentObject var study: Study
    @EnvironmentObject var journal: ContextJournal
    @Environment(\.dismiss) var dismiss
    @ViewState<Date> private var started = Date()
    @ViewState<String> private var name = ""
    @ViewState<String> private var notes = ""
    var duplicate: Bool { journal.events.contains { $0.patientID == libre.selectedID && $0.kind == kind && $0.end == nil } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if kind == .exercise { Picker("Activity",selection: $name) { Text("Choose activity").tag(""); ForEach(["Running","Cycling","Strength","Walking","Other"],id: \.self) { Text($0).tag($0) } } }
                    else { TextField(kind == .meal ? "Meal name (optional)" : "Label (optional)",text: $name) }
                    DatePicker("Started",selection: $started,in: ...Date())
                    TextField("Notes (optional)",text: $notes,axis: .vertical)
                }
                Section { LabeledContent("Glucose profile",value: libre.profileName) }
                if duplicate { Section { Text("An event of this type is already running. Finish it first.").foregroundStyle(.secondary) } }
                if kind == .meal { Section { Text("Tap Finished eating when done. Then follow the next two hours of readings.").font(.caption).foregroundStyle(.secondary) } }
                if !journal.notice.isEmpty { Section { Text(journal.notice).foregroundStyle(.secondary) } }
            }.navigationTitle(kind == .exercise ? "Start exercise" : kind == .meal ? "Log a meal" : "Start fasting").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Start") { guard let patientID = libre.selectedID else { return }; if journal.start(kind: kind,patientID: patientID,profileName: libre.profileName,title: name,notes: notes,time: started,cache: libre.cache.byPatient,study: study) { dismiss() } }.bold().disabled(!libre.connected || libre.selectedID == nil || duplicate || (kind == .exercise && name.isEmpty)) } }
        }
    }
}
struct ContextRow: View {
    let e: ContextEvent
    let now: Date
    var body: some View {
        HStack(spacing: 14) { Image(systemName: e.kind.symbol).font(.title2).foregroundStyle(e.kind.tint).frame(width: 46,height: 46).background(e.kind.tint.opacity(0.1),in: RoundedRectangle(cornerRadius: 15)); VStack(alignment: .leading,spacing: 5) { Text(e.displayTitle).font(.headline); Text(e.start.formatted(date: .abbreviated,time: .shortened)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(e.phase(at: now)).font(.caption).foregroundStyle(e.end == nil ? e.kind.tint : .secondary); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }.padding(16).background(Color(.secondarySystemGroupedBackground),in: RoundedRectangle(cornerRadius: 22))
    }
}
struct ContextDetail: View {
    let id: UUID
    @EnvironmentObject var journal: ContextJournal
    @EnvironmentObject var libre: LibreSync
    @EnvironmentObject var study: Study
    @Environment(\.dismiss) var dismiss
    @ViewState<Bool> private var ending = false
    @ViewState<Bool> private var deleting = false
    var event: ContextEvent? { journal.events.first { $0.id == id } }
    var body: some View {
        TimelineView(.periodic(from: .now,by: 30)) { clock in
            ScrollView {
                if let e = event {
                    VStack(alignment: .leading,spacing: 20) {
                        HStack { Label(e.phase(at: clock.date),systemImage: e.kind.symbol).foregroundStyle(e.kind.tint); Spacer(); Text(elapsed(e,now: clock.date)).monospacedDigit() }.font(.subheadline.weight(.medium))
                        Panel {
                            Text("Glucose & context").font(.headline)
                            TimelineCurve(points: e.readings,events: [e],from: e.start.addingTimeInterval(-900),through: min(clock.date,e.observationEnd ?? clock.date))
                            if let m = ContextFeedback.snapshot(e.readings,from: e.start,through: e.kind == .meal ? min(clock.date,e.observationEnd ?? clock.date) : min(clock.date,e.end ?? clock.date)) { HStack { stat("First",value: m.first.value); Spacer(); stat("Last",value: m.last.value); Spacer(); stat("Change",value: m.change) } }
                            Text("Experimental · Descriptive observations").font(.caption2).foregroundStyle(.secondary)
                        }
                        Panel { Text(e.end == nil ? "During \(e.kind.title.lowercased())" : "During the event").font(.headline); Text(ContextFeedback.primary(e,now: clock.date)).foregroundStyle(.secondary)
                            if let m = ContextFeedback.snapshot(e.readings,from: e.start,through: min(clock.date,e.end ?? clock.date)) { Text("\(m.count) readings · last \(m.last.time.formatted(date: .omitted,time: .shortened))\(e.end == nil && clock.date.timeIntervalSince(m.last.time) > 300 ? " · older data" : "")").font(.caption).foregroundStyle(.secondary) }
                        }
                        if let text = ContextFeedback.after(e,now: clock.date) { Panel { Text(e.kind.afterTitle).font(.headline); Text(text).foregroundStyle(.secondary); if let until = e.observationEnd { Text("Observation ends \(until.formatted(date: .abbreviated,time: .shortened))").font(.caption).foregroundStyle(.secondary); if let m = ContextFeedback.snapshot(e.readings,from: e.end ?? e.start,through: min(clock.date,until)) { Text("Last follow-up reading \(m.last.time.formatted(date: .omitted,time: .shortened))").font(.caption).foregroundStyle(.secondary) } } } }
                        if e.end == nil { Button { ending = true } label: { Text(e.kind.finishTitle).font(.headline).frame(maxWidth: .infinity).padding(14) }.buttonStyle(.borderedProminent).tint(e.kind.tint).clipShape(RoundedRectangle(cornerRadius: 16)) }
                        Panel { LabeledContent("Started",value: e.start.formatted()); if let end = e.end { LabeledContent("Finished",value: end.formatted()) }; LabeledContent("Profile",value: e.profileName); if !e.notes.isEmpty { Text(e.notes).foregroundStyle(.secondary) }; if e.kind == .exercise && e.end != nil { if study.sessions.contains(where: { $0.id == e.id }) { NavigationLink("Open exercise session") { SessionDetail(id: e.id) } } }; DisclosureGroup("How to read this") { Text("These are recorded interstitial glucose changes, not explanations of what caused them. Sensor and cloud data can lag. Gaps and missing start/end readings limit comparisons. This prototype does not assess fueling needs, fasting safety, or meal quality.").font(.caption).foregroundStyle(.secondary) } }.font(.subheadline)
                    }.padding(20)
                }
            }.background(Color(.systemGroupedBackground))
        }.navigationTitle(event?.displayTitle ?? "Event").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { deleting = true } label: { Image(systemName: "trash") }.accessibilityLabel("Delete event") }
        .sheet(isPresented: $ending) { if let event { FinishContext(event: event) } }
        .confirmationDialog("Delete this event?",isPresented: $deleting,titleVisibility: .visible) { Button("Delete event",role: .destructive) { journal.delete(id: id); dismiss() } } message: { Text("A saved exercise session, if any, is kept separately.") }
    }
    func elapsed(_ e: ContextEvent,now: Date) -> String { let minutes = max(0,Int((e.end ?? now).timeIntervalSince(e.start)/60)); return minutes >= 60 ? "\(minutes/60)h \(minutes%60)m" : "\(minutes)m" }
    func stat(_ name: String,value: Double) -> some View { VStack(alignment: .leading,spacing: 5) { Text(name).font(.caption).foregroundStyle(.secondary); Text(value,format: .number.precision(.fractionLength(1))).font(.title2.weight(.semibold)) } }
}
struct FinishContext: View {
    let event: ContextEvent
    @EnvironmentObject var journal: ContextJournal
    @EnvironmentObject var libre: LibreSync
    @EnvironmentObject var study: Study
    @Environment(\.dismiss) var dismiss
    @ViewState<Date> private var finished = Date()
    var body: some View {
        NavigationStack { Form { Section { DatePicker("Finished",selection: $finished,in: event.start...max(Date(),event.start)) }; Section { Text(event.kind == .meal ? "Glucose observations continue for two hours." : "Glucose observations continue for one hour.").font(.caption).foregroundStyle(.secondary) } }.navigationTitle(event.kind.finishTitle).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Finish") { journal.finish(id: event.id,time: finished,cache: libre.cache.byPatient,study: study); dismiss() }.bold().disabled(finished <= event.start) } } }
    }
}
struct ContextHistory: View {
    @EnvironmentObject var journal: ContextJournal
    @ViewState<Int> private var filter = 0
    var shown: [ContextEvent] { journal.events.filter { filter == 0 || $0.kind == EventKind.allCases[filter-1] }.sorted { $0.start > $1.start } }
    var body: some View {
        ScrollView { LazyVStack(spacing: 14) { Picker("Filter",selection: $filter) { Text("All").tag(0); Text("Exercise").tag(1); Text("Meals").tag(2); Text("Fasts").tag(3) }.pickerStyle(.segmented); if shown.isEmpty { ContentUnavailableView("No events yet",systemImage: "clock",description: Text("Start an event from Live glucose.")) }; ForEach(shown) { e in NavigationLink { ContextDetail(id: e.id) } label: { ContextRow(e: e,now: Date()) }.buttonStyle(.plain) } }.padding(20) }.background(Color(.systemGroupedBackground)).navigationTitle("Events").toolbar { ShareLink(item: ContextJournal.file) { Image(systemName: "square.and.arrow.up") }.simultaneousGesture(TapGesture().onEnded { if journal.notice.isEmpty { journal.persist() } }) }
    }
}
