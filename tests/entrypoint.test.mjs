import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import test from 'node:test';

const entrypoint = resolve('runtime/entrypoint.sh');
const bash = execFileSync('bash', ['-c', 'printf %s "$BASH"'], { encoding: 'utf8' });

async function start(t, overrides = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'wishmachine-entrypoint-'));
  await mkdir(join(directory, 'bin'));
  for (const name of ['dsh', 'cloudflared']) {
    await writeFile(join(directory, 'bin', name), `#!${bash}
set -eu
name=${name}
printf '%s' "\${TUNNEL_TOKEN:-}" > "$TEST_DIRECTORY/$name.token"
printf '%s\\n' "$@" > "$TEST_DIRECTORY/$name.args"
trap 'touch "$TEST_DIRECTORY/$name.stopped"; exit 0' TERM
if [[ \${EXIT_SERVICE:-} == "$name" ]]; then
  while [[ ! -f "$TEST_DIRECTORY/dsh.args" || ! -f "$TEST_DIRECTORY/cloudflared.args" ]]; do sleep 0.01; done
  exit 23
fi
while true; do sleep 0.05; done
`, { mode: 0o755 });
  }
  const child = spawn(bash, [entrypoint], {
    env: {
      ...process.env,
      PATH: `${directory}/bin:${process.env.PATH}`,
      DSH_HOME: `${directory}/home/.dsh`,
      XDG_CACHE_HOME: `${directory}/home/.cache`,
      XDG_CONFIG_HOME: `${directory}/home/.config`,
      XDG_DATA_HOME: `${directory}/home/.local/share`,
      TEST_DIRECTORY: directory,
      TUNNEL_TOKEN: 'test-tunnel-credential',
      DSH_PUBLIC_URL: 'https://harness.example.com',
      ...overrides,
    },
  });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; });
  child.stderr.on('data', chunk => { output += chunk; });
  const exited = new Promise(resolve => child.on('exit', (code, signal) => resolve({ code, signal })));
  t.after(async () => {
    if (child.exitCode === null) child.kill('SIGTERM');
    await exited;
    await rm(directory, { recursive: true, force: true });
  });
  return { child, directory, exited, output: () => output };
}

async function waitForFile(path) {
  for (let attempt = 0; attempt < 200; attempt++) {
    try { return await readFile(path, 'utf8'); } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    await delay(10);
  }
  throw new Error(`Timed out waiting for ${path}`);
}

test('missing tunnel token fails before starting either service', { timeout: 5000 }, async t => {
  const runtime = await start(t, { TUNNEL_TOKEN: '' });
  assert.equal((await runtime.exited).code, 64);
  assert.match(runtime.output(), /TUNNEL_TOKEN is required/);
});

test('launch config preserves auth and routes the token only to cloudflared, then stops both services', { timeout: 5000 }, async t => {
  const runtime = await start(t);
  const dshArgs = await waitForFile(join(runtime.directory, 'dsh.args'));
  await waitForFile(join(runtime.directory, 'cloudflared.args'));
  assert.equal(await readFile(join(runtime.directory, 'dsh.token'), 'utf8'), '');
  assert.equal(await readFile(join(runtime.directory, 'cloudflared.token'), 'utf8'), 'test-tunnel-credential');
  assert.deepEqual(dshArgs.trim().split('\n'), [
    'web', '--host', '127.0.0.1', '--port', '3080', '--no-open',
    '--public-url', 'https://harness.example.com', '--trusted-host', 'harness.example.com',
  ]);
  assert.equal(await readFile(join(runtime.directory, 'cloudflared.args'), 'utf8'), '--no-autoupdate\ntunnel\nrun\n');
  runtime.child.kill('SIGTERM');
  assert.equal((await runtime.exited).code, 143);
  await waitForFile(join(runtime.directory, 'dsh.stopped'));
  await waitForFile(join(runtime.directory, 'cloudflared.stopped'));
  assert.ok(!runtime.output().includes('test-tunnel-credential'));
});

for (const service of ['dsh', 'cloudflared']) {
  test(`${service} failure terminates the peer and propagates status`, { timeout: 5000 }, async t => {
    const runtime = await start(t, { EXIT_SERVICE: service, DSH_PUBLIC_URL: '' });
    assert.equal((await runtime.exited).code, 23);
    await waitForFile(join(runtime.directory, `${service === 'dsh' ? 'cloudflared' : 'dsh'}.stopped`));
  });
}
