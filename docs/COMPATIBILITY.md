# Server compatibility

Cadence uses two separate contracts: Subsonic for available library audio, and Aurral's native JSON API for Discover, playlist imports and preparation. Support for a native version does not certify every external acquisition or metadata provider.

## Choosing a server or service

**Aurral is the tested server path.** Cadence has partial Subsonic compatibility, not a verified general-purpose server integration.

| Connection | Supported scope | Limits |
|---|---|---|
| Aurral | Library browsing/playback plus native Discover, playlist imports and preparation | Verified versions are listed below; permissions and source configuration still apply |
| Other Subsonic-compatible servers | Basic library browsing and playback may work through the existing Subsonic routes | No other server is certified here. Aurral's native Discover, import and preparation routes are required for those features |
| Spotify | Playlist metadata/import through Aurral | No direct Spotify audio streaming; any required Spotify connection is configured on the server |
| Apple Music / iTunes catalog | Public metadata search | No subscription playback, Apple Music account sign-in or personal-library integration |
| Demo mode | Original bundled audio and sample library | No server, external service account or real music library needed |

A successful sign-in to another Subsonic server does not establish full feature compatibility. Missing native routes can leave Discover, importing or preparation unavailable. No direct integrations with other server protocols are claimed. Use [setup](SETUP.md) for the HTTPS connection requirements, and report the server/version and failing action when testing another implementation.

## Covered versions

| Provider | Evidence |
|---|---|
| Aurral 2.12.0 / native API v1 | Retained wire fixtures and prior live library, import and preparation/audio verification. |
| Native API v2, upstream `743b57d94c54656d9cd7a01adf5a715be4c8d762` | Versioned fixtures plus the real production Hono app in an isolated database, serving only original Cadence audio. |
| Unknown future native version | Discover contract negotiation rejects it instead of guessing at its browse routes. |
| Other Subsonic servers | Not certified as complete Aurral replacements. |

The v2 implementation follows the [app contract](https://docs.aurral.org/api/app-contract/) and [pinned registry](https://github.com/lklynet/aurral/blob/743b57d94c54656d9cd7a01adf5a715be4c8d762/backend/config/apiContract.ts). API v2 support starts in Cadence 0.7.2; older 0.7.1 binaries retain their original v1 requirement.

## What changed

Version 1 declares Discover in `api.features`; version 2 includes it in the baseline and can have an empty feature list. Discover refresh checks the contract again, so a server upgrade is picked up on refresh. Version 2 uses `/api/discover/playlists` and provider-specific detail paths. Playlist provider and ID together identify a row; unsupported providers and unsafe IDs are ignored or rejected.

Native import status renamed `sharedPlaylists`/`sharedPlaylistStats` to `staticPlaylists`/`staticPlaylistStats`. Cadence accepts both shapes, prefers modern keys when both occur, and rejects malformed required collections. These are JSON names: the producer's Subsonic implementation still uses `shared:` playlist IDs. Renaming those IDs would break playback.

## Verification boundaries

48 Core tests cover both versions, malformed/unknown versions, old-server capability requirements, provider navigation, partial-source failures, permissions and import status. The real v2 producer check verifies password authentication, Discover/shelf responses, current import-status decoding, a fixture playlist resolving through Subsonic, reuse of an already-owned track, exact full-file checksum, stream duration over 55 seconds and actual AVFoundation timeline advancement.

The integration server uses a temporary database and loopback listener, with three extended original demo clips. Its Spotify-labelled static playlist is synthetic; no real Spotify OAuth account or acquisition provider is copied into it. This proves the consumed producer/client wire paths, not an end-to-end Spotify OAuth import or source-wide download availability. The user's deployed server is not upgraded by these checks.

## Repeat an isolated producer check

Use the production server with a separate test database and authorized original content. Keep a private JSON fixture outside Git with `server`, `username`, `password`, `expectedAPIVersion`, `playlistName`, `trackTitle`, `artist`, `sha256` and `allowOwnedPreparation`. The server must be an explicit loopback URL with a port; HTTP is permitted only by this development probe, not by the app's sign-in form. The named track must already exist and have at least 55 seconds of full audio.

```sh
CADENCE_CONTRACT_FIXTURE=/absolute/private/path/fixture.json \
  swift run --package-path Packages/CadenceCore CadenceProbe --native-contract-check
```

The probe checks streams/downloads without logging credentials or signed URLs. `allowOwnedPreparation` opts into one preparation request which must reuse the already-owned track. Use a disposable isolated account/database; the probe is never run automatically against production or in public CI.
