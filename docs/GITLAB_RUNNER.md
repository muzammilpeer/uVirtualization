# Sprint 13: GitLab Runner and guest network readiness

## Requirements written before implementation

Provide `gitlab-uvm-executor` with GitLab Custom executor `config`, `prepare`, `run` and `cleanup` stages. Each job uses a fresh local clone with a unique MAC address and its own private state directory. Support administrator-selected local or OCI VM images and macOS/Linux guests with SSH, Bash, curl, Git, Git LFS and GitLab Runner installed.

Preparation must wait for a current VM runtime, DHCP address, authenticated SSH and successful HTTPS requests from inside the guest to administrator-configured endpoints. Require consecutive successful rounds. Validate TLS and SSH host identity. A DHCP lease alone is not network readiness. Check again immediately before `get_sources`; do not execute checkout while the readiness gate is failing. Bound attempts and deadlines, distinguish infrastructure failures from job script failures, and never automatically replay arbitrary job scripts.

Keep runner configuration, image selection, host paths, keys and probe destinations under administrator control. Job variables must not select arbitrary host files. Never log scripts, repository credentials, private keys or job tokens. Use GitLab's provided failure codes. Make prepare retries and cleanup idempotent. Stop and remove only the job-owned clone; preserve the base image. Cover cancellation and interrupted preparation with recoverable state.

Internet access cannot be guaranteed during host Wi-Fi/VPN/DNS outages, upstream downtime, invalid certificates or repository authorization failures. The requirement is to detect readiness before checkout, retry transient readiness failures within limits, and report a clear infrastructure failure when connectivity cannot be established. No disabling TLS checks or substituting public DNS behind the user's back.

## Acceptance

- Unit tests: endpoint validation, bounded consecutive-success gate, missing DHCP file, runner identity/config validation, exit mapping and stage isolation.
- Contract tests: prepare/run/cleanup calls, interrupted prepare recovery, checkout gated on readiness, script failure versus transport failure, simultaneous job isolation and no secret logging.
- Hardware: prepared macOS and Linux guests; cold boot with delayed DHCP/DNS; real guest HTTPS readiness; actual GitLab clone/fetch, artifacts/cache, cancellation and repeated concurrent jobs.
- Package the executor with the development app/CLI and add the Homebrew executable link.
- Live GitLab acceptance needs the user's server, prepared image and SSH provisioning. Do not register or publish a runner without its configuration.

