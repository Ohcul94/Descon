/**
 * STRESS TEST SAFE: 30 Pilotos Reales
 * Optimizado para estabilidad total
 */
const { io } = require("socket.io-client");

const SERVER_URL = "http://localhost:3333"; 
const CLIENT_COUNT = 30; 
const clients = [];

console.log(`\n[STRESS-SAFE] Iniciando simulación de ${CLIENT_COUNT} naves...`);

async function createClient(index) {
    const socket = io(SERVER_URL, { transports: ['websocket'], forceNew: true });
    const username = `Pilot_${index}`;
    
    // Spawn cerca del centro para evitar errores de Anti-Cheat
    let posX = 2000 + (Math.random() - 0.5) * 500;
    let posY = 2000 + (Math.random() - 0.5) * 500;
    let rotation = Math.random() * Math.PI * 2;
    let shipId = (index % 4) + 1;

    socket.on("connect", () => {
        socket.emit("register", { user: username, password: "123" });
    });

    socket.on("authError", (err) => {
        if (err.includes("ya existe")) socket.emit("login", { user: username, password: "123" });
    });

    socket.on("loginSuccess", () => {
        // Movimiento a 4Hz (Estabilidad máxima)
        setInterval(() => {
            rotation += 0.05;
            posX += Math.cos(rotation) * 6;
            posY += Math.sin(rotation) * 6;

            socket.emit("playerMovement", {
                x: posX, y: posY, rotation: rotation, zone: 1,
                hp: 2000, sh: 1000, currentShipId: shipId
            });
        }, 250);

        // Habilidades cada 5 segundos
        setInterval(() => {
            if (Math.random() > 0.8) {
                socket.emit("playerSphereSkill", {
                    id: 0, skillName: "REFLECT-Ω", powerValue: 100,
                    targetId: null, posX: posX, posY: posY
                });
            }
        }, 5000);
    });

    return socket;
}

async function start() {
    for (let i = 1; i <= CLIENT_COUNT; i++) {
        clients.push(await createClient(i));
        await new Promise(r => setTimeout(r, 200)); // Spawning lento y seguro
    }
    console.log(`\n[!] TEST SEGURO ACTIVO: 30 pilotos en el sector.`);
}

start().catch(console.error);
