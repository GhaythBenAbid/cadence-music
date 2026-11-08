# Privacy and data flow

This describes the current source, not the privacy practices of your separately operated music server or external providers.

## Where data goes

- **Your configured Aurral server:** account authentication, library/search requests, playlist/favorite changes, preparation/import requests and audio streaming. Server operators control their own storage, logs and providers.
- **Apple's public Search API:** All music search terms, metadata lookups and normal network information such as IP address. Aurral credentials are not attached. The client uses the US catalog; it does not authenticate to Apple Music.
- **Artwork/preview hosts:** displaying external artwork or playing Discover previews may contact the URLs returned by catalog/server metadata. Those hosts can receive normal request information. Full playback uses your library audio rather than substituting previews.
- **Spotify integrations:** playlist links and import settings go through Aurral; the server may need its own Spotify connection. Browser OAuth is handled by the user and provider. Cadence does not include a shared Spotify credential.
- **Your paired devices:** WatchConnectivity transfers music, metadata, receipts and control state. Private Mac control exchanges encrypted playback state/commands over Tailscale; Bonjour advertises non-secret connection information on the nearby network.

Cadence includes no advertising, analytics or tracking SDK. It has no Cadence cloud account or listening-profile synchronization. This does not prevent your server, operating system, VPN or contacted providers from keeping their own logs.

## On-device storage

Server credentials and native-session data use Keychain on iPhone/Mac. Credentials use this-device-only accessibility. Downloaded audio, cached artwork/catalog details, queue state, listening history, followed artists, bookmarks and preparation metadata live on the device. Account-scoped files and generation checks separate sessions; account hashes are identifiers, not encryption of music metadata. These files are not an application-level encrypted vault.

The Watch receives audio and state without server credentials. Mac pairing links contain device identity, private address and port; treat them as private network information even though they contain no password.

Sign-out clears credentials and local downloaded music/cache and invalidates active account work. iPhone sign-out also requests Watch erasure through WatchConnectivity; an offline Watch may not receive that immediately. Do not interpret sign-out as a complete wipe of every account-scoped listening/preparation record: those stores can survive for the same account's next sign-in. **Clear history** removes listening events without deleting follows/bookmarks; **Clear completed** cleans finished preparation rows. Server playlists and accepted acquisition jobs remain on the server. Device backups and OS-managed storage have their own retention behavior.

## Permissions

- Background audio supports playback when the app is not foreground.
- Local-network permission and Bonjour support private Mac discovery/control.
- WatchConnectivity and background URLSession support scheduled file delivery/downloads; their timing is controlled by the OS.

No microphone, calendar, health, location or contacts permission is requested by the current app. The bundled privacy manifest declares no tracking/collected-data categories and the UserDefaults required-reason use. Distribution maintainers must review actual behavior, third-party endpoints and Apple's current disclosure rules before submission; the manifest is not a substitute for that review.

## Reporting safely

Redact server addresses, account names, tokens, passwords, cookies, private pairing links, signed audio URLs and personal artwork/history before sharing logs or screenshots. Never commit `.build`, live test fixtures, Keychain exports or Apple signing files. See [security reporting](../SECURITY.md).
