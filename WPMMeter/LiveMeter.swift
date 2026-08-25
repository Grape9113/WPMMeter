import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import Speech

enum MeterStatus: Equatable {
    case paused
    case preparing(String)
    case listening
    case permissionRequired
    case unavailable(String)

    var message: String {
        switch self {
        case .paused: "Paused"
        case .preparing(let language): "Preparing \(language)…"
        case .listening: "Listening for speech"
        case .permissionRequired: "System audio access required"
        case .unavailable(let message): message
        }
    }
}

@MainActor
final class MeterModel: ObservableObject {
    @Published private(set) var wordsPerMinute: Int?
    @Published private(set) var status: MeterStatus = .paused

    private var pipeline: SpeechMeterPipeline?
    private var silenceTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?

    init() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "paused") {
                self.stop()
            } else if defaults.bool(forKey: "permissionIntroduced") {
                self.start(danish: defaults.bool(forKey: "danish"))
            } else {
                self.requirePermission()
            }
        }
    }

    func start(danish: Bool) {
        stop(markPaused: false)
        status = .preparing(danish ? "Danish" : "English")
        let pipeline = SpeechMeterPipeline(danish: danish) { [weak self] event in
            Task { @MainActor in self?.receive(event) }
        }
        self.pipeline = pipeline
        startTask = Task { await pipeline.start() }
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let pipeline = self.pipeline else { return }
                let value = await pipeline.currentValue()
                self.wordsPerMinute = value
            }
        }
    }

    func requirePermission() { status = .permissionRequired }

    func stop(markPaused: Bool = true) {
        silenceTask?.cancel()
        silenceTask = nil
        startTask?.cancel()
        startTask = nil
        let oldPipeline = pipeline
        pipeline = nil
        Task { await oldPipeline?.stop() }
        wordsPerMinute = nil
        if markPaused { status = .paused }
    }

    private func receive(_ event: SpeechMeterPipeline.Event) {
        switch event {
        case .ready: status = .listening
        case .permissionRequired: status = .permissionRequired
        case .failed(let message): status = .unavailable(message)
        }
    }
}

