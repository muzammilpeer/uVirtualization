#!/usr/bin/env python3
import json, os, pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='uvm-cli-') as folder:
    env = dict(os.environ, UVM_HOME=folder, UVM_JSON_ERRORS='1')
    count = 0
    def run(*args, ok=True):
        global count
        p = subprocess.run([str(root / '.build/debug/uvm'), *args], env=env, capture_output=True, text=True, timeout=15)
        assert (p.returncode == 0) == ok, (args, p.returncode, p.stdout, p.stderr)
        if not ok: assert 'error' in json.loads(p.stderr)
        count += 1
        return p.stdout
    assert json.loads(run('list')) == []
    run('init', 'one', '--cpu=2', '--memory', '4096')
    assert json.loads(run('get', 'one'))['cpuCount'] == 2
    run('set', 'one', '--disk=80')
    run('clone', 'one', 'two')
    run('rename', 'two', 'three')
    archive = str(pathlib.Path(folder) / '.archive.uvma')
    run('export', 'three', archive)
    run('import', archive, 'four')
    assert len(json.loads(run('list'))) == 3
    assert json.loads(run('status', 'one'))['state'] == 'stopped'
    run('delete', 'three')
    for args in [('init', 'one'), ('init', '../bad'), ('set', 'one', '--disk', '1'), ('init', 'bad', '--cpu', 'x'), ('init', 'bad', '--cpu', '2', '--cpu', '4'), ('run', 'one'), ('stop', 'one'), ('unknown',), ('init', 'bad', '--weird'), ('image-info', 'http://bad/image')]:
        run(*args, ok=False)
    for shell in ['bash', 'zsh', 'fish']: assert 'uvm' in run('completions', shell)
    run('help'); run('version')
    print(f'{count} CLI smoke checks passed')
