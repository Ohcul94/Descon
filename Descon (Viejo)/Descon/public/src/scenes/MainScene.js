import Player from '../entities/Player.js';
import Enemy from '../entities/Enemy.js';
import SocketManager from '../core/SocketManager.js';
import { GAME_CONFIG, SHIP_MODELS } from '../data/Constants.js';
import UISystem from '../systems/UISystem.js';
import HangarSystem from '../systems/HangarSystem.js';
import AdminSystem from '../systems/AdminSystem.js';
import ShopSystem from '../systems/ShopSystem.js';
import MinimapSystem from '../systems/MinimapSystem.js';

// Mapas Modulares (Architecture v97.50 / v98.20: Rebranded M1-M3)
import GalaxyMap from '../maps/GalaxyMap(M1).js';
import TitanDungeon from '../maps/TitanDungeon(M2).js';
import AncientDungeon from '../maps/AncientDungeon(M3).js';
import VFXSystem from '../systems/VFXSystem.js';
import CombatSystem from '../systems/CombatSystem.js';

export default class MainScene {
    constructor(app) {
        this.app = app;
        this.container = new PIXI.Container();
        this.world = new PIXI.Container();
        this.container.addChild(this.world);
        window.gameScene = this; // Exposición global para sistemas HUD v76.0

        this.worldSize = GAME_CONFIG.worldSize;
        this.entities = {
            players: new Map(),
            remotePlayers: new Map(), // Sincronización v69.11
            enemies: new Map(),
            bullets: new PIXI.Container()
        };
        this.bullets = []; // v117.20: Lista de Lógica para CombatSystem
        this.world.addChild(this.entities.bullets);
        this.currentZone = 1; // v46.0 Zone System

        // Bus de Eventos para comunicación entre sistemas
        this.events = new PIXI.utils.EventEmitter();
        this.isPaused = false;
        this.keys = new Set(); // Mover aquí para evitar errores de timing v52.2
        this.escPressed = false;
        this.f2Pressed = false;
        this.isSelectingAmmo = false;
        this.aiming = { active: false, type: null, startPos: null, currentPos: null, angle: 0 };

        this.init();
    }

