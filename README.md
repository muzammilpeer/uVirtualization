# uVirtualization

A native Swift VM manager for Apple silicon Macs, with a command-line tool (`uvm`) and a SwiftUI application. Uses Apple's Virtualization framework directly.

**Development build.** macOS installation and EFI runtime controls have passed hardware checks on the development host. Full Tart parity and the remaining guest acceptance tests are still open; see [acceptance](docs/ACCEPTANCE.md) and [compatibility audit](docs/PARITY.md).

## Build

Requires an Apple silicon Mac, macOS 13+, Xcode and Swift 5.9+.

```sh
./scripts/check.sh
python3 scripts/cli-smoke.py
./scripts/sign.sh
.build/debug/uvm doctor
./scripts/package-dev.sh
open .build/uVirtualization.app
```

The CLI must be signed with the virtualization entitlement. `swift run` can rebuild it without that entitlement; use the signed executable for guest operations. Build scripts place compiler caches inside the workspace.

## Install and run macOS

```sh
.build/debug/uvm create my-mac --from-ipsw latest --disk 64
.build/debug/uvm run my-mac
```

Or supply a local `.ipsw` file. `latest` downloads Apple's compatible restore image. The guest opens Setup Assistant after installation; uvm does not create a guest user or enable SSH.

## Clone a registry VM

```sh
.build/debug/uvm clone ghcr.io/cirruslabs/macos-tahoe-base:latest tahoe-base
.build/debug/uvm run tahoe-base
```

The adapter supports ARM64 Tart v1 configurations with raw disks in v2 LZ4 layers, and native uvm image layers. Compatibility testing of the pinned Tahoe image is tracked in the acceptance record. Ordinary container images are rejected. Use `--discard-blobs` on remote clone to reduce cache space.

## Linux

```sh
.build/debug/uvm create linux-dev --linux --disk 40
.build/debug/uvm run linux-dev --disk /absolute/path/to/arm64-installer.iso
# After installing and shutting down, omit the ISO:
.build/debug/uvm run linux-dev
```

Optional Linux flags: `--serial`, `--rosetta`. Rosetta must first be installed with `uvm install-rosetta` and configured inside the guest.

## Manage VMs

```sh
uvm list
uvm inspect my-mac
uvm set my-mac --cpu 4 --memory 8192 --disk 80
uvm clone my-mac my-mac-copy
uvm run my-mac --headless --dir source=/absolute/path:ro
uvm status my-mac
uvm pause my-mac
uvm resume my-mac
uvm stop my-mac
```

These examples assume the signed CLI is on your PATH. `stop` requests guest shutdown; `stop NAME --force` immediately stops it. Wait for `status` to report stopped before changing resources. `suspend` uses Apple's saved-state support on compatible macOS 14+ configurations; `run` restores the saved state. Cloning/configuring/deleting a suspended guest is refused.

Memory uses MiB; disk capacity uses GiB. Growing the virtual disk does not automatically expand the guest filesystem. Extra `run --disk` attachments are read-only. Audio, clipboard and writable shared folders are opt-in. Clipboard requires guest agent support. Bridging requires an additional Apple entitlement.

## Registry and archives

```sh
printf '%s' "$REGISTRY_TOKEN" | uvm login ghcr.io --username USER --password-stdin
uvm push my-mac ghcr.io/OWNER/IMAGE:TAG
uvm export my-mac backup.uvma
uvm import backup.uvma restored-mac
uvm prune --all
```

Push writes uvm's native OCI format. `.uvma` is a checksum-protected uvm archive, not Tart's export format. Exports stream disk contents and may require space equal to the disk's logical size. Registry credentials are stored in Keychain. Never log tokens.

Data lives in `~/.uvm`; `UVM_HOME` selects a different inventory. The app also offers **File → Choose VM Storage**. Failed macOS installations retain their files under `.staging` with `failure.txt`. `init NAME` creates only a configuration draft, not a bootable VM.

## GitLab Runner

The development bundle includes `gitlab-uvm-executor`. It creates an isolated VM for each job and checks authenticated guest HTTPS connectivity before checkout. See the [setup guide](docs/GITLAB_RUNNER.md) and [runner examples](examples/gitlab/config.toml). Live GitLab acceptance is pending runner and guest provisioning.

## Plan and validation

- [Requirements](docs/REQUIREMENTS.md)
- [Sprint progress and commits](docs/SPRINTS.md)
- [Compatibility audit](docs/PARITY.md)
- [Hardware acceptance](docs/ACCEPTANCE.md)
- [Automation contract](docs/AUTOMATION.md)
- [Control API and future extensions](docs/CONTROL_API.md)
- [Development packaging and final release](docs/RELEASE.md)

`UVCore` owns storage, installation, runtime and registry services. `uvm` and `UVApp` share that implementation. No Tart source code is included. Release signing, notarization and publication are deferred until final release details are supplied.
