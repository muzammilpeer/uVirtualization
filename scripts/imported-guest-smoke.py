#!/usr/bin/env python3
"""Boot an existing disposable guest and verify NAT and runtime controls."""
import argparse
import ipaddress
import json
import os
import pathlib
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--store', required=True, type=pathlib.Path)
parser.add_argument('--name', required=True)
parser.add_argument('--graceful', action='store_true', help='Require guest shutdown within 120 seconds')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
binary = str(root / '.build/debug/uvm')
env = dict(os.environ, UVM_HOME=str(args.store.resolve()))

def invoke(*arguments):
    result = subprocess.run([binary, *arguments], env=env, capture_output=True, text=True, timeout=130)
    if result.returncode:
        raise RuntimeError(f'{arguments}: {result.stderr.strip()}')
    return result.stdout

if json.loads(invoke('status', args.name))['state'] != 'stopped':
    raise RuntimeError('The test requires a stopped, disposable guest')

with open(root / '.build/imported-guest-runtime.log', 'w') as log:
    process = subprocess.Popen([binary, 'run', args.name, '--headless'], env=env, stdout=log, stderr=log)
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError('Guest exited; inspect .build/imported-guest-runtime.log')
            if json.loads(invoke('status', args.name))['state'] == 'running':
                break
            time.sleep(.2)
        else:
            raise RuntimeError('Guest did not start')
        print('Guest running; waiting for NAT lease', flush=True)
        address = invoke('ip', args.name, '--timeout', '120').strip()
        ipaddress.IPv4Address(address)
        print(f'NAT address: {address}', flush=True)
        invoke('pause', args.name)
        assert json.loads(invoke('status', args.name))['state'] == 'paused'
        invoke('resume', args.name)
        assert json.loads(invoke('status', args.name))['state'] == 'running'
        invoke('stop', args.name, *([] if args.graceful else ['--force']))
        assert process.wait(timeout=120) == 0
        assert json.loads(invoke('status', args.name))['state'] == 'stopped'
        print('Imported guest: start, NAT lease, pause, resume, stop: PASS', flush=True)
    finally:
        if process.poll() is None:
            try:
                invoke('stop', args.name, '--force')
                process.wait(timeout=30)
            except Exception:
                process.kill()
                process.wait()
