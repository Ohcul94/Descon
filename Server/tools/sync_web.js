const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn, execSync } = require('child_process');

const CHUNK_SIZE = 2 * 1024 * 1024; // 2 MB

// 1. Cargar .env.deploy
function loadEnv() {
  const envPath = path.resolve(__dirname, '../../.env.deploy');
  if (!fs.existsSync(envPath)) {
    throw new Error('No se encontró el archivo .env.deploy en ' + envPath);
  }
  const content = fs.readFileSync(envPath, 'utf8');
  const env = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith('#')) {
      const idx = trimmed.indexOf('=');
      if (idx !== -1) {
        env[trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim();
      }
    }
  }
  return env;
}

const env = loadEnv();
const SSH_KEY = env.SSH_KEY_PATH;
const SERVER_USER = env.SERVER_USER;
const SERVER_IP = env.SERVER_IP;
const REMOTE_DEST = `${SERVER_USER}@${SERVER_IP}`;
const REMOTE_DIR = `/home/${SERVER_USER}/Descon/Server/public`;

function execSSH(command) {
  return execSync(`ssh -i "${SSH_KEY}" ${REMOTE_DEST} "${command.replace(/"/g, '\\"')}"`, {
    maxBuffer: 50 * 1024 * 1024
  }).toString();
}

async function syncSmallFile(localRelPath, remoteFileName) {
  const localPath = path.resolve(__dirname, '../public', localRelPath);
  if (!fs.existsSync(localPath)) return;

  const localSize = fs.statSync(localPath).size;
  const remoteFilePath = `${REMOTE_DIR}/${remoteFileName}`;

  let needUpload = true;
  try {
    const remoteSizeStr = execSSH(`if [ -f "${remoteFilePath}" ]; then stat -c%s "${remoteFilePath}"; else echo -1; fi`).trim();
    const remoteSize = parseInt(remoteSizeStr, 10);
    if (remoteSize === localSize) {
      // Comparar hash md5
      const localHash = crypto.createHash('md5').update(fs.readFileSync(localPath)).digest('hex');
      const remoteHash = execSSH(`md5sum "${remoteFilePath}" | awk '{print $1}'`).trim();
      if (localHash === remoteHash) {
        needUpload = false;
      }
    }
  } catch (e) {
    needUpload = true;
  }

  if (needUpload) {
    process.stdout.write(`  -> Subiendo ${remoteFileName} (${(localSize / 1024).toFixed(1)} KB)... `);
    execSync(`scp -C -i "${SSH_KEY}" "${localPath}" ${REMOTE_DEST}:${REMOTE_DIR}/`);
    console.log('OK');
  } else {
    console.log(`  -> ${remoteFileName} ya está al día en el servidor.`);
  }
}

