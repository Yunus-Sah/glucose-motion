import Foundation

enum EventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case exercise, meal, fasting
    var id: String { rawValue }
    var title: String { switch self { case .exercise: return "Exercise"; case .meal: return "Meal"; case .fasting: return "Fasting" } }
    var symbol: String { switch self { case .exercise: return "figure.run"; case .meal: return "fork.knife"; case .fasting: return "moon" } }
    var finishTitle: String { switch self { case .exercise: return "Finish workout"; case .meal: return "Finished eating"; case .fasting: return "Finish fast" } }
    var afterTitle: String { switch self { case .exercise: return "After exercise"; case .meal: return "After meal"; case .fasting: return "After fasting" } }
    // Observation windows are display choices, not physiological or clinical cutoffs.
    var followUp: TimeInterval { self == .meal ? 7200 : 3600 }
}
struct ContextEvent: Codable, Identifiable, Sendable {
    var id = UUID()
    var kind: EventKind
    var patientID: String
    var profileName: String
    var start: Date
    var end: Date? = nil
    var title: String = ""
    var notes: String = ""
    var rpe: Int? = nil // Legacy backup field; no longer collected.
    var readings: [Reading] = []
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.title : title }
    var observationEnd: Date? { end?.addingTimeInterval(kind.followUp) }
    func phase(at now: Date) -> String { guard let end else { return kind == .meal ? "Eating" : kind == .fasting ? "Fasting" : "Exercising" }; return now < end.addingTimeInterval(kind.followUp) ? kind.afterTitle : "Summary" }
}
struct GlucoseSnapshot: Sendable {
    var first: Reading
    var last: Reading
    var min: Double
    var max: Double
    var count: Int
    var hasGaps: Bool
    var change: Double { last.value-first.value }
    var minutes: Int { maxMinutes }
    private var maxMinutes: Int { Swift.max(0,Int(last.time.timeIntervalSince(first.time)/60)) }
}
enum ContextFeedback {
    static func readings(_ p: [Reading],from: Date,through: Date) -> [Reading] {
        guard through >= from else { return [] }
        var map: [Date:Reading] = [:]
        for v in p where v.time >= from && v.time <= through && v.value.isFinite && v.value > 0 { map[v.time] = v }
        return map.values.sorted { $0.time < $1.time }
    }
    static func snapshot(_ points: [Reading],from: Date,through: Date) -> GlucoseSnapshot? {
        let p = readings(points,from: from,through: through)
        guard let first = p.first,let last = p.last else { return nil }
        return GlucoseSnapshot(first: first,last: last,min: p.map(\.value).min()!,max: p.map(\.value).max()!,count: p.count,hasGaps: zip(p,p.dropFirst()).contains { $1.time.timeIntervalSince($0.time) > 15*60 })
    }
    static func nearBefore(_ time: Date,in p: [Reading]) -> Reading? { readings(p,from: time.addingTimeInterval(-600),through: time).last }
    static func number(_ v: Double) -> String { String(format: "%.1f",v) }
    static func changeText(_ delta: Double) -> String {
        if abs(delta) < 0.05 { return "was unchanged" }
        return "\(delta > 0 ? "increased" : "decreased") by \(number(abs(delta))) mmol/L"
    }
    static func primary(_ event: ContextEvent,now: Date) -> String {
        let stop = event.kind == .meal ? min(now,event.observationEnd ?? now) : min(now,event.end ?? now)
        guard let m = snapshot(event.readings,from: event.start,through: stop),m.count >= 2,m.minutes >= 5 else { return event.observationEnd.map { now >= $0 } == true ? "Not enough readings were recorded to describe this event." : "Waiting for enough readings during this \(event.kind == .exercise ? "workout" : event.kind.rawValue) to describe a change." }
        let early = m.first.time.timeIntervalSince(event.start) > 600
        let tail = m.hasGaps || early ? " Coverage is incomplete." : ""
        switch event.kind {
        case .exercise: return "Recorded glucose \(changeText(m.change)) over \(m.minutes) min during this workout.\(tail)"
        case .fasting: return "During this logged fast, recorded glucose ranged from \(number(m.min)) to \(number(m.max)) mmol/L.\(tail)"
        case .meal:
            let observed = min(now,event.observationEnd ?? now)
            guard let baseline = nearBefore(event.start,in: event.readings),let latest = readings(event.readings,from: event.start,through: observed).last else { return "No glucose reading was available close to meal start. A before-meal comparison is unavailable." }
            return "Recorded glucose \(changeText(latest.value-baseline.value)) from the reading near meal start.\(tail)"
        }
    }
    static func after(_ event: ContextEvent,now: Date) -> String? {
        guard let end = event.end,now >= end else { return nil }
        let until = min(now,end.addingTimeInterval(event.kind.followUp))
        guard let m = snapshot(event.readings,from: end,through: until),m.count >= 2,m.minutes >= 5 else { return now >= end.addingTimeInterval(event.kind.followUp) ? "Not enough follow-up readings were recorded." : "Waiting for readings \(event.kind.afterTitle.lowercased())." }
        if event.kind == .meal {
            guard let whole = snapshot(event.readings,from: event.start,through: until) else { return nil }
            let soFar = now < end.addingTimeInterval(event.kind.followUp) ? "so far" : "in this observation window"
            return "Highest recorded glucose \(soFar): \(number(whole.max)) mmol/L.\(whole.hasGaps ? " Readings contain gaps." : "")"
        }
        guard let baseline = nearBefore(end,in: event.readings) else { return "No reading was available close to the end. An end-to-follow-up comparison is unavailable." }
        return "In the recorded follow-up, glucose \(changeText(m.last.value-baseline.value)) from the reading near the end.\(m.hasGaps ? " Readings contain gaps." : "")"
    }
    static func recent(_ p: [Reading],now: Date) -> String {
        let current = readings(p,from: now.addingTimeInterval(-86400),through: now).last
        guard let current else { return "Waiting for sensor readings." }
        guard now.timeIntervalSince(current.time) <= 300 else { return "Showing older data. A current trend is unavailable." }
        guard let m = snapshot(p,from: current.time.addingTimeInterval(-1200),through: current.time),m.count >= 2,m.minutes >= 5,!m.hasGaps else { return "Gathering readings for a recent change." }
        return "Recorded glucose \(changeText(m.change)) over \(m.minutes) min."
    }
    static func merge(_ events: [ContextEvent],cache: [String:[Reading]],now: Date) -> [ContextEvent] {
        events.map { event in
            var e = event
            let from = e.start.addingTimeInterval(-900),through = min(now,e.observationEnd ?? now)
            let available = e.readings + (cache[e.patientID] ?? [])
            e.readings = readings(available,from: from,through: through)
            return e
        }
    }
}
