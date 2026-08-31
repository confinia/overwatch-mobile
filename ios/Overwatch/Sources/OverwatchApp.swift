import SwiftUI

/// One screen, iso with Android and the PWA: pick your station once, then the
/// app opens straight onto it. Nothing stands between launch and the answer
/// to "is my station okay?" — same rule as ecobuilding: no account, no tour.
@main
struct OverwatchApp: App {
    var body: some Scene {
        WindowGroup { RootView().preferredColorScheme(.dark) }
    }
}

struct RootView: View {
    @AppStorage("station") private var saved = ""
    var body: some View {
        NavigationStack {
            if saved.isEmpty { StationList() }
            else { StationView(observer: saved) }
        }
    }
}

struct StationList: View {
    @State private var stations: [API.Station] = []
    @State private var query = ""
    @State private var failed = false

    var hits: [API.Station] {
        query.isEmpty ? stations
        : stations.filter { $0.observer.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(hits.prefix(30)) { s in
            NavigationLink(value: s.observer) {
                VStack(alignment: .leading) {
                    Text(s.observer).bold()
                    Text("\(s.frames) frames · \(s.satellites) satellites · 7 days")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationDestination(for: String.self) { StationView(observer: $0) }
        .searchable(text: $query, prompt: "Your callsign or station")
        .navigationTitle("My station")
        .overlay {
            // not ContentUnavailableView: that is iOS 17+, and the 16.0 target
            // is deliberate — a ham's phone is often not a new phone
            if failed { Unreachable(text: "Couldn't reach Overwatch") }
        }
        .task {
            do { stations = try await API.stations() } catch { failed = true }
        }
    }
}

/// The API sends fractional seconds ("2026-08-31T14:26:44.539006+00:00").
/// A default ISO8601DateFormatter does NOT parse those, and every caller here
/// fell back to printing the raw string, so every pass time on the station
/// screen rendered as an unformatted timestamp wrapping over three lines.
/// Try with fractions first, then without, because not every timestamp we are
/// given carries them.
enum ISO {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func date(_ s: String) -> Date? {
        withFraction.date(from: s) ?? plain.date(from: s)
    }
}

struct StationView: View {
    let observer: String
    @AppStorage("station") private var saved = ""
    @State private var health: API.StationHealth?
    @State private var failed = false

    /// The verdict is RELATIVE — same thresholds as the server-side detector.
    /// A station that never listened to the tracked fleet is not "bad", and
    /// colour appears only when there is a baseline to fall from.
    var verdict: (String, Color) {
        guard let h = health, let r = h.recent_rate else { return ("no recent data", .orange) }
        guard let b = h.baseline_rate, b >= 0.05 else { return ("hearing as usual", .green) }
        if r <= b * 0.25 { return ("far below your own baseline", .red) }
        if r <= b * 0.6  { return ("below your own baseline", .orange) }
        return ("hearing as usual", .green)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let h = health {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(h.recent_rate.map { "\(Int($0 * 100))%" } ?? "—")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(verdict.1)
                        Text(verdict.0).foregroundStyle(.secondary)
                        if let b = h.baseline_rate {
                            Text("your baseline \(Int(b * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Bars(days: Array(h.days.suffix(21)))
                        Text("hit rate — frames heard / passes available")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))

                    if !h.next_passes.isEmpty {
                        PassCard(title: "Next passes", passes: h.next_passes, when: when)
                    }
                    if let past = h.past_passes, !past.isEmpty {
                        PassCard(title: "Recent passes", passes: past, when: when,
                                 detail: { p in PassDetailView(
                                    observer: observer, pass: p, when: when) })
                    }
                } else if failed {
                    Unreachable(text: "Couldn't load \(observer)") {
                        failed = false
                        Task { do { health = try await API.health(observer) }
                               catch { failed = true } }
                    }
                } else { ProgressView().frame(maxWidth: .infinity) }

                Text("Overwatch sees your station only through the satellites it tracks — compare against your own history, not an absolute.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle(observer)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(saved == observer ? "My station ✓" : "Set as mine") {
                    saved = saved == observer ? "" : observer
                }.font(.caption)
            }
        }
        .task {
            do { health = try await API.health(observer) } catch { failed = true }
        }
        .refreshable { health = try? await API.health(observer) }
    }

    func when(_ iso: String) -> String {
        guard let d = ISO.date(iso) else { return iso }
        let f = DateFormatter(); f.dateFormat = "EEE HH:mm"
        return f.string(from: d)
    }
}

/// 21-day sparkline. Grey = no passes available that day (unknown, not zero).
struct Bars: View {
    let days: [API.Day]
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(days, id: \.self) { d in
                RoundedRectangle(cornerRadius: 1)
                    .fill(d.hit_rate == nil ? Color.secondary.opacity(0.3) : Color.accentColor)
                    // clamped: rates above 1.0 are real (several frames per
                    // pass — UX5UL runs ~2.5) and must not overflow the frame
                    .frame(height: max(3, CGFloat(min(d.hit_rate ?? 0, 1.0)) * 56))
            }
        }.frame(height: 56, alignment: .bottom)
    }
}


