# Releasing Cadence

Releasing is a maintainer operation. A successful local build is not a public beta, processed TestFlight build or notarized Mac download.

## Prepare

1. Review [QA](QA.md), [privacy](PRIVACY.md) and [public-release readiness](OPEN-SOURCE-READINESS.md).
2. Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; regenerate with `xcodegen generate`. Keep phone, embedded Watch and Mac versions consistent unless intentionally releasing separately.
3. Run package, script, app and platform checks relevant to the change. Record optional skips and unresolved physical-device acceptance.
4. For a fork, configure unique bundle IDs, companion IDs and your own Apple team; see [building](BUILDING.md).

## Private Apple configuration

The helpers read `~/.config/cadence/apple.json`, an explicit `--config` path, or `CADENCE_ASC_CONFIG`. Copy the **placeholder** [example](../examples/apple-upload.example.json) outside the checkout and replace values privately. Keep the `.p8` key outside the repository and restrict its/configuration permissions, for example `chmod 600` on those private files.

Required fields are `keyPath`, `keyId`, `issuerId` and `teamId`. The key path supports `~`; use Apple's `AuthKey_KEYID.p8` naming for altool. The API key must have appropriate App Store Connect permissions. No shared signing team, key, certificate or provisioning profile is provided.

Older local setups must pass their existing private config explicitly or set `CADENCE_ASC_CONFIG`, and add their own `teamId` field. The helper no longer searches an unrelated application's configuration or falls back to the original maintainer's team. Do not copy private configuration into this checkout.

## iPhone and embedded Watch

Archive and export without uploading:

```sh
python3 Scripts/release.py --config /absolute/path/to/private/apple.json \
  --build-dir .build/release
```

This uses your team for archive/export, permits Xcode provisioning updates and creates `.build/release/export/Cadence.ipa`. It can contact Apple for signing even without uploading. Inspect both phone/Watch `Info.plist` versions, supported platforms and background modes before distribution.

To archive, export **and upload** intentionally:

```sh
python3 Scripts/release.py --config /absolute/path/to/private/apple.json \
  --build-dir .build/release --upload
```

Uploading does not prove availability. Verify processing is VALID, compliance is complete, and the intended testing group has the build. Tester invitations, public links, external review and notifications are separate distribution choices. Do not enable them implicitly.

`Scripts/asc.py` is a small optional App Store Connect JSON helper. Its bearer token is passed to curl through stdin; GETs have bounded retries, mutations do not automatically retry. Use `--help`, and review any non-GET operation before running it. Never publish API output containing personal tester data or credentials.

## Mac

Build an archive with your team and signing identity, optionally including both architectures:

```sh
xcodebuild -project Cadence.xcodeproj -scheme CadenceMac \
  -destination 'generic/platform=macOS' -archivePath .build/CadenceMac.xcarchive \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive
```

An Apple Development signature is for development; it is not general public distribution. For a public download, use your own Developer ID signing, hardened runtime and Apple notarization/stapling workflow. The 0.7.1 Mac release completed this workflow; its [verification record](releases/0.7.1-mac.json) records the accepted submission, final checksum and Gatekeeper result. Do not advise users to disable Gatekeeper globally.

Before attaching a binary, verify its signature, architectures, version and privacy: no private server defaults, signed URLs, live fixtures or embedded configuration. Package with `ditto -c -k --keepParent`, calculate `shasum -a 256`, and publish a checksum alongside sanitized release notes.

### Sign, notarize and staple

Sign a separate distribution copy using your own Developer ID Application identity, `--options runtime`, a secure timestamp and the source entitlements. Confirm `com.apple.security.get-task-allow` is absent; development-signed builds can inject it even in Release. Preserve the sandbox and network entitlements. An isolated build keychain can hold only the release signing identity, without changing the login keychain's settings.

```sh
codesign --force --options runtime --timestamp \
  --sign 'Developer ID Application: YOUR NAME (YOUR_TEAM_ID)' \
  --entitlements Apps/macOS/Cadence.entitlements .build/Distribution/Cadence.app
codesign --verify --deep --strict .build/Distribution/Cadence.app
ditto -c -k --keepParent .build/Distribution/Cadence.app .build/notary-input.zip
xcrun notarytool submit .build/notary-input.zip \
  --key /absolute/private/path/AuthKey_YOUR_KEY_ID.p8 \
  --key-id YOUR_KEY_ID --issuer YOUR_ISSUER_ID --wait
```

Record the returned submission ID. If processing remains In Progress or the wait times out, query/wait on that ID; do not re-upload the same build blindly. Only after **Accepted**:

```sh
xcrun stapler staple .build/Distribution/Cadence.app
xcrun stapler validate .build/Distribution/Cadence.app
spctl --assess --type execute --verbose=4 .build/Distribution/Cadence.app
```

Require Gatekeeper acceptance from Notarized Developer ID. Repackage the stapled app alongside `LICENSE`, `THIRD_PARTY_NOTICES.md` and short install instructions; calculate the final ZIP checksum. After release upload, download it anonymously and repeat checksum/signature/ticket/Gatekeeper checks on the extracted copy. Never distribute signing keys, private configuration or live fixtures.

## Public-source and binary releases

This repository starts from a reviewed source snapshot. Internal development history, private distribution records, live fixtures and old binaries are not included. Keep that boundary when synchronizing changes: use reviewed source exports or individual changes, never merge an internal repository's history into this public one.

A source tag does not imply a public app download. Publish only newly built, sanitized and properly signed binaries after the platform requirements above pass. Keep private TestFlight availability and tester information in private release records. This public repository provides no signing credentials, hosted music server or shared account.
