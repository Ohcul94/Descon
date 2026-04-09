import { SHIP_MODELS, SHOP_ITEMS } from '../data/Constants.js';

/**
 * SHOP SYSTEM: Script independiente para la tienda y transacciones en MongoDB.
 */
export default class ShopSystem {
    constructor(scene) {
        this.scene = scene;
        this.setup();
    }

    setup() {
        // Exponer funciones globales para los botones del HTML
        window.buyItem = (cat, index, cur) => this.handleBuy(cat, index, cur);
        window.buyShip = (index, cur) => this.handleBuyShip(index, cur);
        window.buyAmmo = (type, index, cur) => this.handleBuyAmmo(type, index, cur);
        
        // v147.91: Navegación y Reinicio Táctico (Costo: 5000 OHCU)
        window.switchShopTab = (tab) => this.render(tab);
        window.resetSkills = () => this.handleReset();
        
        // v45.3: Función de cálculo en vivo para el modal de munición
        window.updateAmmoLiveTotal = (unitPrice, currency) => {
            const input = document.getElementById('ammo-live-qty');
            const totalEl = document.getElementById('ammo-live-total');
            if (input && totalEl) {
                const qty = Math.max(0, parseInt(input.value) || 0);
                const total = qty * unitPrice;
                totalEl.innerHTML = `${unitPrice.toLocaleString()} x ${qty.toLocaleString()} = <span style="color:${currency==='hubs'?'#00ffff':'#ff33ff'}; font-weight:bold;">${total.toLocaleString()} ${currency.toUpperCase()}</span>`;
            }
        };
    }

    render(tab = 'ships') {
        const container = document.getElementById('shop-container');
        if (!container) return;
        container.innerHTML = '';

        this.currentTab = tab;
        
        // Actualizar SALDO en el HTML (Tienda)
        const shopHubs = document.getElementById('shop-hubs-val');
        const shopOhcu = document.getElementById('shop-ohcu-val');
        if (shopHubs) shopHubs.innerText = (this.scene.hubs || 0).toLocaleString();
        if (shopOhcu) shopOhcu.innerText = (this.scene.ohculianos || 0).toLocaleString();

        // Actualizar Clase Active en los Tabs visuales
        document.querySelectorAll('.shop-sub-tab').forEach(el => {
            const elId = el.id.replace('tab-s-', '');
            el.classList.toggle('active', elId === tab);
        });

        if (tab === 'ships') {
            this.renderCategory(container, 'Naves (Flota)', SHIP_MODELS, 'ships');
        } else if (tab === 'ammo') {
            this.renderAmmoSections(container);
        } else {
            const data = SHOP_ITEMS[tab];
            const titles = { weapons: 'Armas Láser', shields: 'Generadores de Escudo', engines: 'Impulsores de Motor' };
            this.renderCategory(container, titles[tab] || tab.toUpperCase(), data, tab);
        }
    }

    renderAmmoSections(container) {
        if (!this.currentAmmoSubTab) this.currentAmmoSubTab = 'laser';
        
        const section = document.createElement('div');
        section.className = 'shop-category-section';
        section.innerHTML = `
            <div style="margin-bottom:20px; border-bottom:1px solid rgba(0,255,255,0.05); padding-bottom:10px;">
                <h3 class="shop-title" style="margin:0; font-size:16px;">PARRILLA DE SUMINISTROS</h3>
            </div>
        `;
        
        // Sub-tabs de munición (Láser, Misiles, Minas)
        const subTabs = document.createElement('div');
        subTabs.className = 'ammo-tabs';
        subTabs.style.cssText = 'display:flex; gap:10px; margin-bottom:20px; border-bottom:1px solid rgba(0,255,255,0.1); padding-bottom:5px;';
        
        ['laser', 'missile', 'mine'].forEach(type => {
            const btn = document.createElement('div');
            btn.className = 'shop-sub-tab' + (this.currentAmmoSubTab === type ? ' active' : '');
            btn.innerText = type.toUpperCase();
            btn.style.cursor = 'pointer';
            btn.onclick = () => { this.currentAmmoSubTab = type; this.render('ammo'); };
            subTabs.appendChild(btn);
        });
        section.appendChild(subTabs);

        const grid = document.createElement('div');
        grid.className = 'shop-grid';
        
        const ammoList = SHOP_ITEMS.ammo[this.currentAmmoSubTab] || [];
        ammoList.forEach((item, idx) => {
            grid.appendChild(this.createCard(item, 'ammo', idx, true));
        });
        
        section.appendChild(grid);
        container.appendChild(section);
    }

