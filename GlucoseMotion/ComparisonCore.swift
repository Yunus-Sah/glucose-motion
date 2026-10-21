import Foundation

struct ComparedSession {
    let session: Session
    let mealEvent: ContextEvent?
    let exerciseEvent: ContextEvent?
    init(_ session: Session,events: [ContextEvent]) {
        self.session = session
        exerciseEvent = events.first { $0.id == session.id && $0.kind == .exercise && $0.patientID == session.librePatientID }
        if session.mealKnown != false,let patient = session.librePatientID {
            mealEvent = events.filter { $0.kind == .meal && $0.patientID == patient && abs($0.start.timeIntervalSince(session.meal)) < 60 && $0.start <= session.start }.min { abs($0.start.timeIntervalSince(session.meal)) < abs($1.start.timeIntervalSince(session.meal)) }
        } else { mealEvent = nil }
    }
    var mealTime: Date? {
        guard session.mealKnown != false else { return nil }
        if let end = mealEvent?.end,end <= session.start { return end }
        return session.meal <= session.start ? session.meal : nil
    }
    var finishedMeal: Bool { mealEvent?.end != nil && mealTime == mealEvent?.end }
    var delay: Double? { mealTime.map { session.start.timeIntervalSince($0)/60 } }
    var delayLabel: String { delay.map { "\(Int($0.rounded())) min" } ?? "No meal time" }
    var delayExplanation: String { delay == nil ? "Meal timing unavailable" : "\(delayLabel) after meal \(finishedMeal ? "finish" : "start")" }
    var day: String { Self.date(session.start,"d MMM") }
    var dateLabel: String { Self.date(session.start,"d MMM yyyy") }
    var mealName: String { mealEvent?.displayTitle ?? (mealTime == nil ? "No meal recorded" : "Recorded meal") }
    var mealClock: String {
        if let mealEvent { return Self.date(mealEvent.start,"HH:mm") + (mealEvent.end.map { "–"+Self.date($0,"HH:mm") } ?? " (start)") }
        return mealTime.map { Self.date($0,"HH:mm")+" (start)" } ?? "—"
    }
    var trainingClock: String { "\(Self.date(session.start,"HH:mm"))–\(Self.date(session.end,"HH:mm"))" }
    var durationMinutes: Double { session.end.timeIntervalSince(session.start)/60 }
    var mealOffset: Double? { mealTime.map { $0.timeIntervalSince(session.start)/60 } }
    var chartReadings: [Reading] {
        ContextFeedback.readings(session.readings+(exerciseEvent?.readings ?? [])+(mealEvent?.readings ?? []),from: .distantPast,through: .distantFuture)
    }
    var earlyFall: Bool {
        let p = session.window
        guard let first = p.first,p.count >= 4,first.time.timeIntervalSince(session.start) <= 600 else { return false }
        let half = session.start.addingTimeInterval(session.end.timeIntervalSince(session.start)/2)
        return p.filter { $0.time <= half }.contains { $0.value < first.value-0.05 }
    }
    var postChange: (change:Double,minutes:Double)? {
        guard let baseline = session.window.last,session.end.timeIntervalSince(baseline.time) <= 600 else { return nil }
        let p = session.readings.filter { $0.time > session.end && $0.time <= session.end.addingTimeInterval(3600) }.sorted { $0.time < $1.time }
        guard p.count >= 2,let last = p.last,last.time.timeIntervalSince(session.end) >= 300 else { return nil }
        return (last.value-baseline.value,last.time.timeIntervalSince(session.end)/60)
    }
    static func date(_ date: Date,_ format: String) -> String { let f = DateFormatter(); f.locale = Locale(identifier:"en_GB"); f.dateFormat = format; return f.string(from:date) }
    static func value(_ v: Double) -> String { String(format:"%.2f",locale:Locale(identifier:"en_GB"),v) }
    static func signed(_ v: Double) -> String { String(format:"%+.2f",locale:Locale(identifier:"en_GB"),v) }
}
struct ComparisonData {
    let a: ComparedSession
    let b: ComparedSession
    var compatible: Bool {
        if let x = a.session.librePatientID,let y = b.session.librePatientID { return x == y }
        return true
    }
    var title: String {
        let types = a.session.title == b.session.title ? a.session.title : "\(a.session.title) vs \(b.session.title)"
        if a.delay != nil && b.delay != nil && a.finishedMeal == b.finishedMeal { return "\(types) · \(a.delayLabel) vs \(b.delayLabel)" }
        return "\(types) · \(a.day) vs \(b.day)"
    }
    var subtitle: String { a.delay != nil && b.delay != nil && a.finishedMeal == b.finishedMeal ? "After meal \(a.finishedMeal ? "finish" : "start") · recorded timing" : "Selected exercise sessions" }
    var domain: ClosedRange<Double> {
        let low = min(-30,a.mealOffset ?? -30,b.mealOffset ?? -30)-15
        return (floor(low/30)*30)...(ceil((max(a.durationMinutes,b.durationMinutes)+60)/30)*30)
    }
    var values: [Double] {
        [a,b].flatMap { item in item.chartReadings.filter { domain.contains($0.time.timeIntervalSince(item.session.start)/60) }.map(\.value) }
    }
    var yDomain: ClosedRange<Double> {
        let p = values
        return max(0,floor(((p.min() ?? 4)-0.5)*2)/2)...(ceil(((p.max() ?? 8)+0.5)*2)/2)
    }
    var summary: String {
        guard let x = a.session.stats,let y = b.session.stats else { return "Not enough readings to compare." }
        func verb(_ d:Double) -> String { abs(d)<0.05 ? "was nearly unchanged" : d<0 ? "decreased" : "increased" }
        return "During exercise, glucose \(verb(x[4])) in A (\(ComparedSession.signed(x[4]))) and \(verb(y[4])) in B (\(ComparedSession.signed(y[4]))) mmol/L."
    }
    var duringFeedback: String {
        func describe(_ item: ComparedSession,_ letter:String) -> String {
            guard let m = item.session.stats else { return "\(letter): insufficient workout readings." }
            let ending = abs(m[4]) < 0.05 ? "ended close to its starting value" : "ended \(ComparedSession.value(abs(m[4]))) mmol/L \(m[4] > 0 ? "above" : "below") its start"
            return "\(letter) \(item.earlyFall && m[4] > 0.05 ? "fell in the first half, then " : "")\(ending)."
        }
        return describe(a,"A")+" "+describe(b,"B")
    }
    var afterFeedback: String {
        func text(_ item: ComparedSession,_ letter:String) -> String {
            guard let post = item.postChange else { return "\(letter): insufficient follow-up readings." }
            return "\(letter) \(ComparedSession.signed(post.change)) mmol/L at ~\(Int(post.minutes.rounded())) min."
        }
        return "From the last exercise reading to the last available reading within 60 min: "+text(a,"A")+" "+text(b,"B")
    }
    var interpretationFeedback: String {
        let limit = "One session per condition cannot isolate meal timing. Repeat the conditions before choosing a timing strategy."
        guard let x = a.postChange,let y = b.postChange,x.minutes >= 45,y.minutes >= 45,abs(x.minutes-y.minutes) <= 5 else { return "Follow-up coverage is too different or incomplete to compare the drops fairly. "+limit }
        guard min(x.change,y.change) < -0.05,abs(x.change-y.change) >= 0.05 else { return "There was no clearly larger recorded follow-up drop in this pair. "+limit }
        let larger = x.change < y.change ? a : b
        let letter = x.change < y.change ? "A" : "B"
        if let da = a.delay,let db = b.delay,a.finishedMeal == b.finishedMeal,abs(da-db)>1 {
            let interval = (x.change < y.change ? da : db) > (x.change < y.change ? db : da) ? "longer" : "shorter"
            return "The \(interval) meal-to-workout interval (\(larger.delayLabel), \(letter)) coincided with a larger follow-up drop. "+limit
        }
        return "\(letter) showed a larger recorded follow-up drop. "+limit
    }

}
