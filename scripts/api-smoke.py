#!/usr/bin/env python3
import http.client, json, os, pathlib, secrets, socket, subprocess, tempfile, time
root = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='uvm-api-') as folder:
    token = secrets.token_hex(32)
    path = pathlib.Path(folder) / 'token'
    path.write_text(token); path.chmod(0o600)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
    env = dict(os.environ, UVM_HOME=str(pathlib.Path(folder) / 'vms'))
    with open(root / '.build/api-smoke.log', 'w') as log:
        process = subprocess.Popen([str(root / '.build/debug/uvm'), 'serve', '--token-file', str(path), '--port', str(port)], env=env, stdout=log, stderr=log)
        def request(auth):
            conn = http.client.HTTPConnection('127.0.0.1', port, timeout=3)
            conn.request('GET', '/v1/vms', headers={'Authorization': 'Bearer ' + auth})
            reply = conn.getresponse(); result = (reply.status, reply.read()); conn.close(); return result
        try:
            for _ in range(50):
                if process.poll() is not None: raise RuntimeError('Server exited; inspect api-smoke.log')
                try: status, body = request(token); break
                except (ConnectionRefusedError, OSError): time.sleep(.1)
            else: raise RuntimeError('Server failed to bind')
            assert status == 200 and json.loads(body) == []
            assert request('invalid')[0] == 401
            print('Loopback API authenticated inventory and unauthorized rejection: PASS')
        finally:
            process.terminate()
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
