//
//  PodPlayApp.swift
//  PodPlay
//
//  Created by Arjun Sharma on 19/07/26.
//

import SwiftUI

@main
struct PodPlayApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    configureWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 460, height: 230)
        .commands {
            // Remove the Enter Full Screen menu item
            CommandGroup(replacing: .windowSize) {}

            CommandGroup(replacing: .pasteboard) {
                Button("Paste Podcast RSS Link") {
                    NotificationCenter.default.post(name: .pasteRSSNotification, object: nil)
                }
                .keyboardShortcut("v", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Open Podcast RSS Feed...") {
                    NotificationCenter.default.post(name: .openURLDialogNotification, object: nil)
                }
                .keyboardShortcut("u", modifiers: .command)

                Button("Open Audio Files...") {
                    NotificationCenter.default.post(name: .openFilesNotification, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Start / Toggle Pomodoro (25m / 5m)") {
                    NotificationCenter.default.post(name: .togglePomodoroNotification, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
    }

    private func configureWindow() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first,
                  let screen = window.screen ?? NSScreen.main else { return }

            // Disable automatic frame restoration so our explicit size always wins
            window.isRestorable = false

            // Show close and minimize buttons, hide the zoom/fullscreen button
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = true

            // Enable resizing
            window.styleMask.insert(.resizable)

            // Prevent full screen
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenAuxiliary)

            // --- Force the correct content size every launch ---
            let targetSize = NSSize(width: 460, height: 230)

            let rightMargin: CGFloat = 30
            let topMargin: CGFloat = 60

            let screenFrame = screen.frame
            let originX = screenFrame.maxX - targetSize.width - rightMargin
            let originY = screenFrame.maxY - targetSize.height - topMargin

            window.setFrame(
                NSRect(x: originX, y: originY, width: targetSize.width, height: targetSize.height),
                display: true
            )
        }
    }
}
