/// Helper code for UI and transcription.

import Foundation
import AVFoundation
import SwiftUI

extension Story: Equatable {
    static func == (lhs: Story, rhs: Story) -> Bool {
        lhs.id == rhs.id
    }
}

extension Story: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum TranscriptionState {
    case transcribing
    case notTranscribing
}

public enum TranscriptionError: Error {
    case couldNotDownloadModel
    case failedToSetupRecognitionStream
    case invalidAudioDataType
    case localeNotSupported
    case noInternetForModelDownload
    case audioFilePathNotFound
    
    var descriptionString: String {
        switch self {

        case .couldNotDownloadModel:
            return "Could not download the model."
        case .failedToSetupRecognitionStream:
            return "Could not set up the speech recognition stream."
        case .invalidAudioDataType:
            return "Unsupported audio format."
        case .localeNotSupported:
            return "This locale is not yet supported by SpeechAnalyzer."
        case .noInternetForModelDownload:
            return "The model could not be downloaded because the user is not connected to internet."
        case .audioFilePathNotFound:
            return "Couldn't write audio to file."
        }
    }
}

public enum RecordingState: Equatable {
    case stopped
    case recording
    case paused
}

public enum PlaybackState: Equatable {
    case playing
    case notPlaying
}

public struct AudioData: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer
    var time: AVAudioTime
}

// Ask for permission to access the microphone.
extension Recorder {
    func isAuthorized() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }
        
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
    
    func writeBufferToDisk(buffer: AVAudioPCMBuffer) {
        do {
            try self.file?.write(from: buffer)
        } catch {
            print("file writing error: \(error)")
        }
    }
}

extension AVAudioPlayerNode {
    var currentTime: TimeInterval {
        guard let nodeTime: AVAudioTime = self.lastRenderTime, let playerTime: AVAudioTime = self.playerTime(forNodeTime: nodeTime) else { return 0 }
        
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
}

extension TranscriptView {
    
    func handlePlayback() {
        guard story.url != nil else {
            return
        }
        
        if isPlaying {
            recorder.playRecording()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                currentPlaybackTime = recorder.playerNode?.currentTime ?? 0.0
            }
        } else {
            recorder.stopPlaying()
            currentPlaybackTime = 0.0
            timer = nil
        }
    }
    
    func beginTalk() {
        guard !isRecording else { return }
        if isPlaying { isPlaying = false }
        if story.isDone { story.isDone = false }
        speechTranscriber.resetCodeBuffer()
        isRecording = true
    }

    func endTalk() {
        guard isRecording else { return }
        isRecording = false
    }

    /// While linked to a computer, keep the mic open so the Mac talk key can gate typing.
    func syncLinkedListening() {
        let shouldListen = sendToPC && keyboard.isConnectedToPC
        if shouldListen, !isRecording {
            beginTalk()
        } else if !shouldListen, isRecording, sendToPC {
            // Stay listening while Link is on even if PC briefly disconnects;
            // only stop when Link is turned off (handled by the Link toggle).
        }
    }
    
    func handlePlayButtonTap() {
        isPlaying.toggle()
    }
    
    @ViewBuilder func textScrollView(attributedString: AttributedString) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                textWithHighlighting(attributedString: attributedString)
                Spacer()
            }
        }
        .scrollIndicators(.hidden)
    }
    
    func attributedStringWithCurrentValueHighlighted(attributedString: AttributedString) -> AttributedString {
        var copy = attributedString
        copy.runs.forEach { run in
            if shouldBeHighlighted(attributedStringRun: run) {
                let range = run.range
                copy[range].foregroundColor = DeviceChrome.ink
                copy[range].backgroundColor = DeviceChrome.ink.opacity(0.08)
            }
        }
        return copy
    }
    
    func shouldBeHighlighted(attributedStringRun: AttributedString.Runs.Run) -> Bool {
        guard isPlaying else { return false }
        let start = attributedStringRun.audioTimeRange?.start.seconds
        let end = attributedStringRun.audioTimeRange?.end.seconds
        guard let start, let end else {
            return false
        }
        
        if end < currentPlaybackTime { return false }
        
        if start < currentPlaybackTime, currentPlaybackTime < end {
            return true
        }
        
        return false
    }
    
    @ViewBuilder func textWithHighlighting(attributedString: AttributedString) -> some View {
        Text(attributedStringWithCurrentValueHighlighted(attributedString: attributedString))
            .font(.system(size: 40, weight: .ultraLight, design: .default))
            .tracking(1.5)
            .monospacedDigit()
            .lineSpacing(10)
            .foregroundStyle(DeviceChrome.inkQuiet)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
