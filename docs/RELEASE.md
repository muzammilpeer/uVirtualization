# Development build and release process

The current user-selected mode is development signing. Developer ID, notarization profile and final Homebrew repository will be supplied later. No public release or notarization has been performed.

## Local application

```sh
./scripts/check.sh
python3 scripts/cli-smoke.py
./scripts/package-dev.sh
open .build/uVirtualization.app
```

The bundle contains both the native application and `Contents/MacOS/uvm`. Development signing uses an ad-hoc identity by default and includes `com.apple.security.virtualization`. It does not grant privileged bridging or make an Internet-downloaded build trusted by Gatekeeper.

## Optimized artifact

```sh
./scripts/package-release.sh --development
python3 scripts/homebrew-formula.py
```

Outputs are a signed `.app`, ZIP, SHA-256 checksum and local Homebrew formula under `dist/`. The default generated formula points to this machine's built ZIP. To create a distributable formula after uploading an approved release, pass `--url https://YOUR_APPROVED_RELEASE_URL`. Review the homepage and package identifiers before publication.

## Final signed/notarized build (later)

Provide a Developer ID Application signing identity, stored notarytool Keychain profile, final bundle identifier, repository URL and Homebrew tap. Then use:

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
NOTARY_PROFILE='YOUR_STORED_PROFILE' \
./scripts/package-release.sh --notarize
```

This command submits the artifact to Apple. Run it only for the final build after the release details are supplied. Never put passwords/API keys in source or command arguments.

## Release gate

Complete the outstanding rows in ACCEPTANCE.md and PARITY.md. Verify the oldest supported macOS host and a physical M1 in addition to a newer Apple silicon host. Confirm archive migrations, interrupted operations, private registry round trips, guest sharing, display/input and shutdown. A development artifact does not imply production readiness or complete Tart compatibility.
