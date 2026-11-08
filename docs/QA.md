# Testing and verification

## Verified baseline: 0.7.0 (16)

These are recorded local results for the released implementation, not a claim that every contributor or CI host has run them:

| Check | Result |
|---|---|
| CadenceCore | 42 tests passed |
| iOS app unit suite | 54 tests, 7 optional skips, zero failures |
| iPhone demo UI | 10 distinct flows passed |
| Native Mac | 3 tests passed, including encrypted real-network handoff transport |
| Real preparation | Initially missing song acquired through production PreparationCenter; audio timeline advanced and reported duration exceeded 30 seconds; completed journal reloaded |
| Builds | Mac universal signed build; paired iPhone/Watch archive and export; matching embedded versions and background audio declarations |
| Distribution | Private Mac release and private internal TestFlight verified; no public testing link |

The real preparation acceptance took about 71 seconds on the tested server. It proves that one configured path worked, not instant playback or catalog-wide availability. Existing-song and initially-missing-song checks are different tests.

## Reproduce locally

Follow [BUILDING.md](BUILDING.md) for exact package, script, Mac and iOS simulator commands. Demo tests use original generated audio and synthetic metadata, without real music credentials. New setup/signing-script tests use temporary synthetic configuration and stub process execution; they do not contact Apple or upload builds.

Optional live tests deliberately skip unless a local private fixture authorizes them. Read each test's fixture schema and side effects before supplying one; never include real fixtures in Git, CI, screenshots or issues. Live tests can download/acquire music, edit server state or move playback. Use a dedicated account/library and authorized content. Host directories and credentials are intentionally not documented as copy/paste defaults.

CI covers deterministic Core/script tests, XcodeGen generation, an unsigned Mac build and native Mac tests. The transport test may skip without Tailscale. Hosted CI is neither a production-server contract check nor physical Watch acceptance.

## Manual acceptance before a dependable running release

- iPhone: stream/download, lock screen/media controls, background download completion, app relaunch, network loss/recovery and account changes.
- Watch: real paired-device transfer receipt, Bluetooth headphones, wrist-down/background listening, phone-off playback with Watch Wi-Fi/cellular disabled, playlist switching/removal and shared-file cleanup.
- Lifecycle: low storage, interrupted/expired background work, unavailable server, old-client migration, delayed files after sign-out or playlist deletion.
- Mac: Space while playing/paused; text editing/dialogs untouched; Now Playing/Boring Notch metadata and media commands.
- Handoff: both directions with queue/duplicates/position; stale acknowledgments; unreachable peer; foreground/background phone transitions; no second player after uncertain confirmation.
- Imports/preparation: invalid link, blank name, disconnected Spotify, unavailable track, server refusal, partial readiness, ambiguous mutation and relaunch review.

Physical Watch background/Bluetooth/standalone-run tests remain **pending**. Do not mark them passed based on simulator screenshots, compilation or storage tests.

## Release evidence

Keep raw `.xcresult`, logs, archives, signing output and private fixtures in ignored local storage. Public release notes should include sanitized test summaries, toolchain, known skips and artifact checksums. Private distribution status is kept outside the public source release; a source tag is not a public installer or TestFlight invitation.

## Open-source preparation verification — 8 November 2026

The current source cleanup was verified with 42 Core tests, three release-helper tests, three native Mac tests, a fresh unsigned Mac build and the iPhone welcome-validation UI test. The latter confirms the server field is initially blank/visible and validates HTTPS before account sign-in. XcodeGen generation, local Markdown links, Python compilation and workflow YAML parsing passed.

## Public Mac 0.7.1 (17)

Apple accepted notarization submission `78a5f9ae-0a16-42da-8746-9b42bbf3b6c1`. The universal Developer ID signed app has hardened runtime, a secure timestamp, the original sandbox/network permissions and no debugger entitlement. Signature verification, stapling/ticket validation and Gatekeeper assessment passed. The final archive contains the MIT license and asset notices; an anonymous GitHub download matched SHA-256 `841ba26667d289f4e7982c126f4e017e2c189f525410a21c61c1dc716c0b3035` and its extracted app passed those checks again. [Machine-readable verification](releases/0.7.1-mac.json). No private server default or signing material was included.

## 0.7.2 compatibility and client CI

The new CI job passed its Watch simulator build, iPhone app unit suite and fresh-user Server URL UI check alongside existing Mac/Core checks. Local v2 source verification passed 48 Core tests, 54 iOS app tests (seven optional live skips) and three focused iPhone UI flows. The real upstream v2 production app was exercised in an isolated database on loopback, using extended original audio only: bootstrap/authentication, Discover/shelf, import status, retained Subsonic playlist identity, owned-track preparation, complete download checksum and actual full-audio playback passed. See [compatibility](COMPATIBILITY.md) for the exact producer pin and limits.


## 0.7.2 (18) distribution

The final source commit `274130ed2ca49efa0b99d76434c447058f3aef0e` passed both [hosted CI jobs](https://github.com/bahachammakhi/cadence-music/actions/runs/42512991060), covering Mac, iPhone and Watch. Local native Mac tests passed all three tests. Phone and embedded Watch archive/export passed with matching 0.7.2 (18) values, background audio declarations and no private server defaults in either executable. Internal TestFlight processing and availability were verified separately; no public beta link is supplied.

Mac notarization was Accepted. The final universal archive passed strict signature, secure timestamp/hardened runtime, no-debugger-entitlement, stapled-ticket and Gatekeeper checks. The anonymously downloaded GitHub ZIP matched SHA-256 `bc49a365dc35db5a4c5c45e51a6a01758ce7d07cebcc692037af12d232379637` and its extracted app passed signature, ticket and Gatekeeper verification again. [Verification record](releases/0.7.2-mac.json).

The local migration from the existing development-signed Mac install stopped in a Keychain read before a responsive window could be verified. The previous working 0.7.1 installation was restored and reopened with its paused song and position preserved. The 0.7.2 upgrade check on that account needs the user's macOS Keychain approval; it is not reported as passed. Physical Watch background/Bluetooth/phone-off acceptance also remains pending.
