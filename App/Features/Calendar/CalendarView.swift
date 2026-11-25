import SwiftUI
import PilothouseKit

struct CalendarEntry: Identifiable, Hashable {
    enum Kind: Hashable { case movie(Int), episode(seriesId: Int) }
    let id: String
    let date: Date
    let title: String
    let subtitle: String
    let kind: Kind
    let hasFile: Bool
    let monitored: Bool
    let poster: [URL?]
    let releaseType: String?
    var instance: UUID? = nil

    var color: Color {
        if hasFile { return .green }
        if !monitored { return .gray }
        if date < .now { return .red }
        switch kind { case .movie: return .yellow; case .episode: return .cyan }
    }
}

struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.calendarDays) private var days = 30
    @AppStorage(Prefs.showUnmonitoredCalendar) private var showUnmonitored = true
    @State private var mode = 0
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var entries: [CalendarEntry] = []
    @State private var state: LoadState = .idle
    @State private var path = NavigationPath()

    private var range: (Date, Date) {
        let cal = Calendar.current
        if mode == 0 {
            let start = cal.startOfDay(for: .now).addingTimeInterval(-86400 * 2)
            return (start, start.addingTimeInterval(Double(days + 2) * 86400))
        }
        let start = cal.date(byAdding: .day, value: -7, to: month)!
        return (start, cal.date(byAdding: .day, value: 45, to: month)!)
    }

    var body: some View {
        NavigationStack(path: $path) {
            StateSwitch(state: state, isEmpty: entries.isEmpty && state != .loaded, retry: { Task { await load() } }) {
                if mode == 0 { agenda } else { monthGrid }
            }
            .navigationTitle("Calendar")
            .navigationDestination(for: MovieRoute.self) { r in
                if let s = r.instance.flatMap({ app.radarrStores[$0] }) ?? app.radarr { MovieDetailView(store: s, movieId: r.id) }
            }
            .navigationDestination(for: SeriesRoute.self) { r in
                if let s = r.instance.flatMap({ app.sonarrStores[$0] }) ?? app.sonarr { SeriesDetailView(store: s, seriesId: r.id) }
            }
            .toolbar {
                ToolbarItemGroup {
                    Picker("Mode", selection: $mode) {
                        Label("Agenda", systemImage: "list.bullet").tag(0)
                        Label("Month", systemImage: "calendar").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if mode == 1 {
                        Button { shiftMonth(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                        Button("Today") { month = Calendar.current.dateInterval(of: .month, for: .now)!.start }
                        Button { shiftMonth(1) } label: { Label("Next", systemImage: "chevron.right") }
                    }
                    Toggle(isOn: $showUnmonitored) { Label("Unmonitored", systemImage: "bookmark.slash") }
                }
            }
        }
        .task(id: "\(mode)-\(month)-\(days)-\(showUnmonitored)") { await load() }
        .focusedSceneValue(\.refreshAction) { Task { await load() } }
    }

    private func shiftMonth(_ d: Int) {
        month = Calendar.current.date(byAdding: .month, value: d, to: month)!
    }

    private func load() async {
        if entries.isEmpty { state = .loading }
        let (start, end) = range
        var out: [CalendarEntry] = []
        var err: String?
        for r in app.allRadarr {
            do {
                let movies = try await r.client.calendar(start: start, end: end, unmonitored: showUnmonitored)
                for m in movies {
                    let candidates: [(Date?, String)] = [(m.inCinemas, "In Cinemas"), (m.digitalRelease, "Digital"), (m.physicalRelease, "Physical")]
                    for (d, label) in candidates {
                        guard let d, d >= start, d <= end else { continue }
                        out.append(CalendarEntry(id: "\(r.config.id)m\(m.id ?? 0)-\(label)", date: d, title: m.title, subtitle: label,
                                                 kind: .movie(m.id ?? 0), hasFile: m.downloaded, monitored: m.monitored ?? true,
                                                 poster: r.posterURLs(m, width: 185), releaseType: label, instance: r.config.id))
                    }
                }
            } catch { err = error.localizedDescription }
        }
        for s in app.allSonarr {
            do {
                let eps = try await s.client.calendar(start: start, end: end, unmonitored: showUnmonitored)
                for e in eps {
                    guard let d = e.airDateUtc else { continue }
                    let series = e.series ?? s.series(id: e.seriesId)
                    out.append(CalendarEntry(id: "\(s.config.id)e\(e.id)", date: d, title: series?.title ?? "Episode",
                                             subtitle: "\(e.code) · \(e.title ?? "TBA")", kind: .episode(seriesId: e.seriesId),
                                             hasFile: e.hasFile ?? false, monitored: e.monitored,
                                             poster: series.map { s.posterURLs($0, width: 185) } ?? [], releaseType: e.finaleType.map { "\($0.capitalized) finale" }, instance: s.config.id))
                }
            } catch { err = error.localizedDescription }
        }
        entries = out.sorted { $0.date < $1.date }
        state = (out.isEmpty && err != nil) ? .failed(err!) : .loaded
    }

    // MARK: Agenda

    private var agenda: some View {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: entries) { cal.startOfDay(for: $0.date) }
        let daysSorted = grouped.keys.sorted()
        return ScrollViewReader { proxy in
            List {
                ForEach(daysSorted, id: \.self) { day in
                    SwiftUI.Section {
                        ForEach(grouped[day] ?? []) { e in
                            EntryLink(entry: e) { CalendarRow(entry: e) }
                        }
                    } header: {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            if cal.isDateInToday(day) { Pill(text: "Today", color: .accentColor) }
                            if cal.isDateInTomorrow(day) { Pill(text: "Tomorrow", color: .blue) }
                        }
                    }
                    .id(day)
                }
            }
            .overlay { if entries.isEmpty { ContentUnavailableView("Nothing Scheduled", systemImage: "calendar") } }
            .onAppear {
                if let first = daysSorted.first(where: { $0 >= cal.startOfDay(for: .now) }) { proxy.scrollTo(first, anchor: .top) }
            }
        }
    }

    private func route(_ e: CalendarEntry) -> AnyHashable {
        switch e.kind {
        case .movie(let id): AnyHashable(MovieRoute(id: id))
        case .episode(let sid): AnyHashable(SeriesRoute(id: sid))
        }
    }

    // MARK: Month

    private var monthGrid: some View {
        let cal = Calendar.current
        let firstWeekday = cal.component(.weekday, from: month)
        let lead = (firstWeekday - cal.firstWeekday + 7) % 7
        let daysInMonth = cal.range(of: .day, in: .month, for: month)!.count
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<daysInMonth).map { cal.date(byAdding: .day, value: $0, to: month) }
        let symbols = cal.shortWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.largeTitle.bold())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(ordered, id: \.self) { Text($0).font(.caption.bold()).foregroundStyle(.secondary) }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let items = entries.filter { cal.isDate($0.date, inSameDayAs: day) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(cal.component(.day, from: day))")
                                    .font(.callout.weight(cal.isDateInToday(day) ? .bold : .regular))
                                    .foregroundStyle(cal.isDateInToday(day) ? Color.accentColor : .primary)
                                ForEach(items.prefix(4)) { e in
                                    EntryLink(entry: e) {
                                        HStack(spacing: 4) {
                                            Capsule().fill(e.color).frame(width: 3, height: 12)
                                            Text(e.title).font(.caption2).lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                        .contentShape(.rect)
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .buttonStyle(.plain)
                                    .help("\(e.title) — \(e.subtitle)")
                                }
                                if items.count > 4 { Text("+\(items.count - 4) more").font(.caption2).foregroundStyle(.secondary) }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                            .glassEffect(.regular.tint(cal.isDateInToday(day) ? Color.accentColor.opacity(0.15) : nil), in: .rect(cornerRadius: 12))
                        } else {
                            Color.clear.frame(minHeight: 110)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct CalendarRow: View {
    let entry: CalendarEntry
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(entry.poster, pixelWidth: 80).frame(width: 34, height: 51).clipShape(.rect(cornerRadius: 4))
            Capsule().fill(entry.color).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.callout.weight(.medium)).lineLimit(1)
                Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let r = entry.releaseType, case .episode = entry.kind { Pill(text: r, color: .purple) }
            Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Image(systemName: entry.hasFile ? "checkmark.circle.fill" : (entry.date < .now ? "exclamationmark.circle" : "clock"))
                .foregroundStyle(entry.color)
        }
        .padding(.vertical, 2)
    }
}

/// NavigationLink to the right typed route for a calendar entry.
struct EntryLink<Label: View>: View {
    let entry: CalendarEntry
    @ViewBuilder var label: () -> Label
    var body: some View {
        switch entry.kind {
        case .movie(let id): NavigationLink(value: MovieRoute(id: id, instance: entry.instance), label: label)
        case .episode(let sid): NavigationLink(value: SeriesRoute(id: sid, instance: entry.instance), label: label)
        }
    }
}