    switchTab(tab) {
        this.render(tab);
    }

    renderCategory(container, title, items, cat, isAmmo = false) {
        const section = document.createElement('div');
        section.className = 'shop-category-section';
        section.innerHTML = `<h3 class="shop-title">${title.toUpperCase()}</h3>`;
        
        const grid = document.createElement('div');
        grid.className = 'shop-grid';
        
        if (items) {
            items.forEach((item, idx) => {
                grid.appendChild(this.createCard(item, cat, idx, isAmmo));
            });
        }
        section.appendChild(grid);
        container.appendChild(section);
    }

    createCard(item, cat, idx, isAmmo) {
        const div = document.createElement('div');
        div.className = 'shop-card';
        const isShip = cat === 'ships';
        const isOwned = isShip && this.scene.ownedShips && this.scene.ownedShips.includes(item.id);
        
        let priceH = item.prices.hubs;
        let priceO = item.prices.ohcu;

        const buyFn = isAmmo ? `window.buyAmmo('${this.currentAmmoSubTab}', ${idx},` : (isShip ? `window.buyShip(${idx},` : `window.buyItem('${cat}', ${idx},`);
        
        div.innerHTML = `
            <div class="item-name">${item.name}</div>
            <div class="item-desc" style="font-size:10px; color:#888; margin-bottom:10px;">
                ${isAmmo ? `<div style="color:var(--neon-blue);">VALOR POR UNIDAD</div>` : (item.desc || '')}
            </div>
            
            ${isOwned ? `
                <div class="owned-tag" style="background:rgba(0,255,0,0.1); border:1px solid var(--neon-green); color:var(--neon-green); padding:10px; text-align:center; font-family:'Orbitron'; font-size:10px; letter-spacing:1px;">
                    ESTA NAVE YA SE ENCUENTRA EN TU FLOTA
                </div>
            ` : `
                <div class="dual-prices">
                    ${priceH > 0 || (isAmmo && item.prices.hubs > 0) ? `
                        <div class="price hubs" onclick="${buyFn} 'hubs')" style="display:flex; flex-direction:column; gap:2px;">
                            <span style="font-size:14px;">${isAmmo ? Math.ceil(priceH/100) : priceH.toLocaleString()} HUBS</span>
                        </div>
                    ` : `<div class="price hubs locked" style="opacity:0.3; cursor:not-allowed;">BLOQUEADO</div>`}
                    
                    ${priceO > 0 || (isAmmo && item.prices.ohcu > 0) ? `
                        <div class="price ohcu" onclick="${buyFn} 'ohcu')" style="display:flex; flex-direction:column; gap:2px;">
                            <span style="font-size:14px;">${isAmmo ? Math.ceil(priceO/100) : priceO.toLocaleString()} OHCU</span>
                        </div>
                    ` : `<div class="price ohcu locked" style="opacity:0.3; cursor:not-allowed;">BLOQUEADO</div>`}
                </div>
            `}
        `;
        return div;
    }

    handleBuy(cat, idx, cur) {
        const item = window.SHOP_ITEMS[cat][idx]; // Referencia Global v42.1
        const price = item.prices[cur];
        const wallet = cur === 'hubs' ? this.scene.hubs : this.scene.ohculianos;

        const detail = `¿Deseas adquirir <b>${item.name}</b> por <span style="color:${cur === 'hubs' ? '#00ffff' : '#ff00ff'}">${price.toLocaleString()} ${cur.toUpperCase()}</span>?`;

        window.openConfirmModal(detail, () => {
            if (wallet >= price) {
                this.scene[cur === 'hubs' ? 'hubs' : 'ohculianos'] -= price;
                this.scene.inventory.push({ ...item, type: cat[0], instanceId: Date.now() });
                
                this.scene.saveProgress(); // Guardado Atómico v17.0
                this.render(cat);
                
                window.showResultModal(`Has adquirido <b>${item.name}</b> de forma exitosa. El ítem se encuentra en tu bodega.`, '¡ADQUISICIÓN COMPLETADA!');
            } else {
                window.hudNotify('FONDOS INSUFICIENTES', 'warn');
            }
        });
    }

