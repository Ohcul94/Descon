/**
 * STRESS TEST LITE: Test de Carga sin saturar la CPU local
 * Optimizado para interactuar en vivo
 */
const { io } = require("socket.io-client");

const SERVER_URL = "http://localhost:3333"; 
const CLIENT_COUNT = 25; // Cantidad equilibrada para pruebas locales
const clients = [];

console.log(`\n[STRESS-LITE] Iniciando simulación ligera de ${CLIENT_COUNT} naves...`);

async function createClient(index) {
    // v262.80: Conexión pasiva (No procesa eventos de entrada para ahorrar CPU)
    const socket = io(SERVER_URL, { 
        transports: ['websocket'], 
        forceNew: true,
        autoConnect: true
    });
    
    // IMPORTANTE: No registramos 'onAny' ni escuchamos eventos de otros jugadores
    // para que este proceso no consuma CPU procesando la red.

    const username = `TestBot_${index}`;
    let posX = Math.random() * 3000 + 500;
    let posY = Math.random() * 3000 + 500;
    let rotation = Math.random() * Math.PI * 2;

    socket.on("connect", () => {
        socket.emit("register", { user: username, password: "123" });
    });

    socket.on("authError", (err) => {
        if (err.includes("ya existe")) socket.emit("login", { user: username, password: "123" });
    });

    socket.on("loginSuccess", () => {
        // Enviar movimiento cada 200ms (5 FPS de red)
        setInterval(() => {
            rotation += 0.05;
            posX += Math.cos(rotation) * 5;
            posY += Math.sin(rotation) * 5;

            socket.emit("playerMovement", {
                x: posX, y: posY, rotation: rotation, zone: 1,
                hp: 2000, sh: 1000, currentShipId: (index % 4) + 1
            });
        }, 200);

        // Disparos ocasionales cada 5 segundos
        setInterval(() => {
            socket.emit("playerFire", {
                type: "laser", ammoType: 0,
                x: posX, y: posY, angle: rotation, rotation: rotation,
                bulletId: Date.now() + index
            });
        }, 5000);
    });

    return socket;
}

async function start() {
    for (let i = 1; i <= CLIENT_COUNT; i++) {
        clients.push(await createClient(i));
        await new Promise(r => setTimeout(r, 150));
    }
    console.log(`\n[!] TEST LITE ACTIVO: ${CLIENT_COUNT} bots en segundo plano.`);
    console.log("[!] Presioná CTRL+C para terminar.");
}

start().catch(console.error);
