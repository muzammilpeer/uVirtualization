# Sprint roadmap

Work sequentially. Each sprint ends with build/test evidence and an honest status update. Sprint duration is a planning unit, not a delivery promise.

| Sprint | Deliverable | Exit criteria | Status |
|---|---|---|---|
| 01 | Swift package, shared models, local config store, CLI, diagnostics | Build and persistence/validation tests pass; CLI smoke test | Complete |
| 02 | macOS IPSW installation | Signed installer creates boot artifacts; failures/cancellation recover safely | Implemented; guest acceptance pending |
| 03 | Runtime and VM window | Boot, interact, graceful/force stop, ownership lock and status verified on hardware | Implemented; guest acceptance pending |
| 04 | Local operations | Offline configure/clone/rename/delete, sparse disk growth, archive safety | Planned |
| 05 | Network and devices | NAT/IP, directory sharing, display/audio, bridged capability checks | Planned |
| 06 | OCI pull and compatibility | Verify digest, stream layers, clone and boot a pinned Tart image | Planned |
| 07 | OCI publishing and cache | Keychain auth, push, retries, cancellation, prune under concurrent use | Planned |
| 08 | ARM Linux | ISO install, EFI persistence, serial console, guest-specific devices | Planned |
| 09 | Native app | Shared library, wizard, settings, VM windows, lifecycle errors | Planned |
| 10 | Automation and parity audit | Version-pinned Tart command matrix, JSON/completions, CI examples; close gaps | Planned |
| 11 | Release engineering | M1 hardware suite, signed/notarized artifacts, Homebrew recipe and upgrade tests | Planned |
| 12+ | Extensions | Remote control, pools and multi-host orchestration separately specified | Backlog |

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
