#!/usr/bin/env python3
"""Exercise the packaged driver's stage protocol without GitLab credentials."""
import json
import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
binary = str(root / '.build/debug/gitlab-uvm-executor')
config = json.loads((root / 'examples/gitlab/executor.json').read_text())
with tempfile.TemporaryDirectory(prefix='uvm-executor-contract-') as temp:
    folder = pathlib.Path(temp)
    config['storePath'] = str(folder / 'vms')
    cfg = folder / 'config.json'
    cfg.write_text(json.dumps(config)); cfg.chmod(0o600)
    job = folder / 'job.json'; job.write_text('{"id":123}')
    env = dict(os.environ, JOB_RESPONSE_FILE=str(job), BUILD_FAILURE_EXIT_CODE='41', SYSTEM_FAILURE_EXIT_CODE='42', CUSTOM_ENV_CI_JOB_ID='../evil')
    def invoke(stage, *args):
        return subprocess.run([binary, stage, '--config', str(cfg), *args], env=env, capture_output=True, text=True, timeout=15)
    result = invoke('config')
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data['hostname'].startswith('ci-') and data['shell'] == 'bash'
    assert data['builds_dir_is_shared'] is False
    assert invoke('cleanup').returncode == 0
    result = invoke('run', '/nonexistent', 'get_sources')
    assert result.returncode == 42 and 'not passed preparation' in result.stderr
    job.write_text('{"id":123,"services":[{"name":"redis:latest"}]}')
    result = invoke('config')
    assert result.returncode == 42 and 'services are not supported' in result.stderr
    print('Executor binary config, trusted identity, cleanup and unprepared-stage failure: PASS')
