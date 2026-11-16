/// iverson.io transcript view — aluminum shell, glass display, number / glyph-name speech input.

import Foundation
import SwiftUI
import Speech
import AVFoundation

struct TranscriptView: View {
    @Binding var story: Story
    var keyboard: BluetoothKeyboardPeripheral
    var onNewSession: () -> Void = {}

    @State var isRecording = false
    @State var isPlaying = false
    @State var sendToPC = false
    #if DEBUG
    @State var showDiagnostics = false
    #endif

    @State var recorder: Recorder
    @State var speechTranscriber: SpokenWordTranscriber

    @State var currentPlaybackTime = 0.0
    @State var timer: Timer?
    @State private var displayOpacity = 0.0
    @FocusState private var talkFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(
        story: Binding<Story>,
        keyboard: BluetoothKeyboardPeripheral,
        onNewSession: @escaping () -> Void = {}
    ) {
        self._story = story
        self.keyboard = keyboard
        self.onNewSession = onNewSession
        let transcriber = SpokenWordTranscriber(story: story)
        _recorder = State(initialValue: Recorder(transcriber: transcriber, story: story))
        _speechTranscriber = State(initialValue: transcriber)
    }

    private var liveText: AttributedString {
        speechTranscriber.finalizedTranscript + speechTranscriber.volatileTranscript
    }

    private var hasLiveText: Bool {
        !String(liveText.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            DeviceChrome.shellGradient
                .ignoresSafeArea()

            RadialGradient(
                colors: [.white.opacity(0.22), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 28)
                    .padding(.horizontal, 28)

                glassDisplay
                    .padding(.horizontal, 28)
                    .padding(.top, 28)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .opacity(displayOpacity)

                Spacer(minLength: 24)

                controlDeck
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
            }
        }
        .onAppear {
            speechTranscriber.keyboard = keyboard
            talkFocused = true
            withAnimation(.easeOut(duration: 0.9).delay(0.1)) {
                displayOpacity = 1
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                keyboard.resumeIfNeeded()
                talkFocused = true
            }
        }
        .onChange(of: isRecording) { oldValue, newValue in
            guard newValue != oldValue else { return }
            if newValue {
                Task {
                    do { try await recorder.record() }
                    catch { print("could not record: \(error)") }
                }
            } else {
                Task { try await recorder.stopRecording(finishSession: false) }
            }
        }
        .onChange(of: isPlaying) {
            handlePlayback()
        }
        .onChange(of: keyboard.isConnectedToPC) { _, _ in
            syncLinkedListening()
        }
        .onChange(of: sendToPC) { _, linked in
            if linked {
                syncLinkedListening()
            } else if isRecording {
                endTalk()
            }
        }
        .focusable()
        .focused($talkFocused)
    }

    // MARK: - Regions

    private var topBar: some View {
        HStack(alignment: .center) {
            DeviceWordmark(subtitle: "Numbers · Glyphs")
            Spacer()
            if story.isDone {
                Button("New") {
                    isPlaying = false
                    isRecording = false
                    onNewSession()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DeviceChrome.bezel.opacity(0.5))
                .buttonStyle(.plain)
            }
        }
    }

