# MeetHelp

MeetHelp is a macOS menu bar overlay app built with SwiftUI, ScreenCaptureKit, Deepgram, OpenRouter, and Gemini.

## Development

Run the app directly during development:

```sh
swift run
```

SwiftPM is kept for fast local iteration. The package auto-discovers Swift files under `MeetHelp/`; `MeetHelp/Resources` is excluded because Xcode owns app resources and entitlements.

## Packaging

Build a distributable app bundle from the Xcode project:

```sh
./build_app.sh
```

This delegates to `scripts/package_app.sh`, which:

1. Builds `MeetHelp.xcodeproj` with the `MeetHelp` scheme.
2. Copies the Xcode-produced app bundle to `MeetHelp.app`.
3. Bundles `.env` into `MeetHelp.app/Contents/Resources/.env` when present.
4. Signs the app with `MeetHelp/Resources/MeetHelp.entitlements`.
5. Uses a stable designated requirement for local TCC permissions:

```text
designated => identifier "com.bhanuprakash.MeetHelp"
```

6. Verifies the code signature and creates `MeetHelp.zip`.

Generated outputs such as `.build/`, `.xcodebuild/`, `MeetHelp.app/`, and `MeetHelp.zip` are intentionally ignored by git.

## Permissions

The packaged app requests Screen & System Audio Recording through the app bundle identity `com.bhanuprakash.MeetHelp`. If macOS still shows a stale permission state after changing signing behavior, reset the app-specific entry:

```sh
tccutil reset ScreenCapture com.bhanuprakash.MeetHelp
```

Then relaunch `MeetHelp.app` and grant access once.
