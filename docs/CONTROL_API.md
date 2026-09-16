# Control API and extension boundary

The first extension is a token-protected, single-host HTTP API. It binds **127.0.0.1 only**. For remote use, forward the port through an authenticated SSH tunnel. It is not a public Internet service or a multi-host scheduler.

```sh
mkdir -p "$HOME/.config/uvm"
umask 077
openssl rand -hex 32 > "$HOME/.config/uvm/control-token"
uvm serve --token-file "$HOME/.config/uvm/control-token" --port 9022
```

The token must be owned by the current user, private to that user (0600), and 32–256 non-whitespace characters. Tokens are never logged. Requests require `Authorization: Bearer TOKEN`. Keep the token out of URLs and access logs.

| Method | Path | Result |
|---|---|---|
| GET | /v1/host | Host capabilities |
| GET | /v1/vms | VM configurations |
| GET | /v1/vms/NAME/status | Runtime state |
| POST | /v1/vms/NAME/start | Start an existing installed VM headlessly |
| POST | /v1/vms/NAME/stop | Request guest shutdown |
| POST | /v1/vms/NAME/force-stop | Force stop |
| POST | /v1/vms/NAME/pause | Pause |
| POST | /v1/vms/NAME/resume | Resume |
| POST | /v1/vms/NAME/suspend | Save state on supported configurations |

POST requests have no body. Responses are JSON. A successful start response means the operation was accepted: poll status to observe runtime progress. Errors return 400, unauthorized requests 401. The implementation limits header size, idle connection time and concurrent connections, rejects ambiguous framing and strips no authentication checks for local callers.

On Ctrl+C, the server requests shutdown of its owned VMs and waits for them. If a guest will not shut down, send `force-stop` through the API or CLI. Do not terminate the process forcibly unless disk-write loss is acceptable.

## Future multi-host work

The original sprint 12+ was an open-ended backlog. This sprint delivers the control boundary; it does not pretend to deliver an Orchard replacement. A production orchestration project needs a separate specification and acceptance suite for:

1. Host enrollment, mutual TLS, credential rotation and roles.
2. Durable jobs, host heartbeats and lease fencing to prevent duplicate writers.
3. CPU/RAM/disk scheduling, quotas and fairness.
4. Warm VM pools with immutable image digests and reset policies.
5. Guest-secret injection, audit retention and tenant separation.
6. Failure recovery across controller/worker restarts and network partitions.

Keep orchestration outside `UVCore`. The CLI/app/API should continue using the same configuration, storage and runtime services. Add backend implementations behind shared capability/lifecycle interfaces when another virtualization backend is actually introduced, rather than duplicating state management.

## Verification

`python3 scripts/api-smoke.py` starts a temporary loopback server, verifies authenticated inventory access and unauthorized rejection, then shuts it down. API parser/token tests run in `scripts/check.sh`.
