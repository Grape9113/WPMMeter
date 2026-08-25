# WPM Meter

A minimal native macOS menu-bar app built with SwiftUI. It currently displays a
placeholder `0 WPM`; audio capture and speech recognition are intentionally not
implemented yet.

## Run

1. Open `WPMMeter.xcodeproj` in Xcode 14 or newer.
2. Select the **WPMMeter** scheme and **My Mac** destination.
3. Press **Run**.

The app appears only in the menu bar because `LSUIElement` is enabled.
