# Public release status

The public Cadence repository starts from a reviewed source snapshot with one new root commit. It includes no prior private history, delivery records, live fixtures or old app binaries. The original internal repository is separate.

## Included

- MIT license, original asset notices and reviewed demo screenshots/audio.
- Explicit blank Server URL inputs on iPhone and Mac; the Watch uses its paired iPhone and receives no server credentials.
- Contributor setup, HTTPS server instructions, architecture, privacy/security, release and test guides.
- Read-only source CI without signing credentials or live-server fixtures, plus issue/PR templates.
- No shared Apple team, signing key, server address, Spotify credential, cookies or hosted service.

## Public source is separate from app distribution

The source can be built locally in demo mode without a music server. Source CI covers the package, release helpers, unsigned Mac build, native Mac tests, Watch simulator build, iPhone unit tests and the fresh-user sign-in UI check. See [QA](QA.md) for verification scope.

A public Developer ID signed and Apple-notarized Mac ZIP is available from the [0.7.1 release](https://github.com/bahachammakhi/cadence-music/releases/tag/v0.7.1). Its ticket is stapled; the final anonymous download passed checksum, signature, ticket and Gatekeeper verification. The archive includes the MIT license and asset notices. [Verification record](releases/0.7.1-mac.json).

An iPhone/Watch public beta still requires an intentionally configured testing/distribution route; private TestFlight access is not a public invitation. Older internal binaries are not attached to this repository.

Physical iPhone/Watch background transfer, Bluetooth, wrist-down playback and phone-off running remain pending hardware acceptance. API v1 (Aurral 2.12.0) and consumed API v2 routes (upstream `743b57d`) are covered starting with Cadence 0.7.2. External provider configuration remains server-specific. These limitations remain explicit for this experimental source release.

## Maintainer checks

Before sharing a new source commit, check current files for credentials, personal endpoints, private contact information and unintended media; run relevant tests and review external contributions. A heuristic scan is not proof of perfect secret detection.

Keep private build/test fixtures and signing configuration outside version control. Use source exports or reviewed individual changes to synchronize internal work; never merge private repository history. Keep GitHub private vulnerability reporting enabled and verify the [reporting form](https://github.com/bahachammakhi/cadence-music/security/advisories/new) remains available.
