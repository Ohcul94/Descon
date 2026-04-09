const { io } = require('socket.io-client');
const axios = require('axios');

const SERVER_URL = 'http://localhost:3333';
const BOT_COUNT = 30;
const PASS = '1234';

const bots = [];

async function startStressTest() {
    console.log(`\x1b[36m[STRESS-TEST]\x1b[0m Iniciando enjambre de ${BOT_COUNT} bots...`);

    for (let i = 4; i <= 34; i++) {
        const username = `Player${i}`;
        
        try {
            // Intentamos registrar al bot (si ya existe, el servidor dará error pero no importa)
            const socket = io(SERVER_URL);

            socket.on('connect', () => {
                // 1. Registrar (por las dudas)
                socket.emit('register', { user: username, password: PASS });
                
                // 2. Loguear después de un segundo
                setTimeout(() => {
                    socket.emit('login', { user: username, password: PASS });
                }, 1000);
            });

            socket.on('loginSuccess', (data) => {
                console.log(`\x1b[32m[BOT]\x1b[0m ${username} logueado con éxito.`);
                
                // Iniciar patrón de movimiento aleatorio para estresar el grid espacial
                let angle = Math.random() * Math.PI * 2;
                let posX = 500 + Math.random() * 3000;
                let posY = 500 + Math.random() * 3000;

                setInterval(() => {
                    angle += (Math.random() - 0.5) * 0.5;
                    posX += Math.cos(angle) * 10;
                    posY += Math.sin(angle) * 10;

                    // Límites del mapa
                    if (posX < 100 || posX > 3900) angle += Math.PI;
                    if (posY < 100 || posY > 3900) angle += Math.PI;

                    socket.emit('playerMovement', {
                        x: posX,
                        y: posY,
                        rotation: angle,
                        zone: 1,
                        hp: 2000,
                        sh: 1000,
                        maxHp: 2000,
                        maxSh: 1000
                    });
                }, 100); // 10 actualizaciones por segundo por bot
            });

            socket.on('authError', (msg) => {
                // Si ya existe, intentamos el login directo
                if (msg.includes('ya existe')) {
                    socket.emit('login', { user: username, password: PASS });
                }
            });

            bots.push(socket);
        } catch (e) {
            console.error(`Error con ${username}:`, e.message);
        }
        
        // Delay pequeño entre conexiones para no saturar el login
        await new Promise(r => setTimeout(r, 200));
    }
}

// Manejo de salida limpia
process.on('SIGINT', () => {
    console.log('\n\x1b[33m[STRESS-TEST]\x1b[0m Desconectando enjambre...');
    bots.forEach(s => s.disconnect());
    process.exit();
});

startStressTest();