    init() { // Modular Map Setup v97.50
        this.createTextures();
        // El mapa se crea dinámicamente según la zona v97.50

        const gameData = window.pendingGameData || {};
        const username = window.loggedUser || 'Piloto';

        console.log("DESCON: Sincronizando datos de sesión...", gameData);
        this.currentZone = gameData.zone || 1; // Hidratación v69.8
        this.worldSize = this.currentZone === 1 ? GAME_CONFIG.worldSize : GAME_CONFIG.worldSize / 2;

        this.hudConfig = gameData.hudConfig || { chat: false, stats: false, minimap: false, skills: false, party: false };
        this.hudPositions = gameData.hudPositions || {}; // v66.0 Persistence Fixed v69.24
        this.isDraggingHUD = false;

        this.hubs = gameData.hubs || 0;
        this.ohculianos = gameData.ohcu || 0;

        this.player = new Player(
            this, 
            window.pendingGameData.lastPos.x, 
            window.pendingGameData.lastPos.y, 
            'ship', 
            window.loggedUser || 'Piloto' // Identidad Real Fix v134.12
        );
        this.player.id = window.loggedId; // Identidad Inmutable v123.50
        this.player.socketId = window.loggedSocketId;
        
        // Carga de Datos Inicial para hidratar sistemas v68.5
        this.player.loadData(gameData);
        this.world.addChild(this.player.container);

        // Proxys de Datos (Sincronizan con Hangar/Shop v22.1)
        this.inventory = this.player.inventory;
        this.equipped = this.player.equipped;
        this.ownedShips = this.player.ownedShips;

        const shipId = this.player.currentShipId || 1;
        this.currentShipModel = SHIP_MODELS.find(m => m.id === shipId) || SHIP_MODELS[0];

        // Recalcular bonificaciones sin sobrescribir el máximo cargado de DB (v68.5 Fix)
        this.player.updateStats(this.currentShipModel, this.player.equipped, true);

        // Inicializar Sistemas Basales
        this.uiSystem = new UISystem(this);
        this.hangarSystem = new HangarSystem(this);
        this.adminSystem = new AdminSystem(this);
        this.shopSystem = new ShopSystem(this);
        this.minimapSystem = new MinimapSystem(this);
        this.vfx = new VFXSystem(this);
        this.combat = new CombatSystem(this);
        
        // Inicializar el Mapa según la zona actual (v97.50)
        this.setupCurrentMap();
        
        // Registro Único de Eventos (v129.40: Prevenir fugas de FPS por listeners duplicados)
        if (!window.hasGlobalEvents) {
            this.initMobileInput(); 
            this.initKeyboardInput(); // Mover aquí v129.40
            window.hasGlobalEvents = true;
        }

        // Registrar Eventos Multiplayer (v69.11 Fix: Removido reinicio de entities que borraba enemigos)
        this.events.on('spawnRemotePlayer', (data) => {
            if (this.entities.remotePlayers.has(data.id)) return;
            const p = new Player(this, data.x, data.y, 'ship', data.user, true); // true = isRemote
            p.id = data.dbId || data.id; // dbId persistente v132.31
            p.sid = data.id; // Socket ID (Conexión)
            p.hp = data.hp;
            p.shield = data.shield;
            p.maxHp = data.maxHp || 2000;
            p.maxShield = data.maxShield || 1000;
            p.latency = data.latency || 0;
            this.entities.remotePlayers.set(data.id, p);
            this.world.addChild(p.container);
            p.drawBars(); // Actualizar HUD inmediatamente con stats reales
            console.log(`DESCON: Avistado piloto remoto: ${data.user}`);
        });

        this.events.on('remotePlayerMoved', (data) => {
            // Anti-Ghosting v73.02: Ignorar si el ID es mi propio socket
            if (this.socketManager && data.id === this.socketManager.socket.id) return;

            let p = this.entities.remotePlayers.get(data.id);
            
            // Si el jugador está en mi zona pero no lo tengo, spawnearlo
            if (!p && data.zone === this.currentZone) {
                p = new Player(this, data.x, data.y, 'ship', data.user, true);
                this.entities.remotePlayers.set(data.id, p);
                this.world.addChild(p.container);
            }

            if (p) {
                const isVisible = (data.zone === this.currentZone);
                p.container.visible = isVisible;
                
                if (isVisible) {
                    p.container.x = data.x;
                    p.container.y = data.y;
                    p.sprite.rotation = data.rotation;
                    p.hp = data.hp;
                    p.shield = data.shield;
                    p.drawBars(); // Refresco visual v145.71
                    p.maxHp = data.maxHp || p.maxHp || 2000;
                    p.maxShield = data.maxShield || p.maxShield || 1000;
                    p.sid = data.id; // Socket ID para compatibilidad HUD v132.50
                    p.id = data.dbId || p.id; // dbId como identificador de lógica
                    p.latency = data.latency;
                    
                    // Asegurar indexación por ID persistente si cambió
                    if (p.id && !this.entities.remotePlayers.has(p.id)) {
                        this.entities.remotePlayers.set(p.id, p);
                    }
                }
            }
        });

        this.events.on('removeRemotePlayer', (id) => {
            const p = this.entities.remotePlayers.get(id);
            if (p) {
                p.container.destroy({ children: true });
                this.entities.remotePlayers.delete(id);
            }
        });

        // Sincronía Total de Vida Server-Authoritative v125.40 (Identity/Socket Aware)
        this.events.on('playerStatSync', (data) => {
            // v145.11: Detección Dinámica de Identidad (Local o Remoto)
            if (this.player && (this.player.id === data.id || this.player.socketId === data.id)) {
                this.player.hp = data.hp;
                this.player.shield = data.shield;
                this.player.drawBars();
            } else {
                // Triple Match v145.11 para Aliados
                let p = this.entities.remotePlayers.get(data.id);
                if (!p) {
                    // Fallback: Buscar por propiedad sid o id interno
                    for (const player of this.entities.remotePlayers.values()) {
                        if (player.sid === data.id || player.id === data.id) {
                            p = player; break;
                        }
                    }
                }

                if (p) {
                    p.hp = data.hp;
                    p.shield = data.shield;
                    p.maxHp = data.maxHp || p.maxHp || 2000;
                    p.maxShield = data.maxShield || p.maxShield || 1000;
                    if (data.isDead && !p.isDead) p.die();
                    p.drawBars();
                }
            }
            if (this.uiSystem) this.uiSystem.forceHUDUpdate();
        });

        this.events.on('enemySpawn', (data) => {
            if (data.zone !== this.currentZone) return; // Filtrado de Zona v46.0
            if (!this.entities.enemies.has(data.id)) {
                this.spawnEnemy(data);
            }
        });

        this.events.on('enemiesMoved', (enemiesData) => {
            Object.keys(enemiesData).forEach(id => {
                let enemy = this.entities.enemies.get(id);
                const data = enemiesData[id];

                // Auto-descubrimiento de enemigos de mi zona v46.3
                if (!enemy && data.zone === this.currentZone) {
                    this.spawnEnemy(data);
                    return;
                }

                if (enemy && !enemy.isDead && enemy.container && enemy.sprite) {
                    // Visibilidad basada en zona
                    enemy.container.visible = (data.zone === this.currentZone);

                        enemy.container.x = data.x;
                        enemy.container.y = data.y;
                        enemy.sprite.rotation = data.rotation || 0;
                        
                        // Sincronía en Vivo de Regeneración v83.0 / v91.10
                        if (data.hp !== undefined) enemy.hp = data.hp;
                        if (data.shield !== undefined) enemy.shield = data.shield;
                        
                // Punto 4: Renderizado de Camuflaje / Modo Ryze / Ancient / Clones v106.30
                if (data.isCountering) {
                    enemy.sprite.tint = 0xff00ff; // Rosa Neón Reflejo
                } else if (data.isRyze || data.type === 5) {
                    enemy.sprite.tint = 0xff0000;
                    enemy.nameTag.text = data.type === 5 ? `ANCIENT BOSS [RAGE MODE]` : `TITAN BOSS [RAGE MODE]`;
                } else if (data.type === 6) {
                    enemy.sprite.tint = 0xbc13fe; // Violeta místico para clones
                    enemy.nameTag.text = `ANCIENT CLONE [LOWER HP]`;
                    enemy.sprite.alpha = 0.8; // Un toque más tenue
                } else if (data.isInvulnerable) {
                    enemy.sprite.alpha = 0.2; // Casi invisible
                } else {
                    enemy.sprite.tint = 0xffffff;
                    enemy.sprite.alpha = data.isCamo ? 0.25 : 1.0;
                    enemy.nameTag.text = data.type === 5 ? `ANCIENT BOSS` : (data.type === 4 ? `TITAN BOSS` : enemy.nameTag.text);
                }
                }
            });
        });

        // Sincronía Táctica v65.0
        this.events.on('enemiesMoved', (enemiesData) => {
            // ... (Lógica de movimiento existente)
        });

        // v116.30: Visuales Delegados al VFXSystem
        this.events.on('bossEffect', (data) => {
            this.vfx.handleBossEffect(data);
        });
        this.events.on('partyUpdate', (party) => {
            this.currentParty = party;
        });

        this.events.on('enemyDamaged', (data) => {
            const enemy = this.entities.enemies.get(data.id);
            if (enemy) {
                enemy.hp = data.hp;
                enemy.shield = data.shield;
                enemy.drawBars(); // Actualizar barras visuales
            }
            // Borrado preventivo de bala por red v73.90
            if (data.bulletId) {
                const bIdx = this.bullets.findIndex(b => b.id === data.bulletId);
                if (bIdx !== -1) {
                    this.bullets[bIdx].life = 0;
                }
            }
        });

        this.events.on('serverEnemyDead', (data) => {
            const enemy = this.entities.enemies.get(data.id);
            if (enemy) {
                // Recompensas...
                const isMyKill = data.killer === this.socketManager.socket.id;
                const isMyTeamShare = data.isShared && data.members.includes(this.socketManager.socket.id);

                if (isMyKill || isMyTeamShare) {
                    this.hubs += data.hubs;
                    this.ohculianos += data.ohcu;
                    if (data.exp && this.player) this.player.addExperience(data.exp);
                    if (window.hudNotify) {
                        const h = data.hubs || 0;
                        const o = data.ohcu || 0;
                        const e = data.exp || 0;
                        const label = isMyTeamShare ? '[GRUPO] ' : '';
                        window.hudNotify(`${label}+${h.toLocaleString()} HUBS`, 'info');
                        if (o > 0) window.hudNotify(`${label}+${o.toLocaleString()} OHCU`, 'info');
                        window.hudNotify(`${label}+${e.toLocaleString()} EXP`, 'info');
                    }
                    this.updateUI();
                    this.saveProgress();
                }

                // Borrar bala que mató al enemigo v73.90
                if (data.bulletId) {
                    const bIdx = this.bullets.findIndex(b => b.id === data.bulletId);
                    if (bIdx !== -1) this.bullets[bIdx].life = 0;
                }

                enemy.die();
                this.entities.enemies.delete(data.id);
            }
        });

        // SINCRONIZACIÓN DE ADMIN EN TIEMPO REAL v38.1 (Fijación de Engineering)
        this.events.on('configUpdated', config => {
            console.log("DESCON: Recibida actualización de configuración global.");

            // Parchear referencias globales sin romper punteros (v5 style)
            if (config.shipModels) {
                config.shipModels.forEach((newShip, i) => {
                    const oldShip = window.SHIP_MODELS.find(s => s.id === newShip.id);
                    if (oldShip) Object.assign(oldShip, newShip);
                });
            }
            if (config.enemyModels) {
                Object.keys(config.enemyModels).forEach(type => {
                    if (window.ENEMY_MODELS[type]) {
                        Object.assign(window.ENEMY_MODELS[type], config.enemyModels[type]);

                        // Actualizar enemigos vivos en caliente (v69.6)
                        this.entities.enemies.forEach(enemy => {
                            if (enemy.type === parseInt(type)) {
                                enemy.config.bulletDamage = window.ENEMY_MODELS[type].bulletDamage;
                                // Nota: HP/Shield no se resetean en caliente para evitar exploits de heal, solo stats ofensivos.
                            }
                        });
                    }
                });
            }

            // Parchear Tienda y Suministros (v43.1 Fix F5)
            if (config.shopItems) {
                Object.keys(config.shopItems).forEach(cat => {
                    if (cat === 'ammo') {
                        // Munición requiere mapeo profundo
                        Object.keys(config.shopItems.ammo).forEach(type => {
                            config.shopItems.ammo[type].forEach((newItem, i) => {
                                if (window.SHOP_ITEMS.ammo[type][i]) Object.assign(window.SHOP_ITEMS.ammo[type][i], newItem);
                            });
                        });
                    } else {
                        config.shopItems[cat].forEach((newItem, i) => {
                            if (window.SHOP_ITEMS[cat][i]) Object.assign(window.SHOP_ITEMS[cat][i], newItem);
                        });
                    }
                });
            }
            if (config.ammoMultipliers) {
                Object.keys(config.ammoMultipliers).forEach(type => {
                    if (window.AMMO_MULTIPLIERS[type]) {
                        config.ammoMultipliers[type].forEach((val, i) => window.AMMO_MULTIPLIERS[type][i] = val);
                    }
                });
            }

            // Recalibrar mi nave si está activa
            if (this.player) {
                const shipId = this.player.currentShipId || 1;
                const updatedModel = window.SHIP_MODELS.find(m => m.id === shipId);
                if (updatedModel) {
                    this.currentShipModel = updatedModel;
                    this.player.updateStats(updatedModel, this.player.equipped);
                    if (window.hudNotify) window.hudNotify("SISTEMAS NAVE RECALIBRADOS EN CALIENTE", 'info');
                }
            }
        });

        this.socketManager = new SocketManager(this);

        // CALIBRACIÓN INICIAL DE ATRIBUTOS v69.20 (Enviar stats reales tras equipos al server)
        console.log("DESCON: Ejecutando sincronía inicial de estadísticas (Pro-Sync)...");
        this.saveProgress(); // Actualizar DB
        this.socketManager.emitMovement({
            x: this.player.container.x,
            y: this.player.container.y,
            rotation: this.player.sprite.rotation,
            hp: this.player.hp,
            shield: this.player.shield,
            maxHp: this.player.maxHp,
            maxShield: this.player.maxShield,
            selectedAmmo: this.player.selectedAmmo,
            zone: this.currentZone
        });

        // LANZAMIENTO INICIAL DE CONFIGURACIÓN (v39.2 - Fix F5)
        if (window.globalAdminConfig) {
            console.log("DESCON: Inyectando configuración persistente de F2...");
            this.events.emit('configUpdated', window.globalAdminConfig);
        }

        // Pool de balas para optimización
        this.bullets = [];

        // Sincronización de Proyectiles v72.05
        this.events.on('playerFire', (data) => {
            if (this.player && this.player.isDead) return;
            this.fireBullet(data); // Spawn local
            if (this.socketManager) this.socketManager.emitFire(data); // Sync al server
        });

        // Sincronización remota (Otras naves disparando)
        this.events.on('remotePlayerFired', (data) => {
            if (data.id === this.socketManager.socket.id) return; // Evitar eco
            this.fireBullet({
                ...data,
                owner: 'remotePlayer'
            });
        });

        this.events.on('serverEnemyFire', (data) => {
            this.fireBullet({
                x: data.x,
                y: data.y,
                angle: data.angle,
                speed: data.speed || 8,
                damage: data.damage || 100,
                type: data.type || 'laser', // Fix v91.0: Permitir misiles
                isHoming: data.isHoming || false,
                targetId: data.targetId,
                life: data.life || 100,
                owner: 'enemy',
                bulletId: data.bulletId
            });
        });

        // Game Loop autorregulado (v69.22 Background Pulse / v97.50 Map Update)
        this.app.ticker.add((delta) => {
            if (!document.hidden) {
                this.update(delta);
                if (this.currentMap) this.currentMap.update(delta, this.player);
            }
        });

        // Hilo de Vida en Segundo Plano (v69.22)
        // Permite que la nave siga moviéndose en piloto automático mientras el usuario está en YouTube
        try {
            const workerCode = `
                let lastTime = Date.now();
                setInterval(() => {
                    const now = Date.now();
                    const dt = (now - lastTime) / (1000/60);
                    lastTime = now;
                    self.postMessage(dt);
                }, 32); // Pulsación de 30FPS en background para ahorrar recursos pero mantener inercia
            `;
            const blob = new Blob([workerCode], { type: 'application/javascript' });
            this.bgWorker = new Worker(URL.createObjectURL(blob));
            this.bgWorker.onmessage = (e) => {
                if (document.hidden && !this.isPaused) {
                    this.update(e.data); // Forzar actualización lógica en background
                }
            };
            console.log("DESCON: Pulso de segundo plano activado (Anti-Throttling).");
        } catch (e) { console.warn("Background Worker no soportado."); }

        // Las recompensas ahora se procesan via serverEnemyDead

        // Autosave Periódico (Dark Orbit Style - Cada 10 segundos)
        setInterval(() => {
            this.saveProgress();
        }, 10000);

        console.log("DESCON v7.5: Pixi World Iniciado.");
    }

