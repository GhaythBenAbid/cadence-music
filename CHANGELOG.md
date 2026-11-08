# Changelog

Versions below describe implementation milestones. Public binary availability is separate; see [release guidance](docs/RELEASE.md).

## 0.7.2 (18) — 8 November 2026

- Support native API v2 bootstrap capabilities and Discover playlist routes while retaining API v1 behavior.
- Decode v2 static playlist import status and preserve the Subsonic `shared:` identifiers used by both server versions.
- Keep provider identity in playlist navigation, reject unsafe/unknown entries and retain visible permission/partial-source errors.
- Add iPhone unit/UI and Watch simulator builds to GitHub CI without signing credentials or live accounts.
- Add an opt-in loopback contract probe; real upstream v2 routes were verified with original demo audio.

## 0.7.1 (17) — 8 November 2026

- Publish a Developer ID signed, Apple-notarized universal Mac download with a stapled ticket, checksum, MIT license and notices.

- Fix clean package builds by giving the `@main` probe a non-special filename.
- Add MIT licensing, contributor setup, architecture, privacy/security and release documentation, community templates and source-build CI.
- Make Server URL an always-visible login input before credentials; remove tailnet-specific assumptions from ordinary playback/download guidance.
- Remove private server defaults and the original development team from new source builds; show the phone server field by default.
- Make Apple release helpers use neutral private config paths and an explicit team, with upload guarded by `--upload`.
- Replace internal delivery chronology with public-facing usage and verification notes; retain reviewed demo screenshots only.

These changes do not rebuild previously distributed apps or remove earlier Git/release artifacts.

## 0.7.0 (16)

- Global catalog song/album Play, Play next, queue, favorites, playlist and download actions.
- Persistent account-scoped preparation with uncertain-request checks and relaunch review.
- Local listening history/resume, artist follows and library ranking.
- Up to 10 offline Watch playlists, migration and safe shared-file cleanup.
- Acknowledged prepared batches across the private handoff transport.

## 0.6.1 (15)

- All music as the default global metadata search and Aurral prepare-to-play path.
- Keep My library for available-audio search and explicit source/error feedback.

## 0.6.0 (14)

- Rich library search/pagination, artist/album navigation, playback recovery and next-item preparation.
- Repeat-one, library autoplay, private foreground iPhone/Mac queue handoff and text-safe Space control.

## 0.5 series

- Native Discover and Spotify playlist import, clearer importer validation/progress.
- iPhone downloads, persistent queues/playlists and system Now Playing integration.
- Native Mac app and Watch remote/offline foundations.
