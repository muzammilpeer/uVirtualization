#!/usr/bin/env python3
"""Exercise a blank EFI VM; this does not assert Linux has been installed."""
import json, os, pathlib, subprocess, time
root = pathlib.Path(__file__).resolve().parent.parent
binary = str(root / '.build/debug/uvm')
env = dict(os.environ, UVM_HOME=str(root / '.build/hardware-smoke'))
def invoke(*args):
    p = subprocess.run([binary, *args], env=env, capture_output=True, text=True, timeout=60)
    if p.returncode:
        raise RuntimeError(f'{args}: {p.stderr}')
    return p.stdout
name = 'efi-smoke'
if not (pathlib.Path(env['UVM_HOME']) / name).exists():
    invoke('create', name, '--linux', '--disk', '20')
with open(root / '.build/hardware-runtime.log', 'w') as log:
    process = subprocess.Popen([binary, 'run', name, '--headless'], env=env, stdout=log, stderr=log)
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError('Runtime exited early; inspect hardware-runtime.log')
            if json.loads(invoke('status', name))['state'] == 'running':
                break
            time.sleep(.2)
        else:
            raise RuntimeError('Runtime did not start')
        invoke('pause', name)
        assert json.loads(invoke('status', name))['state'] == 'paused'
        invoke('resume', name)
        assert json.loads(invoke('status', name))['state'] == 'running'
        invoke('stop', name, '--force')
        assert process.wait(timeout=30) == 0
        assert json.loads(invoke('status', name))['state'] == 'stopped'
        print('EFI VM start, status, pause, resume, force stop: PASS')
    finally:
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