    fireBullet(data) {
        const tex = data.type === 'missile' ? 'missile' : (data.type === 'mine' ? 'mine' : 'laser');
        const bullet = new PIXI.Sprite(PIXI.Texture.from(tex));
        bullet.anchor.set(0.5);
        bullet.x = data.x;
        bullet.y = data.y;
        bullet.rotation = data.angle + Math.PI / 2;

        const speed = data.speed || 10;
        bullet.vx = Math.cos(data.angle) * speed;
        bullet.vy = Math.sin(data.angle) * speed;
        bullet.id = data.bulletId; // Sincronía ID v73.90
        bullet.damage = data.damage;
        bullet.type = data.type || 'laser';
        // Sincronía Homing v90.10 / v108.10
        bullet.isHoming = data.isHoming || false;
        bullet.targetId = data.targetId;
        bullet.owner = data.owner || (data.type === 'mine' ? 'enemy' : 'player'); // Asegurar owner v108.10
        bullet.life = data.life || 200; // v128.30: Inicializar vida para evitar NaN en física

        if (data.type === 'mine') {
            bullet.scale.set(1.5);
            // v111.10: Minas Homing YA no son estáticas
            if (!bullet.isHoming) {
                bullet.vx = 0;
                bullet.vy = 0;
            }
        }

        this.entities.bullets.addChild(bullet);
        this.bullets.push(bullet);
    }
    handleInput() {
        if (!this.player) return;
        const isCtrl = this.keys.has('control');
        const isF2 = this.keys.has('f2');

        // Menús Globales (F2 debe detectarse siempre v66.5)
        if (isF2 && !this.f2Pressed) {
            this.f2Pressed = true;
            const hangar = document.getElementById('equipment-menu');
            if (hangar && hangar.style.display === 'block') {
                if (window.toggleEquipmentMenu) window.toggleEquipmentMenu();
            }
            if (this.adminSystem) this.adminSystem.togglePanel();
            return;
        } else if (!isF2) {
            this.f2Pressed = false;
        }

        if (this.isPaused || this.app.isPaused || this.isDraggingHUD) return;

        // v69.38: El toggle de F1 ahora se gestiona vía evento directo en UISystem para evitar race conditions

        if (isCtrl && !this.isSelectingAmmo) this.toggleAmmoSelector(true);
        if (!isCtrl && this.isSelectingAmmo) this.toggleAmmoSelector(false);

        if (this.player && !this.isPaused && !window.isMenuOpen) {
            // Apuntado Pro v73.30: Las teclas en PC ahora apuntan hacia el cursor del mouse
            const pointer = this.app.renderer.events.pointer;
            const worldPos = this.world.toLocal(pointer.global);
            const aimAngle = Math.atan2(worldPos.y - this.player.container.y, worldPos.x - this.player.container.x);

            if (this.keys.has('q')) this.player.fire('laser', aimAngle);
            if (this.keys.has('w')) this.player.fire('missile', aimAngle);
            if (this.keys.has('e')) this.player.fire('mine', aimAngle);
        }
    }

