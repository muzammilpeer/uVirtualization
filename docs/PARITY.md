# Compatibility audit

Baseline: Tart source commit `acaf3ca7ef57bcd33e405d84409424bc0c1bef86`, inspected 2026-09-16. Source: https://github.com/cirruslabs/tart/tree/acaf3ca7ef57bcd33e405d84409424bc0c1bef86/Sources/tart

This is a workflow-level audit, not a claim of flag-for-flag compatibility. uvm is an independent implementation using public Apple APIs. It does not require Tart.

| Workflow | uvm support | Difference / remaining acceptance |
|---|---|---|
| create macOS | local IPSW or latest supported restore | Installation passed on the development host; interrupted-install hardware acceptance pending |
| create Linux | ARM64 EFI and ISO | EFI runtime passed; distribution installation pending |
| clone | local and OCI | New hardware/network identities; real Tart image acceptance in progress |
| run | native guest window or headless | Default NAT; optional audio, clipboard, folders, ISO disks, serial and Rosetta |
| set/get/list | configure/inspect (get alias)/list | JSON inventory; resource units MiB/GiB |
| stop | graceful request and --force | Graceful shutdown depends on guest readiness; request acceptance is not shutdown completion |
| suspend | Apple saved-state APIs on macOS 14+ | Default device set only; host compatibility checked by Apple; guest acceptance pending |
| pause/resume | live runtime control | Additional uvm commands |
| login/logout | Keychain and scoped environment credentials | Bearer-token registry flow; Docker credential helper and direct Basic challenge support pending |
| pull/push | verified OCI blobs, native compressed image publishing | Pull reads Tart raw-disk v2 LZ4 images; push currently writes uvm media types |
| import/export | checked streaming .uvma archive | uvm archive format; not Tart archive interchange |
| prune | explicit --all registry cache | Cache lock excludes concurrent pull/clone; selective age/size policies pending |
| rename/delete | offline operations | Active and suspended guests protected |
| ip | NAT DHCP lease lookup | Bridged IP discovery requires external DHCP/guest tooling |
| exec | system SSH with argument quoting | Explicit --user; requires guest SSH and existing host trust; not Tart's guest-agent transport |
| fqn | resolves tag to immutable digest | Emits registry/repository@sha256:digest |
| completion/automation | bash/zsh/fish, JSON errors, smoke scripts | Noninteractive CLI; no credential logging |

## Device and integration gaps before a parity release

- Privileged bridging requires Apple's additional entitlement and validation on an entitled build.
- Writable extra disks, raw block/NBD storage, USB passthrough, recovery boot, VNC integration and every upstream option are not all implemented.
- Clipboard requires compatible guest agent support; adding a virtual port alone does not install guest software.
- Restarted downloads reuse verified blobs; partial-blob byte resume is not yet implemented.
- Native OCI push round trip against a credentialed registry remains unverified.
- Crash recovery for interrupted rename and OS/firmware upgrades needs release testing.
- Hosted CI runners and Orchard-style multi-host orchestration are separate extensions, not local Tart CLI parity.

## Hardware evidence

See `SPRINTS.md` and `ACCEPTANCE.md`. A successful build is not guest acceptance. The project remains a development build while these gaps are open.
