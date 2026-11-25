import Foundation
import SwiftUI
import ArrcadeKit

enum Fmt {
    static func eta(_ seconds: Int) -> String {
        if seconds <= 0 || seconds >= 8_640_000 { return "∞" }
        let d = Duration.seconds(seconds)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return d.formatted(.units(allowed: [.minutes, .seconds], width: .narrow, maximumUnitCount: 2)) }
        if seconds < 86400 { return d.formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2)) }
        return d.formatted(.units(allowed: [.days, .hours], width: .narrow, maximumUnitCount: 2))
    }

    static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    static func runtime(_ minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.relative(presentation: .named))
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func bytes(_ v: Int64?) -> String { (v ?? 0).byteString }
    static func bytes(_ v: Double?) -> String { Int64(v ?? 0).byteString }
    static func speed(_ v: Int) -> String { v <= 0 ? "0 B/s" : Int64(v).byteString + "/s" }

    static func ratio(_ v: Double) -> String { v < 0 ? "∞" : String(format: "%.2f", v) }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded(.down)))%" }

    static func age(hours: Double?) -> String {
        guard let h = hours else { return "—" }
        if h < 1 { return "\(Int(h * 60))m" }
        if h < 48 { return "\(Int(h))h" }
        return "\(Int(h / 24))d"
    }
}

extension QBTorrent {
    var stateColor: Color {
        switch stateGroup {
        case .downloading: .blue
        case .seeding: .green
        case .completed: .teal
        case .paused: .gray
        case .stalled: .orange
        case .checking: .purple
        case .errored: .red
        default: .secondary
        }
    }
    var stateSymbol: String {
        switch stateGroup {
        case .downloading: "arrow.down.circle.fill"
        case .seeding: "arrow.up.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .stalled: "exclamationmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath.circle.fill"
        case .errored: "xmark.octagon.fill"
        default: "circle"
        }
    }
}

extension RadarrMovie {
    var statusColor: Color {
        if downloaded { return .green }
        if monitored == false { return .gray }
        if isAvailable == true { return .red }
        return .blue
    }
}

extension SonarrSeries {
    var statusColor: Color {
        let s = statistics
        let have = s?.episodeFileCount ?? 0, total = s?.episodeCount ?? 0
        if monitored == false { return .gray }
        if total > 0, have >= total { return isContinuing ? .green : .teal }
        return isContinuing ? .orange : .red
    }
}

extension SeerrMediaStatus {
    var color: Color {
        switch self {
        case .available: .green
        case .partiallyAvailable: .teal
        case .processing: .indigo
        case .pending: .orange
        case .blocklisted, .deleted: .red
        case .unknown: .secondary
        }
    }
}

extension SeerrRequestStatus {
    var color: Color {
        switch self {
        case .pending: .orange
        case .approved: .indigo
        case .declined: .red
        case .failed: .red
        case .completed: .green
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// "importBlocked" → "Import Blocked", "downloading" → "Downloading"
    var humanized: String {
        var out = ""
        for (i, ch) in enumerated() {
            if i > 0, ch.isUppercase { out.append(" ") }
            out.append(i == 0 ? Character(ch.uppercased()) : ch)
        }
        return out
    }
}
