import { readlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const workDir = join(process.env.HOME || '.', '.tunnel-client');
const readyFile = join(workDir, 'client.ready');
const captureFile = process.env.TUNNEL_CAPTURE_FILE;

writeFileSync(readyFile, String(process.pid));

if (captureFile) {
  let stdinTarget = '';
  try {
    stdinTarget = readlinkSync('/proc/self/fd/0');
  } catch {
    stdinTarget = 'unavailable';
  }

  writeFileSync(
    captureFile,
    JSON.stringify({
      pid: process.pid,
      ppid: process.ppid,
      stdinTarget,
    }),
  );
}

setInterval(() => {}, 1000);
