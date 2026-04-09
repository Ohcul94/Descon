import { SHOP_ITEMS } from '../data/Constants.js';

export default class Player {
    constructor(scene, x, y, texture, userData, isRemote = false) {
        this.scene = scene;
        this.isRemote = isRemote;
        this.container = new PIXI.Container();
        this.container.x = x;
        this.container.y = y;

        this.sprite = new PIXI.Sprite(PIXI.Texture.from(texture));
        this.sprite.anchor.set(0.5);
        this.container.addChild(this.sprite);

        this.userData = userData;
        this.activeShip = true;
        this.isInvulnerable = true;
        
        this.hp = 2000;
        this.maxHp = 2000;
        this.shield = 1000;
        this.maxShield = 1000;
        this.speed = 300;
        this.vx = 0;
        this.vy = 0;

        this.lastShootTimes = { laser: 0, missile: 0, mine: 0 };
        this.shootDelays = { laser: 500, missile: 4000, mine: 10000 };
        this.laserDamage = 100; // Daño base mínimo

        this.cooldowns = { q: 0, w: 0, e: 0 };
        this.ammo = { laser: [1000,0,0,0,0,0], missile: [50,0,0,0,0,0], mine: [10,0,0,0,0,0] };
        this.selectedAmmo = { laser: 0, missile: 0, mine: 0 };

        // Atributos de Progresión v47.0
        this.level = 1;
        this.exp = 0;
        this.nextLevelExp = 1000;
        this.skillPoints = 0; // v69.26
        this.skillTree = {
            engineering: [0, 0, 0, 0, 0, 0, 0, 0],
            combat: [0, 0, 0, 0, 0, 0, 0, 0],
            science: [0, 0, 0, 0, 0, 0, 0, 0]
        };

        // Inventario y Equipo (Architecture v134.12 Rescue)
        this.inventory = [];
        this.equipped = { w: [], s: [], e: [], x: [] };
        this.ownedShips = [1];
        this.maxShips = 2;
        this.currentShipId = 1;

        // Inactividad de Combate v62.0
        this.lastCombatTime = 0; 

        // Piloto Automático v66.7
        this.isAutopilotActive = false;
        this.autopilotTarget = null;
        this.lastAutopilotSetTime = 0;

        this.latency = 0;
        this.createHUD();
    }

    createHUD() {
        const name = (this.userData && typeof this.userData === 'object') ? (this.userData.user || 'Piloto') : (this.userData || 'Piloto');
        this.nameTag = new PIXI.Text(name, { 
            fontFamily: 'Orbitron', 
            fontSize: 13, 
            fill: 0xffffff, 
            align: 'center', 
            fontWeight: 'bold' 
        });
        this.nameTag.anchor.set(0.5);
        this.nameTag.y = -86;
        this.container.addChild(this.nameTag);

        this.shTag = new PIXI.Text(`SH: ${this.shield}`, { 
            fontFamily: 'Rajdhani', 
            fontSize: 11, 
            fill: 0xffffff, 
            align: 'center' 
        });
        this.shTag.anchor.set(0.5);
        this.shTag.y = -72;
        this.container.addChild(this.shTag);

        this.hpTag = new PIXI.Text(`HP: ${this.hp}`, { 
            fontFamily: 'Rajdhani', 
            fontSize: 11, 
            fill: 0xffffff, 
            align: 'center' 
        });
        this.hpTag.anchor.set(0.5);
        this.hpTag.y = -60;
        this.container.addChild(this.hpTag);

        this.bars = new PIXI.Graphics();
        this.container.addChild(this.bars);

        // Sistema de Burbujas de Chat v60.0
        this.chatBubble = new PIXI.Container();
        this.chatBubble.y = -110;
        this.chatBubble.visible = false;
        this.container.addChild(this.chatBubble);

        this.chatBg = new PIXI.Graphics();
        this.chatBubble.addChild(this.chatBg);

        this.chatText = new PIXI.Text('', {
            fontFamily: 'Outfit',
            fontSize: 11,
            fill: 0xffffff,
            align: 'center',
            wordWrap: true,
            wordWrapWidth: 150
        });
        this.chatText.anchor.set(0.5);
        this.chatBubble.addChild(this.chatText);
    }

