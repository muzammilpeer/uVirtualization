# Automation contract

Commands do not prompt for input except explicit `login --password-stdin`. `init` is a configuration draft; `create` provisions a guest. Names and resource values are validated before writes. `UVM_HOME` isolates test/CI inventories.

- Exit 0: successful operation or accepted runtime request.
- Exit 1: validation, host, network or operation failure.
- Exit 130: task cancellation.
- `exec` preserves the system SSH/remote command exit status.
- `stop` acknowledges shutdown request; poll `status` until `stopped` to wait for completion.
- Inventory/config/status/manifest results are JSON. Progress and diagnostics go to stderr.
- Set `UVM_JSON_ERRORS=1` for an `{ "error": "..." }` error line. Host system logs may still appear for windowed AppKit execution; use headless for automation.
- Registry credentials: Keychain, or all three of `UVM_REGISTRY_HOST`, `UVM_REGISTRY_USERNAME`, `UVM_REGISTRY_PASSWORD`. The host must match exactly. Avoid printing these environment values in CI.
- Generate completions with `uvm completions bash`, `uvm completions zsh` or `uvm completions fish`.
- `clone REMOTE LOCAL --discard-blobs` reduces cache disk usage; it discards compressed source blobs after each layer is imported. The assembled image remains cached.

## CI execution

Use a dedicated Apple silicon host with the virtualization entitlement on the signed CLI. Never run untrusted workflows on a privileged shared runner. The supplied workflow is manually dispatched and targets a self-hosted ARM64 macOS runner; configure that runner yourself. It performs build/unit/CLI checks, not multi-gigabyte guest downloads.

```sh
export UVM_HOME="$PWD/.ci-vms"
uvm clone registry.example/team/image@sha256:REPLACE_WITH_DIGEST ci-vm
uvm run ci-vm --headless &
uvm ip ci-vm --timeout 120
uvm exec ci-vm --user builder -- /bin/sh -lc 'cd project && ./test.sh'
uvm stop ci-vm
# Poll status and wait for stopped before deleting.
```

Use registry digests for reproducibility. Provision SSH keys/known_hosts separately; uvm does not disable verification or create a guest account.
