const ChaseAI = require('../behaviors/ChaseAI');
const OrbitAI = require('../behaviors/OrbitAI');
const BossAI = require('../behaviors/BossAI');
const AncientBossAI = require('../behaviors/AncientBossAI');
const MechanicBossAI = require('../behaviors/MechanicBossAI');
const SniperAI = require('../behaviors/SniperAI');
const ChargerAI = require('../behaviors/ChargerAI');
const GravityAI = require('../behaviors/GravityAI');

/**
 * AIManager
 * Gestiona el spawn y la lógica de los enemigos.
 */
class AIManager {
    constructor(io, state, hordeManager) {
        this.io = io;
        this.state = state;
        this.hordeManager = hordeManager;
    }

    serverSpawnEnemy(zone = 1, forceType = null, posX = null, posY = null, forceName = null, isHorde = false) {
        const { enemies, SERVER_CONFIG } = this.state;
        
        const isHordeZone = this.hordeManager && this.hordeManager.config.active && this.hordeManager.config.map === zone;
        
        if (zone === 1 && !isHordeZone) {
            return null;
        }

        if (!forceType && zone === 2 && Object.keys(enemies).filter(e => enemies[e].zone === 2).length >= 15) return;
        
        const type = forceType || (Math.floor(Math.random() * 3) + 1);
        const cfg = (SERVER_CONFIG && SERVER_CONFIG.enemyModels) ? SERVER_CONFIG.enemyModels[type.toString()] : null;
        
        const isBoss = (type >= 101) || (cfg && cfg.isBoss);
        const id = 'enemy_' + (isBoss ? 'boss_' : '') + Date.now() + Math.floor(Math.random() * 1000);
        
        const name = forceName || (cfg ? cfg.name : (type === 4 ? "Boss1" : (type === 5 ? "Boss2" : (type === 6 ? "Boss3" : "Enemigo"))));

        const initialHp = cfg ? cfg.hp : (type === 6 ? 150000 : (type === 5 ? 200000 : (type === 4 ? 100000 : (type * 2000))));
        const initialShield = cfg ? cfg.shield : (type === 6 ? 75000 : (type === 5 ? 100000 : (type === 4 ? 50000 : (type * 1000))));

        const finalX = posX || (zone === 9 ? 2000 : (Math.random() * 3400 + 300));
        const finalY = posY || (zone === 9 ? 2000 : (Math.random() * 3400 + 300));

        const e = {
            id, type, zone, name,
            isHorde,
            x: finalX,
            y: finalY,
            hp: initialHp,
            maxHp: initialHp,
            shield: initialShield,
            maxShield: initialShield,
            rotation: 0,
            lastHit: 0,
            lastDash: 0,
            shotsInBurst: 0,
            nextShotTime: 0
        };

        const movSpeed = cfg ? (cfg.speed * 0.033) : (type === 1 ? 4.5 : 3.5);
        const aiConfig = cfg ? { ...cfg, speed: movSpeed } : { bulletDamage: (type * 100), fireRate: 2000, speed: movSpeed, bulletSpeed: 800 };
        
        // v266.230: Asignación Dinámica de Cerebros basada en Configuración
        const movementType = cfg ? cfg.movementAI : null;

        const AI_MAP = {
            "chase": ChaseAI,
            "sniper": SniperAI,
            "orbit": OrbitAI,
            "charger": ChargerAI,
            "gravity": GravityAI,
            "boss": BossAI,
            "ancient": AncientBossAI,
            "mechanic": MechanicBossAI
        };

        if (movementType && AI_MAP[movementType]) {
            e.ai = new AI_MAP[movementType](e, aiConfig);
        } else {
            // Fallback para tipos hardcodeados antiguos si no hay config
            if (type === 103) e.ai = new MechanicBossAI(e, aiConfig); 
            else if (type === 102) e.ai = new AncientBossAI(e, aiConfig); 
            else if (type === 101) e.ai = new BossAI(e, aiConfig); 
            else if (type === 8 || type === 3) e.ai = new ChargerAI(e, aiConfig);
            else if (type === 6 || type === 7) e.ai = new GravityAI(e, aiConfig);
            else if (type === 5 || type === 2 || type === 12) e.ai = new SniperAI(e, aiConfig); 
            else if (type === 1 || type === 9 || type === 13 || type === 4) e.ai = new ChaseAI(e, aiConfig); 
            else e.ai = new OrbitAI(e, aiConfig);
        }

        enemies[id] = e;

        const { ai, ...spawnData } = e;
        this.io.to(`zone_${zone}`).emit('enemySpawn', spawnData);
        return e;
    }

    runGuardians() {
        // Guardián Zona 2 (Mapa 1)
        let tCounts = { 1: 0, 5: 0, 8: 0 };
        Object.values(this.state.enemies).forEach(e => {
            if (e.zone === 2 && e.hp > 0 && tCounts[e.type] !== undefined) {
                tCounts[e.type]++;
            }
        });

        if (tCounts[1] < 4) this.serverSpawnEnemy(2, 1);
        if (tCounts[5] < 4) this.serverSpawnEnemy(2, 5);
        if (tCounts[8] < 4) this.serverSpawnEnemy(2, 8);

        // Guardián Jefes
        const hasTitanZ2 = Object.values(this.state.enemies).some(e => e.type === 4 && e.zone === 2);
        if (!hasTitanZ2 && Date.now() - this.state.lastTitanDeath > 10000) {
            this.serverSpawnEnemy(2, 4);
        }
        
        // v266.150: SHOWCASE DE ENEMIGOS EN ZONA 9 (Testeo Visual)
        const regularEnemyTypes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];
        regularEnemyTypes.forEach((type, index) => {
            const exists = Object.values(this.state.enemies).some(e => e.type == type && e.zone === 9);
            if (!exists) {
                const angle = (index / regularEnemyTypes.length) * Math.PI * 2;
                const radius = 800;
                const px = 2000 + Math.cos(angle) * radius;
                const py = 2000 + Math.sin(angle) * radius;
                this.serverSpawnEnemy(9, type, px, py);
            }
        });

        // v266.155: GUARDIANES DE BOSSES (Nuevos IDs)
        const boss101 = Object.values(this.state.enemies).find(e => e.type === 101 && e.zone === 9);
        if (!boss101) this.serverSpawnEnemy(9, 101, 2000, 2000);

        const boss102s = Object.values(this.state.enemies).filter(e => e.type === 102 && e.zone === 8);
        if (boss102s.length === 0) {
            this.serverSpawnEnemy(8, 102, 2000, 2000);
        }

        const boss103s = Object.values(this.state.enemies).filter(e => e.type === 103 && e.zone === 7);
        if (boss103s.length === 0) {
            this.serverSpawnEnemy(7, 103, 2000, 2000);
        }

        // v266.185: Spawning Enemigo 2 (Hielo) en Mapa 6 para testeo
        const iceEnemiesZ6 = Object.values(this.state.enemies).filter(e => e.type === 2 && e.zone === 6);
        if (iceEnemiesZ6.length < 5) {
            this.serverSpawnEnemy(6, 2);
        }
    }
}

module.exports = AIManager;
