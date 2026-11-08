# Private Mac playback control

Target: Watch controls Cadence on iPhone, Cadence on Mac, or its own saved offline mix.

The Mac bridge uses the existing iPhone companion and private Tailscale network. It adds no Pi/VPS service, public listener or daemon. The in-app Mac listener binds only the Tailscale IPv4 interface (identified using Tailscale's ULA as well as CGNAT IPv4, since other VPNs can also use 100.x addresses). Nearby Bonjour advertises a non-secret connection link for setup. A pasted connection link is available if discovery is unavailable. After setup, requests use the cached private endpoint and do not depend on foreground Bonjour discovery.

Frames use Apple's CryptoKit ChaChaPoly with an account-specific, domain-separated key derived from the existing Aurral credentials. Passwords and key material are never advertised or transferred. Requests/replies have bounded frames, freshness checks, unique IDs and duplicate-command protection. iPhone and Mac must use the same Aurral account. The Watch receives playback state, not Mac credentials or keys.

A production server/client probe exercised encrypted state, next, pause and volume requests, confirmed duplicate commands execute once, and rejected a wrong password. An OS-level `lsof` check confirmed the test listener bound only the actual Tailscale IP, never a wildcard. The test-only port is 47824; the app uses 47823.

See [QA](QA.md) for the current verification baseline. Native Mac universal Release and iPhone/Watch archive/export succeeded. `CadenceProbe --mac-remote-self-test` repeats the live transport check with throwaway fixture credentials; it never reads real music credentials.

Mac and iPhone local-network permission is for nearby setup discovery. Manual connection links contain only device name/ID, private IP and port. No Aurral password, key or playback token is in the link. Mac commands use dedicated Watch message keys, so an older phone version ignores them instead of accidentally controlling its own player.

Physical Watch/iPhone background connectivity remains a separate acceptance check. No claim of direct Watch-to-Mac operation without the paired iPhone.


Setup: update both iPhone/Watch and Mac apps, sign into the same Aurral account, open Cadence’s account screen on Mac and the player’s **Playback devices → Connect a Mac** on iPhone. Select the nearby Mac or paste its copied link. Check the connection, start a song on Mac, and choose **Mac** on Watch.

Apple’s [requiredLocalEndpoint documentation](https://developer.apple.com/documentation/network/nwparameters/requiredlocalendpoint) describes the explicit bind used here. The [local-network privacy technote](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) covers the Bonjour permission declarations.

## 0.6 queue and playback handoff

The same private port (47823) now accepts versioned, optional handoff payloads. No new daemon, public listener or server deployment is required. Both apps must use 0.6 or newer for handoff; capability negotiation keeps older control-only versions usable. Frames are bounded at 2 MB, transfer responses are cached for 60 seconds (20 entries) and request IDs prevent duplicate execution. Credentials and endpoint generations reject replies from an earlier connection/account. Existing ordinary control frames retain their legacy limits.

On iPhone, tap the player’s device button, connect the Mac, then choose the Mac or This iPhone. On Mac, tap its iPhone control to move playback, then the Mac control to bring it back. The full ordered queue (including duplicate song entry IDs), current position, shuffle, repeat and autoplay transfer together; destination volume is preserved. New song selections and queue additions follow the selected output. Additions compare the destination queue IDs/current entry before applying, without restarting audio. Ordinary system commands and Mac Space route to the selected peer instead of restarting the paused local player. Watch users should choose the actual output (Mac or iPhone); the wrong source gives an explanatory error.

Mac-initiated operations reach the iPhone through a foreground heartbeat. Availability expires after eight seconds without it, and pending instructions expire after 25 seconds. Keep Cadence foreground on the iPhone when receiving or controlling it; the bridge cannot wake a suspended app. One Mac and the active paired iPhone are the supported scope. Local files are not sent during handoff: each destination resolves its own download or Aurral stream.

Source playback pauses before the destination starts. If confirmation is lost, the source remains paused; retry uses the original request ID and saved transfer rather than silently starting a second player. After the retry-cache window, inspect the destination before retrying. An unreachable-peer fallback explicitly warns that it cannot stop that peer and restores this device’s saved queue, which may differ from the peer’s latest queue.

Verification includes encrypted real-network roundtrips on the isolated test port (full queue/position, replay, instruction acknowledgment, wrong-account rejection and old-client capability fallback) plus a real production Mac↔iOS-simulator handoff with Aurral audio advancing. The live test restored the original queue, position and paused intent afterward. Physical iPhone foreground/background transitions and Watch connectivity remain hardware acceptance checks.

## 0.7 prepared catalog batches

Catalog queue/play actions follow the selected output. Mac batches destined for iPhone wait for each instruction acknowledgment to avoid replacing pending instructions. The final phone acknowledgment is sent only after the action succeeds. The server keeps the handoff instruction ID long enough to accept that acknowledgment after the transfer clears its pending slot; an old acknowledgment cannot erase a newer pending command. Tests exercise these transitions over the real encrypted transport. Foreground receiver and existing private-network limits are unchanged.
