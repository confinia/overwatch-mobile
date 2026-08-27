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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Next passes").bold()
                            ForEach(h.next_passes, id: \.self) { p in
                                HStack {
                                    Text(p.satellite)
                                    Spacer()
                                    Text("\(when(p.aos)) · \(Int(p.max_el_deg))°")
                                        .foregroundStyle(.secondary).monospacedDigit()
                                }.font(.callout)
                            }
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                    }
                } else if failed {
                    Unreachable(text: "Couldn't load \(observer)")
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
        guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
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
                    .frame(height: max(3, CGFloat(d.hit_rate ?? 0) * 56))
            }
        }.frame(height: 56, alignment: .bottom)
    }
}


/// iOS 16 stand-in for ContentUnavailableView (17+).
struct Unreachable: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
