# Sprint roadmap

Work sequentially. Each sprint ends with build/test evidence and an honest status update. Sprint duration is a planning unit, not a delivery promise.

| Sprint | Deliverable | Exit criteria | Status |
|---|---|---|---|
| 01 | Swift package, shared models, local config store, CLI, diagnostics | Build and persistence/validation tests pass; CLI smoke test | Complete |
| 02 | macOS IPSW installation | Signed installer creates boot artifacts; failures/cancellation recover safely | Installation verified; failure/cancel acceptance pending |
| 03 | Runtime and VM window | Boot, interact, graceful/force stop, ownership lock and status verified on hardware | Implemented; guest acceptance pending |
| 04 | Local operations | Offline configure/clone/rename/delete, sparse disk growth, archive safety | Implemented; guest acceptance pending |
| 05 | Network and devices | NAT/IP, directory sharing, display/audio, bridged capability checks | Implemented; guest acceptance pending |
| 06 | OCI pull and compatibility | Verify digest, stream layers, clone and boot a pinned Tart image | Implemented; registry boot acceptance pending |
| 07 | OCI publishing and cache | Keychain auth, push, retries, cancellation, prune under concurrent use | Implemented; private registry acceptance pending |
| 08 | ARM Linux | ISO install, EFI persistence, serial console, guest-specific devices | Implemented; distribution install acceptance pending |
| 09 | Native app | Shared library, wizard, settings, VM windows, lifecycle errors | Implemented; UI acceptance partially verified |
| 10 | Automation and parity audit | Version-pinned Tart command matrix, JSON/completions, CI examples; close gaps | Automation implemented; parity gaps documented |
| 11 | Release engineering | M1 hardware suite, signed/notarized artifacts, Homebrew recipe and upgrade tests | Development packaging complete; release gates deferred/open |
| 12 | Extension foundation | Token-protected local control API and future orchestration specification | Implemented; local API smoke passed |
| Future | Multi-host orchestration | Enrollment, scheduling, pools, isolation and recovery | Separate product backlog |

## Sprint 01 scope

Implement `uvm doctor`, `uvm init NAME`, `uvm list`, `uvm inspect NAME`, and `uvm version`. `init` explicitly creates a configuration draft, not a disk or installed VM. Configuration defaults: 4 CPUs, 4096 MiB RAM, 64 GiB disk, 1920×1200 display. Keep initial code free of remote package dependencies. Add virtualization entitlements for later runtime signing. Do not expose unimplemented commands as successful operations.

## Sprint 02 implementation notes

Add `create NAME --from-ipsw PATH|latest`; validate available disk and Apple restore requirements; persist platform identity; allocate sparse disk; install using VZMacOSInstaller on its owning queue. Stage installs separately, expose progress, retain actionable failures and publish only complete bundles. Add signing helper and hardware acceptance instructions. Follow with sprint 03 before presenting a create/run quick start as usable.

## Sprint 01 verification — 2026-09-16

- Swift 6.4 / arm64 host: debug build passed.
- Five XCTest cases passed with zero failures.
- Nine CLI smoke scenarios passed, including diagnostics with unavailable virtualization.
- The current process reports `VZVirtualMachine.isSupported == false`; no VM installation or boot was attempted. Signed runtime and physical M1 guest acceptance remain for sprints 02–03.
- Build required workspace-local compiler caches due to filesystem restrictions. Xcode emitted duplicate private-framework class warnings during the successful test run.
- Next sprint: 02, macOS IPSW installation.

## Sprint 02 implementation — 2026-09-16

Implemented local/latest IPSW installation, platform artifacts, sparse disks, staging/failure records, progress/cancellation, ownership locks and development signing scripts. Eight unit tests pass. Ad-hoc signature verifies. Signed doctor outside the execution sandbox reports virtualization supported; inside the sandbox it reports unavailable. Actual installation acceptance follows runtime implementation. User requested development signing until release credentials are supplied at the final build.

## Sprint 03 implementation — 2026-09-16

Added VZ runtime, native guest window, headless mode, lifecycle commands, session-scoped control requests and runtime ownership. Ten tests pass, including stale-status and stopped-guest control checks. Guest boot/input/shutdown acceptance is pending a restore image installation.

