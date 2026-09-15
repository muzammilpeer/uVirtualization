# uVirtualization

A Swift-based VM manager for Apple silicon Macs, starting with M1. The planned CLI and native app share Apple's Virtualization framework through `UVCore`.

**Current milestone: Sprint 01 foundation.** You can inspect host capabilities and manage persistent configuration drafts. macOS installation, guest execution, Tart registry compatibility and the native app are planned, not implemented yet.

## Build and try

Requires an Apple silicon Mac, macOS 13 or newer, and Xcode/Swift 5.9 or newer.

```sh
swift build
swift test
swift run uvm doctor
swift run uvm init tahoe-base --cpu 4 --memory 4096 --disk 64
swift run uvm list
swift run uvm inspect tahoe-base
```

`init` writes a draft only; it does not allocate a disk or install macOS. Memory is in MiB; disk capacity is in GiB. Defaults are 4 CPUs, 4096 MiB RAM and 64 GiB disk. Hardware-specific resource limits will also be checked when installation/runtime is implemented.

Data lives in `~/.uvm`. Set `UVM_HOME` to use a different directory. Inventory and configuration output is JSON. Errors go to stderr with exit code 1; success uses 0. An existing name is never overwritten. Do not manually edit storage while a command is running.

For environments that restrict user cache access:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox --cache-path .build/cache
```

## Design and work plan

- [Requirements](docs/REQUIREMENTS.md): product scope, acceptance criteria and references.
- [Sprint roadmap](docs/SPRINTS.md): ordered implementation and delivery status.
- `Sources/UVCore`: versioned configuration, store and host capability checks.
- `Sources/uvm`: command-line interface.
- `Resources/uvm.entitlements`: virtualization entitlement for the future signed runtime. The current build does not perform runtime signing.

The app will use SwiftUI/AppKit and `VZVirtualMachineView`. OCI images will require an explicit Tart image-format adapter; ordinary container images cannot be booted as VMs. No Tart source code is included.
