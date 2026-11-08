# Building Cadence

## Requirements

Use macOS with full Xcode, its command-line tools selected, and XcodeGen (`brew install xcodegen`). The Swift package requires Swift 6 tooling and uses Swift 5 language mode. The most recently verified development toolchain is Xcode 27.2 (27B52); older Xcode versions have not been certified.

The apps target iOS 18, watchOS 10 and macOS 14. CadenceCore also supports macOS 13. No npm, Docker, backend checkout or paid API key is needed to build or explore demo mode.

```sh
xcodebuild -version
xcodegen generate
open Cadence.xcodeproj
```

Select **CadenceMac** for Mac or **Cadence** for iPhone with its embedded Watch app. The separate **CadenceWatch** scheme is useful for Watch development. Use **Explore demo** to work without a server.

## Mac without signing

```sh
xcodebuild -project Cadence.xcodeproj -scheme CadenceMac \
  -destination 'generic/platform=macOS' -derivedDataPath .build/Mac \
  CODE_SIGNING_ALLOWED=NO build
open .build/Mac/Build/Products/Debug/Cadence.app
```

This builds locally; it does not create a notarized installer. Apple Silicon hosts compile their native architecture by default. Public distribution needs your own signing/notarization process; see [releases](RELEASE.md).

## iPhone and Watch

For simulator development, choose an installed iPhone simulator in Xcode. List available destinations with:

```sh
xcodebuild -project Cadence.xcodeproj -scheme Cadence -showdestinations
```

For physical devices, select your development team under Signing & Capabilities and pair the Watch with the iPhone. `project.yml` deliberately supplies no development team. XcodeGen regeneration replaces manual project edits, so keep persistent changes in `project.yml` or pass `DEVELOPMENT_TEAM=YOUR_TEAM_ID` on the command line.

A fork should replace **every** `com.bahachammakhi.cadencemusic` bundle ID occurrence in `project.yml`, including test targets and `WKCompanionAppBundleIdentifier`, with its own reverse-DNS prefix, then regenerate. Also review Keychain service strings, the background download session identifier and `cadence` URL scheme before shipping a separately branded app. Changing these in an existing install can disconnect stored credentials, downloads or pairing links; plan migration explicitly. Upstream identifiers remain stable for existing installations.

Physical-device builds and App Store/TestFlight distribution follow Apple's provisioning rules. The source license does not include an Apple developer membership or signing identity.

## Tests

Run the fast, deterministic package and release-script tests:

```sh
swift test --package-path Packages/CadenceCore
python3 -m unittest discover -s Scripts/tests -v
```

Run native Mac tests:

```sh
xcodebuild -project Cadence.xcodeproj -scheme CadenceMacTests \
  -destination 'platform=macOS' -derivedDataPath .build/MacTests test
```

The real Tailscale transport check skips when no matching private interface is available. Other Mac tests should run without a music server.

For iOS app unit tests, replace `SIMULATOR_ID` with an installed destination from `-showdestinations`:

```sh
xcodebuild -project Cadence.xcodeproj -scheme Cadence \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath .build/iOSTests CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  ONLY_ACTIVE_ARCH=YES -only-testing:CadenceTests test
```

Use `-only-testing:CadenceUITests` for demo UI flows. Simulator ad-hoc signing preserves background-download behavior; no Apple team is required. Optional live-server tests skip without an explicitly supplied private fixture. They can mutate your server or transfer real playback and must never be enabled automatically in CI. See [QA](QA.md).

The GitHub workflow runs package/script tests, project generation, an unsigned Mac build, native Mac tests, a Watch simulator app/UI-test build, iPhone app unit tests with ad-hoc signing and a fresh-user Server URL UI check. It selects an installed iPhone simulator dynamically and uses no Apple signing credentials or live music accounts. Hosted CI does not establish real Watch operation, server compatibility or public signing readiness.

## Changing resources

`swift Scripts/generate-icon.swift` regenerates original brand assets. `python3 Scripts/generate-demo.py` regenerates original short demo WAVs. See [brand notes](../Resources/Brand/README.md). Do not replace the demo with copyrighted recordings or publish live account screenshots.

## Watch UI checks

With an installed watchOS simulator runtime, choose a Watch UDID from `xcrun simctl list devices available` and run:

```sh
xcodebuild -project Cadence.xcodeproj -scheme CadenceWatch \
  -destination 'platform=watchOS Simulator,id=WATCH_SIMULATOR_UDID' \
  -derivedDataPath .build/WatchTests CODE_SIGN_IDENTITY=- test
```

The Watch UI suite uses the bundled original demo audio with muted output. It covers device selection, the disconnected Mac fallback, local playback, queue navigation and seeking. It needs no live server, shared credentials or real Mac connection. The large-text case injects SwiftUI `xxLarge` in Debug only, because this watchOS simulator runtime does not support `simctl ui content_size`; it does not change system preferences. Repeat on a small Watch; screenshots are stored in the result bundle. The hosted job builds the Watch app and its UI test bundle without signing; it does not install a Watch runtime or claim to execute these UI checks. Physical-device acceptance is separate.
