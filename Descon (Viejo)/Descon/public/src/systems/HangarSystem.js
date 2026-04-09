import { SHOP_ITEMS } from '../data/Constants.js';

export default class HangarSystem {
    constructor(scene) {
        this.scene = scene;
        this.setup();
    }

    setup() {
        window.equipItem = (itemIdx) => this.handleEquip(itemIdx);
        window.unequipItem = (cat, slotIdx) => this.handleUnequip(cat, slotIdx);
        window.buyShipSlot = () => this.handleBuySlot();
        window.switchShip = (shipId) => this.handleSwitchShip(shipId);
        window.sellItem = (itemIdx) => this.handleSellItem(itemIdx);
    }

    checkCombatLock() {
        const player = this.scene.player;
        if (!player) return false;
        const diff = Date.now() - player.lastCombatTime;
        if (diff < 10000) {
            const remaining = ((10000 - diff) / 1000).toFixed(1);
            window.hudNotify(`SISTEMA BLOQUEADO: EN COMBATE (${remaining}s)`, 'warn');
            return true;
        }
        return false;
    }

    render() {
        const container = document.getElementById('hangar-container');
        if (!container) return;
        container.innerHTML = '';

        const player = this.scene.player;
        const currentModel = this.scene.currentShipModel;

        const layout = document.createElement('div');
        layout.className = 'hangar-layout';
        layout.innerHTML = `
            <div class="hangar-left">
                <div class="fleet-section">
                    <h3 style="font-size:12px; margin-bottom:15px; color:var(--neon-blue);">FLOTA DE COMBATE</h3>
                    <div class="fleet-list">${this.renderFleet()}</div>
                </div>
                <div class="active-ship-section">
                    <div class="ship-header">
                        <h2 style="color:#fff; font-family:'Orbitron'; margin:0;">${currentModel.name.toUpperCase()}</h2>
                        <div class="ship-stats-mini">W:${currentModel.slots.w} S:${currentModel.slots.s} E:${currentModel.slots.e} X:${currentModel.slots.x}</div>
                    </div>
                    <div class="slots-area">
                        ${this.renderSlots('w', currentModel.slots.w, 'BLOQUE DE ARMAMENTO')}
                        ${this.renderSlots('s', currentModel.slots.s, 'GENERADORES DE ESCUDO')}
                        ${this.renderSlots('e', currentModel.slots.e, 'SISTEMAS DE IMPULSIÓN')}
                        ${this.renderSlots('x', currentModel.slots.x, 'MÓDULOS EXTRAS / CPU')}
                    </div>
                </div>
            </div>
            <div class="hangar-right">
                <div class="inventory-section">
                    <h3 style="font-size:12px; margin-bottom:15px; color:var(--neon-blue);">INVENTARIO / BODEGA</h3>
                    <div class="inventory-list">${this.renderInventory()}</div>
                </div>
            </div>
        `;
        container.appendChild(layout);
    }

    renderFleet() {
        let html = '';
        const maxShips = this.scene.player.maxShips || 2;
        for (let i = 0; i < maxShips; i++) {
            const shipId = this.scene.player.ownedShips[i];
            if (shipId) {
                const model = window.SHIP_MODELS.find(m => m.id === shipId);
                const isActive = this.scene.currentShipModel.id === shipId;
                html += `
                    <div class="fleet-card ${isActive ? 'active' : ''}" onclick="${isActive ? '' : `window.switchShip(${shipId})`}">
                        <div class="ship-name">${model.name}</div>
                        <div class="ship-status">${isActive ? 'NAVE ACTIVA' : 'EN HANGAR'}</div>
                    </div>`;
            } else {
                html += `<div class="fleet-card empty"><div class="ship-name">SLOT VACÍO</div><div class="ship-status">SIN ASIGNAR</div></div>`;
            }
        }
        const nextPrice = 1000000 * Math.pow(2, maxShips - 2);
        html += `<div class="fleet-card buy-slot" onclick="window.buyShipSlot()"><div class="ship-name" style="color:var(--neon-green);">+ AMPLIAR FLOTA</div><div class="ship-status">${nextPrice.toLocaleString()} HUBS</div></div>`;
        return html;
    }

