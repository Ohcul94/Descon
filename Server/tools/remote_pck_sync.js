const fs = require('fs');
const crypto = require('crypto');

const CHUNK_SIZE = 2 * 1024 * 1024; // 2 MB

const action = process.argv[2];
const targetFile = process.argv[3];

if (!action || !targetFile) {
  console.error('Uso: node remote_pck_sync.js [hash|patch|full_hash] <archivo>');
  process.exit(1);
}

if (action === 'hash') {
  if (!fs.existsSync(targetFile)) {
    process.stdout.write(JSON.stringify({ exists: false }));
    process.exit(0);
  }
  const fd = fs.openSync(targetFile, 'r');
  const size = fs.fstatSync(fd).size;
  const total = Math.ceil(size / CHUNK_SIZE);
  const buf = Buffer.alloc(CHUNK_SIZE);
  const hashes = [];
  for (let i = 0; i < total; i++) {
    const bytesRead = fs.readSync(fd, buf, 0, CHUNK_SIZE, i * CHUNK_SIZE);
    const hash = crypto.createHash('md5').update(buf.subarray(0, bytesRead)).digest('hex');
    hashes.push(hash);
  }
  fs.closeSync(fd);
  process.stdout.write(JSON.stringify({ exists: true, size, hashes }));
  process.exit(0);
}

if (action === 'full_hash') {
  if (!fs.existsSync(targetFile)) {
    process.stdout.write('NO_FILE');
    process.exit(0);
  }
  const hash = crypto.createHash('sha256');
  const stream = fs.createReadStream(targetFile);
  stream.on('data', chunk => hash.update(chunk));
  stream.on('end', () => {
    process.stdout.write(hash.digest('hex'));
    process.exit(0);
  });
}

if (action === 'patch') {
  // Protocolo binario por stdin:
  // [4 bytes: chunk_index (int32)]
  // Si chunk_index === -1:
  //   [8 bytes: new_size (bigint64LE)] -> trunca y finaliza
  // Si chunk_index >= 0:
  //   [4 bytes: chunk_length (int32)]
  //   [chunk_length bytes: datos]
  const fd = fs.openSync(targetFile, fs.existsSync(targetFile) ? 'r+' : 'w+');
  const stdin = process.stdin;
  let bufferAcc = Buffer.alloc(0);

  stdin.on('data', chunk => {
    bufferAcc = Buffer.concat([bufferAcc, chunk]);
    processBuffer();
  });

  function processBuffer() {
    while (bufferAcc.length >= 4) {
      const chunkIndex = bufferAcc.readInt32LE(0);
      if (chunkIndex === -1) {
        if (bufferAcc.length >= 12) {
          const newSize = Number(bufferAcc.readBigInt64LE(4));
          fs.ftruncateSync(fd, newSize);
          fs.closeSync(fd);
          process.stdout.write('PATCH_OK');
          process.exit(0);
        }
        return; // Esperar más bytes
      }

      if (bufferAcc.length < 8) return;
      const chunkLength = bufferAcc.readInt32LE(4);
      if (bufferAcc.length < 8 + chunkLength) return; // Esperar el payload completo

      const payload = bufferAcc.subarray(8, 8 + chunkLength);
      const offset = chunkIndex * CHUNK_SIZE;
      fs.writeSync(fd, payload, 0, chunkLength, offset);

      bufferAcc = bufferAcc.subarray(8 + chunkLength);
    }
  }

  stdin.on('end', () => {
    try { fs.closeSync(fd); } catch (e) {}
  });
}