actor SpeechMeterPipeline {
    enum Event: Sendable { case ready, permissionRequired, failed(String) }

    private let danish: Bool
    private let report: @Sendable (Event) -> Void
    private var estimator = WPMEstimator()
    private var stream: SCStream?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var captureContinuation: AsyncStream<CMReadySampleBuffer<CMReadOnlyDataBlockBuffer>>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var output: CaptureOutput?
    private var analyzerFormat: AVAudioFormat?
    private var inputConverter: AnalyzerInputConverter?
    private var lastAudioTime: TimeInterval?
    private var lastResultUptime: TimeInterval?

    init(danish: Bool, report: @escaping @Sendable (Event) -> Void) {
        self.danish = danish
        self.report = report
    }

    func start() async {
        do {
            if danish {
                let locale = try await Self.locale(for: Locale(identifier: "da_DK"), using: DictationTranscriber.self)
                let module = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
                try await run(module: module, results: module.results)
            } else {
                guard SpeechTranscriber.isAvailable else { throw PipelineError.unsupported("English speech analysis is unavailable on this Mac") }
                let locale = try await Self.locale(for: Locale(identifier: "en_US"), using: SpeechTranscriber.self)
                let module = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
                try await run(module: module, results: module.results)
            }
        } catch let error as SCStreamError where error.code == .userDeclined {
            report(.permissionRequired)
        } catch let error as PipelineError {
            report(.failed(error.message))
        } catch {
            report(.failed("WPM Meter could not start. Try pausing and resuming."))
        }
    }

    func stop() async {
        inputContinuation?.finish()
        captureContinuation?.finish()
        resultTask?.cancel()
        analysisTask?.cancel()
        audioTask?.cancel()
        if let stream { try? await stream.stopCapture() }
        await analyzer?.cancelAndFinishNow()
        self.stream = nil
        analyzer = nil
        analyzerFormat = nil
        inputConverter = nil
        output = nil
        captureContinuation = nil
        estimator.reset()
    }

    func currentValue() -> Int? {
        guard let lastAudioTime, let lastResultUptime else { return nil }
        let elapsed = ProcessInfo.processInfo.systemUptime - lastResultUptime
        return estimator.value(at: lastAudioTime + elapsed)
    }

    private func run<M: LocaleDependentSpeechModule>(module: M, results: M.Results) async throws where M.Result: SpeechModuleResult {
        try await Self.ensureAssets(for: module)
        let modules: [any SpeechModule] = [module]
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw PipelineError.unsupported("No compatible audio format is available")
        }

        let inputs = AsyncStream<AnalyzerInput>(bufferingPolicy: .bufferingOldest(128)) { inputContinuation = $0 }
        let analyzer = SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer
        analyzerFormat = format
        inputConverter = try await AnalyzerInputConverter.converter(compatibleWith: modules)
        try await analyzer.prepareToAnalyze(in: format)

        resultTask = Task { [weak self] in
            do {
                for try await result in results {
                    guard !Task.isCancelled else { return }
                    await self?.consume(text: Self.resultText(result), range: result.range)
                }
            } catch { await self?.reportFailure() }
        }
        analysisTask = Task {
            do { _ = try await analyzer.analyzeSequence(inputs) }
            catch { report(.failed("Speech analysis stopped unexpectedly")) }
        }

        try await startCapture(sampleRate: Int(format.sampleRate), channelCount: Int(format.channelCount))
        report(.ready)
    }

    private func startCapture(sampleRate: Int, channelCount: Int) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw PipelineError.unsupported("No display is available for system audio capture") }
        let ownBundleID = Bundle.main.bundleIdentifier
        let ownApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = sampleRate
        configuration.channelCount = channelCount
        configuration.width = 2
        configuration.height = 2
        configuration.queueDepth = 1

        let capturedBuffers = AsyncStream<CMReadySampleBuffer<CMReadOnlyDataBlockBuffer>>(
            bufferingPolicy: .bufferingOldest(128)
        ) { captureContinuation = $0 }
        guard let captureContinuation else { throw PipelineError.unsupported("Audio buffering is unavailable") }

        audioTask = Task { [weak self] in
            for await sampleBuffer in capturedBuffers {
                guard !Task.isCancelled else { return }
                await self?.yield(sampleBuffer)
            }
        }

        let output = CaptureOutput { [report] sampleBuffer in
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
            let ready = CMReadySampleBuffer<CMReadOnlyDataBlockBuffer>(unsafeWithDataBuffer: sampleBuffer)
            if case .dropped = captureContinuation.yield(ready) {
                captureContinuation.finish()
                report(.failed("System audio arrived faster than it could be analyzed"))
            }
        }
        self.output = output
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        self.stream = stream
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        try await stream.startCapture()
    }

    private func yield(_ sampleBuffer: CMReadySampleBuffer<CMReadOnlyDataBlockBuffer>) {
        do {
            let directInput = AnalyzerInput(buffer: sampleBuffer)
            if directInput.bufferFormat == analyzerFormat {
                try yieldToAnalyzer(directInput)
                return
            }

            guard let inputConverter else { throw PipelineError.unsupported("Audio conversion is unavailable") }
            let pcmBuffer = try Self.pcmBuffer(from: sampleBuffer)
            let sampleTime = AVAudioFramePosition(sampleBuffer.presentationTimeStamp.seconds * pcmBuffer.format.sampleRate)
            let audioTime = AVAudioTime(sampleTime: sampleTime, atRate: pcmBuffer.format.sampleRate)
            for input in try inputConverter.convert(pcmBuffer, at: audioTime) {
                try yieldToAnalyzer(input)
            }
        } catch {
            report(.failed("System audio could not be converted for speech analysis"))
        }
    }

    private func yieldToAnalyzer(_ input: AnalyzerInput) throws {
        guard let inputContinuation else { throw PipelineError.unsupported("Speech input is unavailable") }
        if case .dropped = inputContinuation.yield(input) {
            inputContinuation.finish()
            throw PipelineError.unsupported("Speech analysis could not keep up with system audio")
        }
    }

    private static func pcmBuffer(from sampleBuffer: CMReadySampleBuffer<CMReadOnlyDataBlockBuffer>) throws -> AVAudioPCMBuffer {
        guard
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(sampleBuffer.formatDescription),
            let format = AVAudioFormat(streamDescription: streamDescription),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleBuffer.sampleCount))
        else { throw PipelineError.unsupported("System audio has an unsupported format") }

        buffer.frameLength = AVAudioFrameCount(sampleBuffer.sampleCount)
        let status = sampleBuffer.withUnsafeSampleBuffer { unsafeBuffer in
            CMSampleBufferCopyPCMDataIntoAudioBufferList(
                unsafeBuffer,
                at: 0,
                frameCount: Int32(sampleBuffer.sampleCount),
                into: buffer.mutableAudioBufferList
            )
        }
        guard status == noErr else { throw PipelineError.unsupported("System audio could not be copied") }
        return buffer
    }

    private func consume(text: AttributedString, range: CMTimeRange) {
        let start = range.start.seconds
        let end = range.end.seconds
        var replacements: [TimedWordBatch] = []
        for (index, run) in text.runs.enumerated() {
            let string = String(text[run.range].characters)
            let count = string.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }.count
            guard count > 0 else { continue }
            let timedRange = run.audioTimeRange ?? range
            replacements.append(.init(
                id: "\(range.start.value)-\(index)",
                start: timedRange.start.seconds,
                end: timedRange.end.seconds,
                wordCount: count
            ))
        }
        estimator.replace(rangeStart: start, rangeEnd: end, with: replacements)
        lastAudioTime = end
        lastResultUptime = ProcessInfo.processInfo.systemUptime
    }

    private func reportFailure() { report(.failed("Speech analysis stopped unexpectedly")) }

    private static func resultText<R>(_ result: R) -> AttributedString {
        if let result = result as? SpeechTranscriber.Result { return result.text }
        if let result = result as? DictationTranscriber.Result { return result.text }
        return AttributedString()
    }

    private static func locale<M: LocaleDependentSpeechModule>(for requested: Locale, using type: M.Type) async throws -> Locale {
        guard let locale = await M.supportedLocale(equivalentTo: requested) else {
            throw PipelineError.unsupported("The selected language is unavailable on this Mac")
        }
        return locale
    }

    private static func ensureAssets(for module: any SpeechModule) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }
}

private enum PipelineError: Error {
    case unsupported(String)
    var message: String { switch self { case .unsupported(let message): message } }
}

private final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "WPMMeter.system-audio", qos: .userInitiated)
    private let handler: @Sendable (CMSampleBuffer) -> Void

    init(handler: @escaping @Sendable (CMSampleBuffer) -> Void) { self.handler = handler }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        handler(sampleBuffer)
    }
}
