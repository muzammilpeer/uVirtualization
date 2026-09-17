#!/usr/bin/env python3
"""Verify a real job clone stays gated without SSH trust, then is reclaimed.

Uses an existing stopped disposable Linux base in .build/linux-acceptance.
No real GitLab token, guest login, or checkout is needed for this negative test.
"""
import json
import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
binary = str(root / '.build/debug/gitlab-uvm-executor')
uvm = str(root / '.build/debug/uvm')
store = root / '.build/linux-acceptance'
if not (store / 'ubuntu/config.json').is_file():
    raise SystemExit('This test requires the disposable Ubuntu acceptance image')
with tempfile.TemporaryDirectory(prefix='uvm-gitlab-') as folder:
    folder = pathlib.Path(folder)
    # Intentionally absent trust/authorization: readiness must fail closed.
    (folder / 'key').write_text('invalid test key\n')
    (folder / 'key').chmod(0o600)
    (folder / 'known_hosts').write_text('')
    response = folder / 'job.json'
    response.write_text(json.dumps({'id': 731991}))
    config = folder / 'executor.json'
    config.write_text(json.dumps({
        'runnerID': 'hardware-smoke', 'uvmPath': uvm, 'storePath': str(store), 'image': 'ubuntu',
        'ssh': {'user': 'builder', 'identityFile': str(folder / 'key'), 'knownHostsFile': str(folder / 'known_hosts'), 'hostKeyAlias': 'untrusted-test'},
        'readinessURLs': ['https://gitlab.muzammilpeer.uk/'], 'readinessTimeout': 8,
        'buildsDirectory': '/tmp/builds', 'cacheDirectory': '/tmp/cache', 'stageTimeout': 30
    }))
    config.chmod(0o600)
    env = dict(os.environ, JOB_RESPONSE_FILE=str(response), BUILD_FAILURE_EXIT_CODE='41', SYSTEM_FAILURE_EXIT_CODE='42')
    def invoke(stage, *args):
        return subprocess.run([binary, stage, '--config', str(config), *args], env=env, capture_output=True, text=True, timeout=90)
    configured = invoke('config')
    assert configured.returncode == 0, configured.stderr
    name = json.loads(configured.stdout)['hostname']
    try:
        prepared = invoke('prepare')
        assert prepared.returncode == 42, prepared.stderr
        assert 'readiness deadline' in prepared.stderr.lower(), prepared.stderr
        assert (store / name / 'config.json').exists()
        status = subprocess.run([uvm, 'status', name], env=dict(os.environ, UVM_HOME=str(store)), capture_output=True, text=True, check=True)
        assert json.loads(status.stdout)['state'] == 'running', status.stdout
        script = folder / 'must-not-run'
        script.write_text('exit 0\n')
        run = invoke('run', str(script), 'get_sources')
        assert run.returncode == 42 and 'has not passed preparation' in run.stderr
        print('Real clone/runtime survives prepare exit; missing SSH trust blocks checkout: PASS')
    finally:
        cleaned = invoke('cleanup')
        assert cleaned.returncode == 0, cleaned.stderr
        assert not (store / name).exists()
        assert (store / 'ubuntu/config.json').exists()
        assert invoke('cleanup').returncode == 0
        print('Job clone cleanup and repeated cleanup preserve base: PASS')
