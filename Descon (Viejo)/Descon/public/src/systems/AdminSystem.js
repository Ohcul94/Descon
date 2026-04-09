import { SHIP_MODELS, ENEMY_MODELS, SHOP_ITEMS, AMMO_MULTIPLIERS } from '../data/Constants.js';

/**
 * ADMIN SYSTEM: Controlador maestro para configuración del universo (F2).
 * Conectado a MongoDB a través de SocketManager.
 */
export default class AdminSystem {
    constructor(scene) {
        this.scene = scene;
        this.setup();
    }

    setup() {
        // Exponer constantes y funciones necesarias al objeto window
        window.adminSystem = this;
        window.SHIP_MODELS = SHIP_MODELS;
        window.ENEMY_MODELS = ENEMY_MODELS;
        window.SHOP_ITEMS = SHOP_ITEMS;
        window.AMMO_MULTIPLIERS = AMMO_MULTIPLIERS;
        
        window.saveAdminChanges = () => this.saveChanges();
        window.switchAdminMainTab = (tab) => this.switchTab(tab);
        window.switchAdminSubTab = (main, sub) => this.switchSubTab(main, sub);
        
        this.currentMainTab = 'ships';
        this.currentSubTabs = { shop: 'weapons', ammo: 'laser', enemies: '1' };
    }

    togglePanel() {
        const panel = document.getElementById('master-admin-panel');
        if (!panel) return;
        
        const isVisible = panel.style.display === 'flex';
        panel.style.display = isVisible ? 'none' : 'flex';
        window.isMenuOpen = !isVisible; // v69.34 Bloqueo combat entry
        
        if (!isVisible) {
            this.switchTab('ships');
        }
    }

    switchTab(tab) {
        this.currentMainTab = tab;
        
        // Actualizar visual de pestañas activas v57.2
        document.querySelectorAll('.admin-main-tab').forEach(btn => {
            btn.classList.remove('active');
        });
        const activeBtn = document.getElementById(`admin-tab-${tab}`);
        if (activeBtn) activeBtn.classList.add('active');

        this.render();
    }

    switchSubTab(main, sub) {
        this.currentSubTabs[main] = sub;
        this.render();
    }

    render() {
        const area = document.getElementById('admin-work-area');
        if (!area) return;
        area.innerHTML = '';

        // Renderizar barra de sub-pestañas si el tab principal las requiere
        if (this.currentMainTab === 'items') this.renderSubTabs(area, 'items', ['weapons', 'shields', 'engines', 'extras'], ['ARMAMENTO', 'GENERADORES', 'IMPULSORES', 'EXTRAS']);
        if (this.currentMainTab === 'ammo') this.renderSubTabs(area, 'ammo', ['laser', 'missile', 'mine'], ['LÁSER', 'MISILES', 'MINAS']);
        
        const content = document.createElement('div');
        content.className = 'admin-content-box';
        area.appendChild(content);

        if (this.currentMainTab === 'ships') this.renderShips(content);
        if (this.currentMainTab === 'items') this.renderItems(content, this.currentSubTabs.items || 'weapons');
        if (this.currentMainTab === 'enemies') this.renderEnemies(content);
        if (this.currentMainTab === 'ammo') this.renderAmmo(content, this.currentSubTabs.ammo || 'laser');
    }

    renderSubTabs(container, mainKey, subs, titles) {
        const bar = document.createElement('div');
        bar.style.cssText = 'display:flex; gap:5px; margin-bottom:20px; border-bottom:1px solid rgba(0,255,255,0.1); padding-bottom:10px;';
        subs.forEach((sub, i) => {
            const btn = document.createElement('button');
            const isActive = (this.currentSubTabs[mainKey] || subs[0]) === sub;
            btn.className = 'admin-sub-tab-btn' + (isActive ? ' active' : '');
            btn.innerText = titles[i];
            btn.onclick = () => this.switchSubTab(mainKey, sub);
            bar.appendChild(btn);
        });
        container.appendChild(bar);
    }

