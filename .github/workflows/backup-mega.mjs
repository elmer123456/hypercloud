import { createHash } from 'node:crypto';
import { createReadStream, statSync, appendFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { basename } from 'node:path';
import { once } from 'node:events';

const require = createRequire(import.meta.url);
const { Storage } = require('megajs');
const email = process.env.MEGA_EMAIL;
const password = process.env.MEGA_PASSWORD;
const dumpPath = process.env.DUMP_FILE;
const folderName = process.env.MEGA_FOLDER || 'Hypercloud-Backups';
const keepCount = 14;

for (const [name, value] of Object.entries({ MEGA_EMAIL: email, MEGA_PASSWORD: password, DUMP_FILE: dumpPath })) {
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
}

const dumpName = basename(dumpPath);
if (!/^hypercloud-db-\d{8}T\d{6}Z\.dump$/.test(dumpName)) throw new Error('Unexpected backup filename');
const dumpSize = statSync(dumpPath).size;
if (!dumpSize) throw new Error('Database dump is empty');

function redact(message) {
  return String(message || 'unknown error')
    .replaceAll(email, '[MEGA_EMAIL]')
    .replaceAll(password, '[MEGA_PASSWORD]');
}

async function sha256File(filePath) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(filePath)) hash.update(chunk);
  return hash.digest('hex');
}

async function sha256Stream(stream) {
  const hash = createHash('sha256');
  for await (const chunk of stream) hash.update(chunk);
  return hash.digest('hex');
}

function isBackup(file) {
  return !file.directory && /^hypercloud-db-\d{8}T\d{6}Z\.dump$/.test(file.name || '');
}

async function getBackupFolder(storage) {
  await storage.reload(true);
  let folder = (storage.root.children || []).find(item => item.name === folderName);
  if (folder && !folder.directory) throw new Error('MEGA backup path exists but is not a folder');
  if (!folder) folder = await storage.root.mkdir(folderName);
  await storage.reload(true);
  folder = (storage.root.children || []).find(item => item.name === folderName && item.directory);
  if (!folder) throw new Error('Could not open the MEGA backup folder');
  return folder;
}

async function info(storage) {
  const account = await storage.getAccountInfo();
  return {
    total: Number(account.spaceTotal || 0),
    used: Number(account.spaceUsed || 0),
  };
}

async function makeRoom(storage, folder) {
  let { total, used } = await info(storage);
  let free = Math.max(0, total - used);
  const margin = Math.max(10 * 1024 * 1024, Math.ceil(dumpSize * 0.05));
  const needed = dumpSize + margin;
  if (free >= needed) return { total, free };

  const backups = (folder.children || []).filter(isBackup).sort((a, b) => a.name.localeCompare(b.name));
  // Keep the newest verified copy even when space is tight.
  const newest = backups.at(-1);
  for (const old of backups) {
    if (old === newest || free >= needed) continue;
    await old.delete(true);
    free += Number(old.size || 0);
  }
  ({ total, used } = await info(storage));
  free = Math.max(free, total - used);
  if (free < needed) throw new Error('Not enough free MEGA space for another backup; kept the newest existing copy');
  return { total, free };
}

async function uploadAndVerify(folder) {
  const upload = folder.upload({ name: dumpName, size: dumpSize });
  let uploadError;
  upload.on('error', error => { uploadError = error; });
  const complete = upload.complete.catch(error => { uploadError = error; return null; });
  try {
    for await (const chunk of createReadStream(dumpPath)) {
      if (uploadError) throw uploadError;
      if (!upload.write(chunk)) await once(upload, 'drain');
    }
    upload.end();
    const file = await complete;
    if (!file || uploadError) throw uploadError || new Error('MEGA did not confirm the upload');
    if (Number(file.size) !== dumpSize) throw new Error('MEGA upload size check failed');
    const localHash = await sha256File(dumpPath);
    const remoteHash = await sha256Stream(file.download());
    if (localHash !== remoteHash) {
      await file.delete(true).catch(() => {});
      throw new Error('MEGA upload integrity check failed');
    }
    return { file, sha256: localHash };
  } catch (error) {
    try { upload.destroy?.(); } catch {}
    throw error;
  }
}

let storage;
let stage = 'MEGA authentication';
try {
  storage = await new Storage({ email, password, keepalive: false, autoload: true, userAgent: 'HypercloudBackup/1.0' }).ready;
  stage = 'MEGA folder and quota check';
  const folder = await getBackupFolder(storage);
  const quota = await makeRoom(storage, folder);
  stage = 'database backup upload and integrity check';
  const { file, sha256 } = await uploadAndVerify(folder);
  stage = 'backup rotation';
  await storage.reload(true);
  const currentFolder = (storage.root.children || []).find(item => item.name === folderName && item.directory);
  if (!currentFolder) throw new Error('MEGA backup folder disappeared after upload');
  const backups = (currentFolder.children || []).filter(isBackup).sort((a, b) => b.name.localeCompare(a.name));
  for (const old of backups.slice(keepCount)) await old.delete(true);

  const { total, used } = await info(storage);
  const result = {
    status: 'ok',
    file: file.name,
    bytes: dumpSize,
    sha256,
    retainedBackups: Math.min(keepCount, backups.length),
    megaTotalBytes: total,
    megaUsedBytes: used,
    megaFreeBytes: Math.max(0, total - used),
  };
  console.log(JSON.stringify(result));
  if (process.env.GITHUB_STEP_SUMMARY) {
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, `## Hypercloud backup: OK\n\n- File: \`${file.name}\`\n- Size: ${dumpSize} bytes\n- Integrity: SHA-256 verified after download from MEGA\n- Retained copies: ${result.retainedBackups}\n- MEGA free space: ${result.megaFreeBytes} bytes\n`);
  }
} catch (error) {
  console.error(`Backup failed during ${stage}: ${redact(error?.message || error)}`);
  if (process.env.GITHUB_STEP_SUMMARY) {
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, `## Hypercloud backup: FAILED\n\nBackup stage: ${stage}. Review the failed workflow run; secrets were not printed.\n`);
  }
  process.exitCode = 1;
} finally {
  try { await storage?.close(); } catch {}
        }