/// iOS 16 stand-in for ContentUnavailableView (17+). "wifi.slash" rather than
/// the antenna symbol: the latter is missing on some iOS 16 point releases,
/// and SwiftUI renders a missing symbol as a bare warning triangle with no
/// text — which is exactly the unhelpful screen this view exists to avoid.
struct Unreachable: View {
    let text: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let retry { Button("Try again", action: retry).buttonStyle(.bordered) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}

/// One card of passes. Past passes carry frames: green when the station heard
/// the pass, dim red zero when it did not — the per-pass "was it me?".
struct PassCard<Detail: View>: View {
    let title: String
    let passes: [API.Pass]
    let when: (String) -> String
    /// When set, tapping a row pushes the frame-by-frame view (#368).
    var detail: ((API.Pass) -> Detail)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).bold()
            ForEach(passes, id: \.self) { p in
                row(p)
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
    @ViewBuilder func row(_ p: API.Pass) -> some View {
        if let detail {
            NavigationLink { detail(p) } label: { rowBody(p, chevron: true) }
                .buttonStyle(.plain)
        } else { rowBody(p, chevron: false) }
    }
    func rowBody(_ p: API.Pass, chevron: Bool) -> some View {
        HStack {
                    // in-app card, not Safari: the control room is a desk
                    // tool, and the card answers "what is this?" in one screen
                    NavigationLink { SatCardView(norad: p.norad,
                                                 satName: p.satellite) }
                        label: { Text(p.satellite)
                            .foregroundStyle(Color.accentColor) }
                        .buttonStyle(.plain)
                    Spacer()
                    if let f = p.frames {
                        Text(f > 0 ? "\(f) frames" : "nothing heard")
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(f > 0 ? .green : .red)
                    }
                    Text("\(when(p.aos)) · \(Int(p.max_el_deg))°")
                        .foregroundStyle(.secondary).monospacedDigit()
                    if chevron { Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary) }
        }.font(.callout)
    }
}

extension PassCard where Detail == EmptyView {
    init(title: String, passes: [API.Pass], when: @escaping (String) -> String) {
        self.init(title: title, passes: passes, when: when, detail: nil)
    }
}

/// Frame-by-frame view of one pass (#368). The timeline is the diagnostic:
/// ticks only around the middle suggest a horizon problem, ticks across the
/// whole bar a healthy chain.
struct PassDetailView: View {
    let observer: String
    let pass: API.Pass
    let when: (String) -> String
    @State private var detail: API.PassDetail?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let d = detail {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(when(d.aos)) · max \(Int(d.max_el_deg))° · \(d.duration_s / 60) min")
                            .foregroundStyle(.secondary).font(.callout)
                        Timeline(detail: d)
                        Text(d.frames.isEmpty
                             ? "No frames decoded during this pass."
                             : "\(d.frames.count) frames — position along the bar is position in the pass")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))

                    if !d.frames.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Frames").bold()
                            ForEach(d.frames, id: \.self) { f in
                                if f.fields > 0 {
                                    NavigationLink {
                                        FrameFieldsView(norad: pass.norad,
                                                        satName: pass.satellite,
                                                        ts: f.ts)
                                    } label: { frameRow(f, link: true) }
                                    .buttonStyle(.plain)
                                } else { frameRow(f, link: false) }
                            }
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                    }
                } else if failed {
                    Unreachable(text: "Couldn't load this pass") {
                        failed = false
                        Task { detail = try? await API.passDetail(observer,
                            norad: pass.norad, aos: pass.aos)
                               if detail == nil { failed = true } }
                    }
                } else { ProgressView().frame(maxWidth: .infinity) }
            }.padding()
        }
        .navigationTitle(pass.satellite)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { detail = try await API.passDetail(observer,
                    norad: pass.norad, aos: pass.aos) }
            catch { failed = true }
        }
    }

    func hms(_ iso: String) -> String {
        guard let d = ISO.date(iso) else { return iso }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    func frameRow(_ f: API.Frame, link: Bool) -> some View {
        HStack {
            Text(hms(f.ts)).monospacedDigit()
            Spacer()
            Text(f.fields > 0 ? "\(f.fields) fields decoded"
                              : "received, not decoded")
                .font(.caption)
                .foregroundStyle(f.fields > 0 ? .green : .secondary)
            if link { Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary) }
        }.font(.callout)
    }
}