    renderSlots(type, count, label) {
        let html = `<div class="slot-group"><label>${label}</label><div class="slots-row">`;
        const catMap = { w: 'weapons', s: 'shields', e: 'engines', x: 'extras' };
        
        for (let i = 0; i < count; i++) {
            const itemId = this.scene.equipped[type][i];
            const item = itemId ? SHOP_ITEMS[catMap[type]]?.find(it => it.id === itemId) : null;
            
            html += `
                <div class="item-slot ${item ? 'filled' : 'empty'}" 
                     onclick="${item ? `window.unequipItem('${type}', ${i})` : ''}">
                    ${item ? `<span class="item-icon" style="font-size:8px;">${item.name}</span>` : '+'}
                </div>`;
        }
        html += `</div></div>`;
        return html;
    }

    renderInventory() {
        if (!this.scene.inventory || this.scene.inventory.length === 0) return '<div class="empty-msg">BODEGA VACÍA</div>';
        return this.scene.inventory.map((item, idx) => `
            <div class="inventory-card" style="display:flex; justify-content:space-between; align-items:center; background: rgba(255,255,255,0.02); padding:8px; margin-bottom:5px; border: 1px solid rgba(0,255,255,0.1);">
                <div>
                    <div class="item-name" style="font-size:10px; color:#fff;">${item.name}</div>
                    <div class="item-type" style="font-size:8px; color:var(--neon-blue);">${item.type === 'w' ? 'ARMA' : (item.type === 's' ? 'ESCUDO' : 'MOTOR')}</div>
                </div>
                <div style="display:flex; gap:5px;">
                    <button onclick="window.equipItem(${idx})" style="padding:4px 8px; font-size:9px; background:rgba(0,255,255,0.1); border:1px solid var(--neon-blue); color:white; cursor:pointer;">EQUIPAR</button>
                    <button onclick="window.sellItem(${idx})" style="padding:4px 8px; font-size:9px; background:rgba(255,0,0,0.1); border:1px solid #ff3333; color:#ff3333; cursor:pointer;">VENDER</button>
                </div>
            </div>
        `).join('');
    }

    handleEquip(idx) {
        if (this.checkCombatLock()) return;
        const item = this.scene.inventory[idx];
        const type = item.type;
        const maxSlots = this.scene.currentShipModel.slots[type];

        if (this.scene.equipped[type].length < maxSlots) {
            this.scene.inventory.splice(idx, 1);
            // v148.13: Guardar solo el ID para persistencia y cálculo de Player.js
            this.scene.equipped[type].push(item.id);
            this.scene.player.updateStats(this.scene.currentShipModel, this.scene.equipped);
            this.saveAndRefresh();
            window.hudNotify(`EQUIPADO: ${item.name}`, 'info');
        } else {
            window.hudNotify(`SIN SLOTS DISPONIBLES`, 'warn');
        }
    }

    handleUnequip(type, slotIdx) {
        if (this.checkCombatLock()) return;
        const itemId = this.scene.equipped[type].splice(slotIdx, 1)[0];
        if (itemId) {
            const catMap = { w: 'weapons', s: 'shields', e: 'engines', x: 'extras' };
            const item = SHOP_ITEMS[catMap[type]]?.find(it => it.id === itemId);
            if (item) this.scene.inventory.push(item);
            
            this.scene.player.updateStats(this.scene.currentShipModel, this.scene.equipped);
            this.saveAndRefresh();
            window.hudNotify(`DESEQUIPADO`, 'info');
        }
    }

    handleBuySlot() {
        const maxShips = this.scene.player.maxShips || 2;
        const price = 1000000 * Math.pow(2, maxShips - 2);
        window.openConfirmModal(`¿Ampliar flota a ${maxShips + 1} naves por ${price.toLocaleString()} HUBS?`, () => {
            if (this.scene.hubs >= price) {
                this.scene.hubs -= price;
                this.scene.player.maxShips += 1;
                this.saveAndRefresh();
            }
        }, "¿AMPLIAR HANGAR?");
    }

    handleSwitchShip(shipId) {
        if (this.checkCombatLock()) return;
        const model = window.SHIP_MODELS.find(m => m.id === shipId);
        if (model) {
            this.scene.currentShipModel = model;
            this.scene.player.currentShipId = shipId;
            this.scene.player.updateStats(model, this.scene.equipped);
            this.saveAndRefresh();
        }
    }

    saveAndRefresh() {
        if (this.scene && this.scene.saveProgress) this.scene.saveProgress();
        this.render();
    }
}
