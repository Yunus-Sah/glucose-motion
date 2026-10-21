import SwiftUI
import Security

private enum LibreKeychain {
    static let service = "GlucoseMotion.LibreLinkUp"
    static var query: [String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"session"] }
    static func load() -> LibreCredential? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary,&result) == errSecSuccess,let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(LibreCredential.self,from: data)
    }
    static func save(_ credential: LibreCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let attrs: [String:Any] = [kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary,attrs as CFDictionary)
        if result == errSecItemNotFound {
            var q = query; attrs.forEach { q[$0.key] = $0.value }
            let added = SecItemAdd(q as CFDictionary,nil)
            guard added == errSecSuccess else { throw LibreRequestFailure(reason: .keychain,stage: "Secure login",code: "Keychain \(added)") }
        } else if result != errSecSuccess { throw LibreRequestFailure(reason: .keychain,stage: "Secure login",code: "Keychain \(result)") }
    }
    static func delete() { SecItemDelete(query as CFDictionary) }
}
struct LibreCredentialStorage {
    var load: () -> LibreCredential?
    var save: (LibreCredential) throws -> Void
    var delete: () -> Void
    static var keychain: LibreCredentialStorage { LibreCredentialStorage(load: LibreKeychain.load,save: LibreKeychain.save,delete: LibreKeychain.delete) }
}
struct LibreLoginResult: Identifiable {
    let id = UUID()
    let success: Bool
    let message: String
}
struct LibreCache: Codable {
    var byPatient: [String:[Reading]] = [:]
}
// Pure merge logic shared by foreground sync, newly saved activities and fixture checks.
enum LibreMerge {
    static func merge(_ sessions: [Session],cache: [String:[Reading]]) -> [Session] {
        sessions.map { original in
            guard !original.demo,original.libreSyncEnabled != false,let id = original.librePatientID,let readings = cache[id],original.end > original.start else { return original }
            var s = original
            let low = s.mealKnown == false ? s.start.addingTimeInterval(-3600) : min(s.meal,s.start.addingTimeInterval(-3600)),high = s.end.addingTimeInterval(3600)
            var map = Dictionary(s.readings.map { ($0.time,$0) },uniquingKeysWith: { _,b in b })
            for r in readings where r.time >= low && r.time <= high { map[r.time] = r }
            s.readings = map.values.sorted { $0.time < $1.time }
            return s
        }
    }
}
@MainActor final class LibreSync: ObservableObject {
    @Published private(set) var credential: LibreCredential?
    @Published private(set) var profiles: [LibreProfile] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var busy = false
    @Published private(set) var progress = ""
    @Published var loginResult: LibreLoginResult?
    @Published private(set) var notice = ""
    @Published private(set) var lastSync: Date?
    @Published private(set) var cache = LibreCache()
    @Published private(set) var retryAfter = Date.distantPast
    private let client: LibreClient
    private var generation = UUID()
    private let cacheURL: URL
    private let credentialStorage: LibreCredentialStorage
    private let defaults: UserDefaults
    var connected: Bool { credential != nil }
    var latest: Reading? { guard let selectedID else { return nil }; return cache.byPatient[selectedID]?.last }
    var profileName: String { profiles.first { $0.id == selectedID }?.name ?? "Choose a profile" }
    var canRequest: Bool { !busy && Date() >= retryAfter }
    init(client: LibreClient = LibreClient(),credentialStorage: LibreCredentialStorage = .keychain,cacheURL: URL? = nil,defaults: UserDefaults = .standard) {
        self.client = client; self.credentialStorage = credentialStorage; self.defaults = defaults
        self.cacheURL = cacheURL ?? URL.documentsDirectory.appending(path: "libre-cache.json")
        credential = credentialStorage.load(); selectedID = credential?.patientID
        if let data = try? Data(contentsOf: self.cacheURL),let saved = try? JSONDecoder().decode(LibreCache.self,from: data) { cache = saved }
        let until = defaults.double(forKey: "libre.retryAfter")
        retryAfter = Date(timeIntervalSince1970: until)
    }
    @discardableResult func signIn(email: String,password: String,host: String,study: Study) async -> Bool {
        guard canRequest else {
            let message = busy ? "A connection request is already running. Please wait for it to finish." : "Please wait until \(retryAfter.formatted(date: .omitted,time: .shortened)) before trying again."
            loginResult = LibreLoginResult(success: false,message: message)
            return false
        }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,!password.isEmpty else {
            loginResult = LibreLoginResult(success: false,message: "Enter your LibreLinkUp email and password.")
            return false
        }
        busy = true; progress = "Contacting Abbott…"; notice = ""; loginResult = nil; let g = generation
        defer { busy = false; progress = "" }
        do {
            var c = try await client.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines),password: password,host: host)
            guard g == generation else { return false }
            progress = "Saving secure login…"
            do { try credentialStorage.save(c) } catch let error as LibreRequestFailure { throw error } catch { throw LibreError.keychain }
            credential = c
            c.patientID = nil; selectedID = nil
            progress = "Loading shared profiles…"
            let available = try await client.profiles(c)
            guard g == generation else { return false }
            profiles = available
            notice = profiles.isEmpty ? "No shared profiles yet. Accept the invitation in LibreLinkUp, then refresh." : "Signed in. Tap your shared profile to start syncing."
            loginResult = LibreLoginResult(success: true,message: notice)
            return true
        } catch {
            guard g == generation else { return false }
            if error is CancellationError || Task.isCancelled {
                notice = "The connection was interrupted. Try again when the app is active."
            } else { handle(error) }
            loginResult = LibreLoginResult(success: connected,message: connected ? "Your login was saved, but shared profiles could not be loaded. Use Refresh to try again.\n\n\(notice)" : notice)
            return connected
        }
    }
    func choose(_ profile: LibreProfile,study: Study) async {
        guard !busy,var c = credential else { return }
        generation = UUID(); c.patientID = profile.id
        do { try credentialStorage.save(c); credential = c; selectedID = profile.id; notice = "" }
        catch { handle(error); return }
        await sync(study: study)
    }
    func sync(study: Study) async {
        guard canRequest,let c = credential else { return }
        busy = true; progress = "Refreshing glucose…"; let g = generation
        defer { busy = false; progress = "" }
        do {
            // Fetch connections again before each graph: verify the selected profile is still shared.
            let available = try await client.profiles(c)
            guard g == generation else { return }
            profiles = available
            guard let selectedID else { notice = available.isEmpty ? "No shared profiles yet. Check the invitation in LibreLinkUp." : "Choose a profile to start syncing."; return }
            guard available.contains(where: { $0.id == selectedID }) else { notice = "This profile is no longer shared. Choose another profile."; self.selectedID = nil; return }
            let readings = try await client.readings(c,patientID: selectedID)
            guard g == generation,!Task.isCancelled else { return }
            let existing = cache.byPatient[selectedID] ?? []
            var map = Dictionary(existing.map { ($0.time,$0) },uniquingKeysWith: { _,b in b })
            let cutoff = Date().addingTimeInterval(-30*86400)
            for p in readings { map[p.time] = p }
            let saved = map.values.filter { $0.time >= cutoff }.sorted { $0.time < $1.time }
            var updated = cache; updated.byPatient[selectedID] = saved
            // Never report a successful sync if the on-device cache could not be saved.
            let data = try JSONEncoder().encode(updated)
            try data.write(to: cacheURL,options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            cache = updated; lastSync = Date(); notice = readings.isEmpty ? "Waiting for sensor data. Your sensor may still be initializing." : ""
            apply(to: study)
        } catch { if g == generation,!Task.isCancelled { handle(error) } }
    }
    func apply(to study: Study) {
        let merged = LibreMerge.merge(study.sessions,cache: cache.byPatient)
        // Avoid a publish/persist loop when a session's context hasn't changed its data.
        if zip(merged,study.sessions).contains(where: { a,b in a.readings.count != b.readings.count || zip(a.readings,b.readings).contains { $0.time != $1.time || $0.value != $1.value } }) { study.sessions = merged }
    }
    func link(sessionID: UUID,study: Study) {
        guard let patientID = selectedID,let i = study.sessions.firstIndex(where: { $0.id == sessionID }),!study.sessions[i].demo else { return }
        guard study.sessions[i].librePatientID == nil || study.sessions[i].librePatientID == patientID else { study.message = "This activity belongs to another shared profile. Create a new activity to keep their readings separate."; return }
        study.sessions[i].librePatientID = patientID; study.sessions[i].libreSyncEnabled = true; apply(to: study)
    }
    func unlink(sessionID: UUID,study: Study) {
        if let i = study.sessions.firstIndex(where: { $0.id == sessionID }) { study.sessions[i].libreSyncEnabled = false }
    }
    func disconnect() {
        generation = UUID(); credentialStorage.delete(); credential = nil; selectedID = nil; profiles = []; cache = LibreCache(); lastSync = nil; notice = ""
        try? FileManager.default.removeItem(at: cacheURL)
        // Imported readings in saved activities are intentionally retained.
    }
    private func handle(_ error: Error) {
        if error is CancellationError { return }
        notice = (error as? LibreRequestFailure)?.localizedDescription ?? (error as? LibreError)?.localizedDescription ?? "Couldn’t save synced data. Try again."
        if let e = (error as? LibreRequestFailure)?.reason ?? (error as? LibreError) {
            switch e {
            case .expired: credential = nil; selectedID = nil; profiles = []; credentialStorage.delete()
            case .limited: retryAfter = Date().addingTimeInterval(15*60); defaults.set(retryAfter.timeIntervalSince1970,forKey: "libre.retryAfter")
            case .network,.server: retryAfter = Date().addingTimeInterval(120)
            case .login: retryAfter = Date().addingTimeInterval(10)
            default: break
            }
        }
    }
}
struct LibreConnectionView: View {
    @EnvironmentObject var libre: LibreSync
    @EnvironmentObject var study: Study
    @ViewState<String> private var email = ""
    @ViewState<String> private var password = ""
    @ViewState<String> private var host = "api-eu.libreview.io"
    @ViewState<Bool> private var disconnect = false
    @FocusState private var input: Field?
    private enum Field: Hashable { case email, password }
    var body: some View {
        Form {
            if libre.busy {
                Section { HStack(spacing: 12) { ProgressView(); Text(libre.progress.isEmpty ? "Connecting…" : libre.progress) }.accessibilityElement(children: .combine) }
            }
            if !libre.notice.isEmpty {
                Section { Text(libre.notice).font(.subheadline).foregroundStyle(.primary).textSelection(.enabled) }
            }
            if !libre.connected {
                Section {
                    TextField("Email",text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().focused($input,equals: .email).submitLabel(.next).onSubmit { input = .password }
                    SecureField("Password",text: $password).textContentType(.password).focused($input,equals: .password).submitLabel(.go).onSubmit { connect() }
                    TimelineView(.periodic(from: .now,by: 1)) { clock in
                        Button { connect() } label: { HStack { Text(libre.busy ? "Connecting…" : "Connect"); Spacer(); if libre.busy { ProgressView() } } }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || libre.busy || clock.date < libre.retryAfter)
                    }
                } header: { Text("LibreLinkUp account") } footer: { Text("Use the receiving account you signed into LibreLinkUp with. Your password is sent to Abbott and is not saved.") }
                Section { DisclosureGroup("Region") { Picker("Server",selection: $host) { Text("Europe / Sweden").tag("api-eu.libreview.io"); Text("Germany").tag("api-de.libreview.io"); Text("United States").tag("api-us.libreview.io"); Text("Canada").tag("api-ca.libreview.io"); Text("Australia").tag("api-au.libreview.io"); Text("Asia Pacific").tag("api-ap.libreview.io"); Text("Japan").tag("api-jp.libreview.io") } } }.disabled(libre.busy)
            } else {
                Section("Shared profiles") {
                    ForEach(libre.profiles) { profile in
                        Button { Task { await libre.choose(profile,study: study) } } label: { HStack { Text(profile.name); Spacer(); if libre.selectedID == profile.id { Image(systemName: "checkmark.circle.fill") } } }.disabled(!libre.canRequest)
                    }
                    TimelineView(.periodic(from: .now,by: 1)) { clock in
                        Button { Task { await libre.sync(study: study) } } label: { Label(libre.busy ? "Refreshing…" : "Refresh",systemImage: "arrow.clockwise") }.disabled(libre.busy || clock.date < libre.retryAfter)
                    }
                }
                if let latest = libre.latest { Section("Last reading") { HStack(alignment: .firstTextBaseline) { Text(latest.value,format: .number.precision(.fractionLength(1))).font(.largeTitle.bold()); Text("mmol/L").foregroundStyle(.secondary) }; Text(latest.time.formatted()).font(.caption).foregroundStyle(.secondary) } }
                Section { Button("Disconnect",role: .destructive) { disconnect = true } }
            }
            TimelineView(.periodic(from: .now,by: 1)) { clock in
                if libre.retryAfter > clock.date { Section { Text("Try again after \(libre.retryAfter.formatted(date: .omitted,time: .shortened)).").font(.caption).foregroundStyle(.secondary) } }
            }
            Section { Text("Unofficial experimental connection. Updates every minute while this app is open. Sync resumes when you return. Not an alarm or medical monitoring app.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("LibreLinkUp").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .alert(item: $libre.loginResult) { result in Alert(title: Text(result.success ? "Signed in" : "Couldn’t connect"),message: Text(result.message),dismissButton: .default(Text("OK"))) }
        .confirmationDialog("Disconnect LibreLinkUp?",isPresented: $disconnect,titleVisibility: .visible) { Button("Disconnect",role: .destructive) { libre.disconnect() } } message: { Text("Login and cached cloud data will be removed. Saved activities will stay.") }
        .onDisappear { password = "" }
    }
    private func connect() {
        // Snapshot inputs before scheduling the request. Keep the field on failure for correction.
        let enteredEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredPassword = password
        let enteredHost = host
        guard !enteredEmail.isEmpty,!enteredPassword.isEmpty,!libre.busy else { return }
        input = nil
        Task {
            let signedIn = await libre.signIn(email: enteredEmail,password: enteredPassword,host: enteredHost,study: study)
            if signedIn { password = "" }
        }
    }
}
struct LibreHomeCard: View {
    @EnvironmentObject var libre: LibreSync
    var body: some View {
        NavigationLink { LibreConnectionView() } label: {
            Panel {
                HStack { Label("LibreLinkUp",systemImage: "antenna.radiowaves.left.and.right").font(.headline); Spacer(); if libre.busy { ProgressView() } else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) } }
                if libre.connected,let r = libre.latest {
                    HStack(alignment: .firstTextBaseline) { Text(r.value,format: .number.precision(.fractionLength(1))).font(.system(size: 42,weight: .semibold,design: .rounded)); Text("mmol/L").foregroundStyle(.secondary) }
                    TimelineView(.periodic(from: .now,by: 60)) { context in Text("Last reading · \(r.time.formatted(date: Calendar.current.isDateInToday(r.time) ? .omitted : .abbreviated,time: .shortened))\(context.date.timeIntervalSince(r.time) > 300 ? " · Older data" : "")").font(.caption).foregroundStyle(.secondary) }
                } else { Text(libre.connected ? (libre.selectedID == nil ? "Choose your shared profile" : "Waiting for sensor data") : "Connect your glucose data").foregroundStyle(.secondary) }
                if !libre.notice.isEmpty { Text(libre.notice).font(.caption).foregroundStyle(.secondary) }
                Text("Experimental · not medically validated").font(.caption2).foregroundStyle(.tertiary)
            }
        }.buttonStyle(.plain)
    }
}
