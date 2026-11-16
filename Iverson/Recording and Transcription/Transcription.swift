/// Live transcription code — spoken numbers (and basedpl names) for PC typing.

import Foundation
import Speech
import SwiftUI

@Observable
final class SpokenWordTranscriber {
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), Error>?
    
    // The format of the audio.
    var analyzerFormat: AVAudioFormat?
    
    var converter = BufferConverter()
    var downloadProgress: Progress?
    
    var story: Binding<Story>
    
    var volatileTranscript: AttributedString = ""
    var finalizedTranscript: AttributedString = ""
    var statusMessage: String = ""

    /// Accumulates spoken digits until a full 3-digit Sound Names code is ready.
    var codeBuffer = DigitCodeBuffer()

    /// When set and advertising, completed 3-digit codes are sent to the linked computer.
    /// The computer hold-to-talk key decides when those payloads are typed.
    var keyboard: BluetoothKeyboardPeripheral?

    /// Avoid STT sending the same finalized code several times in a burst.
    private var lastSentCode: String?
    private var lastSentAt: Date = .distantPast
    
    init(story: Binding<Story>) {
        self.story = story
    }

    func resetCodeBuffer() {
        codeBuffer.clear()
        lastSentCode = nil
        lastSentAt = .distantPast
        statusMessage = ""
    }
    
    func setUpTranscriber() async throws {
        let requested = NumeralTranscript.locale
        let locale = await resolvedLocale(for: requested)
        print("[iverson-stt] setUp locale=\(locale.identifier(.bcp47) ?? locale.identifier)")

        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        guard let transcriber else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])
        
        do {
            try await ensureModel(transcriber: transcriber, locale: locale)
            statusMessage = ""
        } catch let error as TranscriptionError {
            statusMessage = error.descriptionString
            print("[iverson-stt] model error: \(error.descriptionString)")
            return
        }
        
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        
        guard let inputSequence else { return }
        
        recognizerTask = Task {
            do {
                for try await case let result in transcriber.results {
                    let plain = String(result.text.characters)
                    let digits = NumeralTranscript.digitize(plain)
                    if result.isFinal {
                        await handleFinalUtterance(plain: plain, digits: digits)
                    } else {
                        await handleVolatile(plain: plain, digits: digits)
                    }
                }
            } catch {
                print("[iverson-stt] speech recognition failed: \(error)")
                statusMessage = "Recognition failed"
            }
        }
        
        try await analyzer?.start(inputSequence: inputSequence)
    }
    
    @MainActor
    private func handleVolatile(plain: String, digits: String) {
        if NumeralTranscript.isNumericPayload(digits) {
            let preview = codeBuffer.pendingDisplay
            let incoming = String(NumeralTranscript.extractDigits(digits))
            var shown = AttributedString(preview)
            if !incoming.isEmpty {
                shown += AttributedString(" ")
                var tail = AttributedString(incoming)
                tail.foregroundColor = DeviceChrome.inkQuiet
                shown += tail
            }
            volatileTranscript = shown
            volatileTranscript.foregroundColor = DeviceChrome.inkQuiet
            statusMessage = codeBuffer.isEmpty
                ? "Speak 3 digits (e.g. zero zero one)"
                : "Code \(codeBuffer.pendingDisplay)"
        } else {
            let glyph = GlyphTranscript.resolve(plain)
            let display = AttributedString(glyph.isEmpty ? plain : glyph)
            volatileTranscript = display
            volatileTranscript.foregroundColor = DeviceChrome.inkQuiet
        }
    }

    @MainActor
    private func handleFinalUtterance(plain: String, digits: String) {
        if NumeralTranscript.isNumericPayload(digits) {
            // One spoken phrase that is already a full code → send once, don't pile onto leftovers.
            let extracted = NumeralTranscript.extractDigits(digits)
            let codes: [String]
            if extracted.count == NumeralTranscript.codeLength, codeBuffer.isEmpty {
                codes = [String(extracted)]
                codeBuffer.clear()
            } else {
                codes = codeBuffer.ingest(digits)
            }
            volatileTranscript = ""
            if codes.isEmpty {
                statusMessage = "Code \(codeBuffer.pendingDisplay) — need \(NumeralTranscript.codeLength - codeBuffer.digits.count) more"
                print("[iverson-stt] digit buffer \(codeBuffer.pendingDisplay)")
                return
            }
            for code in codes {
                let display = AttributedString(code)
                finalizedTranscript += display
                finalizedTranscript += AttributedString(" ")
                updateStoryWithNewText(withFinal: display)
            }
            statusMessage = codeBuffer.isEmpty ? "" : "Code \(codeBuffer.pendingDisplay)"
            return
        }

        let glyph = GlyphTranscript.resolve(plain)
        if glyph.isEmpty {
            volatileTranscript = ""
            print("[iverson-stt] no number/glyph match for: \(plain.prefix(80))")
            return
        }
        let display = AttributedString(glyph)
        finalizedTranscript += display
        finalizedTranscript += AttributedString(" ")
        volatileTranscript = ""
        updateStoryWithNewText(withFinal: display)
    }

    func updateStoryWithNewText(withFinal str: AttributedString) {
        story.text.wrappedValue.append(str)
        story.text.wrappedValue.append(AttributedString(" "))
        let plain = String(str.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        let now = Date()
        if plain == lastSentCode, now.timeIntervalSince(lastSentAt) < 1.5 {
            print("[iverson-bt] skip duplicate \(plain)")
            return
        }
        lastSentCode = plain
        lastSentAt = now
        print("[iverson-bt] send code (\(plain.utf8.count) bytes): \(plain.prefix(120))")
        let keyboard = keyboard
        Task { @MainActor in
            keyboard?.send(plain)
        }
    }
    
    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let inputBuilder, let analyzerFormat else {
            throw TranscriptionError.invalidAudioDataType
        }
        
        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        
        inputBuilder.yield(input)
    }
    
    public func finishTranscribing() async throws {
        inputBuilder?.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
    }
}

extension SpokenWordTranscriber {
    func resolvedLocale(for requested: Locale) async -> Locale {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            return match
        }
        let id = requested.identifier(.bcp47) ?? requested.identifier
        let supported = await SpeechTranscriber.supportedLocales
        if let exact = supported.first(where: { ($0.identifier(.bcp47) ?? $0.identifier) == id }) {
            return exact
        }
        return requested
    }

    public func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw TranscriptionError.localeNotSupported
        }
        
        if await installed(locale: locale) {
            return
        } else {
            statusMessage = "Downloading speech model…"
            try await downloadIfNeeded(for: transcriber)
            statusMessage = ""
        }
    }
    
    func supported(locale: Locale) async -> Bool {
        if await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil {
            return true
        }
        let supported = await SpeechTranscriber.supportedLocales
        let id = locale.identifier(.bcp47) ?? locale.identifier
        return supported.map { $0.identifier(.bcp47) ?? $0.identifier }.contains(id)
    }

    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        let id = locale.identifier(.bcp47) ?? locale.identifier
        return installed.map { $0.identifier(.bcp47) ?? $0.identifier }.contains(id)
    }

    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            self.downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
        }
    }
    
    func releaseLocales() async {
        let reserved = await AssetInventory.reservedLocales
        for locale in reserved {
            await AssetInventory.release(reservedLocale: locale)
        }
    }
}
