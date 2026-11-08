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

A heuristic scan covered 372 reachable historical Git blobs plus the current source tree. No recognized private-key/token patterns were found; literal credential candidates were synthetic test fixtures. Historical personal endpoint/signing/config defaults were found and remain a publication consideration. This is not an independent security audit or a guarantee of secret-free history. The first hosted run exposed an `@main`/`main.swift` filename conflict in the probe on Swift 6.3.3; the source was renamed and all 42 package tests also passed from a fresh local scratch directory. Hosted workflow execution is separate from these local checks.

The follow-up server-setup review passed all 42 Core tests, the Mac build and the focused iPhone welcome UI flow after moving Server URL above credentials as a permanent input. The current-tree pattern scan found no private endpoint/signing/config defaults; the historical scan covered 405 blobs and retained the known historical configuration findings. Ordinary networking guidance was made independent of a particular VPN. These are source checks, not a replacement installed/TestFlight build.
