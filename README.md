# WPM Meter

A native macOS menu-bar utility that measures the pace of spoken system audio.
It captures system audio with a Core Audio process tap, analyzes speech locally with
Apple's on-device models, and keeps audio and recognition state only in memory.

WPM Meter supports English by default and Danish through a persistent checkbox.
An optional target colors the current WPM red when listening pace is below the
chosen goal.

## Run

1. Open `WPMMeter.xcodeproj` in Xcode 27 or newer on macOS 27.
2. Select the **WPMMeter** scheme and **My Mac** destination.
3. Press **Run**.

The app appears only in the menu bar because `LSUIElement` is enabled. On first
run, macOS requests System Audio Recording Only access. Audio is never saved
or uploaded; network access is used only when macOS downloads an Apple speech
model selected by the user.

## Test

Run the `WPMMeter` scheme's test action in Xcode, or:

```sh
xcodebuild -project WPMMeter.xcodeproj -scheme WPMMeter -destination 'platform=macOS' test
```
