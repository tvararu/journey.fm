import Foundation

public func playbackGain(album: Album, track: Track) -> Float {
    let (gain, peak) =
        album.gain.map { ($0, album.peak) } ?? track.gain.map { ($0, track.peak) } ?? (0, nil)
    let factor = pow(10, gain / 20)
    let cap = peak.flatMap { $0 > 0 ? 1 / $0 : nil } ?? 1
    return Float(min(factor, cap))
}