    toggleAmmoSelector(show) {
        if (this.uiSystem && this.uiSystem.showAmmoOverlays) {
            this.uiSystem.showAmmoOverlays(show);
        }
        this.isSelectingAmmo = show;
    }

    // Toggler persistente para móvil v74.30
    toggleAmmoSelection() {
        const state = !this.isSelectingAmmo;
        this.toggleAmmoSelector(state);
        if (window.hudNotify) window.hudNotify(state ? "SELECTOR DE MUNICIÓN ACTIVADO" : "SELECTOR DE MUNICIÓN CERRADO", 'info');
    }
    spawnEnemy(data) {
        const { x, y, type, id, hp, shield } = data;

        // Carga de Datos Boss/Enemigo Unificada (v69.9 Fix HP Mismatch)
        const model = (window.ENEMY_MODELS && window.ENEMY_MODELS[type]) ? window.ENEMY_MODELS[type] : {
            name: `Pirata T${type}`, hp: 2000 * type, shield: 1000 * type, bulletDamage: 100 * type
        };

        const isBoss = (type === 4 || type === 5 || type === 6);
        const config = {
            name: isBoss ? model.name : model.name,
            hp: hp !== undefined ? hp : model.hp,
            shield: shield !== undefined ? shield : model.shield,
            maxHp: model.hp,
            maxShield: model.shield,
            bulletDamage: model.bulletDamage || 100
        };

        const texKey = type === 6 ? 'enemy5' : `enemy${type}`;
        const enemy = new Enemy(this, x, y, texKey, config);
        enemy.type = type;

        // Escala Táctica (v69.9: Solo el sprite, etiquetas estables / v106.40 Ancient/Clone)
        if (isBoss) {
            enemy.sprite.scale.set(3);
            enemy.nameTag.y = -210;
            enemy.shTag.y = -190;
            enemy.hpTag.y = -175;
            // Bars también necesitan subir
            enemy.bars.y = -120; // Elevar barras para que no se pisen con el sprite gigante
        }

        if (id) enemy.id = id;
        this.entities.enemies.set(enemy.id, enemy);
        this.world.addChild(enemy.container);
    }

    spawnBullet(data) {
        const { x, y, angle, type, senderId, ammoType, isHoming, targetId } = data;
        const bullet = new PIXI.Sprite(PIXI.Texture.from(type)); // Fix v144.81: Usar 'type' directamente (laser, missile, mine)
        bullet.anchor.set(0.5);
        bullet.x = x;
        bullet.y = y;
        bullet.rotation = angle + Math.PI / 2;
        
        const speed = type === 'missile' ? 8 : (type === 'mine' ? 2 : 12);
        bullet.vx = Math.cos(angle) * speed;
        bullet.vy = Math.sin(angle) * speed;
        bullet.life = type === 'mine' ? 600 : 100;
        bullet.owner = (senderId === this.socketManager?.socket?.id) ? 'player' : 'remote-player';
        bullet.type = type;
        bullet.id = Math.random().toString(36).substr(2, 9);
        
        // v147.96: Potencia Real Basada en Equipamiento y Talentos
        const baseDmg = (type === 'missile' ? 500 : (type === 'mine' ? 1000 : this.player.laserDamage || 100));
        bullet.damage = baseDmg * (ammoType + 1);
        
        // Atributos Especiales v69.2
        if (isHoming) {
            bullet.isHoming = true;
            bullet.targetId = targetId;
        }

        this.bullets.push(bullet);
        this.world.addChild(bullet);
    }