    handleBuyShip(idx, cur) {
        const ship = window.SHIP_MODELS[idx]; // Referencia Global v42.1
        if (this.scene.ownedShips.includes(ship.id)) return;
        
        const price = ship.prices[cur];
        const detail = `¿Deseas adquirir la nave <b>${ship.name}</b> por <span style="color:${cur === 'hubs' ? '#00ffff' : '#ff00ff'}">${price.toLocaleString()} ${cur.toUpperCase()}</span>?`;

        window.openConfirmModal(detail, () => {
            const wallet = cur === 'hubs' ? this.scene.hubs : this.scene.ohculianos;
            if (wallet >= price) {
                this.scene[cur === 'hubs' ? 'hubs' : 'ohculianos'] -= price;
                this.scene.ownedShips.push(ship.id);
                this.scene.saveProgress(); // Guardado Atómico v17.0
                this.render('ships');
                window.showResultModal(`La nave <b>${ship.name}</b> ya está disponible en tu flota.`, '¡FLOTA AMPLIADA!');
            } else {
                window.hudNotify('FONDOS INSUFICIENTES', 'warn');
            }
        });
    }

    handleBuyAmmo(type, idx, cur) {
        const item = window.SHOP_ITEMS.ammo[type][idx];
        const unitPrice = Math.ceil(item.prices[cur] / 100);
        
        // Modal de Suministros v45.3 (Cálculo en Vivo y Compra Directa)
        const quantityHtml = `
            <div style="font-family:'Orbitron'; color:white; padding:10px; text-align:center;">
                <div style="font-size:11px; color:var(--neon-blue); margin-bottom:15px; letter-spacing:1px;">RECARGA: ${item.name.toUpperCase()}</div>
                <div style="font-size:10px; color:#888; margin-bottom:10px;">SELECCIONÁ LA CANTIDAD DE UNIDADES:</div>
                <input type="number" id="ammo-live-qty" value="1000" step="500" min="1" 
                       oninput="window.updateAmmoLiveTotal(${unitPrice}, '${cur}')"
                       style="width:100%; background:rgba(0,0,0,0.7); border:2px solid var(--neon-blue); color:white; font-family:'Orbitron'; font-size:24px; padding:12px; text-align:center; outline:none; box-shadow:0 0 20px rgba(0,255,255,0.15); margin-bottom:20px;">
                
                <div id="ammo-live-total" style="font-size:14px; color:#aaa; font-family:'Orbitron'; border-top:1px solid rgba(255,255,255,0.05); padding-top:15px;">
                    ${unitPrice.toLocaleString()} x 1.000 = <span style="color:${cur==='hubs'?'#00ffff':'#ff33ff'}; font-weight:bold;">${(unitPrice * 1000).toLocaleString()} ${cur.toUpperCase()}</span>
                </div>
                <div style="font-size:9px; color:#555; margin-top:10px; font-style:italic;">* El total se acreditará inmediatamente al procesar</div>
            </div>
        `;

        window.openConfirmModal(quantityHtml, () => {
            const qtyInput = document.getElementById('ammo-live-qty');
            const qtyNum = Math.max(1, parseInt(qtyInput ? qtyInput.value : 1000));
            const totalPrice = qtyNum * unitPrice;

            const wallet = cur === 'hubs' ? this.scene.hubs : this.scene.ohculianos;
            if (wallet >= totalPrice) {
                this.scene[cur === 'hubs' ? 'hubs' : 'ohculianos'] -= totalPrice;
                
                if (this.scene.player && this.scene.player.ammo) {
                    this.scene.player.ammo[type][item.tier] += qtyNum;
                }
                
                this.scene.saveProgress();
                this.render('ammo');
                
                // Éxito Directo (v45.3)
                setTimeout(() => {
                    window.showResultModal(`Se han acreditado <b>${qtyNum.toLocaleString()}</b> unidades de <b>${item.name}</b> en tu bodega táctica por un total de <b>${totalPrice.toLocaleString()} ${cur.toUpperCase()}</b>.`, '¡SUMINISTROS RECIBIDOS!');
                }, 100);
            } else {
                window.hudNotify('FONDOS INSUFICIENTES', 'warn');
            }
        }, 'CONFIRMAR RECARGA DIRECTA');
    }

    // switchShip movido a HangarSystem.js v34.0
}