## Sprint 04 implementation — 2026-09-16

Added locked configure/clone/rename/delete, sparse disk expansion and streaming checksum-protected `.uvma` archives with a fixed artifact allowlist. Clone/import renew machine identity. Thirteen tests pass, including archive corruption/traversal and busy-VM rejection. Guest filesystem expansion remains a guest-side operation. Rename rolls back ordinary failures; power-loss recovery needs additional validation before release.

## Sprint 05 implementation — 2026-09-16

Added NAT lease discovery with timeout, read-only-by-default directory shares, optional audio output and clipboard, read-only extra disks and bridged interface checks. Fifteen tests pass. Bridging needs Apple-granted networking entitlements; development signing provides NAT only. Guest device acceptance remains pending installation.

## Sprint 06 implementation — 2026-09-16

Implemented OCI reference validation, anonymous bearer authentication, HTTPS redirects without cross-origin credentials, bounded manifests, disk-backed blob downloads, SHA-256 verification, reusable verified blob cache, Tart v1 config/raw LZ4 v2 disk adapter, native image import, remote clone and manifest inspection. Eighteen tests pass including decompression bounds. Retry resumes at verified blob boundaries; partial-blob byte resumption remains a release gap. Registry guest boot acceptance is pending.

## Sprint 07 implementation — 2026-09-16

Added Keychain login/logout and host-scoped environment credentials, native compressed OCI publishing, chunked upload recovery and locked cache pruning. Nineteen tests pass. Real public Tahoe manifest inspection succeeded at digest `sha256:1b093499716409d29e8b5336844528e1cae375db97d2ad8e5aeff78cf0da201e`. Native pushes use uVirtualization media types; Tart-compatible push encoding is not yet implemented. Private registry publishing needs credentialed acceptance.

## Sprint 08 implementation — 2026-09-16

Added Linux EFI machine creation, virtio graphics/balloon, ISO attachment, serial I/O and optional Rosetta directory sharing with explicit installation command. Nineteen tests pass. Signed hardware smoke test on this arm64 host successfully created a blank EFI VM, started it, paused/resumed it, forced stop and verified stopped status. This verifies runtime control, not a Linux distribution installation.

## Sprint 09 implementation — 2026-09-16

Added native SwiftUI library, creation/import forms, resource editor, clone/delete actions, runtime controls, guest-access options and quit protection. Nineteen tests pass; the development-signed app bundle verifies. Launched the app and visually inspected the library and creation form. macOS latest restore installation completed successfully on this host with a 32 GiB sparse disk in `.build/acceptance-vms/acceptance-macos`; remaining guest checks follow.

## Sprint 10 implementation — 2026-09-16

Added SSH exec with argument quoting/host verification, get/fqn, completions, JSON error mode, cancellation, saved-state suspend/restore with offline mutation protection, CI/manual smoke scripts and pinned parity audit. Twenty-one unit tests and 26 CLI scenarios pass. Real image testing found a 32 MiB firmware artifact; the adapter limit was corrected and metadata checks moved before disk transfers. See PARITY.md for unresolved compatibility requirements. An existing user-side Sprint 10 commit was preserved; this commit records the additional automation and audit work.

## Sprint 11 development delivery — 2026-09-16

Produced an optimized development-signed application ZIP, SHA-256 checksum and generated Homebrew formula. Signature verification and formula syntax pass; 21 unit tests and 26 CLI scenarios pass. Added release/notarization tooling, acceptance matrix and current usage documentation. Final Developer ID/notarization/publication are deferred by explicit user direction. M1/newer-host matrix and remaining guest acceptance remain release gates.

## Sprint 12 extension foundation — 2026-09-16

Implemented a token-protected loopback HTTP API for inventory, host diagnostics and lifecycle control. Token permissions, authentication, request framing, connection bounds and shutdown behavior are documented. Twenty-four unit tests pass. Live loopback smoke verifies authenticated inventory and rejection of invalid tokens. The original open-ended 12+ backlog is now separated into this deliverable and a future multi-host product specification; orchestration/pools are not claimed complete.