    setupCurrentMap() {
        if (this.currentMap) this.currentMap.destroy();

        let MapClass = GalaxyMap;
        if (this.currentZone === 2) MapClass = TitanDungeon;
        if (this.currentZone === 3) MapClass = AncientDungeon;

        this.currentMap = new MapClass(this);
        this.currentMap.setup();
        
        this.worldSize = this.currentMap.config.width;
        console.log(`DESCON: Cargando Mapa Modular: ${this.currentMap.config.name} (M${this.currentZone})`);
    }

    createTextures() {
        const g = new PIXI.Graphics();
        
        // Estrellas Realistas (v127.40: Espacio Profundo / Fondo Negro Puro)
        const starSize = 256;
        const starLayer = new PIXI.Graphics();
        starLayer.beginFill(0x000000, 1); // Fondo Negro Absoluto para evitar Gris
        starLayer.drawRect(0, 0, starSize, starSize);
        starLayer.endFill();
        
        // Esparcir estrellitas
        for(let i=0; i<8; i++) {
            const x = Math.random() * starSize;
            const y = Math.random() * starSize;
            const size = 0.5 + Math.random();
            const alpha = 0.3 + Math.random() * 0.7;
            starLayer.beginFill(0xffffff, alpha).drawCircle(x, y, size).endFill();
        }
        
        const starTex = this.app.renderer.generateTexture(starLayer);
        PIXI.Texture.addToCache(starTex, "stars");

        // Ship L1
        g.clear()
            .lineStyle(2, 0x00ffff)
            .beginFill(0x0066cc, 0.7)
            .drawPolygon([20, 5, 35, 35, 20, 25, 5, 35])
            .endFill();

        const shipTex = this.app.renderer.generateTexture(g);
        PIXI.Texture.addToCache(shipTex, 'ship');

        // Enemy 1 (Orange)
        g.clear().lineStyle(2, 0xffa500).beginFill(0x331100, 0.5);
        for (let i = 0; i < 6; i++) {
            const a = (i * 60) * (Math.PI / 180);
            const px = 20 + Math.cos(a) * 18; const py = 20 + Math.sin(a) * 18;
            if (i === 0) g.moveTo(px, py); else g.lineTo(px, py);
        }
        g.closePath().endFill();
        PIXI.Texture.addToCache(this.app.renderer.generateTexture(g), 'enemy1');

        // Enemy 2 (Purple)
        g.clear().lineStyle(2, 0xff00ff).beginFill(0x220022, 0.5);
        for (let i = 0; i < 8; i++) {
            const a = (i * 45) * (Math.PI / 180);
            const px = 20 + Math.cos(a) * 18; const py = 20 + Math.sin(a) * 18;
            if (i === 0) g.moveTo(px, py); else g.lineTo(px, py);
        }
        g.closePath().endFill();
        PIXI.Texture.addToCache(this.app.renderer.generateTexture(g), 'enemy2');

        // Enemy 3 (Red)
        g.clear().lineStyle(3, 0xff3300).beginFill(0x220500, 0.5);
        g.drawRect(5, 5, 30, 30);
        PIXI.Texture.addToCache(this.app.renderer.generateTexture(g), 'enemy3');

        // Enemy 4 (LORD BOSS - Estelar v46.4)
        g.clear().lineStyle(4, 0xff0000).beginFill(0x220000, 0.8);
        const points = [];
        for (let i = 0; i < 12; i++) {
            const rot = (Math.PI / 6) * i;
            const radius = (i % 2 === 0) ? 35 : 15;
            points.push(20 + Math.cos(rot) * radius, 20 + Math.sin(rot) * radius);
        }
        g.drawPolygon(points).endFill();
        g.lineStyle(0).beginFill(0xff3333, 0.4).drawCircle(20, 20, 10).endFill();
        PIXI.Texture.addToCache(this.app.renderer.generateTexture(g), 'enemy4');

        // Ancient Boss Type 5 (Octógono Violeta v101.10)
        g.clear().lineStyle(3, 0xbc13fe).beginFill(0x1a0033, 0.8);
        const sides = 8;
        const pts = [];
        for (let i = 0; i < sides; i++) {
            const a = (i * 360 / sides) * (Math.PI / 180);
            pts.push(20 + Math.cos(a) * 20, 20 + Math.sin(a) * 20);
        }
        g.drawPolygon(pts).endFill();
        // Núcleo de Energía Místico
        g.lineStyle(0).beginFill(0xff00ff, 0.6).drawCircle(20, 20, 8).endFill();
        PIXI.Texture.addToCache(this.app.renderer.generateTexture(g), 'enemy5');

        // Laser
        g.clear().beginFill(0xffff00).drawRect(0, 0, 3, 12).endFill();
        PIXI.Texture.addToCache(this.app.renderer.generateTexture(g), 'laser');

        // Missile
        g.clear().beginFill(0xff6600).drawRoundedRect(0, 0, 6, 18, 3).endFill();
        PIXI.Texture.addToCache(this.app.renderer.generateTexture(g), 'missile');

        // Mine
        g.clear().lineStyle(2, 0xff00ff).beginFill(0x330033).drawCircle(10, 10, 8).endFill();
        PIXI.Texture.addToCache(this.app.renderer.generateTexture(g), 'mine');

        g.destroy();
    }

