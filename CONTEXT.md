# WPM Meter

WPM Meter describes the current pace at which spoken content is being delivered through capturable Mac system audio.

## Language

**Listening pace**:
The rate of recognized words over recent elapsed playback time, including ordinary hesitation and pauses within the spoken content.
_Avoid_: Articulation pace, speaking speed

**Current WPM**:
A recent, recency-sensitive estimate of listening pace based on credible timed words from at most the previous 15 seconds. It is unavailable until at least five credible words span three seconds, or when current evidence becomes stale.
_Avoid_: Instantaneous WPM, average WPM

**Measurement episode**:
A continuous period of useful recognized speech. It allows ordinary pauses, becomes unavailable after five seconds without a credible new word, and ends after eight seconds; evidence never carries into the next episode.
_Avoid_: Recording, listening session, history

**No measurement**:
The state in which WPM Meter lacks enough current evidence to report current WPM, displayed as an em dash rather than zero.
_Avoid_: Zero WPM, idle WPM

**Capturable system audio**:
Audio produced by applications that macOS permits WPM Meter to capture. Protected or otherwise restricted audio is outside the product guarantee.
_Avoid_: All Mac audio, microphone audio

**Overlapping speech**:
Simultaneous voices treated as best-effort input to one listening-pace estimate, without speaker identification or separation.
_Avoid_: Speaker tracking, diarized speech

**Selected language**:
The language used to recognize words for measurement: English by default, or Danish when the user enables the persistent Danish checkbox. Changing it begins a new measurement episode.
_Avoid_: Automatic language, detected language

**Menu bar item**:
The always-visible compact presentation of current WPM as a number followed by “WPM,” or an em dash when no measurement is available. When an optional target is active, below-target WPM is red here as well as in the measurement popover.
_Avoid_: Toolbar item, widget

**Measurement popover**:
The transient, title-bar-free box opened from the menu bar item. It shows current WPM prominently and contains the utility's small set of controls, remaining open until the user clicks elsewhere.
_Avoid_: Window, dashboard, floating panel

**Target WPM**:
An optional persisted listening-pace threshold, disabled by default. When active, it colors WPM red in both presentations while below target; reaching the target clears red, and a five-percent margin prevents color flicker around the boundary.
_Avoid_: Comprehension target, training result
