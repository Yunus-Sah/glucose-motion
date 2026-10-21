import Foundation
import CryptoKit

struct LibreCredential: Codable, Sendable {
    var token: String
    var accountID: String
    var host: String
    var expires: Double?
    var patientID: String?
}
struct LibreProfile: Identifiable, Sendable {
    let id: String
    let name: String
}
enum LibreError: LocalizedError, Sendable {
    case login, expired, limited, action, region, format, server, network, keychain, blocked, upgrade
    var errorDescription: String? {
        switch self {
        case .login: return "Check your LibreLinkUp email and password. Use the receiving account, not the sensor account."
        case .expired: return "Your login expired. Sign in again to resume syncing."
        case .limited: return "Abbott has temporarily limited requests. Wait at least 15 minutes before trying again."
        case .action: return "Open LibreLinkUp and finish any email verification or account steps, then try again."
        case .region: return "This account’s server region isn’t supported yet. CSV import is still available."
        case .format: return "Abbott returned an unfamiliar response. Sync has stopped; CSV import is still available."
        case .server: return "LibreLinkUp is temporarily unavailable. Try again later."
        case .network: return "Couldn’t reach LibreLinkUp. Check your internet connection."
        case .keychain: return "Couldn’t save the login securely. Unlock your iPhone and try again."
        case .upgrade: return "This connection needs an update for Abbott’s required client version."
        case .blocked: return "Abbott refused this connection. An account step or connection update may be needed."
        }
    }
}
// Diagnostics contain only a request stage and numeric status, never credentials or response bodies.
struct LibreRequestFailure: LocalizedError, Sendable {
    let reason: LibreError
    let stage: String
    let code: String
    var errorDescription: String? { "\(reason.localizedDescription)\n\(stage) · \(code)" }
}
// Restrict transport to Abbott hosts; don't forward authentication across HTTP redirects.
final class LibreRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct LibreClient: Sendable {
    static let regions: [String:String] = ["eu":"api-eu.libreview.io","eu2":"api-eu2.libreview.io","de":"api-de.libreview.io","us":"api-us.libreview.io","ca":"api-ca.libreview.io","ap":"api-ap.libreview.io","au":"api-au.libreview.io","jp":"api-jp.libreview.io","ae":"api-ae.libreview.io","fr":"api-fr.libreview.io","la":"api-la.libreview.io"]
    static let allowedHosts = Set(regions.values).union(["api.libreview.io"])
    static let clientVersion = "4.16.0"
    let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let c = URLSessionConfiguration.ephemeral
            c.urlCache = nil; c.httpCookieStorage = nil; c.urlCredentialStorage = nil
            c.timeoutIntervalForRequest = 25; c.timeoutIntervalForResource = 35
            self.session = URLSession(configuration: c,delegate: LibreRedirectGuard(),delegateQueue: nil)
        }
    }
    func request(host: String, path: [String], credential: LibreCredential? = nil, body: [String:String]? = nil) async throws -> [String:Any] {
        let stage = path.last == "login" ? "Sign-in" : path.last == "graph" ? "Readings" : "Shared profiles"
        func failure(_ reason: LibreError,_ code: String) -> LibreRequestFailure { LibreRequestFailure(reason: reason,stage: stage,code: code) }
        guard Self.allowedHosts.contains(host), var url = URL(string: "https://\(host)") else { throw LibreError.region }
        for segment in path { url.appendPathComponent(segment) }
        var req = URLRequest(url: url)
        req.httpMethod = body == nil ? "GET" : "POST"
        req.setValue("application/json",forHTTPHeaderField: "Content-Type")
        req.setValue("application/json",forHTTPHeaderField: "Accept")
        req.setValue("llu.android",forHTTPHeaderField: "product")
        req.setValue(Self.clientVersion,forHTTPHeaderField: "version")
        req.setValue("no-cache",forHTTPHeaderField: "Cache-Control")
        if let credential {
            req.setValue("Bearer \(credential.token)",forHTTPHeaderField: "Authorization")
            let hash = SHA256.hash(data: Data(credential.accountID.utf8)).map { String(format: "%02x",$0) }.joined()
            req.setValue(hash,forHTTPHeaderField: "account-id")
        }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data, response: URLResponse
        do { (data,response) = try await session.data(for: req) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError { if Task.isCancelled { throw CancellationError() }; throw failure(.network,"Network \(error.code.rawValue)") }
        catch { if Task.isCancelled { throw CancellationError() }; throw failure(.network,"Network error") }
        guard let http = response as? HTTPURLResponse else { throw failure(.format,"Missing HTTP response") }
        // Parse only allowlisted error metadata. Never show or log entire response bodies.
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any]
        if payload?["status"] as? Int == 920 {
            let required = Self.minimumVersion(payload)
            throw failure(.upgrade,"HTTP \(http.statusCode) · status 920" + (required.map { " · minimum version \($0)" } ?? ""))
        }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw failure(body == nil ? .expired : .login,"HTTP 401")
        case 403: throw failure(.blocked,"HTTP 403")
        case 429,476: throw failure(.limited,"HTTP \(http.statusCode)")
        default: throw failure(.server,"HTTP \(http.statusCode)")
        }
        guard let json = payload, let status = json["status"] as? Int else { throw failure(.format,"Unrecognized response") }
        switch status {
        case 0: return json
        case 2: throw failure(body == nil ? .expired : .login,"Account status 2")
        case 4: throw failure(.action,"Account status 4")
        case 429,476: throw failure(.limited,"Account status \(status)")
        default: throw failure(.server,"Account status \(status)")
        }
    }
    static func minimumVersion(_ payload: [String:Any]?) -> String? {
        guard let data = payload?["data"] as? [String:Any],let version = data["minimumVersion"] as? String,
              version.count <= 20,version.range(of: #"^[0-9]{1,4}\.[0-9]{1,4}(\.[0-9]{1,4})?$"#,options: .regularExpression) != nil else { return nil }
        return version
    }
    func login(email: String,password: String,host: String = "api-eu.libreview.io") async throws -> LibreCredential {
        var currentHost = host
        // Only follow explicit region metadata, at most twice. Never retry a rejected login.
        for _ in 0..<3 {
            let root = try await request(host: currentHost,path: ["llu","auth","login"],body: ["email":email,"password":password])
            guard let d = root["data"] as? [String:Any] else { throw LibreError.format }
            if d["redirect"] as? Bool == true {
                guard let region = d["region"] as? String,let h = Self.regions[region],h != currentHost else { throw LibreError.region }
                currentHost = h; continue
            }
            if d["step"] != nil { throw LibreError.action }
            guard let ticket = d["authTicket"] as? [String:Any],let token = ticket["token"] as? String,!token.isEmpty,let user = d["user"] as? [String:Any],let id = user["id"] as? String,!id.isEmpty else { throw LibreError.format }
            return LibreCredential(token: token,accountID: id,host: currentHost,expires: ticket["expires"] as? Double,patientID: nil)
        }
        throw LibreError.region
    }
    func profiles(_ c: LibreCredential) async throws -> [LibreProfile] {
        let root = try await request(host: c.host,path: ["llu","connections"],credential: c)
        guard let data = root["data"] as? [[String:Any]] else { throw LibreError.format }
        var result: [LibreProfile] = []
        for p in data {
            guard let id = p["patientId"] as? String,!id.isEmpty else { throw LibreError.format }
            let name = [p["firstName"] as? String,p["lastName"] as? String].compactMap { $0 }.joined(separator: " ")
            if !result.contains(where: { $0.id == id }) { result.append(LibreProfile(id: id,name: name.isEmpty ? "Shared profile" : name)) }
        }
        return result
    }
    func readings(_ c: LibreCredential,patientID: String) async throws -> [Reading] {
        let root = try await request(host: c.host,path: ["llu","connections",patientID,"graph"],credential: c)
        return try Self.decodeGraph(root,patientID: patientID)
    }
    static func decodeGraph(_ root: [String:Any],patientID: String) throws -> [Reading] {
        guard let data = root["data"] as? [String:Any],let connection = data["connection"] as? [String:Any],connection["patientId"] as? String == patientID else { throw LibreError.format }
        let graph = data["graphData"] as? [[String:Any]] ?? []
        var raw = graph
        if let current = connection["glucoseMeasurement"] as? [String:Any],!current.isEmpty { raw.append(current) }
        var map: [Date:Reading] = [:]
        for item in raw { if let p = decodeReading(item) { map[p.time] = p } }
        if !raw.isEmpty && map.isEmpty { throw LibreError.format }
        return map.values.sorted { $0.time < $1.time }
    }
    static func decodeReading(_ item: [String:Any]) -> Reading? {
        // FactoryTimestamp is UTC, independent of the phone's locale and daylight saving.
        guard let timestamp = item["FactoryTimestamp"] as? String else { return nil }
        let iso = ISO8601DateFormatter()
        var time = iso.date(from: timestamp)
        if time == nil { iso.formatOptions.insert(.withFractionalSeconds); time = iso.date(from: timestamp) }
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.timeZone = TimeZone(secondsFromGMT: 0); df.isLenient = false
        for format in ["M/d/yyyy h:mm:ss a","M/d/yyyy H:mm:ss","yyyy-MM-dd HH:mm:ss"] where time == nil { df.dateFormat = format; time = df.date(from: timestamp) }
        let value: Double?
        if let mg = item["ValueInMgPerDl"] as? Double { value = mg/18.0182 }
        else if let v = item["Value"] as? Double,let units = item["GlucoseUnits"] as? Int,units == 1 || units == 2 { value = units == 1 ? v/18.0182 : v }
        else { value = nil }
        guard let time,let value,value.isFinite,value > 0,time.timeIntervalSince1970.isFinite else { return nil }
        return Reading(time: time,value: value)
    }
}