    initKeyboardInput() {
        console.log("DESCON: Iniciando Sensores de Teclado...");
        window.addEventListener('keydown', (e) => {
            const key = e.key;
            const code = e.code;
            if (key === 'F1' || code === 'F1') e.preventDefault();
            
            // Atajos de Debugging v100.10 (Optimized v129.41)
            if (key === '0' || key === '9') {
                const zone = key === '0' ? 2 : 3;
                if(window.currentScene) window.currentScene.switchZone(window.currentScene.currentZone === zone ? 1 : zone);
            }

            this.keys.add(key.toLowerCase());
            this.keys.add(code.toLowerCase());
        });

        window.addEventListener('keyup', (e) => {
            this.keys.delete(e.key.toLowerCase());
            this.keys.delete(e.code.toLowerCase());
        });
    }
    initMobileInput() {
        this.isMobile = /Mobi|Android|iPhone|iPad/i.test(navigator.userAgent);
        const controls = document.getElementById('mobile-controls');
        if (!this.isMobile) {
            if (controls) controls.style.display = 'none';
            return;
        }

        console.log("DESCON: Tactical Flight & Aiming Active.");
        if (controls) controls.style.display = 'block';

        this.aimGraphics = new PIXI.Graphics();
        this.world.addChild(this.aimGraphics);

        // Joystick dinámico clásico v72.06
        this.joystickBase = new PIXI.Graphics();
        this.joystickThumb = new PIXI.Graphics();
        this.app.stage.addChild(this.joystickBase);
        this.app.stage.addChild(this.joystickThumb);
        this.joystickBase.visible = false;
        this.joystickThumb.visible = false;
        
        // Inicialización de Estados Móviles (Soporte Multi-Touch v72.07)
        this.movementTouchId = null;
        this.aiming = { active: false, type: null, startPos: null, currentPos: null, angle: 0 };

        const onStart = (e) => {
            if (this.isPaused || this.isDraggingHUD || window.isMenuOpen) return;
            
            // Procesar todos los nuevos toques (v72.07)
            const touches = e.changedTouches ? Array.from(e.changedTouches) : [e];
            const rect = this.app.view.getBoundingClientRect();

            touches.forEach(touch => {
                const rect = this.app.view.getBoundingClientRect();
                const tx = (touch.clientX - rect.left);
                const ty = (touch.clientY - rect.top);

                // --- INTEGRACIÓN DE APUNTADO MÓVIL v77.0 ---
                if (touch.target.closest && touch.target.closest('.skill-slot')) {
                    const slot = touch.target.closest('.skill-slot');
                    const type = slot.id.includes('q') ? 'laser' : (slot.id.includes('w') ? 'missile' : 'mine');
                    window.startSkillAim(touch, type);
                    return; // Importante para no interferir con joystick si el slot está en zona joystick
                }

                // Otros elementos de UI (Headers y Drag handles)
                if (touch.target.closest && (touch.target.closest('.hud-header') || touch.target.closest('.hud-icon-btn') || touch.target.closest('.menu-header') || touch.target.closest('.drag-handle'))) return;
                
                // ZONA IZQUIERDA (Joystick): 33% de la pantalla
                if (tx < this.app.screen.width * 0.33 && this.movementTouchId === null) {
                    this.movementTouchId = touch.identifier;
                    this.touchTarget = touch; // Backup para compatibles

                    this.joystickBase.clear()
                        .lineStyle(2, 0x00ffff, 0.3)
                        .drawCircle(0, 0, 60) // Radio 60 = 120px ancho (v5 style)
                        .lineStyle(1, 0x00ffff, 0.1)
                        .drawCircle(0, 0, 30);
                        
                    this.joystickThumb.clear()
                        .beginFill(0x00ffff, 0.5)
                        .drawCircle(0, 0, 30)
                        .endFill();

                    this.joystickBase.position.set(tx, ty);
                    this.joystickThumb.position.set(tx, ty);
                    this.joystickBase.visible = true;
                    this.joystickThumb.visible = true;
                    
                    // Removido v73.06: El movimiento ahora se gestiona en Player.js de forma frame-rate dependent
                }
            });
        };

        const onMove = (e) => {
            if (this.movementTouchId !== null) {
                const touches = e.touches ? Array.from(e.touches) : [e];
                const touch = touches.find(t => t.identifier === this.movementTouchId);
                
                if (touch) {
                    this.touchTarget = touch;
                    
                    if (this.joystickThumb.visible) {
                        const rect = this.app.view.getBoundingClientRect();
                        const tx = (touch.clientX - rect.left);
                        const ty = (touch.clientY - rect.top);
                        
                        const dx = tx - this.joystickBase.x;
                        const dy = ty - this.joystickBase.y;
                        const dist = Math.hypot(dx, dy);
                        const maxDist = 60;
                        
                        const angle = Math.atan2(dy, dx);
                        if (dist > maxDist) {
                            this.joystickThumb.x = this.joystickBase.x + Math.cos(angle) * maxDist;
                            this.joystickThumb.y = this.joystickBase.y + Math.sin(angle) * maxDist;
                        } else {
                            this.joystickThumb.x = tx;
                            this.joystickThumb.y = ty;
                        }
                    }
                    // La lógica de movimiento ahora ocurre dentro del update loop de Player.js
                }
            }
        };

        const onEnd = (e) => {
            if (this.movementTouchId !== null) {
                const touches = e.changedTouches ? Array.from(e.changedTouches) : [e];
                const lifted = touches.some(t => t.identifier === this.movementTouchId);
                
                if (lifted) {
                    this.movementTouchId = null;
                    this.touchTarget = null;
                    this.joystickBase.visible = false;
                    this.joystickThumb.visible = false;
                }
            }
        };

        window.addEventListener('touchstart', onStart, { passive: false });
        window.addEventListener('touchmove', onMove, { passive: false });
        window.addEventListener('touchend', onEnd);

        // --- SISTEMA DE APUNTADO MOBA v69.53 (Relinked v69.62) ---
        window.startSkillAim = (e, type) => {
            if (this.isPaused || window.isMenuOpen) return;
            
            // Forzar cierre de selector si se va a disparar v74.30
            if (this.isSelectingAmmo) this.toggleAmmoSelector(false);

            // Dual Logic v73.18: Compatibilidad total Mouse/Touch
            const touch = (e.changedTouches && e.changedTouches.length > 0) ? e.changedTouches[0] : (e.touches ? e.touches[0] : e);
            const touchId = touch.identifier || 'mouse';

            // Prevenir scroll en slots v74.30
            if (e.cancelable) e.preventDefault();

            this.aiming.active = true;
            this.aiming.type = type;
            this.aiming.startPos = { x: touch.clientX, y: touch.clientY };
            this.aiming.currentPos = { x: touch.clientX, y: touch.clientY };
            this.aiming.angle = (this.player.sprite.rotation - Math.PI / 2); // Iniciar ángulo v76.40

            const aimMove = (ev) => {
                let currentTouch = null;
                for (let i = 0; i < ev.touches.length; i++) {
                    if (ev.touches[i].identifier === touchId) {
                        currentTouch = ev.touches[i]; break;
                    }
                }
                if (currentTouch) {
                    this.aiming.currentPos = { x: currentTouch.clientX, y: currentTouch.clientY };
                    this.updateAimGraphics();
                }
            };

            const aimEnd = (ev) => {
                let lifted = false;
                if (ev.changedTouches) {
                    for (let i = 0; i < ev.changedTouches.length; i++) {
                        if (ev.changedTouches[i].identifier === touchId) lifted = true;
                    }
                }

                if (lifted) {
                    window.removeEventListener('touchmove', aimMove);
                    window.removeEventListener('touchend', aimEnd);
                    this.fireAimedSkill();
                }
            };

            window.addEventListener('touchmove', aimMove, { passive: false });
            window.addEventListener('touchend', aimEnd);
        };
    }

