# Contributing

Thanks for helping improve Cadence. Start with the [README](README.md), [build guide](docs/BUILDING.md), [architecture](docs/ARCHITECTURE.md) and [product scope](docs/PRODUCT.md). Contributions are provided under the project's [MIT license](LICENSE).

## Report a problem

Use a bug report with platform/OS, app version, server release/native API version, reproducible steps, expected/actual behavior and whether it happens in demo. Identify simulator versus physical hardware and streaming versus downloaded audio. Include only sanitized screenshots/log excerpts. Security-sensitive reports belong in the private process in [SECURITY.md](SECURITY.md).

For larger features, open a proposal before substantial implementation. Native behavior, dependable playback, clear recovery and minimal infrastructure are the priorities. Describe the user problem and how it can be verified, especially for background/Watch behavior.

## Make a change

1. Create a focused branch and follow the source build instructions.
2. Keep generated Xcode changes reproducible from `project.yml`; regenerate when changing targets, file membership or build settings.
3. Add meaningful tests for state transitions/contracts being changed. Run Core and script tests, then relevant app/platform checks. Do not use live accounts in automated CI.
4. Update usage docs/changelog with behavior and known limits. State skipped or unavailable hardware checks honestly.
5. Submit a focused pull request describing the problem, resulting behavior and verification. Use conventional commit prefixes such as `feat:`, `fix:`, `docs:` or `chore:`.

## Invariants to preserve

- Never commit credentials, keys, cookies, live fixtures, private endpoints, signed stream URLs or personal screenshots. Do not attach raw `.xcresult` bundles without reviewing contents.
- Catalog metadata/previews are not full playable library audio. Surface acquisition failures and account permissions.
- Fence asynchronous work by account/generation. An old callback must not play audio, write files or change a new account's state.
- Persist preparation before a server mutation. Unconfirmed mutations must be checked rather than blindly submitted again.
- Relaunch restores paused playback and asks before applying old playback intentions.
- Watch readiness means a validated saved file and receipt, not merely queued delivery. Preserve migration, deletion tombstones and shared-file references.
- Private Mac transport stays bound to Tailscale; no public listener or wildcard fallback. Credentials never travel in Bonjour or Watch messages.
- Preserve existing user storage identifiers unless a migration is provided. Forks need separate identifiers before distribution.

No paid API, telemetry service, acquisition backend or infrastructure dependency should be added casually. Explain why a dependency is necessary and its privacy/license implications.

## Collaboration

Follow the [code of conduct](CODE_OF_CONDUCT.md). Be respectful and specific. Critique code and behavior rather than people. Harassment, personal attacks and posting private information are unacceptable; maintainers may moderate or close such contributions. There is no guaranteed support response time.
