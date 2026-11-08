# Public release status

The public Cadence repository starts from a reviewed source snapshot with one new root commit. It includes no prior private history, delivery records, live fixtures or old app binaries. The original internal repository is separate.

## Included

- MIT license, original asset notices and reviewed demo screenshots/audio.
- Explicit blank Server URL inputs on iPhone and Mac; the Watch uses its paired iPhone and receives no server credentials.
- Contributor setup, HTTPS server instructions, architecture, privacy/security, release and test guides.
- Read-only source CI without signing credentials or live-server fixtures, plus issue/PR templates.
- No shared Apple team, signing key, server address, Spotify credential, cookies or hosted service.

## Public source is separate from app distribution

The source can be built locally in demo mode without a music server. Current source CI covers the package, release helpers, unsigned Mac build and native Mac tests. iPhone simulator sign-in checks are also run locally. See [QA](QA.md) for verification scope.

Public prebuilt apps are not yet supplied. A general Mac download needs Developer ID signing and notarization. An iPhone/Watch public beta requires an intentionally configured testing/distribution route; private TestFlight access is not a public invitation. Older internal binaries are not attached to this repository.

Physical iPhone/Watch background transfer, Bluetooth, wrist-down playback and phone-off running remain pending hardware acceptance. Aurral 2.12.0 native API v1 is the tested baseline; newer API v2 is unverified. These limitations remain explicit for this experimental source release.

## Maintainer checks

Before sharing a new source commit, check current files for credentials, personal endpoints, private contact information and unintended media; run relevant tests and review external contributions. A heuristic scan is not proof of perfect secret detection.

Keep private build/test fixtures and signing configuration outside version control. Use source exports or reviewed individual changes to synchronize internal work; never merge private repository history. Keep GitHub private vulnerability reporting enabled and verify the [reporting form](https://github.com/bahachammakhi/cadence-music/security/advisories/new) remains available.
