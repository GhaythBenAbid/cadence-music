# Listening additions in 0.7

## Catalog songs and albums

Search All music for a song, artist or album. Song menus offer Play next, Add to queue, Save to favorites, Add to playlist and Download when ready. Album pages offer Play album and the same batch actions. Add to playlist can select an existing playlist or create one immediately, before audio is available. Aurral account permissions still apply.

A catalog favorite is bookmarked locally immediately, so it is visible under Your listening even while preparation is pending. When audio is available, the favorite action also stars the actual Aurral song. Catalog metadata is never passed off as a playable Song or an Apple preview download.

Play album starts its first available song in order, then appends prepared songs as the batch advances. An earlier pending song holds later songs until it resolves; blocked/failed songs remain visible and do not prevent the rest playing. Play next waits for the batch to resolve before inserting it in order. An empty queue keeps album order and stays paused for a queue-only action. Explicit new playback prevents an older pending Play from taking over. Queue edits follow the selected phone/Mac output; Mac-to-phone batches wait for each acknowledgment rather than overwriting a pending instruction.

## Preparing music

On Mac, use the Preparing music sidebar item. On iPhone, open it from Listen or Search. Each row shows the intended action, preparation state and any failure. The client advances two ordinary acquisitions at a time and separately checks unconfirmed requests, with up to 300 unfinished rows and 500 retained rows. Actual server concurrency remains controlled by Aurral. Batch input is capped at 200 unique songs, matching the catalog lookup ceiling.

The account-scoped journal is written before submission. A lost response or an app relaunch during submission becomes Unconfirmed; the app checks matching library audio and existing Aurral jobs instead of automatically submitting again. Request again is an explicit user action after checking Aurral. An interrupted playlist/favorite/queue action asks for review where its result is ambiguous. Existing playlist songs are checked before adding, so a confirmed already-present song is not duplicated.

Accepted jobs continue on Aurral after the client closes. The client checks progress while the process is running; iOS may suspend it without active audio or a background opportunity. This does not add a push service, wake a suspended phone or guarantee a completion time. After relaunch, ready playback/queue actions require Apply prepared music; they do not unexpectedly start listening. Saved favorites/playlist/download intents can finish when the client can run again. Stop waiting prevents pending playback and queue insertion while allowing accepted server acquisition to finish. Remove removes a local intention, not the server's accepted job.

Unreadable or unsupported saved preparation data is preserved and blocks new submissions instead of being overwritten. Preparation metadata contains catalog details and account hashes, not credentials, tokens or signed audio URLs. Sign-in to another account reads a separate journal and invalidates in-flight callbacks.

## Your listening

Mac has a Your listening sidebar item; iPhone has a link from Listen. It contains recently played music with Play/Resume, catalog favorites and followed artists. History begins with this version; earlier listening is not reconstructed.

AudioController counts actual advancing audible time. Seeking and buffering do not count as listening. Progress is merged by listening session, with at most 200 events retained. Early skips, listened time, favorites and followed artist names influence the available-library mix and autoplay ranking; a daily deterministic tie-break adds variety. This is a local ranking of available candidates, not a Spotify-grade global recommendation engine. Discover's existing Aurral feed is unchanged.

History, follows and catalog bookmarks are private to the account on this device. They are not cloud-synchronized. Clear history removes history without removing followed artists or saved favorites.

## Multiple offline Watch playlists

Update both iPhone and Watch to 0.7, then open the Watch app once so the phone can read its multiple-playlist capability. Send an album/playlist from iPhone as before. Up to **10 saved playlists**, with **1–100 unique tracks each**, can coexist. One Watch preparation/sync plan is active at a time. Starting another sync stops the earlier incomplete plan; already-saved playlists remain. Phone selection during an active sync asks before stopping it.

Choose a saved playlist from Your run on iPhone to inspect/resend it. On Watch, choose Watch → Saved playlists, select one and play. Receiving another playlist does not switch or interrupt the active Watch playlist. Switching preserves a paused playback session per playlist. Ready still requires file integrity validation and a receipt from the Watch, not merely a queued transfer.

Remove playlist removes only that collection; audio shared with another saved playlist is retained. Erase saved music on Watch and signing out on iPhone still clear the Watch library. Deleted playlist IDs have tombstones, and old-account transfers are rejected after an account switch. A known playlist resend preserves its ID; a playlist erased on Watch gets a fresh manifest when sent again. Music files remain account-scoped and are reused between playlists rather than copied per playlist.

### Compatibility and migration

| Producer/consumer | Behavior |
|---|---|
| Existing single `mix.json` on a new client | Migrates to one saved playlist, preserving files and selection. |
| New phone + new Watch advertising `mixLibrary` version 2 | Sends optional `keepOtherMixes: true`; new mixes are retained. |
| New phone + older Watch | Adding another playlist is blocked until the updated Watch opens; existing legacy resend remains supported. |
| Older phone + new Watch | Missing/false retention flag preserves the sender's legacy single-mix replacement behavior. |
| Unsupported/corrupt Watch library index | Files are preserved; new imports stop with a visible recovery message. |

Keep both apps updated when using multiple playlists. Downgrading to a single-mix client can replace the library. RunMix and file-transfer protocol version 1 remain readable; the retention flag is optional and the new receipt is separately versioned. No server credentials are sent to Watch. Per-playlist removals use durable WatchConnectivity userInfo delivery, while the latest library receipt uses application context.

Storage/receipt/late-file tests run with the actual shared LocalLibrary code and Watch-style pruning enabled. Watch target compilation and archive/export are checked. Physical Bluetooth, background delivery, wrist-down listening and phone-off running remain hardware acceptance checks; software verification does not establish those outcomes.