    updateAimGraphics() {
        if (!this.aiming.active || !this.player) return;

        const dx = this.aiming.currentPos.x - this.aiming.startPos.x;
        const dy = this.aiming.currentPos.y - this.aiming.startPos.y;
        const dist = Math.hypot(dx, dy);

        this.aimGraphics.clear();
        if (dist < 10) return;

        this.aiming.angle = Math.atan2(dy, dx);

        // Dibujar Flecha de Apuntado desde el Jugador
        const color = this.aiming.type === 'laser' ? 0x00ffff : (this.aiming.type === 'missile' ? 0xff6600 : 0xff00ff);
        this.aimGraphics.lineStyle(2, color, 0.6);
        this.aimGraphics.moveTo(this.player.container.x, this.player.container.y);

        const length = 150;
        const targetX = this.player.container.x + Math.cos(this.aiming.angle) * length;
        const targetY = this.player.container.y + Math.sin(this.aiming.angle) * length;

        this.aimGraphics.lineTo(targetX, targetY);
        this.aimGraphics.beginFill(color, 0.5).drawCircle(targetX, targetY, 15).endFill();
    }

    fireAimedSkill() {
        if (!this.aiming.active || !this.player) return;

        const dx = this.aiming.currentPos.x - this.aiming.startPos.x;
        const dy = this.aiming.currentPos.y - this.aiming.startPos.y;

        // Si no hay arrastre, disparar al frente
        const angle = Math.hypot(dx, dy) < 15 ? (this.player.sprite.rotation - Math.PI / 2) : this.aiming.angle;

        this.player.fire(this.aiming.type, angle);
        
        // ORIENTAR LA NAVE AL DISPARAR v72.03
        this.player.sprite.rotation = angle + Math.PI / 2;

        this.aiming.active = false;
        this.aimGraphics.clear();
    }

    update(delta) {
        this.handleInput(); // Procesar F2 y teclas siempre v73.25 Critical Recovery
        if (this.player && this.player.isDead) return;

        // Update Entidades
        this.player.update(delta);

        // Seguir al jugador (Cámara manual v73.09: Movida tras el update para evitar saltito/jitter)
        const scale = this.isMobile ? 0.7 : 1.0;
        this.world.scale.set(scale);

        const screenCenterX = this.app.screen.width / 2;
        const screenCenterY = this.app.screen.height / 2;

        this.world.x = screenCenterX - (this.player.container.x * scale);
        this.world.y = screenCenterY - (this.player.container.y * scale);

        // Emitir movimiento al server con Throttling (20Hz v73.05)
        const now = this.app.ticker.lastTime;
        if (this.socketManager && (now - (this.lastMovementEmitTime || 0)) > 50) {
            this.lastMovementEmitTime = now;
            this.socketManager.emitMovement({
                x: this.player.container.x,
                y: this.player.container.y,
                rotation: this.player.sprite.rotation,
                hp: this.player.hp,
                shield: this.player.shield,
                maxHp: this.player.maxHp,
                maxShield: this.player.maxShield,
                selectedAmmo: this.player.selectedAmmo,
                zone: this.currentZone
            });
        }

        // Update Enemigos (v120.30 Cleanup Diferido)
        this.entities.enemies.forEach((e, id) => {
            if (!e || !e.container || e.container.destroyed || e.isDead) {
                if (e && !e.container.destroyed) e.container.destroy({ children: true });
                this.entities.enemies.delete(id);
                return;
            }
            e.update(delta, this.player);
        });

        // v116.30: Combate Sincronizado Delegado (v116.32 Clean)
        this.combat.update(delta);

        // Colisión Jugador-Enemigo (v5 Style)
        this.entities.enemies.forEach(enemy => {
            if (!this.player || !this.player.container || !enemy || !enemy.container || enemy.isDead || enemy.container.destroyed) return; // Null Guard Universal v27.0
            const dist = Math.hypot(this.player.container.x - enemy.container.x, this.player.container.y - enemy.container.y);

            if (dist < 50) {
                const now = Date.now();
                if (now - (this.lastCollisionTime || 0) > 1000) {
                    this.lastCollisionTime = now;

                    // Daño aumentado por Embestida o Modo Ryze (v91.40)
                    let dmg = 200;
                    if (enemy.isRamming || enemy.isRyze) dmg = 1000;

                    this.player.takeDamage(dmg);
                    this.showDamageText(this.player.container.x, this.player.container.y, dmg, true);

                    // Capturar posición ANTES de que el enemigo pueda morir y destruirse
                    const targetX = enemy.container.x;
                    const targetY = enemy.container.y;

                    enemy.takeDamage(100);
                    this.showDamageText(targetX, targetY, 100);

                    this.throttledSave(); // Guardado de Daño Recibido v17.5
                }
            }

            // SEPARACIÓN JUGADOR-ENEMIGO (Estándar v14.0)
            if (enemy && !enemy.isDead && enemy.container && !enemy.container.destroyed) {
                const playerDist = Math.hypot(this.player.container.x - enemy.container.x, this.player.container.y - enemy.container.y);
                const combinedRadius = 60; // Radio sólido estandarizado
                if (playerDist < combinedRadius) {
                    const angle = Math.atan2(enemy.container.y - this.player.container.y, enemy.container.x - this.player.container.x);
                    const push = (combinedRadius - playerDist) * 0.6; // Repulsión equilibrada
                    enemy.container.x += Math.cos(angle) * push;
                    enemy.container.y += Math.sin(angle) * push;
                }
            }

            // SEPARACIÓN ENTRE ENEMIGOS (v14.2 Delegado al Servidor)
            // Desactivado en cliente para evitar jitter. El servidor gestiona el espacio.
        });


        // Update Sistemas
        if (this.minimapSystem) this.minimapSystem.draw();
        if (this.uiSystem) this.uiSystem.update(this.app.ticker.lastTime, delta);

        // Update de Jugadores Remotos (Barras y Movimiento Fluido v142.41)
        this.entities.remotePlayers.forEach(p => p.update(delta));
    }

