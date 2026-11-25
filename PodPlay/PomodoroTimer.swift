//
//  PomodoroTimer.swift
//  PodPlay
//
//  Created by Arjun Sharma on 21/11/26.
//

import Foundation
import Combine
import AppKit

enum PomodoroPhase: String, Equatable {
    case idle = "Idle"
    case work = "Focus"
    case rest = "Break"
}

@MainActor
final class PomodoroTimer: ObservableObject {

    // MARK: - Published Properties
    @Published var phase: PomodoroPhase = .idle
    @Published var timeRemaining: Int = 25 * 60
    @Published var isPaused: Bool = false

    // MARK: - Constants
    let workDuration: Int = 25 * 60 // 25 minutes (1500 seconds)
    let restDuration: Int = 5 * 60   // 5 minutes (300 seconds)

    // MARK: - Callbacks
    var onWorkCompleted: (() -> Void)?
    var onBreakCompleted: (() -> Void)?

    // MARK: - High-Precision Timing State
    private var targetEndTime: Date?
    private var pausedRemaining: TimeInterval?
    private var timerCancellable: AnyCancellable?

    init() {
        self.timeRemaining = workDuration
    }

    // MARK: - Controls

    /// Starts or restarts the Pomodoro timer in work phase
    func start() {
        phase = .work
        timeRemaining = workDuration
        isPaused = false
        pausedRemaining = nil
        targetEndTime = Date().addingTimeInterval(TimeInterval(workDuration))
        startTicking()
    }

    /// Toggles between play and pause if running; if idle, starts the timer
    func toggle() {
        switch phase {
        case .idle:
            start()
        case .work, .rest:
            if isPaused {
                resume()
            } else {
                pause()
            }
        }
    }

    func pause() {
        guard !isPaused, phase != .idle else { return }
        isPaused = true
        if let target = targetEndTime {
            pausedRemaining = max(0, target.timeIntervalSinceNow)
        }
        stopTicking()
    }

    func resume() {
        guard isPaused, phase != .idle else { return }
        isPaused = false
        let durationToResume = pausedRemaining ?? TimeInterval(timeRemaining)
        targetEndTime = Date().addingTimeInterval(durationToResume)
        pausedRemaining = nil
        startTicking()
    }

    func reset() {
        stopTicking()
        phase = .idle
        isPaused = false
        targetEndTime = nil
        pausedRemaining = nil
        timeRemaining = workDuration
    }

    func skipToBreak() {
        phase = .rest
        timeRemaining = restDuration
        isPaused = false
        pausedRemaining = nil
        targetEndTime = Date().addingTimeInterval(TimeInterval(restDuration))
        startTicking()
        onWorkCompleted?()
    }

    // MARK: - Timer Engine (High-Frequency Wall-Clock Sync)

    private func startTicking() {
        stopTicking()
        // Fire every 100ms (0.1s) on the .common RunLoop mode so window interaction doesn't freeze the timer
        timerCancellable = Timer.publish(every: 0.1, tolerance: 0.02, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopTicking() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func tick() {
        guard !isPaused, phase != .idle, let target = targetEndTime else { return }

        let diff = target.timeIntervalSinceNow

        if diff > 0.05 {
            let secondsLeft = max(0, Int(ceil(diff)))
            if secondsLeft != timeRemaining {
                timeRemaining = secondsLeft
            }
        } else {
            // Reached zero: phase transition
            timeRemaining = 0
            if phase == .work {
                // 1. Fire completion callback (pauses music + dink sound)
                onWorkCompleted?()
                // 2. Seamlessly transition to 5m break
                phase = .rest
                timeRemaining = restDuration
                targetEndTime = Date().addingTimeInterval(TimeInterval(restDuration))
            } else if phase == .rest {
                // Break ended: fire break completed callback (ding sound)
                onBreakCompleted?()
                reset()
            }
        }
    }

    // MARK: - Sound Alerts

    /// Plays a small "dink" chime (macOS Tink)
    func playDinkSound() {
        if let sound = NSSound(named: "Tink") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    /// Plays a clear "ding" chime (macOS Glass / Ping)
    func playDingSound() {
        if let sound = NSSound(named: "Glass") {
            sound.play()
        } else if let sound = NSSound(named: "Ping") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    // MARK: - Formatting

    var formattedTime: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
