# Acceptance record

Date: 2026-09-16. Host reports arm64, 10 CPUs, 16 GiB RAM, macOS 27.0 build 26A428. Exact hardware model to be recorded before release; no claim that separate M1 and newer-host coverage has been completed.

| Check | Evidence/status |
|---|---|
| Swift debug build | Passed |
| Unit tests | 21 passed at Sprint 10 |
| CLI smoke checks | 26 passed |
| Development signing | codesign strict verification passed |
| Virtualization entitlement | Signed doctor outside sandbox reports supported |
| macOS installation | Latest compatible Apple restore installed to 32 GiB disk |
| macOS start/pause/resume | Passed runtime transitions |
| macOS graceful shutdown | Shutdown requests accepted, but guest did not stop in 30 s or in the later 120 s window; unresolved |
| Linux EFI runtime | Create/start/pause/resume/force stop/status passed |
| Linux distribution install | Pending |
| Native app visual check | Library and creation form inspected |
| Guest display/input | Pending |
| Registry manifest | Public Tahoe manifest resolved to pinned digest |
| Tart image clone/boot | First clone found firmware limit bug; corrected; retest pending |
| Registry push/private auth | Pending credentialed registry |
| Shared folders/audio/clipboard | Implemented; guest checks pending |
| Bridging | Requires Apple entitlement; not covered by development signing |
| Suspend/restore | Implemented; hardware acceptance pending |
| Release packaging | Optimized development ZIP, signature, checksum and formula syntax passed |
| Notarization/publication | Deferred by user until final build |

Scripts: `scripts/check.sh`, `scripts/cli-smoke.py`, `scripts/hardware-smoke.py` and `scripts/hardware-smoke.py --macos`. Hardware scripts use isolated `.build` stores. CLI tests use temporary stores and never alter the default inventory.
