//
//  PodcastModels.swift
//  PodPlay
//
//  Created by Arjun Sharma on 21/11/26.
//

import Foundation
import AppKit

// MARK: - Track Model
/// Represents an audio track in PodPlay, which can be either a local audio file or a podcast episode.
struct Track: Identifiable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var url: URL
    var artworkURL: URL?
    var artwork: NSImage?
    var duration: String?
    var durationSeconds: Double?
    var pubDate: String?
    var isPodcast: Bool
    var episodeDescription: String?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String = "",
        album: String = "",
        url: URL,
        artworkURL: URL? = nil,
        artwork: NSImage? = nil,
        duration: String? = nil,
        durationSeconds: Double? = nil,
        pubDate: String? = nil,
        isPodcast: Bool = false,
        episodeDescription: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.url = url
        self.artworkURL = artworkURL
        self.artwork = artwork
        self.duration = duration
        self.durationSeconds = durationSeconds
        self.pubDate = pubDate
        self.isPodcast = isPodcast
        self.episodeDescription = episodeDescription
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }
}

// MARK: - Podcast Feed Model
struct PodcastFeed: Equatable {
    let title: String
    let author: String
    let feedDescription: String?
    let artworkURL: URL?
    let feedURL: URL
    let episodes: [PodcastEpisode]
}

// MARK: - Podcast Episode Model
struct PodcastEpisode: Identifiable, Equatable {
    let id: String
    let title: String
    let podcastTitle: String
    let podcastAuthor: String
    let audioURL: URL
    let artworkURL: URL?
    let duration: String?
    let pubDate: String?
    let episodeDescription: String?

    func toTrack(fallbackArtworkURL: URL?) -> Track {
        Track(
            title: title,
            artist: podcastAuthor.isEmpty ? podcastTitle : podcastAuthor,
            album: podcastTitle,
            url: audioURL,
            artworkURL: artworkURL ?? fallbackArtworkURL,
            artwork: nil,
            duration: duration,
            pubDate: pubDate,
            isPodcast: true,
            episodeDescription: episodeDescription
        )
    }
}

// MARK: - Screen Modes
enum ScreenMode: Equatable {
    case nowPlaying
    case episodes
}