    renderShips(container) {
        window.SHIP_MODELS.forEach((ship, i) => {
            const card = document.createElement('div');
            card.className = 'admin-form-card';
            card.innerHTML = `
                <div class="admin-section-title">CONFIGURACIÓN DE CHASIS: ${ship.name.toUpperCase()}</div>
                <div class="admin-grid">
                    <div class="admin-field"><label>DENOMINACIÓN DE NAVE</label><input class="admin-input" type="text" value="${ship.name}" onchange="window.SHIP_MODELS[${i}].name = this.value"></div>
                    <div class="admin-field"><label>INTEGRIDAD DEL CASCO (HP)</label><input class="admin-input" type="number" value="${ship.hp}" onchange="window.SHIP_MODELS[${i}].hp = parseInt(this.value)"></div>
                    <div class="admin-field"><label>POTENCIA DE ESCUDO (SH)</label><input class="admin-input" type="number" value="${ship.shield}" onchange="window.SHIP_MODELS[${i}].shield = parseInt(this.value)"></div>
                    <div class="admin-field"><label>VELOCIDAD DE IMPULSIÓN</label><input class="admin-input" type="number" value="${ship.speed}" onchange="window.SHIP_MODELS[${i}].speed = parseInt(this.value)"></div>
                    <div class="admin-field"><label>SLOTS DE ARMAMENTO (W)</label><input class="admin-input" type="number" value="${ship.slots.w}" onchange="window.SHIP_MODELS[${i}].slots.w = parseInt(this.value)"></div>
                    <div class="admin-field"><label>SLOTS DE GENERADORES (S)</label><input class="admin-input" type="number" value="${ship.slots.s}" onchange="window.SHIP_MODELS[${i}].slots.s = parseInt(this.value)"></div>
                    <div class="admin-field"><label>SLOTS DE MOTORES (E)</label><input class="admin-input" type="number" value="${ship.slots.e}" onchange="window.SHIP_MODELS[${i}].slots.e = parseInt(this.value)"></div>
                    <div class="admin-field"><label>SLOTS EXTRAS / CPU (X)</label><input class="admin-input" type="number" value="${ship.slots.x}" onchange="window.SHIP_MODELS[${i}].slots.x = parseInt(this.value)"></div>
                    <div class="admin-field"><label>COSTO EN CRÉDITOS (HUBS)</label><input class="admin-input" type="number" value="${ship.prices.hubs}" onchange="window.SHIP_MODELS[${i}].prices.hubs = parseInt(this.value)"></div>
                    <div class="admin-field"><label>COSTO EN OHCULIANOS (OHCU)</label><input class="admin-input" type="number" value="${ship.prices.ohcu}" onchange="window.SHIP_MODELS[${i}].prices.ohcu = parseInt(this.value)"></div>
                </div>
            `;
            container.appendChild(card);
        });
    }

    renderItems(container, cat) {
        const items = window.SHOP_ITEMS[cat] || [];
        const titleMap = { weapons: 'ARMAMENTO LÁSER', shields: 'GENERADORES DE ESCUDO', engines: 'PROPULSORES IÓNICOS', extras: 'MÓDULOS ESPECIALES' };
        const baseMap = { weapons: 'PUNTERÍA / DAÑO BASE', shields: 'CAPACIDAD DE ENERGÍA', engines: 'EMPULSE DE VELOCIDAD', extras: 'POTENCIA DEL MÓDULO' };

        items.forEach((item, i) => {
            const card = document.createElement('div');
            card.className = 'admin-form-card';
            card.innerHTML = `
                <div class="admin-section-title">${titleMap[cat]}: ${item.name.toUpperCase()}</div>
                <div class="admin-grid">
                    <div class="admin-field"><label>${baseMap[cat]}</label><input class="admin-input" type="number" value="${item.base}" onchange="window.SHOP_ITEMS['${cat}'][${i}].base = parseInt(this.value)"></div>
                    <div class="admin-field"><label>COSTO DE MERCADO (HUBS)</label><input class="admin-input" type="number" value="${item.prices.hubs}" onchange="window.SHOP_ITEMS['${cat}'][${i}].prices.hubs = parseInt(this.value)"></div>
                    <div class="admin-field"><label>COSTO DE MERCADO (OHCU)</label><input class="admin-input" type="number" value="${item.prices.ohcu}" onchange="window.SHOP_ITEMS['${cat}'][${i}].prices.ohcu = parseInt(this.value)"></div>
                </div>
            `;
            container.appendChild(card);
        });
    }