    setAutopilot(x, y) {
        this.isAutopilotActive = true;
        this.autopilotTarget = { x, y };
        this.lastAutopilotSetTime = Date.now();
        if (window.hudNotify) window.hudNotify("SISTEMA DE NAVEGACIÓN: CURSO FIJADO", 'info');
    }

    showChatBubble(text) {
        if (!text) return;
        
        this.chatText.text = text;
        
        const padding = 10;
        const width = Math.max(40, this.chatText.width + padding * 2);
        const height = this.chatText.height + padding;

        this.chatBg.clear();
        this.chatBg.beginFill(0x000000, 0.7);
        this.chatBg.lineStyle(1, 0x00ffff, 0.5);
        this.chatBg.drawRoundedRect(-width / 2, -height / 2, width, height, 5);
        this.chatBg.endFill();

        this.chatBubble.visible = true;

        if (this.bubbleTimeout) clearTimeout(this.bubbleTimeout);
        this.bubbleTimeout = setTimeout(() => {
            this.chatBubble.visible = false;
        }, 3000);
    }

    update(delta) {
        if (!this.activeShip || this.isDead) return;

        const now = Date.now();
        if (!this.isRemote && now - this.lastCombatTime > 5000) {
            let regenHP = (this.maxHp * 0.01) * (delta / 60);
            let regenSH = (this.maxShield * 0.02) * (delta / 60);
            
            if (this.hp < this.maxHp) this.hp = Math.min(this.maxHp, this.hp + regenHP);
            if (this.shield < this.maxShield) this.shield = Math.min(this.maxShield, this.shield + regenSH);
        }

        this.drawBars();

        if (this.isRemote) return;

        let isBoosting = false;
        let angle = this.sprite ? (this.sprite.rotation - Math.PI / 2) : 0;
        let mouse = null;

        if (this.scene.isMobile) {
            if (this.scene.movementTouchId !== null && this.scene.touchTarget) {
                const rect = this.scene.app.view.getBoundingClientRect();
                const tx = this.scene.touchTarget.clientX - rect.left;
                const ty = this.scene.touchTarget.clientY - rect.top;
                
                const dx = tx - this.scene.joystickBase.x;
                const dy = ty - this.scene.joystickBase.y;
                const dist = Math.hypot(dx, dy);
                
                if (dist > 2) {
                    angle = Math.atan2(dy, dx);
                    if (dist > 5) isBoosting = true;
                }
            }
        } else {
            mouse = this.scene.app.renderer.events.pointer;
            if (mouse && !window.isMenuOpen) {
                const worldMouseX = mouse.x - this.scene.app.screen.width / 2 + this.container.x;
                const worldMouseY = mouse.y - this.scene.app.screen.height / 2 + this.container.y;
                angle = Math.atan2(worldMouseY - this.container.y, worldMouseX - this.container.x);
                isBoosting = (mouse.buttons === 1);
            }
        }
        
        if (this.isAutopilotActive && this.autopilotTarget) {
            const dx = this.autopilotTarget.x - this.container.x;
            const dy = this.autopilotTarget.y - this.container.y;
            const dist = Math.sqrt(dx*dx + dy*dy);
            
            if (dist < 50) {
                this.isAutopilotActive = false;
                if (window.hudNotify) window.hudNotify("SISTEMA DE NAVEGACIÓN: DESTINO ALCANZADO", 'success');
            } else {
                angle = Math.atan2(dy, dx);
                isBoosting = true;
                
                const nowAutopilot = Date.now();
                if (isBoosting && (nowAutopilot - (this.lastAutopilotSetTime || 0) > 300)) {
                    const manualInput = this.scene.isMobile ? (this.scene.movementTouchId !== null) : (mouse && mouse.buttons === 1);
                    if (manualInput) {
                        this.isAutopilotActive = false;
                        if (window.hudNotify) window.hudNotify("SITUACIÓN TÁCTICA: CONTROL MANUAL RECUPERADO", 'warn');
                    }
                }
            }
        }

        let visualRotationAngle = angle; 
        if (this.scene.isMobile && this.scene.aiming && this.scene.aiming.active) {
            visualRotationAngle = this.scene.aiming.angle;
        }

        if (!this.scene.isDraggingHUD && !window.isMenuOpen) {
            if (!this.scene.isMobile || isBoosting || this.isAutopilotActive || this.scene.aiming.active) {
                this.sprite.rotation = visualRotationAngle + Math.PI / 2;
            }

            if (isBoosting) { 
                const accel = (this.speed / 600);
                this.vx += Math.cos(angle) * accel * delta;
                this.vy += Math.sin(angle) * accel * delta;
            }
        }

        const friction = Math.pow(0.95, delta);
        this.vx *= friction;
        this.vy *= friction;

        this.container.x += this.vx * delta;
        this.container.y += this.vy * delta;

        this.container.x = Math.max(0, Math.min(this.scene.worldSize, this.container.x));
        this.container.y = Math.max(0, Math.min(this.scene.worldSize, this.container.y));
    }

