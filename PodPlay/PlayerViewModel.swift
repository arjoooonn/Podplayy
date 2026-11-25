//
//  PlayerViewModel.swift
//  PodPlay
//
//  Created by Arjun Sharma on 19/07/26.
//

import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import Combine

@MainActor
final class PlayerViewModel: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isPlaying: Bool = false
    @Published var albumArt: NSImage? = nil
    @Published var trackTitle: String = "No Track Loaded"
    @Published var artistName: String = ""
    @Published var podcastTitle: String = ""
    @Published var playlist: [URL] = []
    @Published var tracks: [Track] = []
    @Published var currentIndex: Int = -1

    @Published var isLoading: Bool = false
    @Published var statusMessage: String? = nil
    @Published var errorMessage: String? = nil

    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    @Published var screenMode: ScreenMode = .nowPlaying
    @Published var isShowingURLDialog: Bool = false
    @Published var urlInputText: String = ""

    @Published var pomodoro = PomodoroTimer()

    // MARK: - Private Properties
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var endObserverToken: Any?
    private var accessedURL: URL?

    private let artworkCache = NSCache<NSURL, NSImage>()

    override init() {
        super.init()
        setupNotifications()
        setupPomodoro()
    }

    private func setupPomodoro() {
        pomodoro.onWorkCompleted = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.pause()
                self.pomodoro.playDinkSound()
            }
        }

        pomodoro.onBreakCompleted = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.pomodoro.playDingSound()
            }
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .pasteRSSNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pasteRSSLink()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openURLDialogNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openURLDialog()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openFilesNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openFiles()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .togglePomodoroNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pomodoro.toggle()
            }
        }
    }

    // MARK: - RSS Feed Support

    /// Pastes and loads an RSS link from the system clipboard or optional passed string
    func pasteRSSLink(overrideString: String? = nil) {
        let stringToUse: String?
        if let override = overrideString, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stringToUse = override
        } else {
            stringToUse = NSPasteboard.general.string(forType: .string)
        }

        guard let rawString = stringToUse?.trimmingCharacters(in: .whitespacesAndNewlines), !rawString.isEmpty else {
            openURLDialog()
            return
        }

        if let validURL = RSSFeedLoader.sanitizeURLString(rawString) {
            loadFeed(from: validURL)
        } else {
            urlInputText = rawString
            isShowingURLDialog = true
        }
    }

    /// Opens the URL input dialog, pre-populating with clipboard URL if available
    func openURLDialog() {
        if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           (clip.lowercased().hasPrefix("http://") || clip.lowercased().hasPrefix("https://") || clip.lowercased().hasPrefix("feed:") || clip.lowercased().hasPrefix("pcast:")) {
            urlInputText = clip
        }
        isShowingURLDialog = true
    }

    /// Loads a podcast feed from a URL and directly plays the latest episode
    func loadFeed(from url: URL) {
        isLoading = true
        statusMessage = "Loading Podcast..."
        errorMessage = nil

        Task {
            do {
                let feed = try await RSSFeedLoader.shared.fetchFeed(from: url)
                
                self.podcastTitle = feed.title
                self.artistName = feed.author.isEmpty ? feed.title : feed.author
                
                // Pre-cache feed artwork if available
                if let artURL = feed.artworkURL {
                    self.downloadArtwork(from: artURL) { [weak self] image in
                        guard let self = self, self.albumArt == nil else { return }
                        self.albumArt = image
                    }
                }

                // Map episodes to Track models
                let newTracks = feed.episodes.map { $0.toTrack(fallbackArtworkURL: feed.artworkURL) }
                self.tracks = newTracks
                self.playlist = newTracks.map { $0.url }

                self.isLoading = false
                self.statusMessage = nil

                // Directly play the first / latest episode!
                if !newTracks.isEmpty {
                    self.playTrack(at: 0)
                }
            } catch {
                self.isLoading = false
                self.statusMessage = nil
                self.errorMessage = error.localizedDescription
                print("Failed to load feed: \(error)")
            }
        }
    }

    // MARK: - Local File Picking

    func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.mp3, .audio]

        panel.begin { [weak self] response in
            guard let self = self, response == .OK, !panel.urls.isEmpty else { return }

            let wasEmpty = self.tracks.isEmpty
            let localTracks = panel.urls.map { url in
                Track(
                    title: url.deletingPathExtension().lastPathComponent,
                    artist: "",
                    album: "",
                    url: url,
                    isPodcast: false
                )
            }

            self.tracks.append(contentsOf: localTracks)
            self.playlist.append(contentsOf: panel.urls)

            if wasEmpty {
                self.playTrack(at: 0)
            }
        }
    }

    // MARK: - Track Playback

    func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }

        cleanupPlayer()

        currentIndex = index
        let track = tracks[index]

        trackTitle = track.title
        artistName = track.artist.isEmpty ? podcastTitle : track.artist
        albumArt = track.artwork
        currentTime = 0
        duration = 0
        errorMessage = nil

        // If artwork is not cached yet, download or load it
        if track.artwork == nil {
            if track.isPodcast, let artURL = track.artworkURL {
                downloadArtwork(from: artURL) { [weak self] image in
                    guard let self = self else { return }
                    if self.tracks.indices.contains(index) {
                        self.tracks[index].artwork = image
                    }
                    if self.currentIndex == index {
                        self.albumArt = image
                    }
                }
            } else if !track.isPodcast {
                loadLocalMetadata(from: track.url, for: index)
            }
        }

        // Setup AVPlayerItem
        let item: AVPlayerItem
        if track.isPodcast {
            item = AVPlayerItem(url: track.url)
        } else {
            let started = track.url.startAccessingSecurityScopedResource()
            accessedURL = started ? track.url : nil
            item = AVPlayerItem(url: track.url)
        }

        self.playerItem = item
        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer

        // Time observer for progress - fires every 0.1s for smooth, accurate seconds counting
        timeObserverToken = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentTime = time.seconds
                if let d = self.playerItem?.duration.seconds, !d.isNaN, !d.isInfinite, d > 0 {
                    self.duration = d
                }
            }
        }

        // Play to end observer -> auto advances to next episode
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.next()
            }
        }

        newPlayer.play()
        isPlaying = true
    }

    // MARK: - Metadata & Artwork Loading

    private func downloadArtwork(from url: URL, completion: @escaping (NSImage?) -> Void) {
        let nsURL = url as NSURL
        if let cached = artworkCache.object(forKey: nsURL) {
            completion(cached)
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = NSImage(data: data) {
                    self.artworkCache.setObject(image, forKey: nsURL)
                    await MainActor.run {
                        completion(image)
                    }
                } else {
                    await MainActor.run { completion(nil) }
                }
            } catch {
                await MainActor.run { completion(nil) }
            }
        }
    }

    private func loadLocalMetadata(from url: URL, for index: Int) {
        let asset = AVURLAsset(url: url)

        Task {
            var title = url.deletingPathExtension().lastPathComponent
            var artist = ""
            var artwork: NSImage? = nil

            if let commonItems = try? await asset.load(.commonMetadata) {
                for item in commonItems {
                    guard let key = item.commonKey else { continue }
                    switch key {
                    case .commonKeyTitle:
                        if let value = try? await item.load(.stringValue), !value.isEmpty { title = value }
                    case .commonKeyArtist:
                        if let value = try? await item.load(.stringValue) { artist = value }
                    case .commonKeyArtwork:
                        if let data = try? await item.load(.dataValue), let image = NSImage(data: data) {
                            artwork = image
                        }
                    default:
                        break
                    }
                }
            }

            if artwork == nil {
                if let formats = try? await asset.load(.availableMetadataFormats), formats.contains(.id3Metadata),
                   let id3Items = try? await asset.loadMetadata(for: .id3Metadata) {
                    for item in id3Items {
                        if let data = try? await item.load(.dataValue), let image = NSImage(data: data) {
                            artwork = image
                            break
                        }
                    }
                }
            }

            await MainActor.run {
                if self.tracks.indices.contains(index) {
                    self.tracks[index].title = title
                    self.tracks[index].artist = artist
                    self.tracks[index].artwork = artwork
                }
                if self.currentIndex == index {
                    self.trackTitle = title
                    self.artistName = artist
                    if artwork != nil {
                        self.albumArt = artwork
                    }
                }
            }
        }
    }

    // MARK: - Transport Controls

    func togglePlayPause() {
        guard player != nil else {
            if !tracks.isEmpty {
                playTrack(at: max(currentIndex, 0))
            }
            return
        }
        isPlaying ? pause() : play()
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func next() {
        guard !tracks.isEmpty else { return }
        playTrack(at: (currentIndex + 1) % tracks.count)
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        // If current track has been playing for more than 3 seconds, restart it
        if currentTime > 3.0 {
            seek(to: 0)
        } else {
            playTrack(at: (currentIndex - 1 + tracks.count) % tracks.count)
        }
    }

    func seek(to seconds: Double) {
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: targetTime)
    }

    func toggleScreenMode() {
        screenMode = (screenMode == .nowPlaying) ? .episodes : .nowPlaying
    }

    // MARK: - Cleanup

    private func cleanupPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
        player?.pause()
        player = nil
        playerItem = nil
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let pasteRSSNotification = Notification.Name("PodPlayPasteRSSNotification")
    static let openURLDialogNotification = Notification.Name("PodPlayOpenURLDialogNotification")
    static let openFilesNotification = Notification.Name("PodPlayOpenFilesNotification")
    static let togglePomodoroNotification = Notification.Name("PodPlayTogglePomodoroNotification")
}
