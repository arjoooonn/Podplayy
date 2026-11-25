//
//  ContentView.swift
//  PodPlay
//
//  Created by Arjun Sharma on 19/07/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var player = PlayerViewModel()
    @State private var isHoveringScreen: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var isShowingPomodoroPopover: Bool = false
    @State private var isHoveringPomodoro: Bool = false

    private let deviceWidth: CGFloat = 460
    private let deviceHeight: CGFloat = 230

    var body: some View {
        ZStack {
            deviceBody

            // URL input dialog overlay
            if player.isShowingURLDialog {
                urlDialogOverlay
            }
        }
        .frame(width: deviceWidth, height: deviceHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .background(WindowConfigurator())
        // Support drag and drop of URLs or plain text (RSS feed links)
        .onDrop(of: [.url, .utf8PlainText, .text], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        // Context menu for quick access
        .contextMenu {
            Button("Paste Podcast RSS Link (⌘V)") {
                player.pasteRSSLink()
            }
            Button("Enter Podcast RSS URL... (⌘U)") {
                player.openURLDialog()
            }
            Divider()
            Button("Open Audio Files... (⌘O)") {
                player.openFiles()
            }
            if !player.tracks.isEmpty {
                Divider()
                Button(player.screenMode == .nowPlaying ? "View Episode List (MENU)" : "View Now Playing (MENU)") {
                    player.toggleScreenMode()
                }
            }
            Divider()
            if player.pomodoro.phase == .idle {
                Button("Start Pomodoro Timer (25m / 5m)") {
                    player.pomodoro.start()
                }
            } else {
                Button(player.pomodoro.isPaused ? "Resume Pomodoro" : "Pause Pomodoro") {
                    player.pomodoro.toggle()
                }
                Button("Reset Pomodoro") {
                    player.pomodoro.reset()
                }
            }
        }
        // Invisible shortcut triggers for direct keyboard paste and shortcuts
        .background(
            Group {
                Button("") {
                    player.pasteRSSLink()
                }
                .keyboardShortcut("v", modifiers: .command)
                .opacity(0)

                Button("") {
                    player.openURLDialog()
                }
                .keyboardShortcut("u", modifiers: .command)
                .opacity(0)

                Button("") {
                    player.openFiles()
                }
                .keyboardShortcut("o", modifiers: .command)
                .opacity(0)
            }
        )
    }

    // MARK: - Device body (fills the entire window)

    private var deviceBody: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.17, green: 0.18, blue: 0.20),
                                 Color(red: 0.07, green: 0.08, blue: 0.09)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            isDropTargeted ? Color.blue : Color.white.opacity(0.08),
                            lineWidth: isDropTargeted ? 2 : 1
                        )
                )

            HStack(spacing: 24) {
                screenView
                wheelView
            }
            .padding(18)

            // Top-right Pomodoro Button & Status Indicator
            pomodoroButton
                .padding(.top, 10)
                .padding(.trailing, 12)
        }
    }

    // MARK: - Screen View

    private var screenView: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .frame(width: 192, height: 192)
                .overlay(
                    Group {
                        if player.isLoading {
                            loadingScreen
                        } else if let error = player.errorMessage {
                            errorScreen(message: error)
                        } else if player.screenMode == .episodes && !player.tracks.isEmpty {
                            episodeListScreen
                        } else {
                            nowPlayingScreen
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Classic iPod Badge (only shown in Now Playing mode when not in error/loading)
            if player.screenMode == .nowPlaying && !player.isLoading && player.errorMessage == nil {
                Text("iPod")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .italic()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHoveringScreen = hovering
            }
        }
    }

    // MARK: - Now Playing Screen

    private var nowPlayingScreen: some View {
        ZStack {
            if let art = player.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 192, height: 192)
                    .clipped()

                // Interactive HUD overlay on hover
                if isHoveringScreen {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(player.trackTitle)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                if !player.artistName.isEmpty {
                                    Text(player.artistName)
                                        .font(.system(size: 8))
                                        .foregroundColor(.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if !player.tracks.isEmpty {
                                Button(action: { player.toggleScreenMode() }) {
                                    Image(systemName: "list.bullet")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.9))
                                        .padding(4)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)

                        Spacer()

                        // Progress Bar & Timestamp
                        if player.duration > 0 {
                            VStack(spacing: 2) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.3))
                                            .frame(height: 3)
                                        Capsule()
                                            .fill(Color.blue)
                                            .frame(width: max(0, min(geo.size.width * CGFloat(player.currentTime / player.duration), geo.size.width)), height: 3)
                                    }
                                }
                                .frame(height: 3)

                                HStack {
                                    Text(timeString(from: player.currentTime))
                                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                    Text(timeString(from: player.duration))
                                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                        }
                    }
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.75), Color.clear, Color.black.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            } else {
                VStack(spacing: 7) {
                    Image(systemName: player.tracks.first?.isPodcast == true ? "antenna.radiowaves.left.and.right" : "music.note")
                        .font(.system(size: 26))
                        .foregroundColor(.white.opacity(0.35))

                    Text(player.trackTitle)
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 10)

                    if !player.artistName.isEmpty {
                        Text(player.artistName)
                            .foregroundColor(.white.opacity(0.5))
                            .font(.system(size: 8))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                    }

                    if player.tracks.isEmpty {
                        Text("Paste RSS (⌘V) or MENU")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.top, 4)
                    }
                }
                .frame(width: 192, height: 192)
            }
        }
    }

    // MARK: - Classic iPod Episode List Screen

    private var episodeListScreen: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 4) {
                Button(action: { player.toggleScreenMode() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                Text(player.podcastTitle.isEmpty ? "Episodes" : player.podcastTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Image(systemName: player.isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [Color(white: 0.25), Color(white: 0.15)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Episodes Scrollable List
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(player.tracks.enumerated()), id: \.element.id) { index, track in
                            let isCurrent = (index == player.currentIndex)
                            Button(action: {
                                player.playTrack(at: index)
                                player.screenMode = .nowPlaying
                            }) {
                                HStack(spacing: 6) {
                                    if isCurrent {
                                        Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                                            .font(.system(size: 7))
                                            .foregroundColor(.white)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(track.title)
                                            .font(.system(size: 8, weight: isCurrent ? .bold : .medium))
                                            .foregroundColor(isCurrent ? .white : .white.opacity(0.85))
                                            .lineLimit(1)

                                        HStack(spacing: 4) {
                                            if let date = track.pubDate {
                                                Text(date)
                                                    .font(.system(size: 7))
                                                    .foregroundColor(isCurrent ? .white.opacity(0.8) : .white.opacity(0.45))
                                            }
                                            if let duration = track.duration {
                                                Text("• \(duration)")
                                                    .font(.system(size: 7))
                                                    .foregroundColor(isCurrent ? .white.opacity(0.8) : .white.opacity(0.45))
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    isCurrent ?
                                    Color(red: 0.18, green: 0.50, blue: 0.92) :
                                    Color.black.opacity(index % 2 == 0 ? 0.4 : 0.2)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
                .onAppear {
                    if player.currentIndex >= 0 {
                        proxy.scrollTo(player.currentIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 192, height: 192)
        .background(Color(white: 0.08))
    }

    // MARK: - Loading Screen

    private var loadingScreen: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))

            Text(player.statusMessage ?? "Loading...")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .frame(width: 192, height: 192)
    }

    // MARK: - Error Screen

    private func errorScreen(message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(.orange)

            Text("Feed Error")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 10)

            Button("Dismiss") {
                player.errorMessage = nil
            }
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(.blue)
            .padding(.top, 4)
            .buttonStyle(.plain)
        }
        .frame(width: 192, height: 192)
    }

    // MARK: - Click Wheel

    private var wheelView: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.30), Color(white: 0.13)],
                        center: .center, startRadius: 6, endRadius: 100
                    )
                )
                .frame(width: 192, height: 192)
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))

            // MENU button
            wheelButton(label: "MENU", isText: true) {
                if player.tracks.isEmpty {
                    player.openFiles()
                } else {
                    player.toggleScreenMode()
                }
            }
            .offset(y: -71)

            // Backward button
            wheelButton(systemImage: "backward.fill") {
                player.previous()
            }
            .offset(x: -71)

            // Forward button
            wheelButton(systemImage: "forward.fill") {
                player.next()
            }
            .offset(x: 71)

            // Play / Pause button
            wheelButton(systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                player.togglePlayPause()
            }
            .offset(y: 71)

            // Center select/play button
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.88), Color(white: 0.62)],
                        center: .center, startRadius: 3, endRadius: 48
                    )
                )
                .frame(width: 89, height: 89)
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                .contentShape(Circle())
                .onTapGesture {
                    player.togglePlayPause()
                }
        }
    }

    private func wheelButton(
        label: String = "",
        systemImage: String = "",
        isText: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isText {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pomodoro Button & Popover

    private var pomodoroButton: some View {
        Button(action: {
            if player.pomodoro.phase == .idle {
                player.pomodoro.start()
            } else {
                isShowingPomodoroPopover.toggle()
            }
        }) {
            Group {
                if player.pomodoro.phase == .idle {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isHoveringPomodoro ? .white : .white.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isHoveringPomodoro ? 0.14 : 0.06))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                } else {
                    let isWork = (player.pomodoro.phase == .work)
                    let accentColor = isWork ? Color(red: 0.98, green: 0.45, blue: 0.28) : Color(red: 0.30, green: 0.85, blue: 0.55)

                    HStack(spacing: 4) {
                        Image(systemName: player.pomodoro.isPaused ? "pause.fill" : (isWork ? "timer" : "cup.and.saucer.fill"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(accentColor)

                        Text(player.pomodoro.formattedTime)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.65))
                    )
                    .overlay(
                        Capsule()
                            .stroke(accentColor.opacity(0.7), lineWidth: 1)
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHoveringPomodoro = hovering
        }
        .help(player.pomodoro.phase == .idle ? "Start Pomodoro (25m Focus / 5m Rest)" : "Pomodoro: \(player.pomodoro.phase.rawValue) (\(player.pomodoro.formattedTime))")
        .popover(isPresented: $isShowingPomodoroPopover, arrowEdge: .top) {
            pomodoroPopoverContent
        }
    }

    private var pomodoroPopoverContent: some View {
        VStack(spacing: 10) {
            HStack {
                Text(player.pomodoro.phase == .work ? "Focus Session" : "Break Time")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(player.pomodoro.phase == .work ? Color(red: 0.98, green: 0.45, blue: 0.28) : Color(red: 0.30, green: 0.85, blue: 0.55))

                Spacer()

                if player.pomodoro.isPaused {
                    Text("Paused")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.yellow)
                }
            }

            Text(player.pomodoro.formattedTime)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(.white)

            HStack(spacing: 8) {
                Button(player.pomodoro.isPaused ? "Resume" : "Pause") {
                    player.pomodoro.toggle()
                }
                .font(.system(size: 10, weight: .medium))

                Button("Reset") {
                    player.pomodoro.reset()
                    isShowingPomodoroPopover = false
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.red.opacity(0.9))

                if player.pomodoro.phase == .work {
                    Button("Skip to Break") {
                        player.pomodoro.skipToBreak()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(14)
        .frame(width: 190)
    }

    // MARK: - URL Input Dialog Overlay

    private var urlDialogOverlay: some View {
        ZStack {
            Color.black.opacity(0.65)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    player.isShowingURLDialog = false
                }

            VStack(spacing: 12) {
                Text("Enter Podcast RSS Feed URL")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)

                TextField("https://example.com/podcast.xml", text: $player.urlInputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 10))
                    .frame(width: 320)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        player.isShowingURLDialog = false
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.75))

                    Button("Paste Clipboard") {
                        if let clip = NSPasteboard.general.string(forType: .string) {
                            player.urlInputText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.85))

                    Button("Play Podcast") {
                        let text = player.urlInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let url = RSSFeedLoader.sanitizeURLString(text) {
                            player.isShowingURLDialog = false
                            player.loadFeed(from: url)
                        }
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.blue)
                    .disabled(player.urlInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(radius: 12)
            )
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        if url.isFileURL {
                            player.tracks.append(
                                Track(title: url.deletingPathExtension().lastPathComponent, url: url, isPodcast: false)
                            )
                            player.playlist.append(url)
                            if player.tracks.count == 1 {
                                player.playTrack(at: 0)
                            }
                        } else {
                            player.loadFeed(from: url)
                        }
                    }
                }
                return true
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string = string else { return }
                    DispatchQueue.main.async {
                        player.pasteRSSLink(overrideString: string)
                    }
                }
                return true
            }
        }
        return false
    }

    private func timeString(from seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = Int(seconds)
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - Window configuration

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    ContentView()
}
