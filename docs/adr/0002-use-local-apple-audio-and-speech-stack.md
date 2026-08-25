# Use the local Apple audio and speech stack

WPM Meter captures capturable system audio with an audio-only ScreenCaptureKit stream and measures it locally with SpeechAnalyzer, using SpeechTranscriber for English and DictationTranscriber for Danish. It never falls back to SFSpeechRecognizer or a remote service because local-only processing, a single capture permission, and bounded ephemeral state matter more than compatibility with older systems.
