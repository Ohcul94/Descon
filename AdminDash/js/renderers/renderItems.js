// AdminDash/js/renderers/renderItems.js
function renderMarket() {
    const container = document.getElementById('market-config-container');
    if (!container) return;
    if (!config.marketConfig) config.marketConfig = JSON.parse(JSON.stringify(DEFAULT_MARKET_CONFIG));
    const cfg = config.marketConfig;

    container.innerHTML = `
        <div class="card">
            <div class="card-tag">CONFIGURACIÓN GLOBAL</div>
            <div style="display:flex; gap:12px; align-items:center; margin-bottom:1rem;">
                <div class="field" style="margin:0; flex-shrink:0;"><label>Habilitado</label><input type="checkbox" ${cfg.enabled ? 'checked' : ''} onchange="config.marketConfig.enabled = this.checked"></div>
                <div class="field" style="margin:0;"><label>Zona de Acceso (ID)</label><input type="number" value="${cfg.accessZoneId}" onchange="config.marketConfig.accessZoneId = parseInt(this.value) || 1"></div>
                <div class="field" style="margin:0;"><label>Duración Publicación (horas)</label><input type="number" value="${cfg.listingDurationHours}" onchange="config.marketConfig.listingDurationHours = parseInt(this.value) || 24"></div>
                <div class="field" style="margin:0;"><label>Impuesto de Venta (%)</label><input type="number" min="0" max="100" value="${cfg.sellTaxPercent}" onchange="config.marketConfig.sellTaxPercent = parseFloat(this.value) || 0"></div>
            </div>
            <div class="form-grid">
                <div class="field"><label>Máx. Publicaciones por Jugador</label><input type="number" min="1" value="${cfg.maxActiveListingsPerPlayer}" onchange="config.marketConfig.maxActiveListingsPerPlayer = parseInt(this.value) || 1"></div>
                <div class="field"><label>Intervalo Expiración (ms)</label><input type="number" min="5000" value="${cfg.expiryCheckIntervalMs}" onchange="config.marketConfig.expiryCheckIntervalMs = parseInt(this.value) || 60000"></div>
                <div class="field"><label>Intervalo Cache Activas (ms)</label><input type="number" min="5000" value="${cfg.cacheRefreshIntervalMs}" onchange="config.marketConfig.cacheRefreshIntervalMs = parseInt(this.value) || 300000"></div>
                <div class="field"><label>Tarifa Publicación (Hubs)</label><input type="number" min="0" value="${cfg.listingFeeHubs}" onchange="config.marketConfig.listingFeeHubs = parseInt(this.value) || 0"></div>
                <div class="field"><label>Tarifa Publicación (Ohcu)</label><input type="number" min="0" value="${cfg.listingFeeOhcu}" onchange="config.marketConfig.listingFeeOhcu = parseInt(this.value) || 0"></div>
                <div class="field"><label>Precio Mín (Hubs)</label><input type="number" min="0" value="${cfg.minPriceHubs}" onchange="config.marketConfig.minPriceHubs = parseInt(this.value) || 0"></div>
                <div class="field"><label>Precio Máx (Hubs · 0 = sin tope)</label><input type="number" min="0" value="${cfg.maxPriceHubs}" onchange="config.marketConfig.maxPriceHubs = parseInt(this.value) || 0"></div>
                <div class="field"><label>Precio Mín (Ohcu)</label><input type="number" min="0" value="${cfg.minPriceOhcu}" onchange="config.marketConfig.minPriceOhcu = parseInt(this.value) || 0"></div>
                <div class="field"><label>Precio Máx (Ohcu · 0 = sin tope)</label><input type="number" min="0" value="${cfg.maxPriceOhcu}" onchange="config.marketConfig.maxPriceOhcu = parseInt(this.value) || 0"></div>
                <div class="field"><label>Permitir AutoCompra</label><input type="checkbox" ${cfg.allowSelfBuy ? 'checked' : ''} onchange="config.marketConfig.allowSelfBuy = this.checked"></div>
                <div class="field full"><label>IDs Bloqueados (separados por coma)</label><input type="text" value="${(cfg.blockedItemIds || []).join(', ')}" onchange="config.marketConfig.blockedItemIds = this.value.split(',').map(s => s.trim()).filter(Boolean)"></div>
            </div>
        </div>
        <div class="card">
            <div class="card-tag">MODERACIÓN DE PUBLICACIONES</div>
            <div style="display:flex; gap:10px; align-items:center; margin-bottom:1rem;">
                <select id="market-status-filter" onchange="window.marketListings = []; renderMarketListingsTable();">
                    <option value="active">Activas</option>
                    <option value="expired">Expiradas</option>
                    <option value="cancelled">Canceladas</option>
                    <option value="sold">Vendidas</option>
                    <option value="all">Todas</option>
                </select>
                <button class="btn btn-primary" onclick="socket.emit('adminGetMarketListings', { limit: 50, status: document.getElementById('market-status-filter').value })">🔄 ACTUALIZAR LISTA</button>
                <span style="font-size:0.7rem; color:#888;">Cancelar una publicación devuelve el ítem al buzón del vendedor.</span>
            </div>
            <div id="market-listings-table-container"></div>
        </div>
    `;
    renderMarketListingsTable();
}

