const { io } = require('socket.io-client');

const SERVER_URL = 'http://localhost:3333';

function wait(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function runTests() {
    console.log("=== INICIANDO PRUEBAS DE SEGURIDAD ===");

    // PRUEBA 1: Anti-NoSQL Injection
    await new Promise((resolve) => {
        console.log("\n[TEST 1] Probando inyección NoSQL en el Login...");
        const socket = io(SERVER_URL, { forceNew: true });
        
        socket.on('connect', () => {
            // Intentar inyectar un objeto en lugar de un string en user
            socket.emit('login', { user: { $ne: null }, password: 'any', isAdmin: false });
        });

        socket.on('authError', (msg) => {
            console.log(`[TEST 1 PASADO] El servidor rechazó la petición de forma segura con: "${msg}"`);
            socket.disconnect();
            resolve();
        });

        socket.on('disconnect', () => resolve());
    });

    // PRUEBA 2: Bloqueo de Fuerza Bruta (Login IP Lockout)
    await new Promise(async (resolve) => {
        console.log("\n[TEST 2] Probando bloqueo por intentos fallidos de login (Fuerza Bruta)...");
        
        for (let i = 1; i <= 6; i++) {
            await new Promise((resolveAttempt) => {
                const socket = io(SERVER_URL, { forceNew: true });
                
                socket.on('connect', () => {
                    socket.emit('login', { user: 'caelli94', password: `intento_incorrecto_${i}`, isAdmin: false });
                });

                socket.on('authError', (msg) => {
                    console.log(`Intento ${i}: ${msg}`);
                    socket.disconnect();
                    resolveAttempt();
                });

                socket.on('disconnect', () => resolveAttempt());
            });
            await wait(100);
        }
        
        // El 6to intento debería habernos dado un mensaje de bloqueo.
        // Hacemos un 7mo intento para confirmarlo explícitamente.
        const socketFinal = io(SERVER_URL, { forceNew: true });
        socketFinal.on('connect', () => {
            socketFinal.emit('login', { user: 'caelli94', password: 'correct_or_incorrect', isAdmin: false });
        });
        socketFinal.on('authError', (msg) => {
            if (msg.includes('Demasiados intentos fallidos') || msg.includes('IP está bloqueada')) {
                console.log(`[TEST 2 PASADO] El servidor bloqueó la IP exitosamente: "${msg}"`);
            } else {
                console.error(`[TEST 2 FALLADO] El servidor no bloqueó la IP. Mensaje recibido: "${msg}"`);
            }
            socketFinal.disconnect();
            resolve();
        });
        socketFinal.on('disconnect', () => resolve());
    });

    // PRUEBA 3: Rate Limiting / Flooding (DDoS)
    await new Promise((resolve) => {
        console.log("\n[TEST 3] Probando rate limiting de paquetes (Flooding)...");
        const socket = io(SERVER_URL, { forceNew: true });
        let pps = 0;
        let disconnected = false;

        socket.on('connect', () => {
            console.log("Inundando al servidor con 100 mensajes ping rápidos...");
            const interval = setInterval(() => {
                if (disconnected) {
                    clearInterval(interval);
                    return;
                }
                socket.emit('ping_custom', {});
                pps++;
            }, 5); // Envía paquetes cada 5ms (200 PPS aprox)
        });

        socket.on('disconnect', (reason) => {
            disconnected = true;
            console.log(`[TEST 3 PASADO] Conexión cerrada por el servidor tras enviar ${pps} paquetes. Motivo: ${reason}`);
            resolve();
        });
    });

    console.log("\n=== PRUEBAS DE SEGURIDAD COMPLETADAS ===");
    process.exit(0);
}

runTests().catch(console.error);
