import AVFoundation
import JourneyKit
import MediaPlayer
import UIKit

@MainActor
final class SystemAudio {
    let player: Player
    let art: () -> ArtCache?
    var observers: [any NSObjectProtocol] = []
    var resumeAfterInterruption = false
    var artworkId: String?
    var artwork: MPMediaItemArtwork?

    init(player: Player, art: @escaping () -> ArtCache?) {
        self.player = player
        self.art = art
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        player.activate = {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                Log.audio.error(
                    "Audio session failed: \(String(describing: error), privacy: .public)")
            }
        }
        player.changed = { [weak self] in self?.update() }
        Self.commands(player)
        observe()
    }

    nonisolated private static func commands(_ player: Player) {
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor @Sendable () -> Void) {
            command.isEnabled = true
            command.addTarget { _ in
                Task { @MainActor in action() }
                return .success
            }
        }
        on(center.playCommand) { player.resume() }
        on(center.pauseCommand) { player.pause() }
        on(center.togglePlayPauseCommand) { player.toggle() }
        on(center.nextTrackCommand) { player.next() }
        on(center.previousTrackCommand) { player.previous() }
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let time = event.positionTime
            Task { @MainActor in player.seek(to: time) }
            return .success
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                let info = note.userInfo ?? [:]
                let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(
                    AVAudioSession.InterruptionType.init)
                let options = AVAudioSession.InterruptionOptions(
                    rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                MainActor.assumeIsolated { self?.interrupted(type, options) }
            })
        observers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
            ) { [weak self] note in
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                    .flatMap(AVAudioSession.RouteChangeReason.init)
                guard reason == .oldDeviceUnavailable else { return }
                MainActor.assumeIsolated { self?.player.pause() }
            })
    }

    private func interrupted(
        _ type: AVAudioSession.InterruptionType?, _ options: AVAudioSession.InterruptionOptions
    ) {
        switch type {
        case .began:
            resumeAfterInterruption = player.isPlaying
            player.pause()
        case .ended:
            if resumeAfterInterruption && options.contains(.shouldResume) { player.resume() }
            resumeAfterInterruption = false
        default:
            break
        }
    }

    private func update() {
        let center = MPNowPlayingInfoCenter.default()
        guard let entry = player.current else {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: entry.track.name,
            MPMediaItemPropertyArtist: entry.track.artistName,
            MPMediaItemPropertyAlbumTitle: entry.album.name,
            MPMediaItemPropertyPlaybackDuration: entry.track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork = artwork(entry.album) { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
    }

    private func artwork(_ album: Album) -> MPMediaItemArtwork? {
        guard let item = album.art else { return nil }
        if artworkId == "\(item.id)-\(item.tag)" { return artwork }
        guard let data = art()?.cached(item), let image = UIImage(data: data) else { return nil }
        artworkId = "\(item.id)-\(item.tag)"
        artwork = Self.artwork(image)
        return artwork
    }

    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
