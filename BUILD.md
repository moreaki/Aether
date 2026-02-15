# Build and Release (Signed + Notarized DMG)

This project includes `scripts/build_dmg.sh` to produce a distributable macOS DMG:

- Output: `dist/Aether.dmg`
- Includes a universal binary (`arm64` + `x86_64`)
- Signs the `.app` and `.dmg`
- Notarizes and staples both (unless `--skip-notarization`)

## What "can run on any computer" means on macOS

For normal Gatekeeper-friendly distribution to other Macs, you need:

1. A `Developer ID Application` signing certificate
2. Apple notarization
3. Stapled notarization ticket

Without notarization/signing, users can still sometimes run the app by bypassing security prompts, but it is not a clean "works anywhere" install experience.

## What notarization is

Notarization is Apple scanning your signed app/archive for malicious content. If accepted, Apple issues a ticket. When you staple that ticket to your app/DMG, macOS can validate it offline and Gatekeeper is much less likely to block first launch.

## Prerequisites

1. macOS with Xcode Command Line Tools
2. Apple Developer Program membership (paid)
3. Installed `Developer ID Application` certificate in your keychain
4. `xcrun notarytool` credentials stored in keychain (profile name)

## Apple ID, Team ID, and certificate details

### Apple ID: can this be any email?

No. It must be the Apple Account that has access to your Apple Developer team. In practice:

- It can be any email address format only if that email is the sign-in for an Apple Account in the developer team
- For Apple ID auth with notarytool, you also need an app-specific password
- If you are in multiple teams with the same Apple ID, `--team-id` selects which team notarytool uses

### Team ID: what is it?

`TEAMID` is your Apple Developer Team identifier (usually 10 uppercase alphanumeric characters), for example `ABCDE12345`.

Use the team that owns the `Developer ID Application` certificate used to sign the app. If team/certificate/auth do not match, notarization will fail.

You can find Team ID in:

- App Store Connect -> Users and Access -> Membership
- developer.apple.com -> Account -> Membership

If you are in multiple teams, use the team that issued the `Developer ID Application` certificate you pass in `APP_SIGN_IDENTITY`.

### Signing identity used by this script

Set `APP_SIGN_IDENTITY` to your certificate common name, for example:

```bash
APP_SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)"
```

You can inspect available code-sign identities with:

```bash
security find-identity -v -p codesigning
```

## Configure notarytool credentials locally

Create or update a local keychain profile (example profile name: `AETHER_NOTARY`):

```bash
xcrun notarytool store-credentials AETHER_NOTARY \
  --apple-id "you@example.com" \
  --team-id "ABCDE12345" \
  --password "<app-specific-password>" \
  --validate
```

Notes:

- `--password` is an Apple app-specific password, not your Apple Account login password
- If you omit `--password`, `notarytool` prompts securely in terminal
- Running `store-credentials` again with the same profile name updates/replaces the saved credentials

## How to update stored credentials later

Common cases:

1. Password rotated/revoked: rerun `store-credentials` with the same profile name
2. Switched Apple ID or Team: rerun with new values under same or new profile name
3. Multiple environments: use separate profile names (for example `AETHER_NOTARY_DEV`, `AETHER_NOTARY_CI`)

A quick validity check is to submit a build; `store-credentials --validate` also performs a credential validation request.

## Build command

From repo root:

```bash
APP_SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" \
NOTARY_PROFILE="AETHER_NOTARY" \
scripts/build_dmg.sh --bundle-id "com.yourcompany.aether" --version "1.2.1"
```

If `--version` is omitted, the script uses the latest git tag (without leading `v`) or falls back to `0.0.0`.

## Useful script options

```bash
scripts/build_dmg.sh --help
```

- `--bundle-id <id>`: CFBundleIdentifier in `Info.plist`
- `--version <semver>`: app short/build version
- `--skip-notarization`: sign only, skip notary submission/stapling

## Resource handling in the DMG build

`scripts/build_dmg.sh` includes resources from both:

- SwiftPM-generated resource bundle(s) (for `Bundle.module`, e.g. `Aether_Aether.bundle`)
- Source resources under `Sources/Aether/Resources` (copied to `Contents/Resources/AetherResources`)

It also generates `Contents/Resources/AppIcon.icns` from:

- `Sources/Aether/Resources/Assets.xcassets/AppIcon.appiconset`

and sets `CFBundleIconFile=AppIcon` in the app `Info.plist` so Finder/Dock can use that icon.

You do not need to move `Sources/Aether/Resources` for this packaging flow.

## Local dry run (no Apple account required)

For packaging flow validation only:

```bash
APP_SIGN_IDENTITY="-" scripts/build_dmg.sh --skip-notarization
```

This uses ad-hoc signing and is not suitable for public distribution.

## Verify output

After build:

```bash
ls -lh dist/Aether.dmg
spctl -a -vvv -t open dist/Aether.dmg
```

You can also mount and inspect:

```bash
hdiutil attach dist/Aether.dmg
```

## CI note

Apple ID + app-specific password works, but App Store Connect API key auth is often preferred for CI (`notarytool store-credentials --key ... --key-id ... --issuer ...`).