/// The deepest level: every decoded value of one frame. The question at this
/// depth is "did it decode SANELY" — 0.02 V tells a different story than a
/// missing frame.
struct FrameFieldsView: View {
    let norad: Int
    let satName: String
    let ts: String
    @State private var detail: API.FrameDetail?
    @State private var failed = false

    var body: some View {
        List {
            if let d = detail {
                ForEach(d.fields, id: \.self) { f in
                    HStack(alignment: .firstTextBaseline) {
                        // #248 rule: a 90-char kaitai path is identified by
                        // its tail
                        Text(f.field.count > 40
                             ? "…" + f.field.split(separator: "_").suffix(4)
                                   .joined(separator: "_")
                             : f.field)
                            .font(.callout)
                        Spacer()
                        Text(f.value.display)
                            .font(.callout).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } else if failed {
                Unreachable(text: "Couldn't load this frame") {
                    failed = false
                    Task { detail = try? await API.frame(norad, ts: ts)
                           if detail == nil { failed = true } }
                }
            } else { ProgressView() }
        }
        .navigationTitle(satName)
        .navigationBarTitleDisplayMode(.inline)
        .task { do { detail = try await API.frame(norad, ts: ts) }
                catch { failed = true } }
    }
}

/// Light in-app satellite card — the full control room (MapLibre + Grafana,
/// tens of MB) stays one explicit link away instead of being the only door.
struct SatCardView: View {
    let norad: Int
    let satName: String
    @State private var sat: API.Satellite?
    @State private var failed = false

    var body: some View {
        List {
            if let s = sat {
                if let note = s.note, !note.isEmpty {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
                row("Altitude", s.alt_km.map { "\(Int($0)) km" } ?? "—")
                row("Position", (s.lat != nil && s.lon != nil)
                    ? String(format: "%.1f°, %.1f°", s.lat!, s.lon!) : "—")
                row("Sunlight", (s.sunlit ?? false) ? "☀ sunlit" : "🌑 in eclipse")
                row("Last heard", s.last_frame.map(when) ?? "never (position only)")
                row("Telemetry", s.has_telemetry ? "decoded here" : "position only")
                Link(destination:
                     URL(string: "https://overwatch.confinia.io/#\(norad)")!) {
                    Text("Open in the full control room ↗").font(.callout)
                }
            } else if failed {
                Unreachable(text: "Couldn't load \(satName)") {
                    failed = false
                    Task { await load() }
                }
            } else { ProgressView() }
        }
        .navigationTitle(satName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    func load() async {
        do { sat = try await API.satellites().first { $0.norad == norad }
             if sat == nil { failed = true } }
        catch { failed = true }
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer()
                 Text(v).foregroundStyle(.secondary) }.font(.callout)
    }

    func when(_ iso: String) -> String {
        guard let d = ISO.date(iso) else { return iso }
        let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"
        return f.string(from: d)
    }
}

/// The pass as a bar, one tick per frame at its offset into the window.
struct Timeline: View {
    let detail: API.PassDetail
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 6)
                ForEach(detail.frames, id: \.self) { f in
                    Rectangle().fill(f.fields > 0 ? Color.green : Color.accentColor)
                        .frame(width: 2, height: 16)
                        .offset(x: offset(f, width: geo.size.width))
                }
            }.frame(maxHeight: .infinity, alignment: .center)
        }.frame(height: 20)
    }
    func offset(_ f: API.Frame, width: CGFloat) -> CGFloat {
        guard let a = ISO.date(detail.aos), let t = ISO.date(f.ts),
              detail.duration_s > 0 else { return 0 }
        let x = t.timeIntervalSince(a) / Double(detail.duration_s)
        return CGFloat(min(max(x, 0), 1)) * max(width - 2, 0)
    }
}
