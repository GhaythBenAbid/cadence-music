# Setup and first listen

## Bring your own server

Cadence is a client, not an Aurral installer or a music provider. Obtain an Aurral account on a server you control or are authorized to use. The tested contract is **Aurral 2.12.0 / native API v1**; newer API v2 support has not been verified. Library playback uses Subsonic endpoints; Discover, importing and preparation also need Aurral's native endpoints.

On iPhone and Mac, the login form has an always-visible **Server URL** field above username/password. It starts blank; `https://music.example.com` is a placeholder, not a configured service. Existing signed-in installations keep their own Keychain credentials. To switch servers, sign out (which removes local downloads), then enter the new URL and account. The Watch is an iPhone companion: it receives music/control state from the paired phone and has no server login or stored server credentials.

Use the server's base HTTPS URL, including a non-default port when needed, such as `https://music.example.com:8443`. Do not append `/rest`, a dashboard route, embedded credentials or a session token. Valid trusted TLS is required. Cadence rejects plain HTTP and does not disable certificate verification.

If you use a tailnet-only server, install/connect Tailscale on the Mac or iPhone and verify that its HTTPS URL opens there. Tailscale is optional for reaching other HTTPS servers, but required by the current private Mac-control bridge. Server deployment, acquisition providers and OAuth credentials are managed in Aurral, not in this repository.

## Play a song

1. Open Cadence on Mac or iPhone. Enter the server URL, username and password, then sign in.
2. Open an album or playlist under Listen and press Play.
3. To look beyond your library, open Search → All music and choose Songs, Artists or Albums.
4. Select a song or Play album. Existing library audio can play immediately. Missing audio goes through Aurral preparation; follow its progress in Preparing music.

All music uses Apple metadata. It never treats a 30-second preview as a full recording. Discover previews are intentionally short. Full playback requires a matching library file; unavailable sources or permissions are reported instead of promising success.

Use **My library** to search only files already available from the server. Save downloads while connected for later offline playback. Downloaded files belong to the signed-in account; signing out erases local downloads. Server favorites and playlists are subject to account permissions.

## Import a Spotify playlist

1. In Listen's playlist actions, choose **Import from Spotify**.
2. Paste a full `https://open.spotify.com/playlist/…` link or `spotify:playlist:…` URI. Track/album links and shortened links are not playlist inputs.
3. Select **Check playlist**. Review the preview and editable suggested name; enter a non-empty name if necessary.
4. Optionally enable daily checks, then select **Import playlist**.
5. Follow Imported Spotify playlists for track/preparation progress. Refresh and open/play the imported server playlist when songs are ready.

The import creates a server playlist and asks Aurral to obtain missing audio through its configured providers. It does not download audio from Spotify. This server version may require a connected Spotify account; complete the server's Spotify OAuth flow yourself. Cadence cannot sign into Spotify on your behalf, bypass permissions or guarantee access to private/editorial playlists. Unavailable tracks may remain pending or fail; preview success does not mean full audio exists.

## Take music on a run

On iPhone, open an album/playlist, choose its Watch action and confirm. Open Cadence on the paired Watch so capabilities and receipts can sync. Up to 10 playlists of 100 unique songs each can be retained, with one active transfer plan.

Wait for **Ready for your run**, which requires Watch acknowledgment of verified files. Select **Watch → Saved playlists** on the Watch, connect Bluetooth headphones, and play. The intended offline path needs neither the phone nor cellular after successful transfer.

Before relying on it, test with the phone off and Watch Wi-Fi/cellular disabled. Background transfer timing, wrist-down playback and Bluetooth listening still need physical-device acceptance for this release. Keep both apps updated. [Detailed behavior](LISTENING-AND-WATCH.md).

## Mac and system controls

Space toggles playback in the active Mac app unless a text field or modal needs it. Media keys and system Now Playing expose metadata, artwork and transport state. For Boring Notch, select **Media → Music Source → Now Playing**.

For Watch remote control or queue handoff, sign into the same account on Mac and iPhone, connect both to Tailscale and use **Playback devices → Connect a Mac** on iPhone. An awake Mac with Cadence running is required; receiving/controlling iPhone must remain foreground. [Connection, security and handoff limits](MAC-CONTROL.md).

## Troubleshooting

| Symptom | Check |
|---|---|
| Cannot connect | Exact HTTPS base URL, trusted certificate, VPN/tailnet access, correct account |
| Only a preview plays | Discover preview is separate from full library playback; inspect preparation status |
| Discover unavailable | Native API v1 capability and permission; newer API v2 is not validated |
| Import button unavailable | Valid playlist preview and non-empty name; inspect visible connection/import errors |
| Song stays preparing | Aurral job status, source availability and add-music permission; do not blindly resubmit an unconfirmed job |
| Watch still syncing | Both apps updated/opened, devices near each other, storage space and actual receipt; OS schedules delivery |
| Mac not discovered | Tailscale interface, local-network permission, same account; try the copied private connection link |

Never post credentials, cookies, pairing links, signed stream URLs or unredacted logs in a public issue.