References reviewed 2026-09-17: [GitLab Custom executor contract](https://docs.gitlab.com/runner/executors/custom/) and [Cirrus Labs executor workflow](https://github.com/cirruslabs/gitlab-tart-executor). GitLab marks Custom executor as maintenance mode; it remains the requested integration interface. Keep the driver separate from VM runtime for future executor adapters.

## Configure the live runner

1. Build with `scripts/package-release.sh --development`. The bundle includes `uvm` and `gitlab-uvm-executor`; the generated Homebrew formula links both. No tap has been published yet.
2. Register GitLab Runner on this Mac against `https://gitlab.muzammilpeer.uk/`, select the custom executor, and give it tag `uvm`. Keep its token local; do not paste it into chat or commit it.
3. Prepare a stopped `ci-base` VM in the configured store. Enable SSH for a dedicated `builder` account, authorize the runner's public key, and install Bash, Git, Git LFS, curl and GitLab Runner inside the guest. An ordinary base image is not automatically a CI-ready image. macOS builds may also need Xcode command-line tools and accepted developer licenses.
4. Fill in `examples/gitlab/executor.json` with the actual image, SSH user and absolute key paths. Keep it owned by the Runner account and not writable by other users. For remote images, use a pinned OCI digest. The administrator selects the image; a job's `image:` does not override it.
5. Obtain the image's SSH host public key through a trusted provisioning channel and place it in the known-hosts file under alias `uvm-ci-base`. Keep that key in the image or use a provisioned host CA. Blind `ssh-keyscan` trust and `StrictHostKeyChecking=no` are not part of this workflow. Install private CA certificates inside the guest when needed.
6. Merge `examples/gitlab/config.toml` into the runner entry created during registration. Preserve its generated token and other runner settings. Start with concurrency 1; raise it after measuring guest RAM and disk use.
7. Run `examples/gitlab/pipeline.yml` as the initial project pipeline. This tests checkout, a guest HTTPS request, artifact upload/download and clone cleanup. Distributed cache additionally requires the Runner's cache backend configuration; clones do not share a host cache directory.

Use distinct `runnerID` values for different runner/server configurations. `JOB_RESPONSE_FILE` supplies the trusted job ID; `CUSTOM_ENV_CI_JOB_ID` and project-controlled variables cannot redirect ownership or choose host paths. Executor configuration must remain unchanged while its jobs run, including cleanup retries.

Readiness endpoints must be unauthenticated HTTPS URLs without embedded credentials or query strings. Configure the actual GitLab/repository service plus required artifact/LFS endpoints (up to eight). The default example probes your GitLab server, not a third-party public test site. Successful guest curl verifies DNS resolution, routing, TLS trust and an HTTP response below 400 for that endpoint; it does not prove repository authorization or indefinite future connectivity. HTTPS redirects are not followed, so add the final service host explicitly when it differs.

The driver requires two consecutive successful rounds and checks again before checkout, cache and artifact transfer stages. Missing DHCP data is retried. Network probe failures include SSH, DNS, connection, HTTP, timeout or TLS categories, without logging URLs or credentials. It does not change guest DNS settings or host network configuration.

GitLab controls retries of infrastructure-failed stages via its attempts settings. Ordinary script failures remain build failures, including exit 255; the driver records the original code for `allow_failure`. It does not replay build scripts itself. A transport disconnect after dispatch is reported as uncertain infrastructure failure; the command may have executed. The initial network gate prevents premature checkout, but authentication and repository errors are still reported by GitLab's checkout script.

Every VM is an ephemeral clone with a new MAC address. Detached runtime ownership survives individual driver calls. Cleanup force-stops the disposable clone and deletes it only after confirming stopped status; the base image is preserved. Interrupted prepare retains a private ownership journal under `.gitlab/jobs`; a repeated prepare or cleanup recovers it. Runtime logs remain there for diagnosis. Cleanup failures must be monitored because GitLab can retain the job's earlier outcome. Host hard crashes require invoking cleanup for the affected job context before reusing that runner configuration.

## Standalone readiness command

```sh
uvm ready ci-vm --user builder \
  --identity /absolute/path/to/private-key \
  --known-hosts /absolute/path/to/known-hosts \
  --host-key-alias uvm-ci-base \
  --url https://gitlab.muzammilpeer.uk/ --timeout 180
```

`run` continues to mean VM runtime start; it does not silently claim Internet readiness for an unprovisioned guest. Use `ready` for interactive automation; the GitLab executor calls the same shared gate automatically.

## Current limitations

- Live GitLab checkout, artifacts, cancellation and concurrent workloads require the user's registered runner and provisioned guest; these are pending.
- Bash guests only. GitLab `services:` containers, job-selected images, Windows and arbitrary custom shell executors are not implemented.
- Network gates detect readiness and bounded recovery; they cannot prevent external network outages or fix incorrect repository credentials.
- Raw job scripts are streamed through SSH, never executed on the host. Their own output is forwarded to Runner, where GitLab applies its masking rules.

## Local verification — 2026-09-17

44 unit tests, 26 CLI smoke checks, `scripts/gitlab-contract-smoke.py` and the real `scripts/gitlab-hardware-smoke.py` negative path passed. Tests cover consecutive network successes, timeouts, absent DHCP data, shell/endpoint validation, trusted job identity, unique job MACs, interrupted preparation, transport versus exit-255 build failures and cleanup ownership. The real test intentionally supplies no valid SSH trust: checkout is rejected while the detached Ubuntu clone stays running, then cleanup deletes it and preserves its base. This does not claim a successful live GitLab checkout or guest Internet test. The user has offered to register the runner for that next step.