function renderMarketListingsTable() {
    const wrapper = document.getElementById('market-listings-table-container');
    if (!wrapper) return;
    const listings = window.marketListings || [];
    if (listings.length === 0) {
        wrapper.innerHTML = `<div style="font-size:0.8rem; color:#888; padding:1rem;">Sin publicaciones. Presiona "ACTUALIZAR LISTA" para consultar el mercado.</div>`;
        return;
    }
    const statusLabel = { active: '🟢 Activa', sold: '🟣 Vendida', expired: '🟡 Expirada', cancelled: '🔴 Cancelada' };
    wrapper.innerHTML = `
        <div class="card" style="width: 100%; padding: 0; overflow: hidden;">
            <table style="width: 100%; border-collapse: collapse; font-size: 0.8rem;">
                <thead style="background: rgba(255,255,255,0.05); text-align: left;">
                    <tr>
                        <th style="padding: 1rem;">VENDEDOR</th>
                        <th style="padding: 1rem;">ÍTEM</th>
                        <th style="padding: 1rem;">CANT.</th>
                        <th style="padding: 1rem;">PRECIO</th>
                        <th style="padding: 1rem;">MONEDA</th>
                        <th style="padding: 1rem;">ESTADO</th>
                        <th style="padding: 1rem;">EXPIRA</th>
                        <th style="padding: 1rem;">ACCIÓN</th>
                    </tr>
                </thead>
                <tbody>
                    ${listings.map(l => `
                        <tr style="border-top: 1px solid rgba(255,255,255,0.05);">
                            <td style="padding: 0.8rem 1rem;">${l.sellerName || '—'}</td>
                            <td style="padding: 0.8rem 1rem;">${(l.item && l.item.name) || '—'}</td>
                            <td style="padding: 0.8rem 1rem;">${l.amount}</td>
                            <td style="padding: 0.8rem 1rem;">${l.price.toLocaleString()}</td>
                            <td style="padding: 0.8rem 1rem; text-transform: uppercase;">${l.currency}</td>
                            <td style="padding: 0.8rem 1rem;">${statusLabel[l.status] || l.status}</td>
                            <td style="padding: 0.8rem 1rem;">${l.status === 'active' && l.expiresAt ? new Date(l.expiresAt).toLocaleString() : '—'}</td>
                            <td style="padding: 0.8rem 1rem;">${l.status === 'active' ? `<button class="btn" style="background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.3); color:#ff6060; cursor:pointer;" onclick="socket.emit('adminCancelMarketListing', { listingId: '${l._id}' }); setTimeout(() => socket.emit('adminGetMarketListings', { limit: 50, status: document.getElementById('market-status-filter').value }), 800);">✕ CANCELAR</button>` : ''}</td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
    `;
}

function renderAmmo() {
    const grid = document.getElementById('ammo-grid'); grid.innerHTML = '';
    const f = getFilter();
    
    const type = currentAmmoTab;
    const multipliers = config.ammoMultipliers[type] || [];
    const shopItems = (config.shopItems.ammo && config.shopItems.ammo[type]) ? config.shopItems.ammo[type] : [];

    const descMap = {
        'laser': '🔦 <strong>Láser:</strong> Proyectil estándar directo. Daño enfocado a distancia media/larga.',
        'mine': '💣 <strong>Mina:</strong> Munición explosiva de proximidad. Ideal para control de zonas o defensa.',
        'missile': '🚀 <strong>Misil:</strong> Misil teledirigido de largo alcance con gran capacidad destructiva.',
        'melee': '👊 <strong>Melee (Tanque):</strong> Ataque cuerpo a cuerpo de muy corto alcance. Ralentiza (paraliza) al enemigo al impactar.',
        'heal': '💚 <strong>Curativa:</strong> Restaura HP y Escudo al propio jugador en PvE. En PvP, cura al aliado impactado y una porción a vos.',
        'siphon': '🧛 <strong>Vampírica (Sifón):</strong> Inflige daño al enemigo y te cura un porcentaje del daño causado.',
        'emp': '⚡ <strong>Pulso EMP:</strong> Silencia habilidades y mecánicas de la IA del enemigo o silencia a jugadores en PvP.',
        'electron': '⚛️ <strong>Electrón:</strong> Lanza una bomba de energía en parábola que explota en área al caer. Si golpea enemigos, te otorga velocidad de movimiento acumulable.'
    };

    const descDiv = document.createElement('div');
    descDiv.style.gridColumn = '1 / -1';
    descDiv.style.background = 'rgba(255, 255, 255, 0.02)';
    descDiv.style.border = '1px solid rgba(255, 255, 255, 0.05)';
    descDiv.style.padding = '1rem';
    descDiv.style.borderRadius = '8px';
    descDiv.style.marginBottom = '1rem';
    descDiv.style.color = '#ccc';
    descDiv.style.fontSize = '0.9rem';
    descDiv.innerHTML = descMap[type] || 'Configuración de munición.';
    grid.appendChild(descDiv);

    multipliers.forEach((m, i) => {
        const item = shopItems[i] || { name: `Tier ${i+1}`, range: 0, cooldown: 1000, prices: { hubs:0, ohcu:0 } };
        if(item.cooldown === undefined) item.cooldown = 1000;
        if(item.bulletSpeed === undefined) item.bulletSpeed = 800;
        if(!item.mechanics) item.mechanics = [];
        
        if(f && !item.name.toLowerCase().includes(f) && !JSON.stringify(item).toLowerCase().includes(f)) return;

        const ammoIconKey = type + '_' + i;
        if (!config.shopItems.ammo_icons) config.shopItems.ammo_icons = {};
        const ammoIconPath = config.shopItems.ammo_icons[ammoIconKey] || '';
        const ammoIconWeb = resolveAssetWebUrl(ammoIconPath);
        const ammoIconPreview = ammoIconWeb
            ? `<img src="${ammoIconWeb}" style="width:64px; height:64px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:64px; height:64px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.6rem; text-align:center; padding:2px;">Sin Ícono</div>`;

        let extraFieldsHTML = '';
        if (type === 'emp') {
            extraFieldsHTML = `
                <div class="field full" style="margin-top: 1rem;">
                    <label>Duración del Silencio (ms)</label>
                    <input type="number" value="${item.silenceDurationMs !== undefined ? item.silenceDurationMs : 3000}" onchange="config.shopItems.ammo['${type}'][${i}].silenceDurationMs = parseInt(this.value)">
                </div>
            `;
        } else if (type === 'heal') {
            extraFieldsHTML = `
                <div class="form-grid" style="margin-top: 1rem; grid-template-columns: 1fr 1fr 1fr;">
                    <div class="field"><label>Curación PvE (%)</label><input type="number" value="${item.healPctPvE !== undefined ? item.healPctPvE : 40}" onchange="config.shopItems.ammo['${type}'][${i}].healPctPvE = parseInt(this.value)"></div>
                    <div class="field"><label>Curación Aliado PvP (%)</label><input type="number" value="${item.healPctVictimPvP !== undefined ? item.healPctVictimPvP : 80}" onchange="config.shopItems.ammo['${type}'][${i}].healPctVictimPvP = parseInt(this.value)"></div>
                    <div class="field"><label>Cura Propia PvP (%)</label><input type="number" value="${item.healPctAttackerPvP !== undefined ? item.healPctAttackerPvP : 30}" onchange="config.shopItems.ammo['${type}'][${i}].healPctAttackerPvP = parseInt(this.value)"></div>
                </div>
            `;
        } else if (type === 'siphon') {
            extraFieldsHTML = `
                <div class="field full" style="margin-top: 1rem;">
                    <label>Eficacia de Sifón / Robo de Vida (%)</label>
                    <input type="number" value="${item.siphonPct !== undefined ? item.siphonPct : 25}" onchange="config.shopItems.ammo['${type}'][${i}].siphonPct = parseInt(this.value)">
                </div>
            `;
        } else if (type === 'melee') {
            extraFieldsHTML = `
                <div class="form-grid" style="margin-top: 1rem; grid-template-columns: 1fr 1fr;">
                    <div class="field"><label>Duración Slow (ms)</label><input type="number" value="${item.slowDurationMs !== undefined ? item.slowDurationMs : 1000}" onchange="config.shopItems.ammo['${type}'][${i}].slowDurationMs = parseInt(this.value)"></div>
                    <div class="field"><label>Cantidad Ralentización (pts)</label><input type="number" value="${item.slowAmount !== undefined ? item.slowAmount : 200}" onchange="config.shopItems.ammo['${type}'][${i}].slowAmount = parseInt(this.value)"></div>
                </div>
            `;
        } else if (type === 'electron') {
            extraFieldsHTML = `
                <div class="form-grid" style="margin-top: 1rem; grid-template-columns: 1fr 1fr 1fr 1fr;">
                    <div class="field"><label>Radio de Explosión (px)</label><input type="number" value="${item.explosionRadius !== undefined ? item.explosionRadius : 120}" onchange="config.shopItems.ammo['${type}'][${i}].explosionRadius = parseInt(this.value)"></div>
                    <div class="field"><label>Velocidad Otorgada (%)</label><input type="number" value="${item.speedBuffPct !== undefined ? item.speedBuffPct : 15}" onchange="config.shopItems.ammo['${type}'][${i}].speedBuffPct = parseInt(this.value)"></div>
                    <div class="field"><label>Duración de Velocidad (ms)</label><input type="number" value="${item.speedBuffDurationMs !== undefined ? item.speedBuffDurationMs : 3000}" onchange="config.shopItems.ammo['${type}'][${i}].speedBuffDurationMs = parseInt(this.value)"></div>
                    <div class="field"><label>Stacks Máximos (cant)</label><input type="number" value="${item.speedBuffMaxStacks !== undefined ? item.speedBuffMaxStacks : 4}" onchange="config.shopItems.ammo['${type}'][${i}].speedBuffMaxStacks = parseInt(this.value)"></div>
                </div>
            `;
        }

        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                <div class="card-tag">TIER ${i+1}</div>
                <button style="background:none; border:none; color:${item.hidden ? '#ff9f0a' : '#00d2ff'}; cursor:pointer; font-size:0.75rem; font-weight:bold; display:flex; align-items:center; gap:4px;" onclick="toggleAmmoVisibility('${type}', ${i})">
                    ${item.hidden ? '🙈 OCULTO' : '👁️ VISIBLE'}
                </button>
            </div>
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${ammoIconPreview}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload('${ammoIconKey}', 'ammo_icon')">🖼️ ICONO</button>
                    ${ammoIconPath ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="delete config.shopItems.ammo_icons['${ammoIconKey}']; renderAmmo();">✕ Quitar</button>` : ''}
                </div>
                <div style="flex-grow:1;">
                    <div class="field full"><label>Nombre Comercial</label><input type="text" value="${item.name}" onchange="config.shopItems.ammo['${type}'][${i}].name = this.value"></div>
                </div>
            </div>
            
            <div class="form-grid" style="margin-top:1.5rem;">
                <div class="field"><label>Mult. Daño (x)</label><input type="number" step="0.1" value="${m}" style="color:var(--accent); font-weight:bold;" onchange="config.ammoMultipliers['${type}'][${i}] = parseFloat(this.value)"></div>
                <div class="field"><label>Alcance (px)</label><input type="number" value="${item.range || 0}" onchange="config.shopItems.ammo['${type}'][${i}].range = parseInt(this.value)"></div>
                <div class="field"><label>Vel. Bala (px/s)</label><input type="number" value="${item.bulletSpeed}" onchange="config.shopItems.ammo['${type}'][${i}].bulletSpeed = parseInt(this.value)"></div>
                <div class="field"><label>Cooldown (ms)</label><input type="number" value="${item.cooldown}" onchange="config.shopItems.ammo['${type}'][${i}].cooldown = parseInt(this.value)"></div>
                <div class="field"><label>Casteo (ms)</label><input type="number" min="0" max="5000" step="50" value="${item.castTimeMs || 0}" onchange="config.shopItems.ammo['${type}'][${i}].castTimeMs = parseInt(this.value) || 0"></div>
            </div>

            ${extraFieldsHTML}
            <div style="margin-top:0.8rem; padding:0.7rem; background:rgba(251,191,36,0.06); border:1px solid rgba(251,191,36,0.15); border-radius:6px;">
                <label style="color:#fbbf24; font-size:0.6rem; font-weight:bold;">SONIDO DE DISPARO (assets/Sonidos/Mecanicas/)</label>
                <div style="display:flex; gap:6px; align-items:center; margin-top:0.4rem;">
                    <input type="text" placeholder="res://assets/Sonidos/Mecanicas/ej.ogg" value="${item.sound || ''}" style="flex:1; font-size:0.65rem;" onchange="config.shopItems.ammo['${type}'][${i}].sound = this.value; renderAmmo();">
                    <button class="btn" style="padding:4px 8px; font-size:0.6rem; background:rgba(251,191,36,0.12); border:1px solid rgba(251,191,36,0.25); color:#fbbf24;" onclick="triggerAssetUpload('${type}_${i}', 'ammo_sound')">SONIDO</button>
                    ${item.sound ? `<button class="btn" style="padding:2px 6px; font-size:0.55rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060;" onclick="config.shopItems.ammo['${type}'][${i}].sound=''; renderAmmo();">X</button>` : ''}
                </div>
                ${item.sound ? `<audio controls preload="none" src="${resolveAssetWebUrl(item.sound)}" style="width:100%; height:26px; margin-top:0.4rem;"></audio>` : ''}
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:0.4rem;">
                    <div class="field"><label>Volumen <input type="number" id="ammo-vol-input-${type}-${i}" min="0" max="100" value="${item.soundVolumePercent !== undefined ? item.soundVolumePercent : 50}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.shopItems.ammo['${type}'][${i}].soundVolumePercent=v; let s=document.getElementById('ammo-vol-slider-${type}-${i}'); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.shopItems.ammo['${type}'][${i}].soundVolumePercent=v; let s=document.getElementById('ammo-vol-slider-${type}-${i}'); if(s) s.value=v;"> %</label><input type="range" id="ammo-vol-slider-${type}-${i}" min="0" max="100" value="${item.soundVolumePercent !== undefined ? item.soundVolumePercent : 50}" oninput="config.shopItems.ammo['${type}'][${i}].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById('ammo-vol-input-${type}-${i}'); if(inp) inp.value=this.value;"></div>
                    <div class="field"><label>Dist Max (px)</label><input type="number" step="50" value="${item.soundMaxDist || 1000}" onchange="config.shopItems.ammo['${type}'][${i}].soundMaxDist = parseInt(this.value) || 1000"></div>
                </div>
            </div>
            
            <div style="margin-top: 1.5rem; padding-top: 1rem; border-top: 1px solid #333;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                    <label style="color:var(--accent); font-size: 0.7rem; font-weight:bold;">✨ EFECTOS DE IMPACTO</label>
                    <button class="btn btn-primary" style="padding: 2px 8px; font-size: 0.6rem;" onclick="addAmmoMechanic('${type}', ${i})">+ EFECTO</button>
                </div>
                <div id="ammo-mech-${type}-${i}">
                    ${item.mechanics.map((me, midx) => `
                        <div style="background:rgba(255,255,255,0.03); padding:8px; border-radius:6px; margin-bottom:8px; border:1px solid rgba(255,255,255,0.05); position:relative;">
                            <button style="position:absolute; top:4px; right:4px; background:none; border:none; color:#ff4444; cursor:pointer; font-size:10px;" onclick="config.shopItems.ammo['${type}'][${i}].mechanics.splice(${midx},1); renderAmmo();">✕</button>
                            <select style="background:transparent; border:none; color:var(--accent); font-size:0.7rem; font-weight:bold; cursor:pointer;" onchange="config.shopItems.ammo['${type}'][${i}].mechanics[${midx}].type = this.value; renderAmmo();">
                                ${Object.keys(AMMO_MECH_LIB).map(mt => `<option value="${mt}" ${me.type===mt?'selected':''}>${AMMO_MECH_LIB[mt].icon} ${AMMO_MECH_LIB[mt].label}</option>`).join('')}
                            </select>
                            <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px; margin-top:5px;">
                                ${AMMO_MECH_LIB[me.type || 'bleed'].fields.map(fld => `
                                    <div class="field" style="margin:0;"><label style="font-size:9px;">${fld}</label><input type="number" value="${me[fld] || 0}" style="font-size:10px; height:20px;" onchange="config.shopItems.ammo['${type}'][${i}].mechanics[${midx}].${fld} = parseInt(this.value)"></div>
                                `).join('')}
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>

            <div class="price-group" style="margin-top:1rem; border-top:1px solid #333; padding-top:1rem;">
                <div class="field"><label>Hubs (qty)</label><input type="number" value="${item.prices.hubs}" onchange="config.shopItems.ammo['${type}'][${i}].prices.hubs = parseInt(this.value)"></div>
                <div class="field"><label>Ohcu (qty)</label><input type="number" value="${item.prices.ohcu}" onchange="config.shopItems.ammo['${type}'][${i}].prices.ohcu = parseInt(this.value)"></div>
                <div class="field"><label>No Comerciable</label><input type="checkbox" ${item.soulbound ? 'checked' : ''} onchange="config.shopItems.ammo['${type}'][${i}].soulbound = this.checked"></div>
            </div>

            ${requirementsSectionHtml('req_ammo_' + reqSectionIdSanitize(type) + '_' + i, `config.shopItems.ammo["${type.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"][${i}]`)}
        `;
        grid.appendChild(card);
    });
}