async function syncPCK() {
  const localPckPath = path.resolve(__dirname, '../public/Descon.pck');
  if (!fs.existsSync(localPckPath)) {
    console.log('[AVISO] No se encontró Server/public/Descon.pck local.');
    return;
  }

  const fdLocal = fs.openSync(localPckPath, 'r');
  const localSize = fs.fstatSync(fdLocal).size;
  const totalLocalChunks = Math.ceil(localSize / CHUNK_SIZE);
  const remotePckPath = `${REMOTE_DIR}/Descon.pck`;

  console.log(`\n--- Sincronizando Descon.pck (${(localSize / (1024*1024)).toFixed(1)} MB, ${totalLocalChunks} bloques) ---`);

  // Asegurar que el script auxiliar exista en el servidor
  const localHelper = path.resolve(__dirname, 'remote_pck_sync.js');
  const remoteHelper = `/home/${SERVER_USER}/Descon/Server/tools/remote_pck_sync.js`;
  try {
    execSync(`scp -i "${SSH_KEY}" "${localHelper}" ${REMOTE_DEST}:${remoteHelper}`);
  } catch (e) {}

  // 1. Obtener hashes del servidor
  process.stdout.write('1. Consultando estado del archivo en el servidor... ');
  let remoteInfo;
  try {
    const raw = execSSH(`node ${remoteHelper} hash "${remotePckPath}"`);
    remoteInfo = JSON.parse(raw);
  } catch (e) {
    remoteInfo = { exists: false };
  }

  if (!remoteInfo.exists) {
    console.log('No existe en el servidor. Subiendo archivo completo con compresión...');
    execSync(`scp -C -i "${SSH_KEY}" "${localPckPath}" ${REMOTE_DEST}:${remotePckPath}`, { stdio: 'inherit' });
    fs.closeSync(fdLocal);
    return;
  }
  console.log(`Encontrado (${(remoteInfo.size / (1024*1024)).toFixed(1)} MB).`);

  // 2. Calcular hashes locales
  process.stdout.write('2. Verificando bloques locales... ');
  const bufLocal = Buffer.alloc(CHUNK_SIZE);
  const localHashes = [];
  for (let i = 0; i < totalLocalChunks; i++) {
    const bytesRead = fs.readSync(fdLocal, bufLocal, 0, CHUNK_SIZE, i * CHUNK_SIZE);
    localHashes.push(crypto.createHash('md5').update(bufLocal.subarray(0, bytesRead)).digest('hex'));
  }
  console.log('OK');

  // 3. Comparar
  const diffIndices = [];
  for (let i = 0; i < totalLocalChunks; i++) {
    if (i >= remoteInfo.hashes.length || localHashes[i] !== remoteInfo.hashes[i]) {
      diffIndices.push(i);
    }
  }

  if (diffIndices.length === 0 && localSize === remoteInfo.size) {
    console.log('[AL DÍA] Descon.pck es 100% idéntico al del servidor. 0 MB transferidos.');
    fs.closeSync(fdLocal);
    return;
  }

  const diffMB = (diffIndices.length * CHUNK_SIZE / (1024*1024)).toFixed(1);
  console.log(`3. Delta detectado: ${diffIndices.length} bloques modificados (${diffMB} MB de ${(localSize / (1024*1024)).toFixed(1)} MB).`);

  if (diffIndices.length > (totalLocalChunks * 0.7)) {
    console.log('Más del 70% de los bloques difieren. Realizando subida completa directa...');
    fs.closeSync(fdLocal);
    execSync(`scp -C -i "${SSH_KEY}" "${localPckPath}" ${REMOTE_DEST}:${remotePckPath}`, { stdio: 'inherit' });
    return;
  }

  // 4. Transferir solo bloques modificados
  console.log(`4. Transfiriendo delta diferencial a Oracle Cloud...`);
  const patchCmd = `node ${remoteHelper} patch "${remotePckPath}"`;
  const sshProc = spawn('ssh', ['-i', SSH_KEY, REMOTE_DEST, patchCmd]);

  let sshStderr = '';
  sshProc.stderr.on('data', d => { sshStderr += d.toString(); });

  let sentBytes = 0;
  const totalDiffBytes = diffIndices.length * CHUNK_SIZE;

  for (let k = 0; k < diffIndices.length; k++) {
    const idx = diffIndices[k];
    const bytesRead = fs.readSync(fdLocal, bufLocal, 0, CHUNK_SIZE, idx * CHUNK_SIZE);
    const header = Buffer.alloc(8);
    header.writeInt32LE(idx, 0);
    header.writeInt32LE(bytesRead, 4);

    sshProc.stdin.write(header);
    sshProc.stdin.write(Buffer.from(bufLocal.subarray(0, bytesRead)));

    sentBytes += bytesRead;
    const pct = Math.min(100, Math.round((sentBytes / totalDiffBytes) * 100));
    process.stdout.write(`\r   Progreso: ${pct}% (${(sentBytes / (1024*1024)).toFixed(1)} MB / ${diffMB} MB)`);
  }

  // Terminador con nuevo tamaño del archivo
  const endHeader = Buffer.alloc(12);
  endHeader.writeInt32LE(-1, 0);
  endHeader.writeBigInt64LE(BigInt(localSize), 4);
  sshProc.stdin.write(endHeader);
  sshProc.stdin.end();

  await new Promise((resolve, reject) => {
    sshProc.on('close', code => {
      if (code === 0) resolve();
      else reject(new Error('SSH patch falló con código ' + code + ': ' + sshStderr));
    });
  });

  fs.closeSync(fdLocal);
  console.log('\n5. Delta aplicado correctamente in-place en el servidor.');
}

async function main() {
  console.log('==============================================');
  console.log('SINCRONIZACION DIFERENCIAL WEB - ORACLE CLOUD');
  console.log('==============================================');

  console.log('Sincronizando archivos estáticos web...');
  await syncSmallFile('index.html', 'index.html');
  await syncSmallFile('Descon.html', 'Descon.html');
  await syncSmallFile('Descon.js', 'Descon.js');
  await syncSmallFile('Descon.wasm', 'Descon.wasm');
  await syncSmallFile('Descon.side.wasm', 'Descon.side.wasm');
  await syncSmallFile('libterrain.web.release.wasm32.wasm', 'libterrain.web.release.wasm32.wasm');

  await syncPCK();

  console.log('==============================================');
  console.log('VERSION WEB ACTUALIZADA EXITOSAMENTE');
  console.log('==============================================');
}

main().catch(err => {
  console.error('[ERROR]', err);
  process.exit(1);
});

