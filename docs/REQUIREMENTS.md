# uVirtualization requirements

## Product and scope

Build an independent Swift VM manager for Apple silicon, starting with M1. Provide a scriptable `uvm` CLI and a native macOS app using the same core. Long-term target: Tart-style local virtualization and image workflows, with extension points for more guests, storage, and orchestration. This is a new implementation, not a wrapper around Tart. Functional parity is a release target, not a claim about the initial implementation.

## Platform decisions

- Initial deployment target: macOS 13+, arm64. Newer features require runtime availability checks.
- Use Apple's Virtualization framework directly in Swift; use SwiftUI/AppKit for the app and VZVirtualMachineView for guest interaction.
- Validate each restore image against the host using Apple's supported configuration requirements. An M1 host does not imply every guest version is supported.
- CLI and app share versioned configuration, storage, validation, and lifecycle services.
- Default storage: ~/.uvm; UVM_HOME overrides it. Resource units are MiB and GiB.

## Functional requirements and acceptance

| ID | Requirement | Acceptance |
|---|---|---|
| F01 | Host diagnostics | Report architecture, OS, CPU, RAM, virtualization availability; unsupported hosts get actionable errors. |
| F02 | VM configuration | Versioned JSON; safe names; CPU, RAM, disk, guest and display settings; reject invalid values and unknown versions. |
| F03 | Local inventory | List, inspect, configure, rename, clone and delete; prevent collisions, traversal and writes to active VMs. |
| F04 | macOS creation | Local IPSW or latest compatible Apple image; progress/cancellation; sparse disk, hardware model, unique machine ID and auxiliary storage; failed installs remain recoverable. |
| F05 | Runtime | Windowed/headless execution, graceful shutdown, explicit force stop, pause/resume, state reporting and cross-process ownership. |
| F06 | Persistence | Preserve boot artifacts; prevent simultaneous disk writers; transactional operations, crash cleanup, version migrations. |
| F07 | Resources/devices | CPU/RAM/display configuration, disk expansion, extra disks, keyboard, pointer, graphics, audio and opt-in clipboard where supported. |
| F08 | Networking | NAT default; stable unique MAC, IP discovery with timeout; bridged networking when available and appropriately entitled; SSH assistance without weakening host verification. |
| F09 | Sharing | Named host directories with read-only/read-write choice, validated paths and guest support detection. |
| F10 | OCI images | Pull/push/remote clone, tags and immutable digests, registry auth via Keychain, digest verification, streamed/resumable transfer, cache/prune and cancellation. |
| F11 | Tart image compatibility | Explicit adapter for supported Tart media/config formats; test ghcr.io/cirruslabs/macos-tahoe-base:latest by resolved digest; incompatible images fail clearly. Container images are not VM images. |
| F12 | Local clone/export | Efficient APFS copy when available, safe fallback, new identities, portable archive import/export and malicious archive rejection. |
| F13 | Linux | ARM64 EFI/ISO install and boot; serial console and optional Rosetta where supported. |
| F14 | Native app | Library, creation/import wizard, configuration editor, progress, VM windows and lifecycle controls; shared ownership with CLI. |
| F15 | Automation | Stable exit codes, JSON output, noninteractive mode, timeouts, structured logs, shell completion and CI examples. |
| F16 | Distribution | Signed app/CLI, notarized releases, reproducible packaging, Homebrew tap, upgrades and migration guidance. |
| F17 | Future extension | Backend/guest/image-store boundaries; remote API, VM pools, CI runners and multi-host scheduling as separate post-parity work. |

## Reliability and safety

Never overwrite an existing VM implicitly. Keep credentials out of config/logs. Do not expose host folders, bridged networking or guest services by default. Require explicit destructive actions. Enforce one owner per running VM and serialize metadata mutations. Use atomic metadata writes and stage incomplete downloads/installations. Report errors to stderr with nonzero exit status. Do not treat merely creating metadata as creating a bootable VM.

## Test and release gates

Unit tests cover configuration boundaries, schema handling, name/path safety, collisions and persistence. Integration tests cover locks, interrupted installs/transfers and corrupt artifacts. Hardware acceptance must install and boot macOS on a physical M1, exercise input/display/network/sharing, stop and reboot, clone without identity collision and boot a registry image. Also test a newer Apple silicon host. Record OS, hardware, image digest and results. No parity claim until each requirement has evidence. No promised performance numbers until measured.

## Assumptions and deferred decisions

Use uVirtualization/uvm as working names. No cloud service or subscriptions in initial releases. Project license, release signing identity, Homebrew organization and distribution image permissions are decisions before publication. Orchard-like orchestration and hosted Cirrus services are separate products, tracked after local parity. Exact Tart flags and obscure device options need a version-pinned command audit before parity sign-off.

## References (reviewed 2026-09-16)

- https://developer.apple.com/documentation/virtualization
- https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon
- https://developer.apple.com/documentation/virtualization/installing-macos-on-a-virtual-machine
- https://tart.run/quick-start/
- https://tart.run/ (OCI and orchestration scope)

Apple documents the platform artifacts and entitlement needed for macOS guests. Tart's quick start establishes the create/clone/run, configuration, sharing and registry workflows used as the interoperability baseline. Implementation details will be checked against the installed SDK and protocol specifications during each sprint.
