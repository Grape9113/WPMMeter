# Apple-native audio and speech options for WPM Meter

Research date: 2026-08-25. Sources are first-party Apple documentation, Apple sessions/support material, and the public Swift interface in the locally installed macOS 27 SDK. Because macOS 27 is currently prerelease, beta APIs must be revalidated against the final SDK.

## Recommendation

For a generally distributed build, target **macOS 26**. For the explicitly scoped build that only needs to run on the owner’s current M4 MacBook Air and current OS generation, target **macOS 27**; see the dated Golden Gate addendum below. Use:

1. `ScreenCaptureKit.SCStream` with only an `.audio` stream output attached, `capturesAudio = true`, microphone capture off, and current-process audio excluded.
2. `SpeechAnalyzer` with a locale-specific transcriber:
   - English: `SpeechTranscriber`, configured for volatile results and audio-time-range attributes.
   - Danish: `DictationTranscriber`, configured equivalently for progressive long-form results and audio-time-range attributes.
3. On macOS 27, direct typed sample-buffer input when compatible, otherwise `AnalyzerInputConverter`; never hard-code a recognition format. A macOS 26-compatible build would instead need its own `AVAudioConverter` bridge because the public converter is new in 27.
4. SwiftUI `MenuBarExtra` as the only normal scene, with `LSUIElement = true` (already true in this project).

This is fully local during recognition. Network access is needed only when the system downloads a missing Apple model asset. The app should explicitly initiate and show that download; it should never fall back to `SFSpeechRecognizer`, because that older API may send audio to Apple servers.

The current skeleton targets macOS 13, contains one SwiftUI `MenuBarExtra`, has no test target, no entitlements file, no App Sandbox capability, and only `LSUIElement` plus the Productivity category in `Info.plist`. Raising the deployment target to 27 for the scoped build is therefore a deliberate future implementation change, not the current state.

## Golden Gate / macOS 27 addendum (2026-08-25)

### Exact local environment

Direct inspection of this development machine reports:

- Hardware: MacBook Air `Mac16,13`, Apple M4 (10 cores), 16 GB RAM.
- Installed OS: **macOS 27.0**, build **26A5421a**.
- Installed developer tools: **Xcode 27.0**, build **27A5237l**.
- Selected SDK: **macOS 27.0**, SDK build **26A5406c**, canonical SDK name `macosx27.0`.

Apple’s current release-note title names this OS generation **macOS 27 Golden Gate** and describes the macOS 27 SDK as bundled with Xcode 27. The local build number alone does not reliably identify the public/developer beta seed, so this note does not claim a beta number beyond the user’s statement that the machine is on the Golden Gate beta. [macOS 27 Golden Gate release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)

### What macOS 27 materially improves

The main useful change is at the boundary between ScreenCaptureKit and SpeechAnalyzer:

