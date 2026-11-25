//
//  RSSParser.swift
//  PodPlay
//
//  Created by Arjun Sharma on 21/11/26.
//

import Foundation

// MARK: - RSS / Podcast Parser
final class RSSParser: NSObject, XMLParserDelegate {

    private(set) var feedTitle: String = ""
    private(set) var feedAuthor: String = ""
    private(set) var feedDescription: String = ""
    private(set) var feedArtworkURL: URL? = nil
    private(set) var episodes: [PodcastEpisode] = []

    private var inItem: Bool = false
    private var inChannel: Bool = false
    private var inChannelImage: Bool = false

    private var currentElement: String = ""
    private var currentText: String = ""

    // Temporary storage for item fields
    private var currentTitle: String = ""
    private var currentAudioURL: URL? = nil
    private var currentArtworkURL: URL? = nil
    private var currentDuration: String? = nil
    private var currentPubDate: String? = nil
    private var currentDescription: String? = nil
    private var currentGuid: String? = nil

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    func parse(data: Data, originalURL: URL) -> PodcastFeed? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            return nil
        }

        // Fallback title if empty
        let title = feedTitle.isEmpty ? (originalURL.host ?? "Podcast") : feedTitle

        return PodcastFeed(
            title: title,
            author: feedAuthor,
            feedDescription: feedDescription.isEmpty ? nil : feedDescription,
            artworkURL: feedArtworkURL,
            feedURL: originalURL,
            episodes: episodes
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let tag = elementName.lowercased()
        currentElement = tag
        currentText = ""

        if tag == "channel" {
            inChannel = true
        } else if tag == "item" || tag == "entry" {
            inItem = true
            currentTitle = ""
            currentAudioURL = nil
            currentArtworkURL = nil
            currentDuration = nil
            currentPubDate = nil
            currentDescription = nil
            currentGuid = nil
        } else if inItem {
            // Check for media enclosure
            if tag == "enclosure" || tag == "media:content" {
                if let urlString = attributeDict["url"] ?? attributeDict["href"] {
                    let cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                    let type = (attributeDict["type"] ?? "").lowercased()
                    let isAudioType = type.isEmpty || type.contains("audio") || type.contains("mpeg") || type.contains("mp3") || type.contains("m4a") || type.contains("aac") || type.contains("ogg") || type.contains("wav")
                    let hasAudioExtension = cleaned.contains(".mp3") || cleaned.contains(".m4a") || cleaned.contains(".aac") || cleaned.contains(".wav") || cleaned.contains(".ogg") || cleaned.contains(".m4b")
                    
                    if isAudioType || hasAudioExtension {
                        if let url = URL(string: cleaned) {
                            currentAudioURL = url
                        }
                    }
                }
            } else if tag == "itunes:image" {
                if let href = attributeDict["href"] ?? attributeDict["url"] {
                    currentArtworkURL = URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        } else if inChannel {
            if tag == "itunes:image" {
                if let href = attributeDict["href"] ?? attributeDict["url"] {
                    feedArtworkURL = URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else if tag == "image" {
                inChannelImage = true
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.lowercased()
        let trimmed = decodeXML(currentText.trimmingCharacters(in: .whitespacesAndNewlines))

        if inItem {
            switch tag {
            case "item", "entry":
                if let audioURL = currentAudioURL {
                    let epTitle = currentTitle.isEmpty ? "Episode \(episodes.count + 1)" : currentTitle
                    let ep = PodcastEpisode(
                        id: currentGuid ?? audioURL.absoluteString,
                        title: epTitle,
                        podcastTitle: feedTitle,
                        podcastAuthor: feedAuthor,
                        audioURL: audioURL,
                        artworkURL: currentArtworkURL ?? feedArtworkURL,
                        duration: currentDuration,
                        pubDate: currentPubDate,
                        episodeDescription: currentDescription
                    )
                    episodes.append(ep)
                }
                inItem = false

            case "title":
                currentTitle = trimmed

            case "itunes:duration":
                currentDuration = formatDuration(trimmed)

            case "pubdate", "published", "updated":
                currentPubDate = formatDate(trimmed)

            case "itunes:summary", "description", "content:encoded":
                if currentDescription == nil || currentDescription?.isEmpty == true {
                    currentDescription = trimmed
                }

            case "guid", "id":
                currentGuid = trimmed

            default:
                break
            }
        } else if inChannel {
            switch tag {
            case "channel":
                inChannel = false

            case "title":
                if feedTitle.isEmpty {
                    feedTitle = trimmed
                }

            case "itunes:author", "author":
                if feedAuthor.isEmpty {
                    feedAuthor = trimmed
                }

            case "description", "itunes:summary":
                if feedDescription.isEmpty {
                    feedDescription = trimmed
                }

            case "url" where inChannelImage:
                if feedArtworkURL == nil {
                    feedArtworkURL = URL(string: trimmed)
                }

            case "image":
                inChannelImage = false

            default:
                break
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // If it's already in MM:SS or HH:MM:SS format
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            if parts.count == 3, parts[0] == "00" || parts[0] == "0" {
                return "\(parts[1]):\(parts[2])"
            }
            return trimmed
        }
        // If it's pure seconds (e.g. 3600)
        if let totalSeconds = Double(trimmed) {
            let total = Int(totalSeconds)
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let seconds = total % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                return String(format: "%d:%02d", minutes, seconds)
            }
        }
        return trimmed
    }

    private func formatDate(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd"
        ]

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .none

        for format in formats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: trimmed) {
                return displayFormatter.string(from: date)
            }
        }
        return trimmed
    }

    private func decodeXML(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&#8217;", with: "'")
        result = result.replacingOccurrences(of: "&#8216;", with: "'")
        result = result.replacingOccurrences(of: "&#8220;", with: "\"")
        result = result.replacingOccurrences(of: "&#8221;", with: "\"")
        result = result.replacingOccurrences(of: "&#8211;", with: "-")
        result = result.replacingOccurrences(of: "&#8212;", with: "—")
        return result
    }
}

// MARK: - RSS Feed Loader
final class RSSFeedLoader {

    static let shared = RSSFeedLoader()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "PodPlay/1.0 (Macintosh; Intel Mac OS X)",
            "Accept": "application/rss+xml, application/rdf+xml, application/atom+xml, application/xml, text/xml, */*"
        ]
        self.session = URLSession(configuration: config)
    }

    /// Sanitizes an input string to a valid URL, handling custom schemes like feed://, pcast://, itpc://
    static func sanitizeURLString(_ string: String) -> URL? {
        var str = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle common podcast scheme prefixes
        if str.lowercased().hasPrefix("feed:http://") {
            str = "http://" + str.dropFirst(12)
        } else if str.lowercased().hasPrefix("feed:https://") {
            str = "https://" + str.dropFirst(13)
        } else if str.lowercased().hasPrefix("feed://") {
            str = "https://" + str.dropFirst(7)
        } else if str.lowercased().hasPrefix("pcast://") {
            str = "https://" + str.dropFirst(8)
        } else if str.lowercased().hasPrefix("itpc://") {
            str = "https://" + str.dropFirst(7)
        }

        if !str.lowercased().hasPrefix("http://") && !str.lowercased().hasPrefix("https://") {
            if str.contains(".") && !str.contains(" ") {
                str = "https://" + str
            }
        }

        return URL(string: str)
    }

    /// Fetches and parses a podcast feed from the provided URL.
    /// If the URL returns an HTML page, attempts to auto-discover the RSS feed link.
    func fetchFeed(from url: URL) async throws -> PodcastFeed {
        let (data, response) = try await session.data(from: url)

        // Check if response is HTML and attempts auto-discovery
        if let mimeType = response.mimeType?.lowercased(), mimeType.contains("html"),
           let htmlString = String(data: data, encoding: .utf8) {
            if let discoveredURL = discoverRSSURL(in: htmlString, baseURL: url) {
                return try await fetchFeed(from: discoveredURL)
            }
        }

        let parser = RSSParser()
        guard let feed = parser.parse(data: data, originalURL: url) else {
            // Also check if data is HTML with discovered feed
            if let htmlString = String(data: data, encoding: .utf8),
               let discoveredURL = discoverRSSURL(in: htmlString, baseURL: url) {
                return try await fetchFeed(from: discoveredURL)
            }
            throw NSError(
                domain: "PodPlay",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Invalid RSS or podcast feed format."]
            )
        }

        if feed.episodes.isEmpty {
            throw NSError(
                domain: "PodPlay",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "No playable episodes found in feed."]
            )
        }

        return feed
    }

    /// Discovers an RSS link from HTML <link> tags
    private func discoverRSSURL(in html: String, baseURL: URL) -> URL? {
        let patterns = [
            #"<link[^>]+type=["']application/rss\+xml["'][^>]+href=["']([^"']+)["']"#,
            #"<link[^>]+href=["']([^"']+)["'][^>]+type=["']application/rss\+xml["']"#,
            #"<link[^>]+type=["']application/atom\+xml["'][^>]+href=["']([^"']+)["']"#,
            #"<link[^>]+href=["']([^"']+)["'][^>]+type=["']application/atom\+xml["']"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let href = String(html[range])
                if let discovered = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                    return discovered
                }
            }
        }
        return nil
    }
}
