export const GAME_CONFIG = {
    worldSize: 4000,
    defaultSpeed: 300,
    regenDelay: 5000,
    regenRate: 0.1
};

export const SHIP_MODELS = [
    { id: 1, name: 'Phoenix-L1', hp: 2000, shield: 1000, speed: 300, slots: { w: 1, s: 1, e: 1, x: 1 }, prices: { hubs: 0, ohcu: 0 } },
    { id: 2, name: 'Vulture-G2', hp: 4500, shield: 2500, speed: 330, slots: { w: 2, s: 2, e: 2, x: 2 }, prices: { hubs: 1000000, ohcu: 1000 } },
    { id: 3, name: 'Falcon-A3', hp: 10000, shield: 6000, speed: 360, slots: { w: 4, s: 4, e: 4, x: 3 }, prices: { hubs: 5000000, ohcu: 5000 } },
    { id: 4, name: 'Titan-S4', hp: 25000, shield: 15000, speed: 390, slots: { w: 8, s: 8, e: 8, x: 4 }, prices: { hubs: 20000000, ohcu: 15000 } },
    { id: 5, name: 'Wraith-X5', hp: 70000, shield: 45000, speed: 420, slots: { w: 12, s: 12, e: 12, x: 5 }, prices: { hubs: 0, ohcu: 50000 }, premium: true },
    { id: 6, name: 'Galactus-Z6', hp: 200000, shield: 130000, speed: 460, slots: { w: 16, s: 16, e: 16, x: 6 }, prices: { hubs: 0, ohcu: 200000 }, premium: true }
];

export const AMMO_MULTIPLIERS = {
    laser: [1, 1.5, 2.5, 4, 8, 15],
    missile: [1, 2, 4, 8, 16, 30],
    mine: [1, 3, 7, 15, 40, 100]
};

export const ENEMY_MODELS = {
    1: { name: 'Phoenix PIRATE', hp: 2000, shield: 500, collisionDamage: 500, fireRate: 2000, bulletDamage: 150, rewardHubs: 100, rewardOhcu: 10, rewardExp: 100 },
    2: { name: 'Vulture REBEL', hp: 4000, shield: 1000, collisionDamage: 800, fireRate: 1800, bulletDamage: 300, rewardHubs: 200, rewardOhcu: 20, rewardExp: 250 },
    3: { name: 'Falcon ELITE', hp: 8000, shield: 3000, collisionDamage: 1200, fireRate: 1500, bulletDamage: 600, rewardHubs: 500, rewardOhcu: 50, rewardExp: 600 },
    4: { name: 'Titan BOSS', hp: 100000, shield: 50000, collisionDamage: 3000, fireRate: 1200, bulletDamage: 1500, rewardHubs: 2000, rewardOhcu: 200, rewardExp: 5000 },
    5: { name: 'Ancient BOSS', hp: 200000, shield: 100000, collisionDamage: 5000, fireRate: 1000, bulletDamage: 2500, rewardHubs: 10000, rewardOhcu: 1000, rewardExp: 15000 },
    6: { name: 'Ancient Clone', hp: 50000, shield: 20000, collisionDamage: 2000, fireRate: 1500, bulletDamage: 800, rewardHubs: 2000, rewardOhcu: 200, rewardExp: 3000 }
};

export const SHOP_ITEMS = {
    weapons: [
        { id: 'las1', name: 'Láser LF-1', desc: 'Láser básico.', stats: 'Daño: 100', base: 100, prices: { hubs: 10000, ohcu: 10 }, type: 'w' },
        { id: 'las2', name: 'Láser LF-2', desc: 'Mejora en potencia.', stats: 'Daño: 250', base: 250, prices: { hubs: 50000, ohcu: 50 }, type: 'w' },
        { id: 'las3', name: 'Láser LF-3', desc: 'Estándar militar.', stats: 'Daño: 600', base: 600, prices: { hubs: 200000, ohcu: 200 }, type: 'w' },
        { id: 'las4', name: 'Láser LF-4', desc: 'Vanguardia.', stats: 'Daño: 1500', base: 1500, prices: { hubs: 1000000, ohcu: 1000 }, type: 'w' },
        { id: 'las5', name: 'Láser Prometheus', desc: 'Solar.', stats: 'Daño: 5000', base: 5000, prices: { hubs: 0, ohcu: 5000 }, type: 'w', premium: true },
        { id: 'las6', name: 'Cañón Hyper', desc: 'Disruptor.', stats: 'Daño: 15000', base: 15000, prices: { hubs: 0, ohcu: 15000 }, type: 'w', premium: true }
    ],
    shields: [
        { id: 'sh1', name: 'Escudo S1', desc: 'Mínima.', stats: '+1000', base: 1000, prices: { hubs: 10000, ohcu: 10 }, type: 's' },
        { id: 'sh2', name: 'Escudo S2', desc: 'Reforzado.', stats: '+5000', base: 5000, prices: { hubs: 100000, ohcu: 100 }, type: 's' },
        { id: 'sh3', name: 'Escudo SG3', desc: 'Gravitacional.', stats: '+15000', base: 15000, prices: { hubs: 500000, ohcu: 500 }, type: 's' },
        { id: 'sh4', name: 'Escudo NX', desc: 'Nanobots.', stats: '+40000', base: 40000, prices: { hubs: 2000000, ohcu: 2000 }, type: 's' },
        { id: 'sh5', name: 'Escudo Fusion', desc: 'Alienígena.', stats: '+100000', base: 100000, prices: { hubs: 0, ohcu: 10000 }, type: 's', premium: true },
        { id: 'sh6', name: 'Generador Z+', desc: 'Invulnerabilidad.', stats: '+250000', base: 250000, prices: { hubs: 0, ohcu: 25000 }, type: 's', premium: true }
    ],
    engines: [
        { id: 'en1', name: 'Motor M1', desc: 'Químico.', stats: '+20', base: 20, prices: { hubs: 5000, ohcu: 5 }, type: 'e' },
        { id: 'en2', name: 'Motor M2', desc: 'Estándar.', stats: '+50', base: 50, prices: { hubs: 50000, ohcu: 50 }, type: 'e' },
        { id: 'en3', name: 'Motor M3', desc: 'Iónico.', stats: '+100', base: 100, prices: { hubs: 300000, ohcu: 300 }, type: 'e' }
    ],
    ammo: {
        laser: Array.from({length:6}, (_, i) => ({
            id: `am_l${i+1}`, name: `Láser T${i+1}`, tier: i, 
            prices: { hubs: i < 4 ? 1000 * (i+1) : 0, ohcu: i < 4 ? i*2 : 10*(i-3) }
        })),
        missile: Array.from({length:6}, (_, i) => ({
            id: `am_m${i+1}`, name: `Misil T${i+1}`, tier: i, 
            prices: { hubs: i < 4 ? 5000 * (i+1) : 0, ohcu: i < 4 ? (i+1)*5 : 50*(i-3) }
        })),
        mine: Array.from({length:6}, (_, i) => ({
            id: `am_n${i+1}`, name: `Mina T${i+1}`, tier: i, 
            prices: { hubs: i < 4 ? 10000 * (i+1) : 0, ohcu: i < 4 ? (i+1)*10 : 100*(i-3) }
        }))
    }
};