- macOS 27 adds `AnalyzerInput.init(buffer: CMReadySampleBuffer<CMReadOnlyDataBlockBuffer>)`. ScreenCaptureKit already delivers audio as `CMSampleBuffer`, and Apple documents converting that to `CMReadySampleBuffer` with `CMReadySampleBuffer(unsafeWithDataBuffer:)`. If the configured ScreenCaptureKit audio format is directly supported by the selected speech module, WPM Meter can pass the time-coded sample buffer into SpeechAnalyzer without first manufacturing an `AVAudioPCMBuffer`. That is a simpler path with fewer wrappers and potential copies. The analyzer still does **no format conversion**, so direct input is conditional on format compatibility. [`AnalyzerInput`](https://developer.apple.com/documentation/speech/analyzerinput), [sample-buffer initializer](https://developer.apple.com/documentation/speech/analyzerinput/init(buffer:)-3nt02)
- macOS 27 adds the public `AnalyzerInputConverter` type and its `converter(compatibleWith:)` factory. When direct ScreenCaptureKit buffers are not compatible, this is the Apple-provided conversion fallback rather than custom `AVAudioConverter` plumbing. It also centralizes flushing and produces one or more correctly formatted `AnalyzerInput` values. [`AnalyzerInputConverter`](https://developer.apple.com/documentation/speech/analyzerinputconverter)
- macOS 27 exposes `AnalyzerInput.bufferDuration` and `bufferFormat`, useful for diagnostics and deterministic timestamp/format assertions without asking for the deprecated `buffer` property (which creates a new copy).
- ScreenCaptureKit adds `SCStream.isCapturing`, which is mildly useful for idempotent start/stop and recovery logic. Its other macOS 27 additions found in the SDK—recording editor, clip buffering, recording-track mixing, video orientation, camera/picker state, and storage errors—serve recording/video products and do not improve WPM Meter. [`SCStream`](https://developer.apple.com/documentation/screencapturekit/scstream)

The new `SpeechAnalyzer.Options.ignoresResourceLimits` flag is not an improvement for this app. WPM Meter needs one analyzer; bypassing the system’s conservative resource guard would conflict with its energy philosophy. The new capture-device sequence provider is for `AVCaptureDevice` sources such as microphones, not ScreenCaptureKit system audio, and is therefore out of scope.

macOS 27 does **not** remove the important language split. A fresh runtime query on this machine still reports English locales in `SpeechTranscriber.supportedLocales` but no `da-DK`; `DictationTranscriber.supportedLocales` reports `da-DK` and English locales. Continue using `SpeechTranscriber` for English and `DictationTranscriber` for Danish, with runtime checks.

### Scoped deployment and build recommendation

Because Tahoe/macOS 26 compatibility is explicitly unnecessary and the only required computer is this macOS 27 M4 MacBook Air, set `MACOSX_DEPLOYMENT_TARGET = 27.0` and build against the macOS 27 SDK. Do not add `#available(macOS 26, ...)` branches, an older conversion implementation, Intel-specific workarounds, or a second target. This materially reduces code and lets the pipeline use the new typed sample-buffer input and system converter directly.

The recommended ingestion architecture is:

1. Configure ScreenCaptureKit for mono system audio and attach only `.audio` output.
2. Determine the selected transcriber’s compatible formats.
3. Prefer direct `CMSampleBuffer` → `CMReadySampleBuffer` → `AnalyzerInput` when ScreenCaptureKit can emit a compatible format.
4. Otherwise create one `AnalyzerInputConverter` for the active module and reuse it for the session; wrap the ScreenCaptureKit audio buffer without copying where Apple’s buffer lifetime rules permit, convert, and flush on orderly shutdown.
5. Preserve ScreenCaptureKit presentation timestamps throughout either path.

Direct input should be treated as the preferred hypothesis, not an assumed optimization: benchmark direct and converter paths on this exact M4 machine, verify buffer ownership/lifetime under sustained capture, and choose the simpler measured-safe path. Even if conversion remains necessary, targeting 27 still removes the custom conversion machinery required by a macOS 26 deployment.

This is a **personal/current-generation build decision**, not evidence that macOS 27 is inherently necessary for the product. Beta SDK declarations and behavior can change; pin the development Xcode intentionally and re-run compilation, locale discovery, permission, timing, and long-duration energy tests after each Golden Gate/Xcode beta update and against the final SDK.

## System-audio capture

ScreenCaptureKit is Apple’s current high-performance API for capturing screen and system audio. Audio capture is opt-in through `SCStreamConfiguration.capturesAudio`; `sampleRate` and `channelCount` set the delivered audio format; and `excludesCurrentProcessAudio` can prevent the utility’s own sounds from feeding the recognizer. Apple exposes separate `.screen`, `.audio`, and `.microphone` output types, and an app attaches each desired destination with `addStreamOutput`. Therefore WPM Meter can attach **only `.audio`**, never receive or process pixel buffers, and never enable microphone capture. [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [`capturesAudio`](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio), [`.audio`](https://developer.apple.com/documentation/screencapturekit/scstreamoutputtype/audio), [`addStreamOutput`](https://developer.apple.com/documentation/screencapturekit/scstream/addstreamoutput(_:type:samplehandlerqueue:))

Important qualification: Apple documents independent output attachment, but does **not** explicitly promise that omitting `.screen` eliminates all internal WindowServer video work. It does guarantee that the app receives no video output. This should be measured with Instruments on the target OS. If needed, configure a minimal video size, queue depth, and very slow `minimumFrameInterval`; do not add a screen-output callback merely to discard frames. Apple says deeper frame queues increase WindowServer memory and gives a default depth of 3. [Apple ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)

A display content filter is still required to define the capture source even when only audio output is attached. Capturing a display while excluding WPM Meter’s own application is the simplest global-system-audio behavior. Protected/DRM content may be unavailable, and application audio routing should be verified with representative browsers, podcast/audiobook apps, TTS, output-device changes, AirPlay, and Bluetooth.

### Permission and recovery

Modern macOS calls the privacy category **Screen & System Audio Recording** and can grant screen plus audio or audio only. The wording is necessarily broader than WPM Meter’s behavior, so onboarding should say that the app reads system audio only and discards it. Apple’s ScreenCaptureKit sample says the first capture prompts for Screen Recording permission and that the app must be restarted after granting it. A denial is reported as `SCStreamError.Code.userDeclined`; audio startup and system interruptions have distinct error codes. [Apple Support: control access](https://support.apple.com/en-euro/guide/mac-help/mchld6aa7d23/mac), [Apple ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos), [`SCStreamError.Code`](https://developer.apple.com/documentation/screencapturekit/scstreamerror/code)

Product behavior should be: remain open with `—`; menu explains “System Audio Access Required”; offer a button/deep link to System Settings > Privacy & Security > Screen & System Audio Recording; after a newly granted permission, clearly ask the user to quit and reopen. If permission is revoked or the system stops the stream, return to `—` and expose recovery rather than retrying noisily. `userStopped` is an intentional stop, not a framework failure. [`SCStreamError`](https://developer.apple.com/documentation/screencapturekit/scstreamerror)

No microphone permission, `NSMicrophoneUsageDescription`, or sandbox audio-input entitlement is needed because the microphone is out of scope. ScreenCaptureKit’s ordinary user-approved capture does not require the special `com.apple.developer.persistent-content-capture` entitlement; Apple describes that entitlement for VNC apps needing persistent capture access. App Sandbox can be enabled without file/media or microphone access. Model installation is system-managed; if sandboxed distribution proves it requires outbound client networking for the initiating app, validate that during a signed sandbox build rather than adding network entitlement speculatively. [Apple entitlements: ScreenCaptureKit](https://developer.apple.com/documentation/bundleresources/entitlements), [audio-input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.microphone)

## Speech stack

`SpeechAnalyzer` and its modules were introduced across Apple platforms in OS 26. The installed SDK declares them `@available(anyAppleOS 26, *)`, so macOS 26 is the clean minimum. Apple describes the new `SpeechTranscriber` model as long-form, low-latency, accurate at a distance, and entirely on-device. The model is not embedded in the app; `AssetInventory` downloads, installs, retains, shares, and automatically updates system-managed assets. [WWDC25: Bring advanced speech-to-text to your app](https://developer.apple.com/videos/play/wwdc2025/277/), [`AssetInventory`](https://developer.apple.com/documentation/speech/assetinventory)

Apple explicitly states that `SpeechAnalyzer` transcriber modules do not send voice audio to Apple’s servers, and that the Speech Recognition authorization flow applies only to `SFSpeechRecognizer`. Consequently the recommended stack should **not request Speech Recognition permission** and should not add `NSSpeechRecognitionUsageDescription`. The single privacy prompt is Screen & System Audio Recording. [Asking permission to use speech recognition](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)

Do not use `SFSpeechRecognizer` as a fallback: Apple warns that some locales require an Internet connection and communicate with its servers. That conflicts with the product’s local-only invariant. [`SFSpeechRecognizer.supportedLocales`](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportedlocales())

### Hardware and availability

The API is OS-available on macOS 26, but `SpeechTranscriber.isAvailable` exists specifically because support depends on device hardware and capabilities. Apple recommends `DictationTranscriber` for unsupported languages or devices; it supports the same languages/models/devices as the older recognizer’s **on-device** mode without requiring the user to enable a dictation language in Settings. Apple does not publish a simple Mac model, Neural Engine, or RAM cutoff in these sources. Therefore do not claim “all Apple-silicon Macs” or impose a guessed minimum: ship for macOS 26, check module availability and locale support at runtime, and define unsupported hardware as a recoverable incompatibility state. [`SpeechTranscriber`](https://developer.apple.com/documentation/speech/speechtranscriber), [WWDC25 session](https://developer.apple.com/videos/play/wwdc2025/277/?time=161)

An Apple-silicon-only build is not presently justified by documented requirements. Test the minimum hardware matrix Apple actually allows for macOS 26 before release.

### English and Danish

There is no basis for automatic bilingual recognition in these APIs: a transcriber is initialized with a locale, and its `selectedLocales` describes that selection. Use an explicit English/Danish menu setting and rebuild the analyzer when it changes. Do not run two recognizers continuously: it doubles scarce model work, complicates attribution, and Apple limits simultaneous analyses based on hardware. Mixed-language speech has no documented seamless behavior; treat embedded words from the non-selected language as best-effort recognition. [`LocaleDependentSpeechModule`](https://developer.apple.com/documentation/speech/localedependentspeechmodule), [`SpeechAnalyzer` resource limits](https://developer.apple.com/documentation/speech/speechanalyzer)

Apple’s docs intentionally require runtime discovery rather than publishing a permanent locale table: `supportedLocales` includes downloadable locales, `installedLocales` only installed locales, and `supportedLocale(equivalentTo:)` resolves equivalents. On the 2026-08-25 development Mac, queried with Apple’s macOS 27 SDK/runtime:

- `SpeechTranscriber.supportedLocales` contained multiple English locales but **not** `da-DK`.
- `DictationTranscriber.supportedLocales` contained `da-DK` and multiple English locales.

This local SDK/runtime observation is reproducible evidence, not a permanent Apple guarantee. The app must query on every relevant device. It supports the recommendation to use `SpeechTranscriber` for English and `DictationTranscriber` for Danish today. Apple explicitly positions `DictationTranscriber` as the fallback and provides `progressiveLongDictation` for immediate lengthy audio plus configurable volatile and audio-time-range options. [`DictationTranscriber.supportedLocales`](https://developer.apple.com/documentation/speech/dictationtranscriber/supportedlocales), [`longDictation`](https://developer.apple.com/documentation/speech/dictationtranscriber/preset/longdictation), [WWDC25 session](https://developer.apple.com/videos/play/wwdc2025/277/?time=161)

For each selected locale: resolve the equivalent supported locale, check `installedLocales`/asset status, reserve the locale, request `assetInstallationRequest(supporting:)`, and show download progress. Assets may already be present or shared by another app; reservations are limited per device and may be released after disuse. Since only one language is active at a time, reserve both if the device’s `maximumReservedLocales` permits it; otherwise reserve the selected language and explain the download/switch cost. [`AssetInventory`](https://developer.apple.com/documentation/speech/assetinventory), [`maximumReservedLocales`](https://developer.apple.com/documentation/speech/assetinventory/maximumreservedlocales)

Changing language should stop/finalize the current analyzer, clear the WPM estimator so words from different sessions cannot mix, ensure the new asset, create the corresponding module/analyzer, and resume capture. System audio capture need not restart.

### Automatic hidden English-versus-Danish selection (2026-08-25 follow-up)

#### Documented facts

There is **no public Apple audio-language-identification module** in the macOS 27 Speech SDK. The complete module surface contains `SpeechTranscriber`, `DictationTranscriber`, and `SpeechDetector`; `SpeechDetector` is voice activity detection and reports only whether speech exists, not its language. Apple describes it as a power-saving gate and warns that aggressive gating can lose speech. [`SpeechDetector`](https://developer.apple.com/documentation/speech/speechdetector)

Neither transcriber is multilingual per instance. Both public initializers accept one `Locale`. They conform to `LocaleDependentSpeechModule`, whose plural `selectedLocales` property can describe module selection in general, but the two concrete macOS 27 transcribers expose no initializer or setter taking multiple locales. In the installed SDK, a transcriber’s locale cannot be changed after construction. The API therefore provides no “English + Danish, choose automatically” mode. [`LocaleDependentSpeechModule`](https://developer.apple.com/documentation/speech/localedependentspeechmodule), [`SpeechTranscriber`](https://developer.apple.com/documentation/speech/speechtranscriber), [`DictationTranscriber`](https://developer.apple.com/documentation/speech/dictationtranscriber)

SpeechAnalyzer can host multiple modules and can add/remove them mid-stream. A newly added module sees only new audio, unless the app separately retains and replays prior audio. Apple also says backing engine/model allocations are limited to protect performance, although its current documentation states there is no fixed limit on macOS; compatible transcribers may share engines/models when similarly configured. An English `SpeechTranscriber` and Danish `DictationTranscriber` use different transcriber classes and locale assets, so no Apple source promises that they share work. Treat concurrent operation as two recognition workloads. [`setModules(_:)`](https://developer.apple.com/documentation/speech/speechanalyzer/setmodules(_:)), [`SpeechAnalyzer`](https://developer.apple.com/documentation/speech/speechanalyzer)

Both transcribers can attach `transcriptionConfidence` values (0–1) to ranges of their attributed result text, and can return alternative interpretations in descending likelihood. These are transcription confidence values, not language probabilities. Apple does not document their calibration across locales or across `SpeechTranscriber` versus `DictationTranscriber`, nor an overall candidate score or likelihood that can compare two recognizers. Consequently “pick the larger average confidence” is not a documented correctness rule. [`SpeechTranscriber.Result`](https://developer.apple.com/documentation/speech/speechtranscriber/result), [`DictationTranscriber.Result`](https://developer.apple.com/documentation/speech/dictationtranscriber/result), [`transcriptionConfidence`](https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/transcriptionconfidence)

Apple does provide local **text** language identification through Natural Language. `NLLanguageRecognizer` can be constrained to English and Danish and returns candidate probabilities for supplied text. It does not inspect audio. Applying it to competing transcripts is circular: each recognizer is biased to emit text in its configured language, including plausible-looking hallucinations, so both candidates may be classified as their configured language. It is useful supporting evidence for detecting obvious mismatch or stable language within the chosen transcript, but not an independent arbiter of the original spoken language. [Identifying language in text](https://developer.apple.com/documentation/naturallanguage/identifying-the-language-in-text), [`NLLanguageRecognizer`](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer)

No first-party API found in Apple’s macOS 27 SDK supplies a normalized recognition likelihood, word-error estimate, or language-ID score for comparing English and Danish candidate transcripts. Sound Analysis can run classification models, but Apple does not ship a documented English-versus-Danish spoken-language classifier; creating and validating such a model would be a separate ML product, not a small use of the operating system.

#### Product conclusion

**Fully automatic, invisible, and reliably credible language choice is not available from the current Apple-native stack.** The strongest correctness-first architecture remains an explicit English/Danish selection remembered as one tiny preference. That is a product-visible compromise, but it avoids silently displaying a confident-looking WPM derived from the wrong recognizer.

If fully automatic hidden behavior is made a hard requirement, the strongest feasible local design is an explicitly experimental **probe, choose, and monitor** heuristic—not continuous dual transcription:

1. Keep a short bounded audio probe after startup, a source discontinuity, or a suspected language change. Do not display WPM until selection is sufficiently confident.
2. Run English `SpeechTranscriber` and Danish `DictationTranscriber` on the same probe, preferably as separate analyzers so incompatible module formats and failures remain isolated. This temporarily doubles transcription/model work.
3. Score finalized candidate ranges using several weak signals: amount of nonempty stable text per second of detected speech; revision instability; coverage by timed/confident text runs; confidence distribution; and constrained `NLLanguageRecognizer` output. Never use raw word count as a quality score because that biases the WPM result being selected.
4. Choose only when multiple signals agree by an empirically calibrated margin. Otherwise remain `—`, retain the prior language when continuity evidence is strong, or—if product correctness takes priority—ask the user rather than guess.
5. Stop and release the losing analyzer immediately. Run one recognizer during steady state. Keep only a small replay buffer sufficient for a later probe; it remains memory-only and bounded.
6. Use strong hysteresis before switching. Short quotations, names, code-switching, recognition revisions, music, and sparse speech must not flip the chosen pipeline. On a confirmed switch, clear the WPM window so counts from different recognition hypotheses never mix.

This heuristic is preferable to permanent parallel recognition because steady-state CPU, Neural Engine/model memory, and energy remain near the single-language design. Its costs are slower first display, temporary doubled work, bounded audio retention, and a residual risk of silent misclassification. Confidence attributes should initially be diagnostic inputs only; cross-engine thresholds must come from measurements, not assumed comparability.

#### Required experiments before accepting the heuristic

Build a non-production evaluation harness using labelled, legally usable English and Danish audio; this is research tooling, not the app pipeline. Include each target content class (YouTube-style speech, podcasts, audiobooks, lectures, TTS), speakers/accents, speeds, compression, background music, silence, proper nouns, English phrases inside Danish, Danish phrases inside English, and source switches.

For probe lengths such as 2, 4, 6, 10, and 15 seconds, record for both candidates: selection accuracy, abstention rate, time to decision, confidence distributions, final/volatile edit rate, speech-time coverage, WPM error against timestamped reference words, CPU, memory, and energy. Calibrate on one corpus and validate thresholds on a disjoint corpus. The acceptance criterion must include wrong-language selection rate, not merely average accuracy, because a wrong but numeric WPM is worse than `—`.

Also compare three variants:

1. The recommended explicit selection baseline.
2. Dual candidate transcripts using the best engine for each language (`SpeechTranscriber` English, `DictationTranscriber` Danish).
3. Two `DictationTranscriber` candidates, one per locale. The latter may make confidence behavior more comparable because the module family matches, but Apple does not guarantee calibration and English recognition/WPM accuracy may regress.

If no tested heuristic reaches the agreed error/abstention target without unacceptable latency or energy, automatic hidden selection should be rejected rather than disguised as reliable. A custom on-device audio language-ID model is the next technical option, but it materially expands scope, model/data maintenance, binary or asset management, and validation; it is not recommended for v0.1.

### Results, timing, and corrections

Configure volatile results for responsiveness and `audioTimeRange` attributes for source-audio timing. Apple says volatile phrase results arrive quickly and may be replaced repeatedly until a final result, after which that audio range will not change. Each result has a phrase/passage `range`, `isFinal`, `resultsFinalizationTime`, and attributed text; time-range attributes associate portions of the attributed string with source-audio ranges. This is finer than merely timing a whole recognition callback, but Apple does not promise that each attribute run equals exactly one linguistic “word.” Tokenization and timing must be empirically validated for English and Danish. [`ReportingOption.volatileResults`](https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption), [`SpeechTranscriber.Result`](https://developer.apple.com/documentation/speech/speechtranscriber/result), [`Preset`](https://developer.apple.com/documentation/speech/speechtranscriber/preset)

The WPM layer must treat each result range as replaceable: volatile revisions replace prior contributions for the overlapping audio range; final results replace and seal them. Never append every volatile string. Retain only the bounded range needed by the WPM window, and call `cancelAnalysis(before:)` for audio no longer relevant after confirming behavior. This makes multi-hour memory bounded. Apple exposes `volatileRange` and explicit finalization/cancellation for this lifecycle. [`SpeechAnalyzer`](https://developer.apple.com/documentation/speech/speechanalyzer), [`finalize(through:)`](https://developer.apple.com/documentation/speech/speechanalyzer/finalize(through:))

### Audio format and efficiency

ScreenCaptureKit delivers audio as `CMSampleBuffer` wrapping an `AudioBufferList`. Configure mono because speech-rate estimation does not benefit from stereo. Do not guess a fixed recognition sample rate: ask `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` (optionally considering the capture format) and convert with `AnalyzerInputConverter`. Feed a bounded async stream with timestamps; avoid storing audio. [ScreenCaptureKit `.audio`](https://developer.apple.com/documentation/screencapturekit/scstreamoutputtype/audio), [`SpeechAnalyzer`](https://developer.apple.com/documentation/speech/speechanalyzer)

For long-running efficiency, use one analyzer only, one active locale, no alternatives, no confidence attribute unless product tests prove it useful, no screen output, mono capture, bounded buffering/backpressure, result-driven estimator updates, and UI coalescing. `prepareToAnalyze` can reduce first-result latency, while the default lazy resource behavior unloads when deallocated. Prefer the default `whileInUse` model retention initially; process-lifetime retention trades memory/energy for faster restarts and needs measurement before adoption. Apple notes that similarly configured transcribers can share backing engines/models, but that does not justify parallel language pipelines. [`SpeechAnalyzer`](https://developer.apple.com/documentation/speech/speechanalyzer), [`SpeechTranscriber`](https://developer.apple.com/documentation/speech/speechtranscriber)

## Menu bar

SwiftUI `MenuBarExtra` is the right API: it creates a persistent menu-bar control and can be the app’s only scene. Apple documents `LSUIElement = true` for hiding a menu-only utility from the Dock and app switcher; this project already has it. Use `.menu` for a tiny conventional command menu unless richer permission/download progress genuinely requires the existing `.window` popover style. A text label can render `347 WPM` or `—`; provide a stable accessibility title independent of the changing number. [`MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra), [`MenuBarExtraStyle`](https://developer.apple.com/documentation/swiftui/menubarextrastyle)

One caveat from Apple: a menu-bar-only app may be automatically terminated if the user removes its extra. WPM Meter should not make the `isInserted` binding user-removable unless that lifecycle is intended. [`MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra)

## Items to prove before locking the implementation spec

1. On final macOS 26/27, confirm English and Danish module availability on the minimum supported hardware and compare timing quality/latency between the two models.
2. Instrument an audio-only `SCStream` to quantify WindowServer, CPU, memory, and energy cost and determine whether minimal video configuration changes it.
3. Verify the exact first-run audio-only permission wording and whether a restart remains required on every supported OS release.
4. Verify App Sandbox + Developer ID/App Store signing behavior, including model download, without microphone or speech-recognition permission.
5. Validate time-range attribute segmentation for contractions, numerals, abbreviations, punctuation, and Danish compounds before defining the WPM counter.
6. Test protected media, multi-output devices, AirPlay/Bluetooth, sleep/wake, output-device switching, display disconnect, and permission revocation.
