/**
 * STRESS TEST FINAL: 50 Pilotos, Variedad de Naves y Habilidades
 * Optimizado para visibilidad y rendimiento local
 */
const { io } = require("socket.io-client");

const SERVER_URL = "http://localhost:3333"; 
const CLIENT_COUNT = 50; 
const clients = [];

const SKILLS = ["REFLECT-Ω", "TURBO-IMPULSO", "BLINK", "FROST-TRAIL"];

console.log(`\n[STRESS-FINAL] Iniciando invasión masiva de ${CLIENT_COUNT} naves...`);

async function createClient(index) {
    const socket = io(SERVER_URL, { transports: ['websocket'], forceNew: true });
    const username = `Hero_${index}`;
    
    let posX = Math.random() * 3500 + 250;
    let posY = Math.random() * 3500 + 250;
    let rotation = Math.random() * Math.PI * 2;
    let shipId = (index % 4) + 1; // Variedad de naves (1, 2, 3, 4)

    socket.on("connect", () => {
        socket.emit("register", { user: username, password: "123" });
    });

    socket.on("authError", (err) => {
        if (err.includes("ya existe")) socket.emit("login", { user: username, password: "123" });
    });

    socket.on("loginSuccess", () => {
        // Movimiento a 5Hz (Ahorro de CPU local, visibilidad fluida en server)
        setInterval(() => {
            rotation += 0.1;
            posX += Math.cos(rotation) * 8;
            posY += Math.sin(rotation) * 8;

            socket.emit("playerMovement", {
                x: posX, y: posY, rotation: rotation, zone: 1,
                hp: 2000, sh: 1000, currentShipId: shipId
            });
        }, 200);

        // Habilidades y Disparos cada 3-7 segundos
        setInterval(() => {
            const r = Math.random();
            if (r > 0.8) {
                // Disparo
                socket.emit("playerFire", {
                    type: "laser", ammoType: 0, x: posX, y: posY, 
                    angle: rotation, rotation: rotation, bulletId: Date.now() + index
                });
            }
            if (r > 0.92) {
                // Habilidad
                const sName = SKILLS[Math.floor(Math.random() * SKILLS.length)];
                socket.emit("playerSphereSkill", {
                    id: 0, skillName: sName, powerValue: 100,
                    targetId: null, posX: posX, posY: posY
                });
            }
        }, 3000);
    });

    return socket;
}

async function start() {
    for (let i = 1; i <= CLIENT_COUNT; i++) {
        clients.push(await createClient(i));
        await new Promise(r => setTimeout(r, 100));
    }
    console.log(`\n[!] INVASIÓN FINAL ACTIVA: ${CLIENT_COUNT} naves sincronizadas.`);
}

start().catch(console.error);
