import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { test } from 'node:test';

const INSTALL_UUID = 'detach-install';
const MINIMAL_PKG = JSON.stringify({
  name: 'detach-client',
  version: '1.0.0',
  type: 'module',
  private: true,
});

function createServer(_port) {
  const bundle = fs.readFileSync('test/fixtures/client-captures-launch.js');
  return http.createServer((req, res) => {
    if (req.url === `/${INSTALL_UUID}-client.js`) {
      res.writeHead(200, { 'Content-Type': 'application/javascript' });
      res.end(bundle);
      return;
    }
    if (req.url === `/${INSTALL_UUID}-client-package.json`) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(MINIMAL_PKG);
      return;
    }
    res.writeHead(404);
    res.end();
  });
}

function runInstaller(homeDir, port, envOverrides = {}) {
  return new Promise((resolve) => {
    const child = spawn('bash', ['serve/setup.sh'], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        HOME: homeDir,
        TUNNEL_SERVER_URL: `ws://127.0.0.1:${port}/tunnel`,
        TUNNEL_USERNAME: 'admin',
        TUNNEL_PASSWORD: 'secret',
        TARGET_ORIGIN: 'http://127.0.0.1:8080',
        INSTALL_UUID,
        ...envOverrides,
      },
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => {
      stdout += chunk;
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk;
    });
    child.on('exit', (status, signal) => resolve({ status, signal, stdout, stderr }));
    child.on('error', (error) => resolve({ status: null, signal: null, stdout, stderr, error }));
  });
}

function resolveCommand(name) {
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    const candidate = path.join(dir, name);
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch {}
  }
  assert.fail(`required test command missing: ${name}`);
}

function pathWithoutSetsid(sandbox) {
  const binDir = path.join(sandbox, 'bin-no-setsid');
  fs.mkdirSync(binDir, { recursive: true });

  const commands = [
    'bash',
    'cat',
    'chmod',
    'curl',
    'cut',
    'env',
    'grep',
    'ln',
    'mkdir',
    'mktemp',
    'mv',
    'node',
    'nohup',
    'npm',
    'readlink',
    'rm',
    'rmdir',
    'sed',
    'seq',
    'sleep',
  ];

  for (const command of commands) {
    fs.symlinkSync(resolveCommand(command), path.join(binDir, command));
  }

  return binDir;
}

function cleanupClient(homeDir) {
  const pidFile = path.join(homeDir, '.tunnel-client', 'client.pid');
  if (!fs.existsSync(pidFile)) return;
  try {
    process.kill(Number(fs.readFileSync(pidFile, 'utf8').trim()));
  } catch {}
}

async function exerciseLaunch(t, { port, fallback }) {
  const sandbox = fs.mkdtempSync('/tmp/installer-detach-');
  const captureFile = path.join(sandbox, 'launch.json');
  t.after(() => {
    cleanupClient(sandbox);
    fs.rmSync(sandbox, { recursive: true, force: true });
  });

  const server = createServer(port);
  await new Promise((resolve) => server.listen(port, resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));

  const envOverrides = { TUNNEL_CAPTURE_FILE: captureFile };
  if (fallback) envOverrides.PATH = pathWithoutSetsid(sandbox);

  const result = await runInstaller(sandbox, port, envOverrides);
  assert.equal(result.status, 0, `installer failed\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

  const workDir = path.join(sandbox, '.tunnel-client');
  const pid = Number(fs.readFileSync(path.join(workDir, 'client.pid'), 'utf8').trim());
  const readyPid = Number(fs.readFileSync(path.join(workDir, 'client.ready'), 'utf8').trim());
  const capture = JSON.parse(fs.readFileSync(captureFile, 'utf8'));

  assert.ok(pid > 0);
  assert.equal(readyPid, pid, 'client.ready must preserve the installer PID contract');
  assert.equal(capture.pid, pid, 'launched node process must be the PID stored by the installer');
  assert.equal(capture.stdinTarget, '/dev/null', 'client stdin must be detached');
}

test('installer detaches client stdin while preserving PID with setsid', async (t) => {
  const setup = fs.readFileSync('serve/setup.sh', 'utf8');
  assert.match(setup, /command -v setsid/);
  assert.doesNotMatch(setup, /setsid\s+-f/);
  await exerciseLaunch(t, { port: 18801, fallback: false });
});

test('installer preserves PID and stdin detachment without setsid', async (t) => {
  await exerciseLaunch(t, { port: 18802, fallback: true });
});