    fire(type = 'laser', overrideAngle = null) {
        const now = Date.now();
        if (window.isMenuOpen) return; 
        if (now - this.lastShootTimes[type] < this.shootDelays[type]) return;

        if (this.ammo[type] && this.ammo[type][this.selectedAmmo[type]] <= 0) {
            if (window.hudNotify) {
                window.hudNotify(`¡SIN SUMINISTROS DE ${type.toUpperCase()} T${this.selectedAmmo[type] + 1}!`, 'warn');
            }
            return;
        }

        this.lastShootTimes[type] = now;
        const angle = overrideAngle !== null ? overrideAngle : (this.sprite.rotation - Math.PI / 2);
        const totalDmg = this.laserDamage;

        this.scene.socketManager.socket.emit('shoot', { 
            type: type, 
            x: this.container.x, 
            y: this.container.y, 
            angle: angle,
            ammoType: this.selectedAmmo[type],
            damageBoost: totalDmg
        });
        
        // v143.61: Spawn Local para Feedback Instantáneo
        if (this.scene.spawnBullet) {
            this.scene.spawnBullet({
                x: this.container.x,
                y: this.container.y,
                angle: angle,
                type: type,
                senderId: this.scene.socketManager.socket.id,
                ammoType: this.selectedAmmo[type]
            });
        }

        this.ammo[type][this.selectedAmmo[type]]--;
        if (this.scene.uiSystem) this.scene.uiSystem.forceHUDUpdate();
    }

    drawBars() {
        if (this.isDead || !this.bars || this.bars.destroyed) return;
        this.shTag.text = `SH: ${Math.ceil(this.shield)}`;
        this.shTag.visible = this.shield > 0;
        this.hpTag.text = `HP: ${Math.ceil(this.hp)}`;

        this.bars.clear();
        const hpPct = this.hp / this.maxHp;
        const shPct = this.shield / this.maxShield;
        
        const barW = 44; 
        const gap = 2;   
        const segments = 4; 
        const segW = (barW - (gap * (segments - 1))) / segments;

        for (let i = 0; i < segments; i++) {
            const x = -(barW / 2) + (i * (segW + gap));
            this.bars.beginFill(0x003333, 0.4).drawRect(x, -51, segW, 3).endFill();
            const shFill = Math.max(0, Math.min(1, (shPct * barW - (i * (segW + gap))) / segW));
            if (shFill > 0) this.bars.beginFill(0x00ffff, 1).drawRect(x, -51, segW * shFill, 3).endFill();
            
            this.bars.beginFill(0x330000, 0.4).drawRect(x, -43, segW, 3).endFill();
            const hpFill = Math.max(0, Math.min(1, (hpPct * barW - (i * (segW + gap))) / segW)); 
            if (hpFill > 0) this.bars.beginFill(hpPct > 0.3 ? 0x00ff00 : 0xff0000, 1).drawRect(x, -43, segW * hpFill, 3).endFill();
        }
    }