function renderWeapons() {
    const grid = document.getElementById('weapons-grid'); grid.innerHTML = '';
    const f = getFilter();
    config.shopItems.weapons.forEach((w, i) => {
        if(f && !w.name.toLowerCase().includes(f) && !w.id.toLowerCase().includes(f)) return;
        const iconWeb = resolveAssetWebUrl(w.icon || '');
        const iconPreview = iconWeb
            ? `<img src="${iconWeb}" style="width:72px; height:72px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:72px; height:72px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.7rem; text-align:center; padding:4px;">Sin Ícono</div>`;
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                <div class="card-tag">ID: ${w.id}</div>
                <button style="background:none; border:none; color:${w.hidden ? '#ff9f0a' : '#00d2ff'}; cursor:pointer; font-size:0.75rem; font-weight:bold; display:flex; align-items:center; gap:4px;" onclick="toggleWeaponVisibility(${i})">
                    ${w.hidden ? '🙈 OCULTO' : '👁️ VISIBLE'}
                </button>
            </div>
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${iconPreview}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload(${i}, 'weapon_icon')">🖼️ ICONO</button>
                    ${w.icon ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="config.shopItems.weapons[${i}].icon=''; renderWeapons();">✕ Quitar</button>` : ''}
                </div>
                <div style="flex-grow:1;">
                    <div class="field full"><label>Nombre del Arma</label><input type="text" value="${w.name}" onchange="config.shopItems.weapons[${i}].name = this.value"></div>
                </div>
            </div>
            <div class="form-grid" style="margin-top:1rem;">
                <div class="field"><label>Daño Base (pts)</label><input type="number" value="${w.base}" onchange="config.shopItems.weapons[${i}].base = parseInt(this.value)"></div>
                <div class="field full"><label>Mod. Velocidad</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${w.speedMod || 0}" onchange="config.shopItems.weapons[${i}].speedMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.weapons[${i}].speedModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(w.speedModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(w.speedModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field full"><label>Mod. Vida</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${w.hpMod || 0}" onchange="config.shopItems.weapons[${i}].hpMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.weapons[${i}].hpModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(w.hpModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(w.hpModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field"><label>Precio Hubs (qty)</label><input type="number" value="${w.prices.hubs}" onchange="config.shopItems.weapons[${i}].prices.hubs = parseInt(this.value)"></div>
                <div class="field"><label>Precio Ohcu (qty)</label><input type="number" value="${w.prices.ohcu}" onchange="config.shopItems.weapons[${i}].prices.ohcu = parseInt(this.value)"></div>
                <div class="field"><label>No Comerciable (Soulbound)</label><input type="checkbox" ${w.soulbound ? 'checked' : ''} onchange="config.shopItems.weapons[${i}].soulbound = this.checked"></div>
            </div>
            ${requirementsSectionHtml('req_weapon_' + i, `config.shopItems.weapons[${i}]`)}
        `;
        grid.appendChild(card);
    });
}

function renderShields() {
    const grid = document.getElementById('shields-grid'); grid.innerHTML = '';
    const f = getFilter();
    config.shopItems.shields.forEach((s, i) => {
        if(f && !s.name.toLowerCase().includes(f) && !s.id.toLowerCase().includes(f) && !JSON.stringify(s).toLowerCase().includes(f)) return;
        const iconWeb = resolveAssetWebUrl(s.icon || '');
        const iconPreview = iconWeb
            ? `<img src="${iconWeb}" style="width:72px; height:72px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:72px; height:72px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.7rem; text-align:center; padding:4px;">Sin Ícono</div>`;
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                <div class="card-tag">ID: ${s.id}</div>
                <button style="background:none; border:none; color:${s.hidden ? '#ff9f0a' : '#00d2ff'}; cursor:pointer; font-size:0.75rem; font-weight:bold; display:flex; align-items:center; gap:4px;" onclick="toggleShieldVisibility(${i})">
                    ${s.hidden ? '🙈 OCULTO' : '👁️ VISIBLE'}
                </button>
            </div>
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${iconPreview}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload(${i}, 'shield_icon')">🖼️ ICONO</button>
                    ${s.icon ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="config.shopItems.shields[${i}].icon=''; renderShields();">✕ Quitar</button>` : ''}
                </div>
                <div style="flex-grow:1;">
                    <div class="field full"><label>Nombre del Escudo</label><input type="text" value="${s.name}" onchange="config.shopItems.shields[${i}].name = this.value"></div>
                </div>
            </div>
            <div class="form-grid" style="margin-top:1rem;">
                <div class="field"><label>Escudo Base (pts)</label><input type="number" value="${s.base}" onchange="config.shopItems.shields[${i}].base = parseInt(this.value)"></div>
                <div class="field full"><label>Mod. Vida</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${s.hpMod || 0}" onchange="config.shopItems.shields[${i}].hpMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.shields[${i}].hpModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(s.hpModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(s.hpModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field full"><label>Mod. Velocidad</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${s.speedMod || 0}" onchange="config.shopItems.shields[${i}].speedMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.shields[${i}].speedModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(s.speedModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(s.speedModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field"><label>Precio Hubs (qty)</label><input type="number" value="${s.prices.hubs}" onchange="config.shopItems.shields[${i}].prices.hubs = parseInt(this.value)"></div>
                <div class="field"><label>Precio Ohcu (qty)</label><input type="number" value="${s.prices.ohcu}" onchange="config.shopItems.shields[${i}].prices.ohcu = parseInt(this.value)"></div>
                <div class="field"><label>No Comerciable (Soulbound)</label><input type="checkbox" ${s.soulbound ? 'checked' : ''} onchange="config.shopItems.shields[${i}].soulbound = this.checked"></div>
            </div>
            ${requirementsSectionHtml('req_shield_' + i, `config.shopItems.shields[${i}]`)}
        `;
        grid.appendChild(card);
    });
}

function renderEngines() {
    const grid = document.getElementById('engines-grid'); grid.innerHTML = '';
    const f = getFilter();
    config.shopItems.engines.forEach((e, i) => {
        if(f && !e.name.toLowerCase().includes(f) && !e.id.toLowerCase().includes(f) && !JSON.stringify(e).toLowerCase().includes(f)) return;
        const iconWeb = resolveAssetWebUrl(e.icon || '');
        const iconPreview = iconWeb
            ? `<img src="${iconWeb}" style="width:72px; height:72px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:72px; height:72px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.7rem; text-align:center; padding:4px;">Sin Ícono</div>`;
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                <div class="card-tag">ID: ${e.id}</div>
                <button style="background:none; border:none; color:${e.hidden ? '#ff9f0a' : '#00d2ff'}; cursor:pointer; font-size:0.75rem; font-weight:bold; display:flex; align-items:center; gap:4px;" onclick="toggleEngineVisibility(${i})">
                    ${e.hidden ? '🙈 OCULTO' : '👁️ VISIBLE'}
                </button>
            </div>
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${iconPreview}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload(${i}, 'engine_icon')">🖼️ ICONO</button>
                    ${e.icon ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="config.shopItems.engines[${i}].icon=''; renderEngines();">✕ Quitar</button>` : ''}
                </div>
                <div style="flex-grow:1;">
                    <div class="field full"><label>Nombre del Motor</label><input type="text" value="${e.name}" onchange="config.shopItems.engines[${i}].name = this.value"></div>
                </div>
            </div>
            <div class="form-grid" style="margin-top:1rem;">
                <div class="field"><label>Velocidad Base (px/s)</label><input type="number" value="${e.base}" onchange="config.shopItems.engines[${i}].base = parseInt(this.value)"></div>
                <div class="field full"><label>Mod. Escudo</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${e.shieldMod || 0}" onchange="config.shopItems.engines[${i}].shieldMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.engines[${i}].shieldModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(e.shieldModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(e.shieldModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field full"><label>Mod. Vida</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${e.hpMod || 0}" onchange="config.shopItems.engines[${i}].hpMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.engines[${i}].hpModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(e.hpModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(e.hpModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field full"><label>Mod. Daño</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${e.dmgMod || 0}" onchange="config.shopItems.engines[${i}].dmgMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.engines[${i}].dmgModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(e.dmgModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(e.dmgModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field"><label>Precio Hubs (qty)</label><input type="number" value="${e.prices.hubs}" onchange="config.shopItems.engines[${i}].prices.hubs = parseInt(this.value)"></div>
                <div class="field"><label>Precio Ohcu (qty)</label><input type="number" value="${e.prices.ohcu}" onchange="config.shopItems.engines[${i}].prices.ohcu = parseInt(this.value)"></div>
                <div class="field"><label>No Comerciable (Soulbound)</label><input type="checkbox" ${e.soulbound ? 'checked' : ''} onchange="config.shopItems.engines[${i}].soulbound = this.checked"></div>
            </div>
            ${requirementsSectionHtml('req_engine_' + i, `config.shopItems.engines[${i}]`)}
        `;
        grid.appendChild(card);
    });
}

// ==========================================
// CATÁLOGO DE ESTADÍSTICAS PARA ESFERAS (Iconos y categorías unificados con Talentos)
// ==========================================
const SPHERE_STATS_CATALOG = [
    // Combate
    { key: 'dmg_pct',           label: 'Daño Total',            icon: '💥', cat: 'combate',   defaultVal: 0.05, desc: 'Aumenta el daño total infligido.' },
    { key: 'laser_dmg_pct',     label: 'Daño Láser',            icon: '🔫', cat: 'combate',   defaultVal: 0.05, desc: 'Aumenta el daño de armamento láser.' },
    { key: 'fire_rate_pct',     label: 'Cadencia de Fuego',     icon: '⚔️', cat: 'combate',   defaultVal: 0.05, desc: 'Aumenta la velocidad de disparo.' },
    { key: 'ignore_shield_pct', label: 'Perforación de Escudo', icon: '⚡', cat: 'combate',   defaultVal: 0.05, desc: 'Porcentaje del daño que penetra directo a la estructura/vida.' },
    { key: 'ammo_bonus_pct',    label: 'Munición Extra',        icon: '💣', cat: 'combate',   defaultVal: 0.05, desc: 'Aumenta la capacidad de munición.' },
    { key: 'crit_chance',       label: 'Probabilidad Crítica',  icon: '💎', cat: 'combate',   defaultVal: 0.05, desc: 'Chance de acertar un impacto crítico.' },
    { key: 'crit_dmg',          label: 'Daño Crítico',          icon: '💥', cat: 'combate',   defaultVal: 0.20, desc: 'Multiplicador de daño al asestar un crítico.' },
    { key: 'accuracy_pct',      label: 'Precisión',             icon: '🎯', cat: 'combate',   defaultVal: 0.05, desc: 'Reduce la dispersión de los disparos.' },

    // Defensa
    { key: 'hp_pct',            label: 'Vida Máxima',           icon: '🛡️', cat: 'defensa',   defaultVal: 0.05, desc: 'Aumenta la vida/estructura máxima de la nave.' },
    { key: 'sh_pct',            label: 'Escudo Máximo',         icon: '🛡️', cat: 'defensa',   defaultVal: 0.05, desc: 'Aumenta la capacidad de escudo de la nave.' },
    { key: 'hp_regen',          label: 'Regen. Vida',           icon: '🔧', cat: 'defensa',   defaultVal: 2,    desc: 'Puntos de vida regenerados por segundo.' },
    { key: 'shield_regen',      label: 'Regen. Escudo',         icon: '🔋', cat: 'defensa',   defaultVal: 3,    desc: 'Puntos de escudo regenerados por segundo.' },
    { key: 'armor_pct',         label: 'Armadura / Mitigación', icon: '🔒', cat: 'defensa',   defaultVal: 0.03, desc: 'Reduce el daño recibido.' },
    { key: 'evasion_pct',       label: 'Evasión',               icon: '🌀', cat: 'defensa',   defaultVal: 0.04, desc: 'Chance de eludir un ataque por completo.' },
    { key: 'stability',         label: 'Estabilidad',           icon: '🛸', cat: 'defensa',   defaultVal: 0.05, desc: 'Resistencia a desestabilizaciones y empujes.' },

    // Utilidad
    { key: 'speed_pct',          label: 'Velocidad',             icon: '🚀', cat: 'utilidad',  defaultVal: 0.05, desc: 'Aumenta la velocidad de desplazamiento.' },
    { key: 'cooldown_reduction', label: 'Reducción CD Global',   icon: '❄️', cat: 'utilidad',  defaultVal: 0.05, desc: 'Reduce el tiempo de enfriamiento de habilidades.' },
    { key: 'cast_time_reduction',label: 'Reducción Cast Time',   icon: '⏱️', cat: 'utilidad',  defaultVal: 0.05, desc: 'Reduce el tiempo de casteo de habilidades.' },
    { key: 'dash_distance',      label: 'Distancia Dash',        icon: '🌀', cat: 'utilidad',  defaultVal: 0.10, desc: 'Aumenta el alcance del impulso/dash.' },
    { key: 'minimap_range',      label: 'Rango Radar',           icon: '📡', cat: 'utilidad',  defaultVal: 100,  desc: 'Aumenta el rango de detección del minimapa.' },
    { key: 'energy_efficiency',  label: 'Eficiencia Energía',    icon: '⚛️', cat: 'utilidad',  defaultVal: 0.05, desc: 'Disminuye el consumo de energía.' },

    // Economía
    { key: 'ohcu_kill_bonus',      label: 'Bonus OHCU por Bajas',  icon: '💎', cat: 'economía',  defaultVal: 0.05, desc: 'Mayor recompensa de OHCU al eliminar objetivos.' },
    { key: 'shop_discount',        label: 'Descuento Tiendas',     icon: '🏪', cat: 'economía',  defaultVal: 0.05, desc: 'Descuento al adquirir ítems en tiendas.' },
    { key: 'repair_cost_reduction',label: 'Costo Reparación',      icon: '💸', cat: 'economía',  defaultVal: 0.05, desc: 'Reduce el costo de reparación de nave.' },
    { key: 'boss_loot_bonus',      label: 'Loot Bosses',           icon: '👑', cat: 'economía',  defaultVal: 0.10, desc: 'Mayor botín al derrotar jefes de zona.' },
    { key: 'group_bonus',          label: 'Bonus Escuadrón',       icon: '👥', cat: 'economía',  defaultVal: 0.05, desc: 'Bonificaciones adicionales al jugar en grupo.' }
];

const SPHERE_STAT_KEYS = SPHERE_STATS_CATALOG.map(s => ({ k: s.key, l: `${s.icon} ${s.label}` }));

function _isSphereStatPct(key, val) {
    if (window._sphereStatsMeta && window._sphereStatsMeta[key] && window._sphereStatsMeta[key].flat !== undefined) {
        return !window._sphereStatsMeta[key].flat;
    }
    if (key.endsWith('Pct') || key.endsWith('Chance') || key.endsWith('Dmg') || 
        key === 'evasion' || key === 'armor' || key === 'fireRate' || 
        key === 'accuracy' || key === 'dashDistance' || key === 'ignoreShield' || 
        key === 'shopDiscount' || key === 'bossLootBonus' || key === 'cooldownReduction' ||
        key.endsWith('_pct') || key.endsWith('_bonus') || key === 'crit_chance' || key === 'crit_dmg') {
        return true;
    }
    const catItem = SPHERE_STATS_CATALOG.find(x => x.key === key);
    if (catItem && catItem.isPct !== undefined) return catItem.isPct;
    if (typeof val === 'number' && val > 0 && val <= 1 && !key.endsWith('Mod') && !key.endsWith('Regen') && !key.endsWith('Range') && !key.endsWith('_regen') && !key.endsWith('_range')) {
        return true;
    }
    return false;
}

function _getSphereStatMeta(key) {
    const found = SPHERE_STATS_CATALOG.find(x => x.key === key);
    if (found) return found;

    // Chequear claves dinámicas (skill:..., weapon:..., ammo:...)
    if (typeof _parseDynamicKey === 'function') {
        const parsed = _parseDynamicKey(key);
        if (parsed) {
            const cfg = (typeof config !== 'undefined' ? config : (window.config || {})) || {};
            if (parsed.type === 'skill') {
                const sk = cfg.skillsData ? cfg.skillsData[parsed.id] : null;
                const attrMeta = window.SKILL_ATTRS ? window.SKILL_ATTRS[parsed.attr] : null;
                return {
                    key: key,
                    label: `${sk ? sk.name : parsed.id} → ${attrMeta ? attrMeta.label : parsed.attr}`,
                    icon: attrMeta ? (attrMeta.icon || '🌀') : '🌀',
                    cat: 'dynamic',
                    isPct: !(attrMeta && attrMeta.flat),
                    desc: 'Modificador de habilidad'
                };
            } else if (parsed.type === 'weapon') {
                const weps = cfg.shopItems && cfg.shopItems.weapons ? cfg.shopItems.weapons : [];
                const w = weps.find(x => x.id === parsed.id);
                const attrMeta = window.WEAPON_ATTRS ? window.WEAPON_ATTRS[parsed.attr] : null;
                return {
                    key: key,
                    label: `${w ? w.name : parsed.id} → ${attrMeta ? attrMeta.label : parsed.attr}`,
                    icon: attrMeta ? (attrMeta.icon || '🔫') : '🔫',
                    cat: 'dynamic',
                    isPct: !(attrMeta && attrMeta.flat),
                    desc: 'Modificador de arma'
                };
            } else if (parsed.type === 'ammo') {
                const attrMeta = window.AMMO_ATTRS ? window.AMMO_ATTRS[parsed.attr] : null;
                return {
                    key: key,
                    label: `Munición ${parsed.id} → ${attrMeta ? attrMeta.label : parsed.attr}`,
                    icon: attrMeta ? (attrMeta.icon || '💣') : '💣',
                    cat: 'dynamic',
                    isPct: !(attrMeta && attrMeta.flat),
                    desc: 'Modificador de munición'
                };
            }
        }
    }

    // Mapeo específico para estadísticas legacy/existentes de esferas (mismos nombres que el catálogo)
    const SPHERE_LEGACY_LABELS = {
        dmgMod:     { label: 'Daño Total',                icon: '💥', cat: 'combate' },
        dmgPct:     { label: 'Daño Total',                icon: '💥', cat: 'combate' },
        dmg_pct:    { label: 'Daño Total',                icon: '💥', cat: 'combate' },
        shieldMod:  { label: 'Escudo Máximo',             icon: '🛡️', cat: 'defensa' },
        shieldPct:  { label: 'Escudo Máximo',             icon: '🛡️', cat: 'defensa' },
        sh_pct:     { label: 'Escudo Máximo',             icon: '🛡️', cat: 'defensa' },
        hpMod:      { label: 'Vida Máxima',               icon: '🛡️', cat: 'defensa' },
        hpPct:      { label: 'Vida Máxima',               icon: '🛡️', cat: 'defensa' },
        hp_pct:     { label: 'Vida Máxima',               icon: '🛡️', cat: 'defensa' },
        healPct:    { label: 'Poder de Curación',         icon: '💚', cat: 'defensa' },
        healMod:    { label: 'Poder de Curación',         icon: '💚', cat: 'defensa' },
        speedMod:   { label: 'Velocidad',                 icon: '🚀', cat: 'utilidad' },
        speedPct:   { label: 'Velocidad',                 icon: '🚀', cat: 'utilidad' },
        speed_pct:  { label: 'Velocidad',                 icon: '🚀', cat: 'utilidad' },
        energyPct:  { label: 'Eficiencia Energía',        icon: '⚛️', cat: 'utilidad' },
        energyMod:  { label: 'Eficiencia Energía',        icon: '⚛️', cat: 'utilidad' },
        evasion:    { label: 'Evasión',                   icon: '🌀', cat: 'defensa' },
        armor:      { label: 'Armadura / Mitigación',     icon: '🔒', cat: 'defensa' }
    };

    if (SPHERE_LEGACY_LABELS[key]) {
        const leg = SPHERE_LEGACY_LABELS[key];
        return {
            key: key,
            label: leg.label,
            icon: leg.icon,
            cat: leg.cat,
            isPct: _isSphereStatPct(key, 0),
            desc: 'Modificador de esfera'
        };
    }

    // Traductor amigable para claves técnicas en camelCase o snake_case
    const SPHERE_TRANSLATIONS = {
        dmg: 'Daño',
        damage: 'Daño',
        laser: 'Láser',
        shield: 'Escudo',
        hp: 'Vida',
        heal: 'Curación',
        speed: 'Velocidad',
        regen: 'Regeneración',
        rate: 'Cadencia',
        range: 'Rango',
        crit: 'Crítico',
        chance: 'Probabilidad',
        armor: 'Armadura',
        evasion: 'Evasión',
        energy: 'Energía',
        discount: 'Descuento',
        bonus: 'Bono',
        loot: 'Botín',
        repair: 'Reparación'
    };

    let prettyLabel = key;
    // Si contiene snake_case o camelCase, intentar traducir palabras
    const words = key.replace(/([A-Z])/g, ' $1').replace(/_/g, ' ').toLowerCase().trim().split(/\s+/);
    const translatedWords = words.map(w => {
        if (w === 'pct') return '(%)';
        if (w === 'mod') return '(Mod)';
        return SPHERE_TRANSLATIONS[w] || (w.charAt(0).toUpperCase() + w.slice(1));
    });
    prettyLabel = translatedWords.join(' ');

    // Detectar icono según el tipo de stat
    let fallbackIcon = '✨';
    const keyLower = key.toLowerCase();
    if (keyLower.includes('dmg') || keyLower.includes('damage') || keyLower.includes('ataque')) fallbackIcon = '💥';
    else if (keyLower.includes('shield') || keyLower.includes('escudo')) fallbackIcon = '🛡️';
    else if (keyLower.includes('hp') || keyLower.includes('vida')) fallbackIcon = '🛡️';
    else if (keyLower.includes('heal') || keyLower.includes('cura')) fallbackIcon = '💚';
    else if (keyLower.includes('speed') || keyLower.includes('vel')) fallbackIcon = '🚀';
    else if (keyLower.includes('crit')) fallbackIcon = '💎';
    else if (keyLower.includes('armor') || keyLower.includes('mitig')) fallbackIcon = '🔒';
    else if (keyLower.includes('energy')) fallbackIcon = '⚛️';
    else if (keyLower.includes('laser')) fallbackIcon = '🔫';

    return {
        key: key,
        label: prettyLabel,
        icon: fallbackIcon,
        cat: 'custom',
        isPct: _isSphereStatPct(key, 0),
        desc: 'Estadística personalizada'
    };
}

function _getSphereCatColor(cat) {
    const colors = {
        combate: '#ef4444',
        combat: '#ef4444',
        defensa: '#3b82f6',
        defense: '#3b82f6',
        utilidad: '#10b981',
        utility: '#10b981',
        economía: '#eab308',
        economy: '#eab308',
        dynamic: '#f97316',
        custom: '#a855f7'
    };
    return colors[cat] || '#888888';
}

function renderSphereStatsBox(sphereIdx) {
    const s = config.shopItems.spheres[sphereIdx];
    if (!s) return '';
    const stats = s.stats || {};
    const statsMeta = s.statsMeta || {};
    const entries = Object.entries(stats);
    const count = entries.length;

    let statsListHtml = '';
    if (count === 0) {
        statsListHtml = `
            <div style="background:rgba(255,255,255,0.02); border:1px dashed rgba(255,255,255,0.08); border-radius:8px; padding:14px; text-align:center;">
                <div style="font-size:0.75rem; color:#777; margin-bottom:4px;">🔮 Sin estadísticas configuradas</div>
                <div style="font-size:0.65rem; color:#555;">Hacé clic en <b>+ AGREGAR ESTADÍSTICA</b> para añadir un modificador pasivo a esta esfera.</div>
            </div>
        `;
    } else {
        statsListHtml = entries.map(([key, val]) => {
            const isFlatExplicit = statsMeta[key] && statsMeta[key].flat === true;
            const isPct = !isFlatExplicit && _isSphereStatPct(key, val);
            const displayVal = isPct ? (val * 100) : val;
            const cleanVal = (typeof formatCleanNumber === 'function')
                ? formatCleanNumber(displayVal, 2)
                : (Number.isInteger(displayVal) ? displayVal : parseFloat(displayVal.toFixed(2)));
            
            const meta = _getSphereStatMeta(key);
            const catColor = _getSphereCatColor(meta.cat);

            return `
            <div style="display:flex; gap:8px; align-items:center; background:rgba(255,255,255,0.03); padding:6px 10px; border-radius:8px; border:1px solid ${catColor}33; transition:all 0.15s;">
                <span style="font-size:1.15rem; flex-shrink:0;">${meta.icon}</span>
                <div style="flex:1; min-width:0;">
                    <div style="font-size:0.75rem; font-weight:bold; color:#fff; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${meta.label}</div>
                    <div style="font-size:0.6rem; color:#888; font-family:'JetBrains Mono',monospace; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${key}</div>
                </div>
                <div style="display:flex; align-items:center; gap:5px; flex-shrink:0;">
                    <input type="number" step="0.01" value="${cleanVal}" 
                        style="width:75px; text-align:right; font-size:0.75rem; padding:4px 6px; background:#141724; border:1px solid rgba(255,255,255,0.12); color:#fff; border-radius:4px; font-family:'JetBrains Mono',monospace;" 
                        onchange="updateSphereStatVal(${sphereIdx}, '${key}', this.value, ${isPct})">
                    <button type="button" onclick="toggleSphereStatType(${sphereIdx}, '${key}')" 
                        style="min-width:40px; padding:3px 6px; font-size:0.65rem; border-radius:4px; cursor:pointer; font-weight:bold; border:1px solid ${isPct ? 'rgba(0,210,255,0.4)' : 'rgba(255,150,50,0.4)'}; background:${isPct ? 'rgba(0,210,255,0.15)' : 'rgba(255,150,50,0.15)'}; color:${isPct ? '#00d2ff' : '#ff9632'};"
                        title="Hacé clic para alternar entre Porcentaje (%) y Valor Fijo (pts)">
                        ${isPct ? '%' : 'FIJO'}
                    </button>
                    <button type="button" onclick="removeSphereStat(${sphereIdx}, '${key}')" 
                        style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.9rem; padding:2px 6px; opacity:0.8; transition:opacity 0.15s;" 
                        onmouseover="this.style.opacity='1'" onmouseout="this.style.opacity='0.8'"
                        title="Eliminar estadística">✕</button>
                </div>
            </div>`;
        }).join('');
    }

    return `
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.8rem;">
            <div>
                <label style="color:var(--accent); font-size:0.72rem; font-weight:bold; letter-spacing:0.5px; display:flex; align-items:center; gap:6px;">
                    <span>📊 MODIFICADORES DE ESTADÍSTICAS</span>
                    <span style="font-size:0.6rem; padding:1px 6px; border-radius:10px; background:rgba(255,255,255,0.06); color:#aaa;">${count}</span>
                </label>
                <p style="font-size:0.63rem; color:#777; margin:2px 0 0;">Se aplican de forma pasiva al equipar esta esfera en un slot orbital.</p>
            </div>
            <button class="btn" type="button" style="padding:4px 10px; font-size:0.68rem; background:linear-gradient(135deg, rgba(0,210,255,0.15), rgba(168,85,247,0.15)); border:1px solid rgba(0,210,255,0.4); color:var(--primary); border-radius:6px; font-weight:600; cursor:pointer; display:flex; align-items:center; gap:4px; box-shadow:0 2px 8px rgba(0,210,255,0.1);" 
                onclick="openSphereStatPickerModal(${sphereIdx})">
                <span>+</span> AGREGAR ESTADÍSTICA
            </button>
        </div>
        <div style="display:flex; flex-direction:column; gap:6px;">
            ${statsListHtml}
        </div>
    `;
}

function refreshSphereStatsBox(sphereIdx) {
    const el = document.getElementById('sphere-stats-box-' + sphereIdx);
    if (el) {
        el.innerHTML = renderSphereStatsBox(sphereIdx);
    }
}

function renderSpheres() {
    const grid = document.getElementById('spheres-grid'); grid.innerHTML = '';
    const f = getFilter();
    if (!config.shopItems.spheres) config.shopItems.spheres = [];
    config.shopItems.spheres.forEach((s, i) => {
        if(f && !s.name.toLowerCase().includes(f) && !s.id.toLowerCase().includes(f) && !JSON.stringify(s).toLowerCase().includes(f)) return;

        const iconWeb = resolveAssetWebUrl(s.icon || '');
        const iconPreview = iconWeb
            ? `<img src="${iconWeb}" style="width:80px; height:80px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:80px; height:80px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.7rem; text-align:center; padding:4px;">Sin Ícono</div>`;

        const sphereColorOptions = [
            { value: 'roja', label: '🔴 Roja (Ataque)', color: '#ff4444' },
            { value: 'azul', label: '🔵 Azul (Defensa)', color: '#4488ff' },
            { value: 'verde', label: '🟢 Verde (Curación)', color: '#44cc44' },
            { value: 'amarilla', label: '🟡 Amarilla (Utilidad)', color: '#ffcc00' }
        ];

        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                <div class="card-tag">ID: ${s.id}</div>
                <button style="background:none; border:none; color:${s.hidden ? '#ff9f0a' : '#00d2ff'}; cursor:pointer; font-size:0.75rem; font-weight:bold; display:flex; align-items:center; gap:4px;" onclick="toggleSphereVisibility(${i})">
                    ${s.hidden ? '🙈 OCULTO' : '👁️ VISIBLE'}
                </button>
            </div>
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${iconPreview}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload(${i}, 'sphere_icon')">🖼️ ICONO</button>
                    ${s.icon ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="config.shopItems.spheres[${i}].icon=''; renderSpheres();">✕ Quitar</button>` : ''}
                </div>
                <div style="flex-grow:1;">
                    <div class="field full"><label>Nombre de la Esfera</label><input type="text" value="${s.name}" onchange="config.shopItems.spheres[${i}].name = this.value"></div>
                    <div class="field full"><label>Descripción</label><input type="text" value="${s.desc || ''}" onchange="config.shopItems.spheres[${i}].desc = this.value"></div>
                    <div style="display:flex; gap:10px; margin-top:8px;">
                        <div class="field" style="margin:0; flex:1;">
                            <label>ID Ítem</label>
                            <input type="text" value="${s.id}" onchange="config.shopItems.spheres[${i}].id = this.value" style="font-family:'JetBrains Mono',monospace;">
                        </div>
                        <div class="field" style="margin:0; flex:1;">
                            <label>Color Visual (Hex)</label>
                            <div style="display:flex; gap:6px; align-items:center;">
                                <input type="color" value="${s.color || '#ffffff'}" onchange="config.shopItems.spheres[${i}].color = this.value" style="width:36px; height:32px; padding:2px; cursor:pointer; border:1px solid rgba(255,255,255,0.15); border-radius:4px; background:transparent;">
                                <input type="text" value="${s.color || '#ffffff'}" onchange="config.shopItems.spheres[${i}].color = this.value" style="flex:1; font-family:'JetBrains Mono',monospace; font-size:0.75rem;">
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <div style="margin-top:0.5rem; padding:0.7rem; background:rgba(168,85,247,0.06); border:1px solid rgba(168,85,247,0.15); border-radius:6px;">
                <label style="color:#a855f7; font-size:0.65rem; font-weight:bold; letter-spacing:1px;">🎨 TIPO / COLOR DE ESFERA</label>
                <div style="display:flex; gap:8px; margin-top:0.5rem; flex-wrap:wrap;">
                    ${sphereColorOptions.map(opt => `
                        <button style="padding:4px 12px; font-size:0.7rem; border-radius:6px; cursor:pointer; border:2px solid ${(s.sphereColor || 'roja') === opt.value ? opt.color : 'rgba(255,255,255,0.1)'}; background:${(s.sphereColor || 'roja') === opt.value ? opt.color + '22' : 'rgba(255,255,255,0.03)'}; color:${(s.sphereColor || 'roja') === opt.value ? opt.color : '#888'}; font-weight:${(s.sphereColor || 'roja') === opt.value ? 'bold' : 'normal'}; transition:all 0.2s;" onclick="config.shopItems.spheres[${i}].sphereColor = '${opt.value}'; config.shopItems.spheres[${i}].color = '${opt.color}'; renderSpheres();">
                            ${opt.label}
                        </button>
                    `).join('')}
                </div>
            </div>

            <div id="sphere-stats-box-${i}" style="margin-top:1rem; padding-top:1rem; border-top: 1px solid rgba(255,255,255,0.05);">
                ${renderSphereStatsBox(i)}
            </div>

            <div class="price-group" style="display:flex; gap:15px; margin-top:1rem; border-top:1px solid #333; padding-top:1rem;">
                <div class="field" style="flex:1;"><label>Precio Hubs (qty)</label><input type="number" value="${s.prices ? s.prices.hubs : 0}" onchange="if(!config.shopItems.spheres[${i}].prices) config.shopItems.spheres[${i}].prices = {hubs:0,ohcu:0}; config.shopItems.spheres[${i}].prices.hubs = parseInt(this.value)"></div>
                <div class="field" style="flex:1;"><label>Precio Ohcu (qty)</label><input type="number" value="${s.prices ? s.prices.ohcu : 0}" onchange="if(!config.shopItems.spheres[${i}].prices) config.shopItems.spheres[${i}].prices = {hubs:0,ohcu:0}; config.shopItems.spheres[${i}].prices.ohcu = parseInt(this.value)"></div>
                <div class="field" style="flex:1;"><label>No Comerciable</label><input type="checkbox" ${s.soulbound ? 'checked' : ''} onchange="config.shopItems.spheres[${i}].soulbound = this.checked"></div>
            </div>

            ${requirementsSectionHtml('req_sphere_' + i, `config.shopItems.spheres[${i}]`)}
        `;
        grid.appendChild(card);
    });
}

// ==========================================
// MODAL SELECTOR DE ESTADÍSTICAS PARA ESFERAS
// ==========================================
window._activeSphereIdx = null;
window._sphereStatActiveTab = 'all';

window.openSphereStatPickerModal = function(sphereIdx) {
    window._activeSphereIdx = sphereIdx;
    window._sphereStatActiveTab = 'all';

    const s = config.shopItems.spheres[sphereIdx];
    const titleEl = document.getElementById('sphere-picker-title');
    if (titleEl && s) {
        titleEl.innerHTML = `<span>🔮</span> Agregar Estadística a: <span style="color:#fff; font-weight:bold; margin-left:6px;">${s.name || s.id}</span>`;
    }

    const searchInput = document.getElementById('sphere-stat-search');
    if (searchInput) searchInput.value = '';

    _renderSphereStatPickerModal();

    const modal = document.getElementById('sphere-stat-picker-modal');
    if (modal) modal.style.display = 'flex';
};

window.closeSphereStatPickerModal = function() {
    const modal = document.getElementById('sphere-stat-picker-modal');
    if (modal) modal.style.display = 'none';
    window._activeSphereIdx = null;
};

window._setSphereStatPickerTab = function(tab) {
    window._sphereStatActiveTab = tab;
    _renderSphereStatPickerModal();
};

window._filterSphereStatPicker = function() {
    _renderSphereStatPickerModal();
};

window._renderSphereStatPickerModal = function() {
    const sphereIdx = window._activeSphereIdx;
    if (sphereIdx === null || !config.shopItems.spheres || !config.shopItems.spheres[sphereIdx]) return;

    const s = config.shopItems.spheres[sphereIdx];
    const currentStats = s.stats || {};
    const searchVal = (document.getElementById('sphere-stat-search')?.value || '').trim().toLowerCase();
    const activeTab = window._sphereStatActiveTab || 'all';

    // Tabs
    const tabsContainer = document.getElementById('sphere-stat-cat-tabs');
    if (tabsContainer) {
        const tabs = [
            { id: 'all', label: 'Todas', icon: '🌐' },
            { id: 'combate', label: 'Combate', icon: '⚔️' },
            { id: 'defensa', label: 'Defensa', icon: '🛡️' },
            { id: 'utilidad', label: 'Utilidad', icon: '🚀' },
            { id: 'economía', label: 'Economía', icon: '💎' },
            { id: 'dynamic', label: 'Dinámicas', icon: '🌀' },
            { id: 'custom', label: 'Personalizada', icon: '✨' }
        ];

        tabsContainer.innerHTML = tabs.map(t => {
            const isActive = activeTab === t.id;
            return `
                <button type="button" onclick="_setSphereStatPickerTab('${t.id}')"
                    style="padding:5px 12px; font-size:0.75rem; border-radius:6px; cursor:pointer; font-weight:${isActive ? 'bold' : 'normal'}; border:1px solid ${isActive ? 'rgba(0,210,255,0.5)' : 'rgba(255,255,255,0.1)'}; background:${isActive ? 'rgba(0,210,255,0.18)' : 'rgba(255,255,255,0.03)'}; color:${isActive ? '#00d2ff' : '#aaa'}; transition:all 0.15s; display:flex; align-items:center; gap:5px;">
                    <span>${t.icon}</span> ${t.label}
                </button>
            `;
        }).join('');
    }

    const optionsContainer = document.getElementById('sphere-stat-options-container');
    if (!optionsContainer) return;

    // Caso 1: Pestaña Personalizada
    if (activeTab === 'custom') {
        optionsContainer.innerHTML = `
            <div style="background:rgba(255,255,255,0.02); border:1px solid rgba(168,85,247,0.3); border-radius:10px; padding:18px; display:flex; flex-direction:column; gap:12px;">
                <div style="font-size:0.85rem; font-weight:bold; color:#a855f7; display:flex; align-items:center; gap:6px;">
                    <span>✨</span> Crear Estadística Libre
                </div>
                <div style="font-size:0.7rem; color:#888;">
                    Podés definir cualquier estadística para esta esfera (ej: un multiplicador especial, un atributo nuevo o una stat custom).
                </div>
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;">
                    <div>
                        <label style="font-size:0.7rem; color:#aaa; display:block; margin-bottom:4px;">Clave Técnica (Key)</label>
                        <input type="text" id="custom-sphere-stat-key" placeholder="ej: laser_burn_dmg o hp_pct" 
                            style="width:100%; padding:8px; background:rgba(0,0,0,0.3); border:1px solid rgba(255,255,255,0.12); border-radius:6px; color:#fff; font-family:'JetBrains Mono',monospace; font-size:0.75rem;">
                    </div>
                    <div>
                        <label style="font-size:0.7rem; color:#aaa; display:block; margin-bottom:4px;">Nombre Visible (Etiqueta)</label>
                        <input type="text" id="custom-sphere-stat-label" placeholder="ej: Quema de Láser" 
                            style="width:100%; padding:8px; background:rgba(0,0,0,0.3); border:1px solid rgba(255,255,255,0.12); border-radius:6px; color:#fff; font-size:0.75rem;">
                    </div>
                </div>
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:12px; align-items:flex-end;">
                    <div>
                        <label style="font-size:0.7rem; color:#aaa; display:block; margin-bottom:4px;">Ícono</label>
                        <input type="text" id="custom-sphere-stat-icon" value="🔮" 
                            style="width:100%; padding:6px; text-align:center; font-size:1.3rem; background:rgba(0,0,0,0.3); border:1px solid rgba(255,255,255,0.12); border-radius:6px; color:#fff;">
                    </div>
                    <div>
                        <label style="font-size:0.7rem; color:#aaa; display:block; margin-bottom:4px;">Valor Inicial</label>
                        <input type="number" step="0.01" id="custom-sphere-stat-val" value="0.05" 
                            style="width:100%; padding:8px; background:rgba(0,0,0,0.3); border:1px solid rgba(255,255,255,0.12); border-radius:6px; color:#fff; font-family:'JetBrains Mono',monospace; font-size:0.75rem;">
                    </div>
                </div>
                <div style="display:flex; justify-content:flex-end; margin-top:8px;">
                    <button type="button" onclick="submitCustomSphereStat(${sphereIdx})" 
                        class="btn btn-primary" style="padding:8px 22px; font-size:0.8rem;">
                        + Agregar a la Esfera
                    </button>
                </div>
            </div>
        `;
        return;
    }

    // Caso 2: Pestaña Dinámicas (Skills, Armas, Munición)
    if (activeTab === 'dynamic') {
        const cfg = (typeof config !== 'undefined' ? config : (window.config || {})) || {};
        const skillsList = cfg.skillsData ? Object.values(cfg.skillsData) : [];
        const weaponsList = cfg.shopItems && cfg.shopItems.weapons ? cfg.shopItems.weapons : [];
        const ammosList = [
            { id: 'laser', name: 'Láser Estándar' },
            { id: 'plasma', name: 'Plasma Pesado' },
            { id: 'missile', name: 'Misiles Dirigidos' },
            { id: 'emp', name: 'Pulso EMP' }
        ];

        const skillAttrs = window.SKILL_ATTRS || {
            cd:              { label: 'Cooldown',         icon: '⏱️' },
            castTimeMs:      { label: 'Casteo',           icon: '⏳' },
            amount:          { label: 'Poder (pts)',       icon: '💪' },
            range:           { label: 'Rango',            icon: '📏' },
            duration:        { label: 'Duración',         icon: '⏳' },
            radius:          { label: 'Radio/Área',       icon: '⭕' },
            speed:           { label: 'Velocidad',        icon: '🚀' }
        };

        const weaponAttrs = window.WEAPON_ATTRS || {
            base:            { label: 'Daño Base',        icon: '💥' },
            speedMod:        { label: 'Mod. Velocidad',   icon: '🚀' }
        };

        const ammoAttrs = window.AMMO_ATTRS || {
            cooldown:        { label: 'Cadencia',         icon: '⏱️' },
            bulletSpeed:     { label: 'Vel. Proyectil',   icon: '🚀' },
            range:           { label: 'Alcance',          icon: '📏' }
        };

        optionsContainer.innerHTML = `
            <div style="display:flex; flex-direction:column; gap:12px;">
                <!-- Habilidades -->
                <div style="background:rgba(255,255,255,0.02); border:1px solid rgba(249,115,22,0.3); border-radius:8px; padding:12px;">
                    <div style="font-size:0.8rem; font-weight:bold; color:#f97316; margin-bottom:8px;">🌀 Potenciar Habilidad Específica</div>
                    <div style="display:grid; grid-template-columns:1fr 1fr auto; gap:8px; align-items:center;">
                        <select id="sphere-dyn-skill-id" style="padding:6px; background:#141724; border:1px solid rgba(255,255,255,0.12); border-radius:4px; color:#fff; font-size:0.75rem;">
                            ${skillsList.map(s => `<option value="${s.id}">${s.name || s.id}</option>`).join('')}
                        </select>
                        <select id="sphere-dyn-skill-attr" style="padding:6px; background:#141724; border:1px solid rgba(255,255,255,0.12); border-radius:4px; color:#fff; font-size:0.75rem;">
                            ${Object.entries(skillAttrs).map(([k, v]) => `<option value="${k}">${v.label || k}</option>`).join('')}
                        </select>
                        <button type="button" class="btn" style="padding:6px 12px; font-size:0.7rem; background:rgba(249,115,22,0.2); border:1px solid #f97316; color:#fff; border-radius:4px;"
                            onclick="selectSphereDynamic('skill', document.getElementById('sphere-dyn-skill-id').value, document.getElementById('sphere-dyn-skill-attr').value)">
                            + Agregar
                        </button>
                    </div>
                </div>

                <!-- Armas -->
                <div style="background:rgba(255,255,255,0.02); border:1px solid rgba(239,68,68,0.3); border-radius:8px; padding:12px;">
                    <div style="font-size:0.8rem; font-weight:bold; color:#ef4444; margin-bottom:8px;">🔫 Potenciar Arma Específica</div>
                    <div style="display:grid; grid-template-columns:1fr 1fr auto; gap:8px; align-items:center;">
                        <select id="sphere-dyn-wep-id" style="padding:6px; background:#141724; border:1px solid rgba(255,255,255,0.12); border-radius:4px; color:#fff; font-size:0.75rem;">
                            ${weaponsList.map(w => `<option value="${w.id}">${w.name || w.id}</option>`).join('')}
                        </select>
                        <select id="sphere-dyn-wep-attr" style="padding:6px; background:#141724; border:1px solid rgba(255,255,255,0.12); border-radius:4px; color:#fff; font-size:0.75rem;">
                            ${Object.entries(weaponAttrs).map(([k, v]) => `<option value="${k}">${v.label || k}</option>`).join('')}
                        </select>
                        <button type="button" class="btn" style="padding:6px 12px; font-size:0.7rem; background:rgba(239,68,68,0.2); border:1px solid #ef4444; color:#fff; border-radius:4px;"
                            onclick="selectSphereDynamic('weapon', document.getElementById('sphere-dyn-wep-id').value, document.getElementById('sphere-dyn-wep-attr').value)">
                            + Agregar
                        </button>
                    </div>
                </div>

                <!-- Munición -->
                <div style="background:rgba(255,255,255,0.02); border:1px solid rgba(244,63,94,0.3); border-radius:8px; padding:12px;">
                    <div style="font-size:0.8rem; font-weight:bold; color:#f43f5e; margin-bottom:8px;">💣 Potenciar Tipo de Munición</div>
                    <div style="display:grid; grid-template-columns:1fr 1fr auto; gap:8px; align-items:center;">
                        <select id="sphere-dyn-ammo-id" style="padding:6px; background:#141724; border:1px solid rgba(255,255,255,0.12); border-radius:4px; color:#fff; font-size:0.75rem;">
                            ${ammosList.map(a => `<option value="${a.id}">${a.name || a.id}</option>`).join('')}
                        </select>
                        <select id="sphere-dyn-ammo-attr" style="padding:6px; background:#141724; border:1px solid rgba(255,255,255,0.12); border-radius:4px; color:#fff; font-size:0.75rem;">
                            ${Object.entries(ammoAttrs).map(([k, v]) => `<option value="${k}">${v.label || k}</option>`).join('')}
                        </select>
                        <button type="button" class="btn" style="padding:6px 12px; font-size:0.7rem; background:rgba(244,63,94,0.2); border:1px solid #f43f5e; color:#fff; border-radius:4px;"
                            onclick="selectSphereDynamic('ammo', document.getElementById('sphere-dyn-ammo-id').value, document.getElementById('sphere-dyn-ammo-attr').value)">
                            + Agregar
                        </button>
                    </div>
                </div>
            </div>
        `;
        return;
    }

    // Caso 3: Catálogo Normal (all, combate, defensa, utilidad, economía)
    const filtered = SPHERE_STATS_CATALOG.filter(item => {
        if (activeTab !== 'all' && item.cat !== activeTab) return false;
        if (searchVal) {
            const matchesKey = item.key.toLowerCase().includes(searchVal);
            const matchesLabel = item.label.toLowerCase().includes(searchVal);
            const matchesDesc = (item.desc || '').toLowerCase().includes(searchVal);
            if (!matchesKey && !matchesLabel && !matchesDesc) return false;
        }
        return true;
    });

    if (filtered.length === 0) {
        optionsContainer.innerHTML = `
            <div style="text-align:center; padding:30px; color:#666;">
                <div style="font-size:1.5rem; margin-bottom:6px;">🔍</div>
                <div style="font-size:0.8rem;">No se encontraron estadísticas para esa búsqueda.</div>
                <div style="font-size:0.7rem; margin-top:6px; color:#888;">Podés crear una nueva en la pestaña <b>Personalizada</b>.</div>
            </div>
        `;
        return;
    }

    optionsContainer.innerHTML = `
        <div style="display:grid; grid-template-columns:1fr 1fr; gap:8px;">
            ${filtered.map(item => {
                const isAlreadyAdded = currentStats.hasOwnProperty(item.key);
                const catColor = _getSphereCatColor(item.cat);
                return `
                <div style="background:rgba(255,255,255,0.025); border:1px solid ${isAlreadyAdded ? 'rgba(0,210,255,0.4)' : catColor + '25'}; border-radius:8px; padding:10px 12px; display:flex; align-items:center; justify-content:space-between; gap:10px; cursor:${isAlreadyAdded ? 'default' : 'pointer'}; transition:all 0.15s; ${isAlreadyAdded ? 'opacity:0.85;' : ''}"
                    ${!isAlreadyAdded ? `onclick="selectSphereStat(${sphereIdx}, '${item.key}', ${item.defaultVal})"` : ''}
                    onmouseover="if(!${isAlreadyAdded}) { this.style.borderColor='${catColor}'; this.style.background='rgba(255,255,255,0.05)'; }"
                    onmouseout="if(!${isAlreadyAdded}) { this.style.borderColor='${catColor}25'; this.style.background='rgba(255,255,255,0.025)'; }">
                    <div style="display:flex; align-items:center; gap:10px; min-width:0; flex:1;">
                        <span style="font-size:1.4rem; flex-shrink:0;">${item.icon}</span>
                        <div style="min-width:0;">
                            <div style="font-size:0.78rem; font-weight:bold; color:#fff; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${item.label}</div>
                            <div style="font-size:0.62rem; color:#777; font-family:'JetBrains Mono',monospace; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${item.key}</div>
                            <div style="font-size:0.62rem; color:#999; margin-top:2px; line-height:1.2;">${item.desc}</div>
                        </div>
                    </div>
                    <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:flex-end; gap:4px;">
                        ${isAlreadyAdded ? `
                            <span style="font-size:0.65rem; color:#00d2ff; font-weight:bold;">✓ Activa</span>
                        ` : `
                            <span style="font-size:0.68rem; color:#aaa; padding:3px 8px; border-radius:4px; background:rgba(255,255,255,0.04); border:1px solid rgba(255,255,255,0.1);">+ Agregar</span>
                        `}
                    </div>
                </div>`;
            }).join('')}
        </div>
    `;
};

window.selectSphereStat = function(sphereIdx, key, defaultVal) {
    const s = config.shopItems.spheres[sphereIdx];
    if (!s) return;
    if (!s.stats) s.stats = {};
    s.stats[key] = (typeof defaultVal === 'number') ? defaultVal : 0.05;
    closeSphereStatPickerModal();
    refreshSphereStatsBox(sphereIdx);
};

window.selectSphereDynamic = function(type, id, attr) {
    const sphereIdx = window._activeSphereIdx;
    if (sphereIdx === null || !config.shopItems.spheres || !config.shopItems.spheres[sphereIdx]) return;
    const s = config.shopItems.spheres[sphereIdx];
    if (!s.stats) s.stats = {};

    const key = `${type}:${id}:${attr}`;
    s.stats[key] = 0.05;
    closeSphereStatPickerModal();
    refreshSphereStatsBox(sphereIdx);
};

window.submitCustomSphereStat = function(sphereIdx) {
    const s = config.shopItems.spheres[sphereIdx];
    if (!s) return;
    if (!s.stats) s.stats = {};

    const keyInput = document.getElementById('custom-sphere-stat-key');
    const valInput = document.getElementById('custom-sphere-stat-val');

    let key = (keyInput ? keyInput.value : '').trim();
    if (!key) {
        if (keyInput) keyInput.style.borderColor = '#ff4444';
        return;
    }

    const rawVal = parseFloat(valInput ? valInput.value : 0.05) || 0.05;
    s.stats[key] = rawVal;
    closeSphereStatPickerModal();
    refreshSphereStatsBox(sphereIdx);
};

window.updateSphereStatVal = function(sphereIdx, key, newVal, isPct) {
    const s = config.shopItems.spheres[sphereIdx];
    if (!s) return;
    if (!s.stats) s.stats = {};
    const parsed = parseFloat(newVal) || 0;
    s.stats[key] = isPct ? (parsed / 100) : parsed;
};

window.toggleSphereStatType = function(sphereIdx, key) {
    const s = config.shopItems.spheres[sphereIdx];
    if (!s || !s.stats) return;
    if (!s.statsMeta) s.statsMeta = {};
    if (!s.statsMeta[key]) s.statsMeta[key] = {};

    const currentVal = s.stats[key] || 0;
    const isCurrentlyFlat = s.statsMeta[key].flat === true;

    // Invertir flag flat en statsMeta
    s.statsMeta[key].flat = !isCurrentlyFlat;

    // Si pasa a flat (fijo), el valor se multiplica por 100 si era porcentaje
    // Si pasa a pct (%), el valor se divide por 100 si era fijo
    if (!isCurrentlyFlat) {
        // Ahora es FIJO
        s.stats[key] = currentVal * 100;
    } else {
        // Ahora es %
        s.stats[key] = currentVal / 100;
    }

    refreshSphereStatsBox(sphereIdx);
};

window.removeSphereStat = function(sphereIdx, key) {
    const s = config.shopItems.spheres[sphereIdx];
    if (s && s.stats) {
        delete s.stats[key];
        if (s.statsMeta && s.statsMeta[key]) delete s.statsMeta[key];
        refreshSphereStatsBox(sphereIdx);
    }
};

// Retrocompatibilidad con nombres anteriores
window.addSphereStat = function(sphereIdx) {
    openSphereStatPickerModal(sphereIdx);
};
window.updateSphereStatKey = function(sphereIdx, oldKey, newKey) {
    const s = config.shopItems.spheres[sphereIdx];
    if (!s || !s.stats) return;
    if (s.stats[newKey] !== undefined) return;
    const val = s.stats[oldKey];
    delete s.stats[oldKey];
    s.stats[newKey] = val;
    refreshSphereStatsBox(sphereIdx);
};

function renderShips() {
    const grid = document.getElementById('ships-grid'); grid.innerHTML = '';
    const f = getFilter();
    config.shipModels.forEach((ship, idx) => {
        if(f && !ship.name.toLowerCase().includes(f) && !ship.id.toString().includes(f)) return;
        
        const shipIconWeb = resolveAssetWebUrl(ship.icon || '');
        const previewHtml = shipIconWeb ? `<img src="${shipIconWeb}" style="width:80px; height:80px; object-fit:contain; border-radius:6px; border:1px solid rgba(255,255,255,0.1); background:rgba(0,0,0,0.2);" onerror="this.style.display='none';">` : `<div style="width:80px; height:80px; border:1px dashed rgba(255,255,255,0.15); border-radius:6px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.75rem;">Sin Icono</div>`;

        const card = document.createElement('div'); card.className = 'card';
        card.style.position = 'relative';
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 8px;">
                <div style="background:rgba(255,255,255,0.06); color:#888; border:1px solid rgba(255,255,255,0.1); border-radius:4px; padding:2px 6px; font-size:0.75rem; font-family:'JetBrains Mono'; font-weight:bold;">#ID ${ship.id}</div>
                <div style="display:flex; gap:12px; align-items:center;">
                    <!-- Switch de visibilidad -->
                    <button style="background:none; border:none; color:${ship.hidden ? '#ff9f0a' : '#00d2ff'}; cursor:pointer; font-size:0.75rem; font-weight:bold; display:flex; align-items:center; gap:4px;" onclick="toggleShipVisibility(${idx})">
                        ${ship.hidden ? '🙈 OCULTO' : '👁️ VISIBLE'}
                    </button>
                    <!-- Eliminar -->
                    <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.75rem; font-weight:bold;" onclick="removeShip(${idx})">
                        ✕ ELIMINAR
                    </button>
                </div>
            </div>
            
            <div style="display:flex; gap:15px; align-items:flex-start; margin-top:0.5rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${previewHtml}
                    <button class="btn" style="padding:4px 8px; font-size:0.65rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.2); color:var(--primary); cursor:pointer; border-radius:4px;" onclick="openAssetPicker(${idx}, 'ship_icon')">🖼️ ICONO</button>
                </div>
                <div style="flex-grow:1; display:flex; flex-direction:column; gap:10px;">
                    <div class="field"><label>Nombre de la Nave</label><input type="text" value="${ship.name}" onchange="config.shipModels[${idx}].name = this.value"></div>
                    <div class="field">
                        <label>Ruta Asset 3D (.glb)</label>
                        <div style="display:flex; gap:8px; align-items:center; width:100%;">
                            <input type="text" value="${ship.assetPath || ''}" placeholder="res://assets/Personajes/3D/Nave..." onchange="config.shipModels[${idx}].assetPath = this.value" style="flex-grow:1; margin:0;">
                            <button class="btn btn-primary" style="padding:8px 12px; font-size:0.75rem; flex-shrink:0; background:var(--accent); border-color:var(--accent);" onclick="triggerAssetUpload(${idx}, 'ship_glb')">📁 SELECCIONAR GLB</button>
                        </div>
                    </div>
                </div>
            </div>

            <h5 style="color:var(--accent); margin:15px 0 5px; font-size:0.75rem; border-bottom:1px solid rgba(6,182,212,0.15); padding-bottom:2px;">⚙️ ROTACIÓN 3D INICIAL</h5>
            <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr; gap:10px; margin-bottom:15px; display:grid;">
                <div class="field"><label>Rotación X (grados)</label><input type="number" value="${ship.rotX || 0}" onchange="config.shipModels[${idx}].rotX = parseFloat(this.value) || 0"></div>
                <div class="field"><label>Rotación Y (grados)</label><input type="number" value="${ship.rotY || 0}" onchange="config.shipModels[${idx}].rotY = parseFloat(this.value) || 0"></div>
                <div class="field"><label>Rotación Z (grados)</label><input type="number" value="${ship.rotZ || 0}" onchange="config.shipModels[${idx}].rotZ = parseFloat(this.value) || 0"></div>
            </div>

            <h5 style="color:var(--primary); margin:15px 0 5px; font-size:0.75rem; border-bottom:1px solid rgba(0,210,255,0.15); padding-bottom:2px;">📊 ESTADÍSTICAS</h5>
            <div class="form-grid" style="margin-top: 0.5rem; display:grid;">
                <div class="field"><label>HP Total (pts)</label><input type="number" value="${ship.hp}" onchange="config.shipModels[${idx}].hp = parseInt(this.value)"></div>
                <div class="field"><label>Escudo Total (pts)</label><input type="number" value="${ship.shield}" onchange="config.shipModels[${idx}].shield = parseInt(this.value)"></div>
                <div class="field"><label>Velocidad (px/s)</label><input type="number" value="${ship.speed}" onchange="config.shipModels[${idx}].speed = parseInt(this.value)"></div>
                <div class="field"><label>Rango de Visión (px)</label><input type="number" value="${ship.vision || 1300}" onchange="config.shipModels[${idx}].vision = parseInt(this.value)"></div>
                <div class="field"><label>Daño Base (sin armas)</label><input type="number" value="${ship.baseDmg !== undefined ? ship.baseDmg : 100}" onchange="config.shipModels[${idx}].baseDmg = parseInt(this.value)"></div>
            </div>
            <div class="form-grid" style="margin-top: 1rem; padding-top: 1rem; border-top: 1px solid #333; display:grid;">
                <div class="field"><label>Slots Armas (W)</label><input type="number" value="${ship.slots.w || 0}" onchange="config.shipModels[${idx}].slots.w = parseInt(this.value)"></div>
                <div class="field"><label>Slots Escudos (S)</label><input type="number" value="${ship.slots.s || 0}" onchange="config.shipModels[${idx}].slots.s = parseInt(this.value)"></div>
                <div class="field"><label>Slots Motores (E)</label><input type="number" value="${ship.slots.e || 0}" onchange="config.shipModels[${idx}].slots.e = parseInt(this.value)"></div>
                <div class="field"><label>Slots Extras (X)</label><input type="number" value="${ship.slots.x || 0}" onchange="config.shipModels[${idx}].slots.x = parseInt(this.value)"></div>
            </div>
            <div class="price-group" style="display:flex; gap:15px; margin-top:1rem;">
                <div class="field" style="flex:1;"><label>Precio Hubs (qty)</label><input type="number" value="${ship.prices.hubs}" onchange="config.shipModels[${idx}].prices.hubs = parseInt(this.value)"></div>
                <div class="field" style="flex:1;"><label>Precio Ohcu (qty)</label><input type="number" value="${ship.prices.ohcu}" onchange="config.shipModels[${idx}].prices.ohcu = parseInt(this.value)"></div>
            </div>
        `;
        grid.appendChild(card);
    });
}

window.toggleShipVisibility = function(idx) {
    config.shipModels[idx].hidden = !config.shipModels[idx].hidden;
    renderShips();
};

window.toggleAmmoVisibility = function(type, i) {
    if (!config.shopItems.ammo[type][i]) config.shopItems.ammo[type][i] = {};
    config.shopItems.ammo[type][i].hidden = !config.shopItems.ammo[type][i].hidden;
    renderAmmo();
};

window.toggleWeaponVisibility = function(i) {
    if (!config.shopItems.weapons[i]) config.shopItems.weapons[i] = {};
    config.shopItems.weapons[i].hidden = !config.shopItems.weapons[i].hidden;
    renderWeapons();
};

window.toggleShieldVisibility = function(i) {
    if (!config.shopItems.shields[i]) config.shopItems.shields[i] = {};
    config.shopItems.shields[i].hidden = !config.shopItems.shields[i].hidden;
    renderShields();
};

window.toggleEngineVisibility = function(i) {
    if (!config.shopItems.engines[i]) config.shopItems.engines[i] = {};
    config.shopItems.engines[i].hidden = !config.shopItems.engines[i].hidden;
    renderEngines();
};

window.toggleSphereVisibility = function(i) {
    if (!config.shopItems.spheres[i]) config.shopItems.spheres[i] = {};
    config.shopItems.spheres[i].hidden = !config.shopItems.spheres[i].hidden;
    renderSpheres();
};

window.addNewSphere = function() {
    if (!config.shopItems.spheres) config.shopItems.spheres = [];
    let maxIdx = config.shopItems.spheres.length;
    const sphereColors = ['roja', 'azul', 'verde', 'amarilla'];
    const nextColor = sphereColors[maxIdx % sphereColors.length];
    const colorHexMap = { roja: '#ff4444', azul: '#4488ff', verde: '#44cc44', amarilla: '#ffcc00' };
    const newSphere = {
        id: 'esfera_' + (maxIdx + 1),
        name: 'Esfera Nueva ' + (maxIdx + 1),
        desc: 'Nueva esfera configurable.',
        type: 'sphere',
        icon: '',
        color: colorHexMap[nextColor] || '#ffffff',
        sphereColor: nextColor,
        maxStack: 1,
        soulbound: false,
        prices: { hubs: 5000, ohcu: 25 },
        stats: {}
    };
    config.shopItems.spheres.push(newSphere);
    renderSpheres();
};

window.removeNewShip = function(idx) {
    if (!config.shipModels) config.shipModels = [];
    let maxId = 0;
    config.shipModels.forEach(s => {
        if (s.id > maxId) maxId = s.id;
    });
    
    const newShip = {
        id: maxId + 1,
        name: "Nueva Nave N" + (maxId + 1),
        assetPath: "res://assets/Personajes/3D/Nave" + (maxId + 1) + "/Nave" + (maxId + 1) + ".glb",
        icon: "",
        rotX: 0,
        rotY: 0,
        rotZ: 0,
        hp: 3000,
        shield: 1000,
        speed: 300,
        vision: 1300,
        baseDmg: 100,
        slots: {
            w: 1,
            s: 1,
            e: 1,
            x: 1
        },
        prices: {
            hubs: 10000,
            ohcu: 100
        }
    };
    config.shipModels.push(newShip);
    renderShips();
};

window.removeShip = function(idx) {
    if (!config.shipModels) return;
    if (confirm(`¿Estás seguro de que deseas eliminar la nave "${config.shipModels[idx].name}"?`)) {
        config.shipModels.splice(idx, 1);
        renderShips();
    }
};



window.removeEnemy = function(id) {
    if (confirm(`¿Estás seguro de que deseas eliminar el enemigo #${id} "${config.enemyModels[id]?.name || 'Enemigo ' + id}"?`)) {
        delete config.enemyModels[id];
        renderEnemies();
    }
};

window.addNewThreat = function() {
    // Calcula el siguiente ID correlativo de cada rango para mostrarlo en el modal
    let maxCommon = 0, maxBoss = 100;
    for(let id in (config.enemyModels || {})) {
        if (id.includes('-')) continue;
        const eid = parseInt(id);
        if (isNaN(eid)) continue;
        if (eid >= 101 && eid > maxBoss) maxBoss = eid;
        else if (eid < 100 && eid > maxCommon) maxCommon = eid;
    }
    document.getElementById('threat-common-id').innerText = 'ID ' + (maxCommon + 1);
    document.getElementById('threat-boss-id').innerText = 'ID ' + (maxBoss + 1);
    document.getElementById('threat-add-overlay').style.display = 'flex';
};

window.closeThreatAddModal = function() {
    document.getElementById('threat-add-overlay').style.display = 'none';
};

window.createThreatFromModal = function(kind) {
    closeThreatAddModal();
    if (kind === 'boss') addNewBoss();
    else addNewEnemy();
};

window.addNewEnemy = function() {
    if (!config.enemyModels) config.enemyModels = {};
    let maxId = 0;
    for(let id in config.enemyModels) {
        if (id.includes('-')) continue;
        const eid = parseInt(id);
        if (isNaN(eid) || eid >= 100) continue; // Solo enemigos comunes (ID < 100); los bosses se crean con addNewBoss()
        if (eid > maxId) maxId = eid;
    }
    
    const newId = (maxId + 1).toString();
    config.enemyModels[newId] = {
        id: newId,
        name: `Nuevo Enemigo ${newId}`,
        icon: "",
        assetPath: "res://assets/Enemigos/3D/Enemigo" + newId + "/Enemigo" + newId + ".glb",
        rotX: 0,
        rotY: 90,
        rotZ: 0,
        scale: 2.0,
        movementAI: 'chase',
        hp: 3000,
        shield: 1000,
        speed: 250,
        stopDist: 150,
        startDelay: 0,
        visionRange: 800,
        chaseIdleTimeout: 0,
        leashRange: 0,
        hpRegenPercent: 3,
        shieldRegenPercent: 5,
        regenDelaySec: 5,
        regenIntervalMs: 1000,
        rewardExp: 300,
        rewardHubs: 300,
        rewardOhcu: 3,
        chestDropChance: 0.1,
        rankingPoints: newId,
        aggressive: false,
        chaseUntilDeath: false,
        stopOnOutOfSight: false,
        mechanics: [{ type: "laser", bulletDamage: 10, bulletSpeed: 800, fireRange: 600, fireRate: 1000, startDelay: 0 }],
        movementPhases: [{ type: 'chase', speed: 250, stopDist: 150, startDelay: 0 }],
        defenseMechanics: [],
        lootDrops: []
    };
    renderEnemies();
    selectEnemy(newId);
};

window.addNewBoss = function() {
    if (!config.enemyModels) config.enemyModels = {};
    let maxId = 100;
    for(let id in config.enemyModels) {
        if (id.includes('-')) continue;
        const eid = parseInt(id);
        if (isNaN(eid)) continue;
        if (eid >= 101 && eid > maxId) maxId = eid;
    }
    
    const newId = (maxId + 1).toString();
    const bossNumber = maxId - 100 + 1;
    config.enemyModels[newId] = {
        id: newId,
        name: `Nuevo Boss ${newId}`,
        icon: "",
        assetPath: "res://assets/Enemigos/3D/Bosses/Boss" + bossNumber + "/Boss" + bossNumber + ".glb",
        rotX: 0,
        rotY: 90,
        rotZ: 0,
        scale: 6.0,
        isBoss: true,
        rageTimer: 20,
        movementAI: 'boss',
        hp: 100000,
        shield: 50000,
        speed: 250,
        stopDist: 150,
        startDelay: 0,
        visionRange: 2000,
        chaseIdleTimeout: 10000,
        leashRange: 2500,
        hpRegenPercent: 25,
        shieldRegenPercent: 30,
        regenDelayMs: 20000,
        regenIntervalMs: 2000,
        rewardExp: 50000,
        rewardHubs: 100000,
        rewardOhcu: 1000,
        chestDropChance: 0.5,
        rankingPoints: parseInt(newId),
        aggressive: true,
        chaseUntilDeath: true,
        stopOnOutOfSight: false,
        mechanics: [{ type: "laser", bulletDamage: 500, bulletSpeed: 900, fireRange: 1200, fireRate: 900, startDelay: 0 }],
        movementPhases: [{ type: 'boss', speed: 250, stopDist: 150, startDelay: 0 }],
        defenseMechanics: [],
        lootDrops: [{ chance: 0.5, itemId: "las1" }, { chance: 0.5, itemId: "sh1" }]
    };
    renderEnemies();
    selectEnemy(newId);
};