    private var glassDisplay: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(DeviceChrome.glassGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.04),
                                    Color.black.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.22), radius: 30, y: 18)
                .shadow(color: .white.opacity(0.25), radius: 1, y: -0.5)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DeviceChrome.glassHighlight, .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Group {
                    if !story.isDone {
                        liveDisplay
                    } else {
                        playbackDisplay
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack {
                    if isRecording {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(DeviceChrome.lens)
                                .frame(width: 6, height: 6)
                            Text(sendToPC && keyboard.isConnectedToPC ? "Live" : "Listening")
                                .font(.system(size: 11, weight: .medium))
                                .tracking(1.0)
                                .foregroundStyle(DeviceChrome.inkQuiet)
                        }
                    }
                    Spacer()
                    // Manual hold remains available; when Linked, listening stays on automatically.
                    DeviceTalkKey(
                        isListening: isRecording,
                        isEnabled: !(sendToPC && keyboard.isConnectedToPC),
                        onPress: beginTalk,
                        onRelease: endTalk
                    )
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
                .padding(.top, 8)
            }
        }
        .frame(minHeight: 320)
        .frame(maxHeight: .infinity)
    }

    private var liveDisplay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if hasLiveText {
                    Text(liveText)
                        .font(.system(size: 40, weight: .ultraLight, design: .default))
                        .tracking(1.5)
                        .monospacedDigit()
                        .lineSpacing(10)
                        .foregroundStyle(DeviceChrome.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeOut(duration: 0.25), value: String(liveText.characters))
                } else {
                    idlePrompt
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var idlePrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isRecording ? "Listening" : "Ready")
                .font(.system(size: 34, weight: .ultraLight))
                .tracking(-0.6)
                .foregroundStyle(DeviceChrome.ink)
            Text(
                sendToPC && keyboard.isConnectedToPC
                    ? "Hold Talk key, speak a 3-digit code (e.g. zero zero one), release."
                    : (isRecording ? "Speak digits — sends when 3 are ready. Or say a glyph name." : "Link to a computer, or hold the key to practice.")
            )
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DeviceChrome.inkQuiet)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 8)
    }

    private var playbackDisplay: some View {
        textScrollView(attributedString: story.storyBrokenUpByLines())
    }

    private var controlDeck: some View {
        VStack(spacing: 22) {
            DeviceStatusLED(
                isOn: sendToPC && keyboard.isConnectedToPC,
                label: sendToPC
                    ? (keyboard.isConnectedToPC ? "Linked" : "Waiting for computer")
                    : "Local"
            )

            if sendToPC, let code = keyboard.linkCode {
                linkCodePanel(code: code)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 28) {
                if story.isDone {
                    Button {
                        handlePlayButtonTap()
                    } label: {
                        Text(isPlaying ? "Pause" : "Replay")
                            .font(.system(size: 13, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(DeviceChrome.bezel.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        sendToPC.toggle()
                        if sendToPC {
                            speechTranscriber.keyboard = keyboard
                            keyboard.startAdvertising()
                        } else {
                            keyboard.stopAdvertising()
                            #if DEBUG
                            showDiagnostics = false
                            #endif
                        }
                    }
                } label: {
                    Text(sendToPC ? "Link On" : "Link")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(
                            sendToPC
                                ? DeviceChrome.bezel.opacity(0.7)
                                : DeviceChrome.bezel.opacity(0.45)
                        )
                }
                .buttonStyle(.plain)

                #if DEBUG
                if sendToPC {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showDiagnostics.toggle()
                        }
                    } label: {
                        Text(showDiagnostics ? "Hide Log" : "Log")
                            .font(.system(size: 13, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(DeviceChrome.bezel.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }

            if !speechTranscriber.statusMessage.isEmpty {
                Text(speechTranscriber.statusMessage)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DeviceChrome.bezel.opacity(0.45))
                    .multilineTextAlignment(.center)
            }

            if let progress = speechTranscriber.downloadProgress {
                ProgressView(progress)
                    .tint(DeviceChrome.bezel.opacity(0.35))
                    .frame(maxWidth: 180)
            }

            if sendToPC {
                Text(keyboard.statusText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DeviceChrome.bezel.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            #if DEBUG
            if showDiagnostics {
                diagnosticsPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            #endif
        }
    }

    private func linkCodePanel(code: String) -> some View {
        VStack(spacing: 8) {
            Text(code)
                .font(.system(size: keyboard.isConnectedToPC ? 22 : 44, weight: .ultraLight, design: .default))
                .monospacedDigit()
                .tracking(keyboard.isConnectedToPC ? 4 : 8)
                .foregroundStyle(DeviceChrome.bezel.opacity(0.72))
                .accessibilityLabel("Link code \(code)")
            Text(
                keyboard.isConnectedToPC
                    ? "Code \(code)"
                    : "Enter this code on your computer"
            )
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(DeviceChrome.bezel.opacity(0.4))
            .multilineTextAlignment(.center)
        }
        .animation(.easeInOut(duration: 0.35), value: keyboard.isConnectedToPC)
    }

    private var diagnosticsPanel: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(Array(keyboard.logLines.suffix(30).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(DeviceChrome.bezel.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: 100)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.06))
        )
        .frame(maxWidth: 520)
    }
}
