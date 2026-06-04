/**
 * STRESS TEST PRO: Simulación Masiva v1.5
 * Naves variadas, Habilidades y Carga de DB
 */
const { io } = require("socket.io-client");

const SERVER_URL = "http://localhost:3333"; 
const CLIENT_COUNT = 50;
const clients = [];

const SKILLS = ["REFLECT-Ω", "TURBO-IMPULSO", "HYPER-DASH", "BLINK", "FROST-TRAIL", "NANO-REGENERACIÓN"];
const AMMO = ["laser", "missile", "mine"];

console.log(`\n[STRESS-TEST-PRO] Desplegando 50 pilotos con armamento variado...`);

async function createClient(index) {
    const socket = io(SERVER_URL, { transports: ['websocket'], forceNew: true });
    const username = `Pilot_Alpha_${index}`;
    
    // Stats aleatorios para simular progresión real
    let posX = Math.random() * 3500 + 200;
    let posY = Math.random() * 3500 + 200;
    let rotation = Math.random() * Math.PI * 2;
    let shipId = Math.floor(Math.random() * 4) + 1;
    let zone = 1;

    socket.on("connect", () => {
        socket.emit("register", { user: username, password: "123" });
    });

    socket.on("authError", (err) => {
        if (err.includes("ya existe")) socket.emit("login", { user: username, password: "123" });
    });

    socket.on("loginSuccess", (data) => {
        // 1. Simular Movimiento (10Hz para no saturar el canal local, pero realista para el server)
        setInterval(() => {
            rotation += (Math.random() - 0.5) * 0.2;
            posX += Math.cos(rotation) * 15;
            posY += Math.sin(rotation) * 15;

            if (posX < 50 || posX > 3950) rotation += Math.PI;
            if (posY < 50 || posY > 3950) rotation += Math.PI;

            socket.emit("playerMovement", {
                x: posX, y: posY, rotation: rotation, zone: zone,
                hp: 2000, sh: 1000, currentShipId: shipId
            });
        }, 100);

        // 2. Simular Combate (Disparos y Habilidades)
        setInterval(() => {
            const action = Math.random();
            
            if (action > 0.7) {
                // Disparo de munición variada
                const type = AMMO[Math.floor(Math.random() * AMMO.length)];
                socket.emit("playerFire", {
                    type: type, ammoType: Math.floor(Math.random() * 3),
                    x: posX, y: posY, angle: rotation, rotation: rotation,
                    bulletId: Date.now() + index
                });
            } 
            
            if (action > 0.9) {
                // Uso de Habilidades de Esferas
                const skill = SKILLS[Math.floor(Math.random() * SKILLS.length)];
                socket.emit("playerSphereSkill", {
                    id: 0, skillName: skill, powerValue: 100,
                    targetId: null, posX: posX, posY: posY
                });
            }
        }, 2000);

        // 3. Simular Carga de Base de Datos (Save Progress)
        setInterval(() => {
            socket.emit("saveProgress", {
                hubs: Math.floor(Math.random() * 1000),
                hp: 2000, shield: 1000,
                lastPos: { x: posX, y: posY }
            });
        }, 10000);
    });

    return socket;
}

async function start() {
    for (let i = 1; i <= CLIENT_COUNT; i++) {
        clients.push(await createClient(i));
        await new Promise(r => setTimeout(r, 80));
    }
    console.log("\n[!] INVASIÓN COMPLETA: 50 naves variadas operando.");
}

start().catch(console.error);
