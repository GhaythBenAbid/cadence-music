# Watch controls and accessibility

Cadence uses native watchOS controls and the existing iPhone/Mac companion protocol. This review covers the music player, not every optional Apple Watch capability. Hardware behavior and battery measurements are separate from simulator verification.

## Implemented baseline in 0.7.5

| Feature | Implementation and verification boundary |
|---|---|
| Digital Crown: Watch audio | The visible player gives Apple's local volume control focus. Focus is released for another page, a sheet, an inactive scene or VoiceOver. Crown input no longer scrolls the player in the regression test. Real headphone loudness still needs a device check. |
| Digital Crown: iPhone/Mac | The volume control adjusts the existing Cadence player volume command, bounded to 0–100%, with coalesced messages. A real Crown-input fixture verifies the component's output; it does not certify a live peer connection. |
| Always On | Reduced luminance while inactive shows a black, gray-text player without artwork or bright fills. An active scene restores controls even if the luminance notification is delayed. Tapping the dimmed display also shows controls. The normal player/navigation hierarchy stays mounted. It observes track/playing changes without subscribing to elapsed-time ticks. watchOS controls physical brightness; no measured battery saving is claimed. |
| Double tap | Default system list/scroll behavior remains. Custom Play/Pause is withheld: synthetic Double Tap followed by touch input failed in the tested simulator, while the same touch flow without the gesture passed. Physical mixed-input verification is needed before adding it. |
| iPhone audio auto-launch | The real `handleRemoteNowPlayingActivity()` delegate selects iPhone controls when watchOS delivers its audio launch event and local Watch audio is not playing. Active Watch playback retains ownership; explicit device selection can still switch devices. OS delivery depends on the user's audio auto-launch settings; the handler/UI route is exercised in tests. |
| Playback basics | Play/Pause, previous/next, shuffle, repeat off/all/one, local queue/seek, saved-playlist selection and position/queue resume. Existing background audio, route interruption and system media-control behavior remain. |
| Screen-reader semantics | Named controls, current selection, shuffle/repeat values, volume percentages, adjustable remote volume and named removal actions for queue entries/playlists. Destructive library actions retain confirmation. |
| VoiceOver focus | Automatic Crown volume focus is suppressed while VoiceOver is enabled so the app does not seize navigation from the screen reader. Native volume/slider controls and explicit actions remain available. |
| Larger text and smaller screens | Native Dynamic Type fonts and scrollable content. The Debug UI suite exercises `xxxLarge` layouts and 40 mm/46 mm simulators; normal and Always On layouts are checked separately. |
| Contrast, motion and transparency | Dark backgrounds, symbols/text alongside selection colors, native focus indication and no custom Always On animation. System controls retain platform accessibility behavior. Automated audits cover touch regions, descriptions, contrast and traits in the library, player, queue, device picker and remote-volume fixture. |

## Using the controls

On the local player, turn the Crown for headphone volume. If touch scrolling moves Crown focus to the scroll view, select the visible volume control again. Swipe left/right to switch pages; the Crown scrolls ordinary library/settings lists and dialogs when they own focus. It is intentionally released while choosing a track position or using the queue.

The remote volume button shows the Cadence volume percentage. Turn the Crown, activate it for a full slider, or use its accessibility adjustment action. It controls the selected iPhone/Mac app's volume, not the Mac's global system output. An unavailable connection disables remote actions.

AssistiveTouch, VoiceOver and double tap have system-defined interactions; Cadence does not override those settings. No custom Double Tap Play/Pause action is registered in this release.

## Device checks still required

- Confirm physical headphone loudness changes with the Crown, including after returning from the queue and after waking.
- Confirm Always On becomes the gray-text layout, restores controls on wrist raise or tap, and keeps music/next-track playback running for several minutes. A 30-second physical stop/return-to-clock report is not certified resolved by simulator tests.
- Compare battery use over a representative session; screenshots cannot measure display nits or energy consumption.
- Confirm real VoiceOver reading order, adjustable volume, named removal actions and AssistiveTouch navigation.
- Check maximum text size, Bold Text, Zoom, Reduce Motion and Reduce Transparency on the user's Watch.
- Check actual iPhone audio auto-launch and remote commands with the user's OS settings and devices.

The user reports playback working on a Series 9, with brightness and Crown-volume concerns reported against 0.7.3. That report is not a complete accessibility or battery certification.

## Optional features not delivered

Custom Double Tap Play/Pause, Siri/App Shortcuts, a Cadence watch-face complication/Smart Stack widget, independent server streaming on Watch, workout tracking and health-data integration are not implemented. Mac remote control still uses the iPhone relay; this update does not add remote wake or a perpetual background connection.

## References

- [Apple: Always On design](https://developer.apple.com/documentation/watchos-apps/designing-your-app-for-the-always-on-state/)
- [Apple: native volume focus](https://developer.apple.com/documentation/watchkit/wkinterfacevolumecontrol/focus())
- [Apple: double tap](https://developer.apple.com/documentation/watchos-apps/enabling-double-tap)
- [Apple: iPhone audio launch event](https://developer.apple.com/documentation/watchkit/wkapplicationdelegate/handleremotenowplayingactivity())
- [Apple: watchOS accessibility](https://developer.apple.com/videos/play/wwdc2021/10223/)
