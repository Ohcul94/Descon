/**
 * STRESS TEST HARD: 100 Pilotos Distribuidos
 * Validando el nuevo AOI de Jugadores y Disparos
 */
const { io } = require("socket.io-client");

const SERVER_URL = "http://localhost:3333"; 
const CLIENT_COUNT = 100; // EL DOBLE DE ANTES
const clients = [];

const SKILLS = ["REFLECT-Ω", "TURBO-IMPULSO", "BLINK", "FROST-TRAIL"];

console.log(`\n[STRESS-HARD] Iniciando invasión CENTENARIA de ${CLIENT_COUNT} naves...`);

async function createClient(index) {
    const socket = io(SERVER_URL, { transports: ['websocket'], forceNew: true });
    const username = `Centurion_${index}`;
    
    // Distribución total por el mapa (0 a 4000)
    let posX = Math.random() * 3800 + 100;
    let posY = Math.random() * 3800 + 100;
    let rotation = Math.random() * Math.PI * 2;
    let shipId = (index % 4) + 1;

    socket.on("connect", () => {
        socket.emit("register", { user: username, password: "123" });
    });

    socket.on("authError", (err) => {
        if (err.includes("ya existe")) socket.emit("login", { user: username, password: "123" });
    });

    socket.on("loginSuccess", () => {
        setInterval(() => {
            rotation += 0.05;
            posX += Math.cos(rotation) * 10;
            posY += Math.sin(rotation) * 10;

            if (posX < 50 || posX > 3950) rotation += Math.PI;
            if (posY < 50 || posY > 3950) rotation += Math.PI;

            socket.emit("playerMovement", {
                x: posX, y: posY, rotation: rotation, zone: 1,
                hp: 2000, sh: 1000, currentShipId: shipId
            });
        }, 200);

        setInterval(() => {
            const r = Math.random();
            if (r > 0.9) {
                socket.emit("playerFire", {
                    type: "laser", ammoType: 0, x: posX, y: posY, 
                    angle: rotation, rotation: rotation, bulletId: Date.now() + index
                });
            }
        }, 5000);
    });

    return socket;
}

async function start() {
    for (let i = 1; i <= CLIENT_COUNT; i++) {
        clients.push(await createClient(i));
        await new Promise(r => setTimeout(r, 50)); // Spawning más rápido
        if (i % 20 === 0) console.log(`[STRESS-HARD] ${i}/${CLIENT_COUNT} centuriones desplegados...`);
    }
    console.log(`\n[!] INVASIÓN CENTENARIA ACTIVA.`);
}

start().catch(console.error);