    takeDamage(amt) {
        if (this.isDead) return;
        if (this.shield >= amt) {
            this.shield -= amt;
        } else {
            const diff = amt - this.shield;
            this.hp -= diff;
            this.shield = 0;
        }
        if (this.hp <= 0) {
            this.hp = 0;
            this.die();
        }
        this.drawBars();
        this.lastCombatTime = Date.now();
    }

    die() {
        if (this.isDead) return;
        this.isDead = true;
        this.container.visible = false;
        if (window.hudNotify) window.hudNotify("¡NAVE DESTRUIDA! Teletransportando a base...", "error");
        setTimeout(() => this.respawn(), 3000);
    }

    respawn() {
        this.hp = this.maxHp;
        this.shield = this.maxShield;
        this.container.x = 2000;
        this.container.y = 2000;
        this.container.visible = true;
        this.isDead = false;
        this.drawBars();
        if (this.scene && this.scene.saveProgress) this.scene.saveProgress();
    }

    updateStats(model, equipped, isInitialScan = false) {
        if (!model) return;
        const baseHp = model.hp || 2000;
        const baseShield = model.shield || 1000;
        this.maxHp = baseHp;
        this.maxShield = baseShield;
        this.speed = model.speed || 300;
        this.laserDamage = 100;
        if (equipped) {
            const findItem = (id, cat) => {
                const targetId = (typeof id === 'string') ? id : id?.id;
                return SHOP_ITEMS[cat].find(i => i.id === targetId);
            };
            
            if (equipped.w) equipped.w.forEach(id => { 
                const item = findItem(id, 'weapons');
                if (item?.base) this.laserDamage += item.base; 
            });
            if (equipped.s) equipped.s.forEach(id => { 
                const item = findItem(id, 'shields');
                if (item?.base) this.maxShield += item.base; 
            });
            if (equipped.e) equipped.e.forEach(id => { 
                const item = findItem(id, 'engines');
                if (item?.base) this.speed += item.base; 
            });
        }
        const engBonus = (this.skillTree.engineering.reduce((a, b) => a + b, 0)) * 0.02; // v147.73: Suma de 8 Niveles
        this.maxHp *= (1 + engBonus);
        this.maxShield *= (1 + engBonus);
        const comBonus = (this.skillTree.combat.reduce((a, b) => a + b, 0)) * 0.03; // v147.73: Suma de 8 Niveles
        this.laserDamage *= (1 + comBonus);
        const sciBonus = (this.skillTree.science.reduce((a, b) => a + b, 0)) * 0.015; // v147.73: Suma de 8 Niveles
        this.speed *= (1 + sciBonus);
        if (isInitialScan) {
            if (this.hp > this.maxHp) this.maxHp = this.hp; 
            if (this.shield > this.maxShield) this.maxShield = this.shield; 
        }
        this.drawBars();
    }

    loadData(data) {
        if (data.level) this.level = data.level;
        if (data.exp) this.exp = data.exp;
        if (data.nextLevelExp) this.nextLevelExp = data.nextLevelExp;
        if (data.skillPoints !== undefined) this.skillPoints = data.skillPoints;
        if (data.skillTree) this.skillTree = data.skillTree;
        if (data.hp) this.hp = data.hp;
        if (data.shield) this.shield = data.shield;
        if (data.ammo) this.ammo = data.ammo;
        
        // PERSISTENCIA DE FLOTA Y BODEGA v134.12
        if (data.inventory) this.inventory = data.inventory;
        if (data.equipped) this.equipped = data.equipped;
        if (data.ownedShips) this.ownedShips = data.ownedShips;
        if (data.maxShips) this.maxShips = data.maxShips;
        if (data.currentShipId) this.currentShipId = data.currentShipId;

        this.drawBars();
    }
}
