# Acceptance record

Date: 2026-09-17. Host reports arm64, 10 CPUs, 16 GiB RAM, macOS 27.0 build 26A428. Hardware model: Mac16,10. Separate physical M1 coverage has not been completed.

| Check | Evidence/status |
|---|---|
| Swift debug build | Passed |
| Unit tests | 31 passed, zero failures |
| CLI smoke checks | 26 passed |
| Development signing | codesign strict verification passed |
| Virtualization entitlement | Signed doctor outside sandbox reports supported |
| macOS installation | Latest compatible Apple restore installed to 32 GiB disk |
| macOS start/pause/resume | Passed runtime transitions |
| macOS graceful shutdown | Shutdown requests accepted, but installed and imported guests did not stop within the acceptance window; unresolved; force stop verified |
| Linux EFI runtime | Create/start/pause/resume/force stop/status passed |
| Linux distribution | Public Ubuntu OCI import, runtime start, NAT lease, SSH banner and pause/resume verified; fresh ISO installation pending |
| Linux shutdown | Graceful request did not exit within 120 s; test cleanup force-stopped the guest and verified stopped status |
| Native app visual check | Library and creation form inspected |
| Guest display/input | Pending |
| Registry manifest | Public Tahoe manifest resolved to pinned digest |
| Tart image clone/boot | Pinned Tahoe image imports, starts, obtains NAT lease, pauses/resumes and force stops; Ubuntu import also succeeds |
| Registry push/private auth | Pending credentialed registry |
| Shared folders/audio/clipboard | Implemented; guest checks pending |
| Bridging | Requires Apple entitlement; not covered by development signing |
| Suspend/restore | Apple save API returns permission denied on this host; VM resumes after failure; successful restore acceptance blocked |
| Release packaging | Optimized development ZIP, signature, checksum and formula syntax passed |
| Notarization/publication | Deferred by user until final build |

Scripts: `scripts/check.sh`, `scripts/cli-smoke.py`, `scripts/hardware-smoke.py`, `scripts/api-smoke.py` and `scripts/imported-guest-smoke.py --store PATH --name NAME [--graceful]`. Imported-guest checks require an explicitly selected disposable guest and verify runtime state and DHCP lease; they do not assert desktop/input or guest application health. Hardware scripts use isolated `.build` stores. CLI tests use temporary stores and never alter the default inventory.

Disposable locally installed macOS acceptance VM was removed after installation/runtime checks to free disk space. The pinned registry acceptance VM is tested separately. Runtime main-thread event delivery was hardened; EFI lifecycle and authenticated API smoke passed again afterward.

The Tahoe test uses `ghcr.io/cirruslabs/macos-tahoe-base@sha256:1b093499716409d29e8b5336844528e1cae375db97d2ad8e5aeff78cf0da201e`. A real Ubuntu image exposed decimal-GB versus GiB validation: its 20 GB disk occupies 19 GiB rounded up. Guest-specific validation and a Tart configuration/firmware regression test now cover this case. Signed CLI creation with 1024 MiB RAM and an 8 GiB Linux disk also passes.

Ubuntu responded on port 22 with an OpenSSH 9.6p1 Ubuntu banner. No guest login credentials were supplied or attempted. The graceful smoke intentionally reports failure for its shutdown timeout; its successful earlier checks are recorded individually above. Both acceptance guests are stopped after testing.

The native library and creation form were inspected earlier. Further guest-window inspection on 2026-09-17 was blocked by the desktop-control connection closing before a response. No guest display/input pass is claimed. Production signing and notarization remain deferred as requested.