    switchZone(zoneId) {
        if (this.currentZone === zoneId) return;
        this.currentZone = zoneId;
        
        // Sincronía Modular: Re-setup del mapa v97.50
        this.setupCurrentMap();
        
        // Teletransportar con margen de seguridad (v69.8)
        const spawnPos = zoneId === 1 ? this.worldSize / 2 : 400;
        this.player.container.x = spawnPos;
        this.player.container.y = spawnPos;

        // Notificar al servidor
        if (this.socketManager) this.socketManager.socket.emit('changeZone', zoneId);

        // Limpiar enemigos visualmente (para que reaparezcan los de la nueva zona)
        this.entities.enemies.forEach(e => {
            if (e.container) e.container.destroy();
        });
        this.entities.enemies.clear();

        // Notificación visual Pro
        window.hudNotify(zoneId === 2 ? 'ENTRANDO EN SECTOR BOSS' : 'REGRESANDO A GALAXIA PRINCIPAL', zoneId === 2 ? 'warn' : 'info');

        // Efecto de Flash (v46.0 Warp Effect)
        const flash = new PIXI.Graphics();
        flash.beginFill(0xffffff, 0.4).drawRect(0, 0, this.app.screen.width, this.app.screen.height).endFill();
        this.app.stage.addChild(flash);
        let alpha = 0.4;
        const fade = () => {
            alpha -= 0.05;
            flash.alpha = alpha;
            if (alpha > 0) setTimeout(fade, 30); else flash.destroy();
        };
        fade();
    }

    throttledSave() {
        const now = Date.now();
        if (now - (this.lastSaveTime || 0) > 1000) {
            this.lastSaveTime = now;
            this.saveProgress();
        }
    }

    saveProgress() {
        if (!this.player || !this.socketManager) return;
        
        // v148.28: Sincronización Blindada y Limpieza de Duplicados (AI-Sync)
        const data = {
            hubs: this.hubs || 0,
            ohcu: this.ohculianos || 0,
            inventory: this.player.inventory || [],
            equipped: this.player.equipped || { w: [], s: [], e: [], x: [] },
            ownedShips: this.player.ownedShips || [1],
            maxShips: this.player.maxShips || 2,
            currentShipId: this.player.currentShipId || 1,
            
            // Atributos del Jugador v134.12
            level: this.player.level || 1,
            exp: this.player.exp || 0,
            skillPoints: this.player.skillPoints || 0,
            skillTree: this.player.skillTree || { engineering: [0,0,0,0,0,0,0,0], combat: [0,0,0,0,0,0,0,0], science: [0,0,0,0,0,0,0,0] },
            hp: Math.ceil(this.player.hp || 2000),
            shield: Math.ceil(this.player.shield || 1000),
            maxHp: this.player.maxHp || 2000,
            maxShield: this.player.maxShield || 1000,
            ammo: this.player.ammo || { laser: [0,0,0,0,0,0], missile: [0,0,0,0,0,0], mine: [0,0,0,0,0,0] },
            selectedAmmo: this.player.selectedAmmo || { laser: 0, missile: 0, mine: 0 },
            
            // Configuración de HUD y Locación v69.8
            zone: this.currentZone || 1,
            hudConfig: this.uiSystem ? this.uiSystem.hudConfig : { chat: false, stats: false, minimap: false, skills: false, party: false },
            hudPositions: this.uiSystem ? this.uiSystem.hudPositions : {},
            lastPos: {
                x: Math.floor(this.player.container.x || 2000),
                y: Math.floor(this.player.container.y || 2000)
            }
        };

        this.socketManager.emitSave(data);
        console.log("DESCON: Progresión galáctica guardada en la base de datos.");
    }

    // UNIFICACIÓN DE UI v20.1: Actualiza todos los labels de moneda en el juego
    updateUI() {
        const hVal = this.hubs.toLocaleString();
        const oVal = this.ohculianos.toLocaleString();

        // HUD Principal
        const hHud = document.getElementById('hubs-val');
        const oHud = document.getElementById('ohcu-val');
        if (hHud) hHud.innerText = hVal;
        if (oHud) oHud.innerText = oVal;

        // Modal Hangar
        const hHangar = document.getElementById('shop-hubs-val');
        const oHangar = document.getElementById('shop-ohcu-val');
        if (hHangar) hHangar.innerText = hVal;
        if (oHangar) oHangar.innerText = oVal;

        // Si hay otros paneles (Tienda)
        const hShop = document.getElementById('shop-currency-hubs');
        const oShop = document.getElementById('shop-currency-ohcu');
        if (hShop) hShop.innerText = hVal;
        if (oShop) oShop.innerText = oVal;

        // HUD de Progresión v47.0
        if (this.player) {
            const lvlEl = document.getElementById('level-val');
            const expBar = document.getElementById('exp-bar-fill');
            const expPct = document.getElementById('exp-pct');

            if (lvlEl) lvlEl.innerText = this.player.level;
            if (expBar) {
                const pct = Math.floor((this.player.exp / this.player.nextLevelExp) * 100);
                expBar.style.width = `${pct}%`;
                if (expPct) expPct.innerText = `${pct}%`;
            }
        }
    }

    showDamageText(x, y, amount, isPlayer = false) {
        if (amount <= 0) return; // v69.30 Fix: No mostrar ceros
        const color = isPlayer ? '#ff3333' : '#ff9900';
        const text = new PIXI.Text(`-${Math.ceil(amount)}`, {
            fontFamily: 'Orbitron',
            fontSize: 18,
            fill: color,
            fontWeight: 'bold'
        });
        text.x = x;
        text.y = y - 30;
        text.anchor.set(0.5);
        this.world.addChild(text);

        let life = 60;
        const tick = (delta) => {
            if (text.destroyed) return;
            text.y -= 1 * delta;
            text.alpha -= 0.02 * delta;
            life -= delta;
            if (life <= 0) {
                text.destroy();
                this.app.ticker.remove(tick);
            }
        };
        this.app.ticker.add(tick);
    }

    showLevelUpText(x, y) {
        const text = new PIXI.Text('¡LEVEL UP!', {
            fontFamily: 'Orbitron',
            fontSize: 24,
            fill: ['#ffff00', '#ffaa00'], // Gradiente dorado
            stroke: '#000000',
            strokeThickness: 4,
            fontWeight: 'bold',
            dropShadow: true,
            dropShadowColor: '#ffcc00',
            dropShadowBlur: 10,
            dropShadowDistance: 0
        });
        text.x = x;
        text.y = y;
        text.anchor.set(0.5);
        this.world.addChild(text);

        let life = 100;
        const tick = (delta) => {
            if (text.destroyed) return;
            text.y -= 1.5 * delta;
            text.alpha -= 0.01 * delta;
            text.scale.set(1 + (100 - life) / 200);
            life -= delta;
            if (life <= 0) {
                text.destroy();
                this.app.ticker.remove(tick);
            }
        };
        this.app.ticker.add(tick);
    }
}