    renderEnemies(container) {
        Object.keys(ENEMY_MODELS).forEach(type => {
            const enemy = ENEMY_MODELS[type];
            const card = document.createElement('div');
            card.className = 'admin-form-card';
            card.innerHTML = `
                <div class="admin-section-title">ENEMIGO: ${enemy.name.toUpperCase()} (TIPO: ${type})</div>
                <div class="admin-grid">
                    <div class="admin-field"><label>Nombre</label><input class="admin-input" type="text" value="${enemy.name}" onchange="ENEMY_MODELS[${type}].name = this.value"></div>
                    <div class="admin-field"><label>Vida (HP)</label><input class="admin-input" type="number" value="${enemy.hp}" onchange="ENEMY_MODELS[${type}].hp = parseInt(this.value)"></div>
                    <div class="admin-field"><label>Escudo (SH)</label><input class="admin-input" type="number" value="${enemy.shield}" onchange="ENEMY_MODELS[${type}].shield = parseInt(this.value)"></div>
                    <div class="admin-field"><label>Daño Bala</label><input class="admin-input" type="number" value="${enemy.bulletDamage}" onchange="ENEMY_MODELS[${type}].bulletDamage = parseInt(this.value)"></div>
                    <div class="admin-field"><label>Cadencia (ms)</label><input class="admin-input" type="number" value="${enemy.fireRate}" onchange="ENEMY_MODELS[${type}].fireRate = parseInt(this.value)"></div>
                    <div class="admin-field"><label>Recompensa HUBS</label><input class="admin-input" type="number" value="${enemy.rewardHubs}" onchange="window.ENEMY_MODELS['${type}'].rewardHubs = parseInt(this.value)"></div>
                    <div class="admin-field"><label>Recompensa OHCU</label><input class="admin-input" type="number" value="${enemy.rewardOhcu}" onchange="window.ENEMY_MODELS['${type}'].rewardOhcu = parseInt(this.value)"></div>
                    <div class="admin-field"><label>Recompensa EXP</label><input class="admin-input" type="number" value="${enemy.rewardExp || 100}" onchange="window.ENEMY_MODELS['${type}'].rewardExp = parseInt(this.value)"></div>
                </div>
            `;
            container.appendChild(card);
        });
    }

    renderAmmo(container, cat) {
        const multipliers = window.AMMO_MULTIPLIERS[cat] || [];
        const items = window.SHOP_ITEMS.ammo[cat] || [];

        multipliers.forEach((mult, i) => {
            const card = document.createElement('div');
            card.className = 'admin-form-card';
            card.innerHTML = `<div class="admin-section-title">SUMINISTRO: ${cat.toUpperCase()} / CALIBRE T${i+1}</div>`;
            
            const grid = document.createElement('div');
            grid.className = 'admin-grid';
            
            grid.innerHTML += `<div class="admin-field"><label>MULTIPLICADOR DE IMPACTO</label><input class="admin-input" type="number" step="0.1" value="${mult}" onchange="window.AMMO_MULTIPLIERS['${cat}'][${i}] = parseFloat(this.value)"></div>`;
            
            if (items[i]) {
                grid.innerHTML += `<div class="admin-field"><label>PRECIO PACK x100 (HUBS)</label><input class="admin-input" type="number" value="${items[i].prices.hubs}" onchange="window.SHOP_ITEMS.ammo['${cat}'][${i}].prices.hubs = parseInt(this.value)"></div>`;
                grid.innerHTML += `<div class="admin-field"><label>PRECIO PACK x100 (OHCU)</label><input class="admin-input" type="number" value="${items[i].prices.ohcu}" onchange="window.SHOP_ITEMS.ammo['${cat}'][${i}].prices.ohcu = parseInt(this.value)"></div>`;
            }

            card.appendChild(grid);
            container.appendChild(card);
        });
    }

    saveChanges() {
        const config = {
            shipModels: window.SHIP_MODELS,
            enemyModels: window.ENEMY_MODELS,
            shopItems: window.SHOP_ITEMS,
            ammoMultipliers: window.AMMO_MULTIPLIERS
        };

        // Enviar al servidor para persistencia en MongoDB
        this.scene.socketManager.socket.emit('saveAdminConfig', config);
        window.hudNotify("UNIVERSO ACTUALIZADO Y GUARDADO EN MONGODB", 'info');
        this.togglePanel();
    }
}
