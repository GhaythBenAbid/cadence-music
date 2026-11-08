# Product scope and roadmap

Cadence aims to make a privately operated music library comfortable on iPhone and Mac, with offline music and remote controls on Apple Watch. Native UI, clear progress and dependable playback take priority over extra infrastructure.

## Implemented in 0.7

Library and global metadata search, artist/album navigation, ordered catalog batch actions, durable preparation, queue editing and paused resume, preloading/repeat-one/autoplay/recovery, editable server playlists/favorites, Spotify import, local history and follows, iPhone/Mac downloads, system Now Playing, private foreground handoff, and multiple offline Watch playlists.

The app asks Aurral to prepare missing audio and surfaces its state. It does not ship an acquisition backend, provider credentials, content catalog or infrastructure deployment. External source success and timing remain outside the client's control. Demo mode needs none of those services.

## Deliberate constraints

- Global search is metadata from Apple's US catalog, capped at 200 results. Library search uses paged server results.
- Local autoplay/ranking and Aurral Discover are useful starting points, not Spotify-level global personalization.
- History/follows/bookmarks/preparation are scoped per account and device, with no cloud synchronization.
- Handoff supports one Mac and its paired iPhone over a private Tailscale link, with foreground iPhone required. It cannot wake suspended clients.
- Watch retains at most 10 playlists of 100 tracks each. One sync plan runs at a time; OS scheduling and storage constrain transfers.
- Discover previews can be short. Full playback requires a real available library file.
- Aurral 2.12.0 native API v1 is tested. API v2 and other Subsonic servers are not certified compatible.

## Next verification and development priorities

1. Complete physical iPhone/Watch acceptance: background downloads/transfers, Bluetooth and wrist-down playback, phone-off offline runs, storage pressure and account erasure.
2. Add tested compatibility with Aurral's newer native API contract before recommending newer server releases.
3. Improve recovery diagnostics and accessibility through real-device feedback.
4. Prepare public distribution: clean publication history/assets, portable signing, Mac notarization and clear public beta availability.

Lyrics, advanced equalizer/crossfade, social features, collaborative/cloud-synced listening profiles, remote wake and a public music service are not delivered features. Roadmap items are proposals, not release promises.

See [QA](QA.md) for verification evidence and [changelog](../CHANGELOG.md) for shipped milestones.
