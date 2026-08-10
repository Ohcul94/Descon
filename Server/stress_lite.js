/**
 * STRESS TEST LITE: Test de Carga con 100 Bots Distribuidos
 * Optimizado para simular movimiento, cambio de mapa y disparos avanzados (simulando habilidades)
 */
const { io } = require("socket.io-client");

const SERVER_URL = "http://138.2.241.76:3333";
const CLIENT_COUNT = 75; // Simulación para 75 naves concurrentes
const clients = [];

console.log(`\n[STRESS-LITE] Iniciando simulación de ${CLIENT_COUNT} naves distribuidas...`);

async function createClient(index) {
    const socket = io(SERVER_URL, {
        transports: ['websocket'],
        forceNew: true,
        autoConnect: true
    });

    const username = `TestBot_${index}`;
    // Asignar zona del 2 al 6
    const targetZone = (index % 5) + 2;

    // Coordenadas iniciales amplias dentro del mapa (tamaño 4000x4000)
    let posX = Math.random() * 3000 + 500;
    let posY = Math.random() * 3000 + 500;
    let rotation = Math.random() * Math.PI * 2;
    let speed = Math.random() * 3 + 2; // Velocidad de movimiento variable

    socket.on("connect", () => {
        socket.emit("register", { user: username, password: "123" });
    });

    socket.on("authError", (err) => {
        if (err.includes("ya existe")) {
            socket.emit("login", { user: username, password: "123" });
        }
    });

    socket.on("loginSuccess", () => {
        // Teletransportarse al mapa destino (Zonas 2 a 6) para salir del Lobby
        setTimeout(() => {
            socket.emit("changeZone", targetZone);
        }, 500);

        // Bucle de movimiento a 5 FPS (cada 200ms)
        setInterval(() => {
            // Cambiar suavemente de dirección
            rotation += (Math.random() - 0.5) * 0.5;
            posX += Math.cos(rotation) * speed * 2;
            posY += Math.sin(rotation) * speed * 2;

            // Rebotar contra los bordes del mapa (4000 x 4000)
            if (posX < 200 || posX > 3800) rotation = Math.PI - rotation;
            if (posY < 200 || posY > 3800) rotation = -rotation;

            socket.emit("playerMovement", {
                x: posX,
                y: posY,
                rotation: rotation,
                zone: targetZone,
                hp: 2000,
                sh: 1000,
                currentShipId: (index % 4) + 1
            });
        }, 200);

        // Disparos ocasionales (simulan combate y habilidades de curación/sifón)
        setInterval(() => {
            const fireTypes = ["laser", "siphon", "heal", "emp"];
            const selectedType = fireTypes[index % fireTypes.length];

            socket.emit("playerFire", {
                type: selectedType,
                ammoType: index % 2, // Tier 0 o Tier 1
                x: posX,
                y: posY,
                angle: rotation,
                rotation: rotation,
                bulletId: Date.now() + index
            });
        }, 3000);
    });

    return socket;
}

async function start() {
    for (let i = 1; i <= CLIENT_COUNT; i++) {
        clients.push(await createClient(i));
        // Intervalo de conexión secuencial corto para no saturar al instante
        await new Promise(r => setTimeout(r, 100));
    }
    console.log(`\n[!] TEST DE ESTRES ACTIVO: ${CLIENT_COUNT} bots distribuidos en Zonas 2-6.`);
    console.log("[!] Presioná CTRL+C para terminar.");
}

start().catch(console.error);
