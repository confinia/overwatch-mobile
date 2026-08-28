import Foundation

/// Client for the Overwatch open-data API (`/api/v1`). Read-only: there is
/// nothing to sign into — the app answers "is my station okay?" from public
/// data, and the org/telemetry surface stays on the web where the tokens are.
enum API {
    static let base = URL(string: "https://overwatch.confinia.io/api/v1")!

    struct Station: Decodable, Identifiable, Hashable {
        let observer: String
        let frames: Int
        let satellites: Int
        var id: String { observer }
    }

    struct Day: Decodable, Hashable {
        let day: String
        let frames: Int
        let passes: Int
        /// nil when no passes were available that day — unknown, not zero.
        let hit_rate: Double?
    }

    struct Pass: Decodable, Hashable {
        let norad: Int
        let satellite: String
        let aos: String
        let max_el_deg: Double
        /// Present only on past passes: receptions decoded during the window.
        let frames: Int?
    }

    struct StationHealth: Decodable {
        let observer: String
        let days: [Day]
        let next_passes: [Pass]
        /// Optional: servers older than #366 do not send it.
        let past_passes: [Pass]?
        let recent_rate: Double?
        let baseline_rate: Double?
    }

    private static func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent(path))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func stations() async throws -> [Station] { try await get("stations") }

    static func health(_ observer: String) async throws -> StationHealth {
        try await get("stations/\(observer)/health")
    }
}


extension API {
    struct Frame: Decodable, Hashable {
        let ts: String
        let fields: Int
    }

    struct PassDetail: Decodable {
        let satellite: String
        let aos: String
        let los: String
        let max_el_deg: Double
        let duration_s: Int
        let frames: [Frame]
    }

    static func passDetail(_ observer: String, norad: Int, aos: String)
    async throws -> PassDetail {
        var comps = URLComponents(url: base
            .appendingPathComponent("stations/\(observer)/pass"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "norad", value: String(norad)),
                            .init(name: "aos", value: aos)]
        // URLComponents leaves "+" literal in query values, and the server
        // decodes + as a space — the aos ends in +00:00, so without this the
        // very first pass-detail request 500d (#369). The server also
        // tolerates the mangled form now; belt and braces.
        comps.percentEncodedQuery = comps.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(PassDetail.self, from: data)
    }
}


extension API {
    struct FrameField: Decodable, Hashable {
        let field: String
        let value: JSONValue
    }

    /// A decoded value is a number or a string ("NOMINAL"); decode either.
    enum JSONValue: Decodable, Hashable {
        case num(Double), text(String)
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let n = try? c.decode(Double.self) { self = .num(n) }
            else { self = .text((try? c.decode(String.self)) ?? "—") }
        }
        var display: String {
            switch self {
            case .num(let n): return n == n.rounded() ? String(Int(n))
                                                      : String(format: "%.4g", n)
            case .text(let t): return t
            }
        }
    }

    struct FrameDetail: Decodable {
        let satellite: String
        let ts: String
        let fields: [FrameField]
    }

    static func frame(_ norad: Int, ts: String) async throws -> FrameDetail {
        var comps = URLComponents(url: base
            .appendingPathComponent("satellites/\(norad)/frame"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "ts", value: ts)]
        comps.percentEncodedQuery = comps.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")     // the #369 lesson
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(FrameDetail.self, from: data)
    }

    struct Satellite: Decodable, Hashable {
        let norad: Int
        let name: String
        let has_telemetry: Bool
        let note: String?
        let lat: Double?
        let lon: Double?
        let alt_km: Double?
        let sunlit: Bool?
        let last_frame: String?
    }

    static func satellites() async throws -> [Satellite] {
        try await get("satellites")
    }
}
