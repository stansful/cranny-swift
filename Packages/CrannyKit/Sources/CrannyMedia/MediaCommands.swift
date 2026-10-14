// CrannyMedia/MediaCommands.swift — ⌘K commands (ARCHITECTURE.md §10.2): Play/Pause, Next, Previous while a
// session exists. In-memory filtering only (queried on every keystroke).
import CrannyCore
import Foundation

final class MediaCommands: PaletteCommandProvider {
    private let service: MediaService

    init(service: MediaService) { self.service = service }

    func commands(matching query: String) -> [PaletteCommand] {
        guard let np = service.nowPlaying, service.supportsCommands else { return [] }
        let service = service
        let kind = MediaStrings.moduleName
        let all = [
            PaletteCommand(id: "media.playPause", title: np.isPlaying ? MediaStrings.pause : MediaStrings.play, kind: kind,
                           symbol: np.isPlaying ? "pause.fill" : "play.fill", keywords: Self.keywords(for: "playPause")) {
                Task { await service.send(.togglePlayPause) }
            },
            PaletteCommand(id: "media.next", title: MediaStrings.nextTrack, kind: kind, symbol: "forward.fill",
                           keywords: Self.keywords(for: "next")) { Task { await service.send(.nextTrack) } },
            PaletteCommand(id: "media.previous", title: MediaStrings.previousTrack, kind: kind, symbol: "backward.fill",
                           keywords: Self.keywords(for: "previous")) { Task { await service.send(.previousTrack) } },
        ]
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter { command in
            command.title.localizedCaseInsensitiveContains(q) || command.kind.localizedCaseInsensitiveContains(q)
                || command.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
                || np.title.localizedCaseInsensitiveContains(q)
        }
    }

    private static func keywords(for command: String) -> [String] {
        switch command {
        case "playPause":
            [String(localized: "music song track resume stop", bundle: .module,
                    comment: "Command palette: extra search words for Play/Pause, space-separated (translate each word)")]
        case "next":
            [String(localized: "skip forward song", bundle: .module,
                    comment: "Command palette: extra search words for Next track, space-separated (translate each word)")]
        default:
            [String(localized: "back song", bundle: .module,
                    comment: "Command palette: extra search words for Previous track, space-separated (translate each word)")]
        }
    }
}
