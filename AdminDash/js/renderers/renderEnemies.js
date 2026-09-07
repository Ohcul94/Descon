// AdminDash/js/renderers/renderEnemies.js
// v900.0: helpers sonido mecanicas hybrid
function mechanicSoundOverrideHtml(enemyId, listName, idx, mech) {
    const libKey = mech.type;
    const MECHANICS_LIB_X = config.mechanicsLib || DEFAULT_MECHANICS_LIB;
    const DEFENSE_LIB_X = config.defenseLib || DEFAULT_DEFENSE_LIB;
    const MOVEMENT_LIB_X = config.movementLib || DEFAULT_MOVEMENT_LIB;
    let lib = MECHANICS_LIB_X[libKey] || DEFENSE_LIB_X[libKey] || MOVEMENT_LIB_X[libKey] || null;
    const defaultSound = lib ? (lib.sound || '') : '';
    const hasOverride = !!(mech.sound && mech.sound !== '');
    const effective = hasOverride ? mech.sound : defaultSound;
    const vol = hasOverride ? (mech.soundVolumePercent !== undefined ? mech.soundVolumePercent : (lib ? lib.soundVolumePercent : 50)) : (lib ? lib.soundVolumePercent : 50);
    const maxd = hasOverride ? (mech.soundMaxDist || (lib ? lib.soundMaxDist : 1200)) : (lib ? lib.soundMaxDist : 1200);
    const preview = effective ? resolveAssetWebUrl(effective) : '';
    return `
    <div class="mech-sound-override" style="margin-top:0.6rem; padding:0.7rem; background:rgba(168,85,247,0.05); border:1px solid rgba(168,85,247,0.12); border-radius:6px; border-left:2px solid #a855f7;">
        <label style="color:#a855f7; font-size:0.6rem; font-weight:bold; display:flex; align-items:center; gap:6px;">SONIDO (Override por enemigo) <span style="font-weight:normal; color:#888; font-size:0.55rem;">vacío = hereda de librería</span></label>
        <div style="font-size:0.55rem; color:#888; margin-top:0.2rem;">Default librería: <span style="color:#a855f7; font-family:JetBrains Mono;">${defaultSound || '(sin sonido)'}</span></div>
        <div style="display:flex; gap:6px; align-items:center; margin-top:0.4rem;">
            <input type="text" placeholder="res://assets/Sonidos/Mecanicas/ej.ogg" value="${mech.sound || ''}" style="flex:1; font-size:0.65rem;" onchange="config.enemyModels['${enemyId}']['${listName}'][${idx}].sound = this.value; renderEnemyDetail();">
            <button class="btn" style="padding:4px 8px; font-size:0.6rem; background:rgba(168,85,247,0.12); border:1px solid rgba(168,85,247,0.25); color:#a855f7;" onclick="triggerAssetUpload('${enemyId}_${listName}_${idx}', 'mechanic_instance_sound')">SONIDO</button>
            ${mech.sound ? `<button class="btn" style="padding:2px 6px; font-size:0.55rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060;" onclick="config.enemyModels['${enemyId}']['${listName}'][${idx}].sound=''; renderEnemyDetail();">X</button>` : ''}
        </div>
        ${preview ? `<audio controls preload="none" src="${preview}" style="width:100%; height:26px; margin-top:0.4rem;"></audio><div style="font-size:0.55rem; color:#a855f7; font-family:JetBrains Mono; overflow:hidden; text-overflow:ellipsis;">Efectivo: ${effective}</div>` : ''}
        <div style="display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:0.4rem;">
            <div class="field"><label>Volumen <input type="number" id="mech-override-vol-input-${enemyId}-${listName}-${idx}" min="0" max="100" value="${mech.soundVolumePercent !== undefined ? mech.soundVolumePercent : (lib ? lib.soundVolumePercent : 50)}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid #a855f7; color:#a855f7; font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.enemyModels['${enemyId}']['${listName}'][${idx}].soundVolumePercent=v; let s=document.getElementById('mech-override-vol-slider-${enemyId}-${listName}-${idx}'); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.enemyModels['${enemyId}']['${listName}'][${idx}].soundVolumePercent=v; let s=document.getElementById('mech-override-vol-slider-${enemyId}-${listName}-${idx}'); if(s) s.value=v;"> %</label><input type="range" id="mech-override-vol-slider-${enemyId}-${listName}-${idx}" min="0" max="100" value="${mech.soundVolumePercent !== undefined ? mech.soundVolumePercent : (lib ? lib.soundVolumePercent : 50)}" oninput="config.enemyModels['${enemyId}']['${listName}'][${idx}].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById('mech-override-vol-input-${enemyId}-${listName}-${idx}'); if(inp) inp.value=this.value;"></div>
            <div class="field"><label>Dist. Máx. (px)</label><input type="number" step="50" value="${mech.soundMaxDist !== undefined ? mech.soundMaxDist : ''}" placeholder="${lib ? lib.soundMaxDist : 1200}" onchange="config.enemyModels['${enemyId}']['${listName}'][${idx}].soundMaxDist = this.value === '' ? undefined : parseInt(this.value)"></div>
        </div>
    </div>`;
}

function renderEnemies() {
    const MECHANICS_LIB = config.mechanicsLib || DEFAULT_MECHANICS_LIB;
    const MOVEMENT_LIB = config.movementLib || DEFAULT_MOVEMENT_LIB;

    updateSidebar();
    const grid = document.getElementById('enemies-grid'); grid.innerHTML = '';
    
    // Botón de Purga Total
    const purgeBtn = document.createElement('button');
    purgeBtn.className = 'btn';
    purgeBtn.style.background = '#ff4444';
    purgeBtn.style.marginBottom = '1rem';
    purgeBtn.style.width = '100%';
    purgeBtn.innerText = '🔥 PURGAR TODOS LOS ENEMIGOS DEL SERVIDOR';
    purgeBtn.onclick = () => {
        if(confirm('¿Estás seguro? Esto eliminará a todos los bichos de todos los mapas.')) {
            socket.emit('adminPurgeEnemies');
        }
    };
    grid.appendChild(purgeBtn);

    const f = getFilter();

    for(let id in config.enemyModels) {
        if (id.includes('-')) continue; // Ocultar variantes sub-tier de la grilla principal
        
        const en = config.enemyModels[id];
        const eid = parseInt(id);
        if (currentEnemySubTab === 'regular' && eid >= 100) continue;
        if (currentEnemySubTab === 'boss' && eid < 100) continue;
        
        const matches = en.name.toLowerCase().includes(f) || id.includes(f) || JSON.stringify(en).toLowerCase().includes(f);
        if (f && !matches) continue;

        const card = document.createElement('div'); card.className = 'card';
        card.style.cursor = 'pointer';
        card.onclick = () => selectEnemy(id);
        const enemyIconWeb = resolveAssetWebUrl(en.icon || '');
        const previewHtml = enemyIconWeb ? `<img src="${enemyIconWeb}" style="width:80px; height:80px; object-fit:contain; border-radius:6px; border:1px solid rgba(255,255,255,0.1); background:rgba(0,0,0,0.2);" onerror="this.style.display='none';">` : `<div style="width:80px; height:80px; border:1px dashed rgba(255,255,255,0.15); border-radius:6px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.75rem;">Sin Icono</div>`;
        const cardHtml = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 8px;">
                <div style="background:rgba(255,255,255,0.06); color:#888; border:1px solid rgba(255,255,255,0.1); border-radius:4px; padding:2px 6px; font-size:0.75rem; font-family:'JetBrains Mono'; font-weight:bold;">#ID ${id}</div>
                <div style="display:flex; gap:12px; align-items:center;">
                    <button class="btn" style="padding:4px 8px; font-size:0.65rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.2); color:var(--primary); cursor:pointer; border-radius:4px;" onclick="openAssetPicker('${id}', 'enemy_icon')">🖼️ ICONO</button>
                    <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.75rem; font-weight:bold;" onclick="removeEnemy('${id}'); renderEnemies();">✕ ELIMINAR</button>
                </div>
            </div>
            
            <div style="display:flex; gap:15px; align-items:flex-start; margin-top:0.5rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${previewHtml}
                </div>
                <div style="flex-grow:1; display:flex; flex-direction:column; gap:10px;">
                    <div class="field"><label>Nombre del Enemigo</label><input type="text" value="${en.name}" onchange="config.enemyModels['${id}'].name = this.value; renderEnemies();"></div>
                    <div class="field">
                        <label>IA de Movimiento</label>
                        <select onchange="config.enemyModels['${id}'].movementAI = this.value; renderEnemies();">
                            <option value="chase" ${en.movementAI === 'chase' ? 'selected' : ''}>Persecución Directa</option>
                            <option value="sniper" ${en.movementAI === 'sniper' ? 'selected' : ''}>Francotirador (Kiting)</option>
                            <option value="orbit" ${en.movementAI === 'orbit' ? 'selected' : ''}>Órbita Circular</option>
                            <option value="charger" ${en.movementAI === 'charger' ? 'selected' : ''}>Embestida (Dash)</option>
                            <option value="zigzag" ${en.movementAI === 'zigzag' ? 'selected' : ''}>Movimiento ZigZag</option>
                            <option value="kamikaze" ${en.movementAI === 'kamikaze' ? 'selected' : ''}>Kamikaze</option>
                            <option value="prowler" ${en.movementAI === 'prowler' ? 'selected' : ''}>Merodeador</option>
                            <option value="aura_speed" ${en.movementAI === 'aura_speed' ? 'selected' : ''}>Aura de Impulso</option>
                        </select>
                    </div>
                </div>
            </div>
            
            <h5 style="color:var(--accent); margin:15px 0 5px; font-size:0.75rem; border-bottom:1px solid rgba(6,182,212,0.15); padding-bottom:2px;">⚙️ ESTADÍSTICAS BÁSICAS</h5>
            <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr 1fr; gap:10px; margin-bottom:15px; display:grid;">
                <div class="field"><label>HP (pts)</label><input type="number" value="${en.hp || 100}" onchange="config.enemyModels['${id}'].hp = parseInt(this.value); renderEnemies();"></div>
                <div class="field"><label>Escudo (pts)</label><input type="number" value="${en.shield || 0}" onchange="config.enemyModels['${id}'].shield = parseInt(this.value); renderEnemies();"></div>
                <div class="field"><label>Velocidad (px/s)</label><input type="number" value="${en.speed || 3.5}" onchange="config.enemyModels['${id}'].speed = parseFloat(this.value); renderEnemies();"></div>
                <div class="field"><label>Rango de Visión (px)</label><input type="number" value="${en.visionRange || 800}" onchange="config.enemyModels['${id}'].visionRange = parseInt(this.value); renderEnemies();"></div>
            </div>
        `;
        card.innerHTML = cardHtml;
        grid.appendChild(card);
    }
}

function renderEnemyDetail() {
    updateSidebar();
    const MECHANICS_LIB = config.mechanicsLib || DEFAULT_MECHANICS_LIB;
    const MOVEMENT_LIB = config.movementLib || DEFAULT_MOVEMENT_LIB;
    const DEFENSE_LIB = config.defenseLib || DEFAULT_DEFENSE_LIB;

    const container = document.getElementById('enemy-detail-container');
    const baseId = selectedEnemyId ? selectedEnemyId.split('-')[0] : '';
    const tiers = [
        { suffix: '', label: 'Base (x1)' },
        { suffix: '-A', label: 'Tier A (x2)', mult: 2, key: 'A' },
        { suffix: '-B', label: 'Tier B (x3)', mult: 3, key: 'B' },
        { suffix: '-C', label: 'Tier C (x4)', mult: 4, key: 'C' },
        { suffix: '-D', label: 'Tier D (x5)', mult: 5, key: 'D' }
    ];

    if (baseId && parseInt(baseId) < 100) {
        const parentModel = config.enemyModels[baseId];
        if (parentModel) {
            tiers.forEach(t => {
                if (t.suffix === '') return;
                const tierId = `${baseId}${t.suffix}`;
                if (!config.enemyModels[tierId]) {
                    const clone = JSON.parse(JSON.stringify(parentModel));
                    clone.name = `${parentModel.name || 'Enemigo ' + baseId} ${t.key}`;
                    clone.hp = parentModel.hp * t.mult;
                    clone.shield = parentModel.shield * t.mult;
                    if (clone.bulletDamage !== undefined) clone.bulletDamage = parentModel.bulletDamage * t.mult;
                    if (clone.rewardExp !== undefined) clone.rewardExp = parentModel.rewardExp * t.mult;
                    if (clone.rewardHubs !== undefined) clone.rewardHubs = parentModel.rewardHubs * t.mult;
                    if (clone.rewardOhcu !== undefined) clone.rewardOhcu = parentModel.rewardOhcu * t.mult;
                    if (Array.isArray(clone.mechanics)) {
                        clone.mechanics.forEach(m => {
                            if (m.bulletDamage !== undefined) m.bulletDamage = m.bulletDamage * t.mult;
                            if (m.damage !== undefined) m.damage = m.damage * t.mult;
                        });
                    }
                    config.enemyModels[tierId] = clone;
                }
            });
        }
    }

    const en = config.enemyModels[selectedEnemyId];
    if(!en) return;

    if (!en.mechanics) {
        en.mechanics = [{ type: "laser", bulletDamage: 10, bulletSpeed: 800, fireRange: 600, fireRate: 1000, startDelay: 0 }];
    }
    if (!en.movementPhases) {
        en.movementPhases = [{ type: en.movementAI || "chase", speed: en.speed || 3.5, stopDist: en.stopDist || 150, startDelay: 0 }];
    }
    if (!en.defenseMechanics) en.defenseMechanics = [];

    container.innerHTML = `
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 2rem; align-items: start;">
            <div class="col">
                <div class="card" style="width:100%; margin-bottom: 2rem;">
                    <div class="field full"><label>NOMBRE DE LA ENTIDAD (#ID ${selectedEnemyId})</label><input type="text" value="${en.name}" style="font-size: 1.5rem; color:var(--accent);" onchange="config.enemyModels['${selectedEnemyId}'].name = this.value; updateSidebar();"></div>
                    <div class="form-grid" style="margin-top:1rem; padding-bottom: 1rem; border-bottom: 1px solid #333;">
                        <div class="field"><label>HP (pts)</label><input type="number" value="${en.hp}" onchange="config.enemyModels['${selectedEnemyId}'].hp = parseInt(this.value)"></div>
                        <div class="field"><label>Escudo (pts)</label><input type="number" value="${en.shield}" onchange="config.enemyModels['${selectedEnemyId}'].shield = parseInt(this.value)"></div>
                    </div>
                    <div class="price-group" style="margin-top:1rem;">
                        <div class="field"><label>Exp (pts)</label><input type="number" value="${en.rewardExp || 0}" onchange="config.enemyModels['${selectedEnemyId}'].rewardExp = parseInt(this.value)"></div>
                        <div class="field"><label>Hubs (pts)</label><input type="number" value="${en.rewardHubs || 0}" onchange="config.enemyModels['${selectedEnemyId}'].rewardHubs = parseInt(this.value)"></div>
                        <div class="field"><label style="color:var(--primary);">Ohcu (qty)</label><input type="number" value="${en.rewardOhcu || 0}" onchange="config.enemyModels['${selectedEnemyId}'].rewardOhcu = parseInt(this.value)"></div>
                        <div class="field"><label style="color:var(--accent);">Probabilidad de Cofre (%)</label><input type="number" min="0" max="100" step="1" value="${en.chestDropChance !== undefined ? Math.round(en.chestDropChance * 100) : 10}" onchange="config.enemyModels['${selectedEnemyId}'].chestDropChance = parseFloat(this.value) / 100"></div>
                        <div class="field"><label style="color:var(--warning);">🏆 Pts Ranking</label><input type="number" value="${en.rankingPoints !== undefined ? en.rankingPoints : parseInt(selectedEnemyId.split('-')[0])}" onchange="config.enemyModels['${selectedEnemyId}'].rankingPoints = parseInt(this.value)"></div>
                    </div>
                    
                    <h5 style="color:var(--warning); margin:15px 0 5px; font-size:0.75rem; border-bottom:1px solid rgba(251,191,36,0.15); padding-bottom:2px;">🖼️ ASSETS Y PREVIOS</h5>
                    <div style="display:flex; gap:15px; align-items:flex-start; margin-top:1rem;">
                        <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                            <label style="color:var(--warning); font-size:0.7rem;">Icono 2D del Enemigo</label>
                            <div style="width:80px; height:80px; border:1px dashed rgba(251,191,36,0.3); border-radius:6px; display:flex; align-items:center; justify-content:center; background:rgba(251,191,36,0.05);">
                                ${(config.enemyModels[selectedEnemyId]?.icon) ? 
                                    `<img src="${resolveAssetWebUrl(config.enemyModels[selectedEnemyId].icon)}" style="width:80px; height:80px; object-fit:contain;">` :
                                    `<div style="color:rgba(251,191,36,0.5); font-size:0.7rem;">Sin Icono</div>`}
                            </div>
                            <button class="btn" style="padding:4px 8px; font-size:0.65rem; background:rgba(251,191,36,0.08); border:1px solid rgba(251,191,36,0.2); color:var(--warning); cursor:pointer; border-radius:4px;" onclick="openAssetPicker('${selectedEnemyId}', 'enemy_icon'); renderEnemyDetail();">🖼️ CAMBIAR ICONO</button>
                        </div>
                        <div style="flex-grow:1; display:flex; flex-direction:column; gap:10px;">
                            <div class="field" style="margin-bottom:10px;">
                                <label>Asset Path 3D (.glb)</label>
                                <div style="display:flex; gap:8px; align-items:center; width:100%;">
                                    <input type="text" value="${config.enemyModels[selectedEnemyId]?.assetPath || ''}" placeholder="res://assets/Enemigos/3D/Enemigo..." onchange="config.enemyModels['${selectedEnemyId}'].assetPath = this.value; renderEnemyDetail();" style="flex-grow:1; margin:0;"></input>
                                    <button class="btn btn-primary" style="padding:8px 12px; font-size:0.75rem; flex-shrink:0; background:var(--warning); border-color:var(--warning);" onclick="openAssetPicker('${selectedEnemyId}', 'enemy_glb'); renderEnemyDetail();">📁 SELECCIONAR GLB</button>
                                </div>
                            </div>
                            <h5 style="color:var(--warning); margin:10px 0 5px; font-size:0.75rem; border-bottom:1px solid rgba(251,191,36,0.15); padding-bottom:2px;">⚙️ ROTACIÓN Y ESCALA 3D INICIAL</h5>
                            <div class="form-grid" style="grid-template-columns: repeat(3, 1fr); gap:10px; display:grid; margin-bottom:10px;">
                                <div class="field"><label>Rotación X (grados)</label><input type="number" value="${en.rotX || 0}" onchange="config.enemyModels['${selectedEnemyId}'].rotX = parseFloat(this.value) || 0"></div>
                                <div class="field"><label>Rotación Y (grados)</label><input type="number" value="${en.rotY || 0}" onchange="config.enemyModels['${selectedEnemyId}'].rotY = parseFloat(this.value) || 0"></div>
                                <div class="field"><label>Rotación Z (grados)</label><input type="number" value="${en.rotZ || 0}" onchange="config.enemyModels['${selectedEnemyId}'].rotZ = parseFloat(this.value) || 0"></div>
                                <div class="field"><label>Escala 3D (mult)</label><input type="number" step="0.1" value="${en.scale || 2}" onchange="config.enemyModels['${selectedEnemyId}'].scale = parseFloat(this.value) || 2"></div>
                                <div class="field"><label>Altura Suelo (posY)</label><input type="number" step="0.1" value="${en.posY !== undefined ? en.posY : 1.0}" onchange="config.enemyModels['${selectedEnemyId}'].posY = parseFloat(this.value) !== undefined ? parseFloat(this.value) : 1.0"></div>
                            </div>
                            
                            <h5 style="color:var(--warning); margin:10px 0 5px; font-size:0.75rem; border-bottom:1px solid rgba(251,191,36,0.15); padding-bottom:2px;">🏃 CONFIGURACIÓN DE ANIMACIONES 3D (GLB)</h5>
                            <div class="form-grid" style="grid-template-columns: repeat(2, 1fr); gap:10px; display:grid;">
                                <div class="field"><label>Animación Quieto (Idle)</label><input type="text" value="${en.animIdle || ''}" placeholder="Ej: 1 o idle" onchange="config.enemyModels['${selectedEnemyId}'].animIdle = this.value"></div>
                                <div class="field"><label>Animación Correr (Run)</label><input type="text" value="${en.animRun || ''}" placeholder="Ej: 5 o run" onchange="config.enemyModels['${selectedEnemyId}'].animRun = this.value"></div>
                                <div class="field"><label>Animación Atacar (Attack)</label><input type="text" value="${en.animAttack || ''}" placeholder="Ej: 4 o attack" onchange="config.enemyModels['${selectedEnemyId}'].animAttack = this.value"></div>
                                <div class="field"><label>Animación Morir (Die)</label><input type="text" value="${en.animDie || ''}" placeholder="Ej: 3 o die" onchange="config.enemyModels['${selectedEnemyId}'].animDie = this.value"></div>
                                <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; grid-column: span 2; margin-top: 5px;">
                                    <input type="checkbox" ${en.canFloat !== false ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].canFloat = this.checked">
                                    <label style="margin:0; font-weight:bold; color:var(--warning);">🛸 Efecto de Flotación/Balanceo (Bobbing)</label>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="card" style="width:100%; margin-bottom: 2rem; border-color: var(--accent); background: rgba(6, 182, 212, 0.1);">
                    <label style="color:var(--accent); font-size: 0.7rem; font-weight:bold; margin-bottom:1rem; display:block;">🧠 COMPORTAMIENTO GLOBAL</label>
                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
                        <div class="field" style="display:flex; align-items:center; gap:10px; background:transparent; border:none;">
                            <input type="checkbox" ${en.aggressive ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].aggressive = this.checked">
                            <label style="margin:0;">Agresivo (Ataca al ver)</label>
                        </div>
                        <div class="field" style="display:flex; align-items:center; gap:10px; background:transparent; border:none;">
                            <input type="checkbox" ${en.chaseUntilDeath ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].chaseUntilDeath = this.checked">
                            <label style="margin:0;">Persistir hasta morir</label>
                        </div>
                        <div class="field" style="display:flex; align-items:center; gap:10px; background:transparent; border:none;">
                            <input type="checkbox" ${en.stopOnOutOfSight ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].stopOnOutOfSight = this.checked">
                            <label style="margin:0;">Parar si no hay visión</label>
                        </div>
                        <div class="field"><label>Timeout Abandono (ms)</label><input type="number" value="${en.chaseIdleTimeout || 0}" onchange="config.enemyModels['${selectedEnemyId}'].chaseIdleTimeout = parseInt(this.value)"></div>
                        <div class="field"><label>Rango de Visión (px)</label><input type="number" value="${en.visionRange || 800}" onchange="config.enemyModels['${selectedEnemyId}'].visionRange = parseInt(this.value)"></div>
                        <div class="field"><label>Rango de Retorno al Spawn (px)</label><input type="number" value="${en.leashRange || 0}" onchange="config.enemyModels['${selectedEnemyId}'].leashRange = parseInt(this.value)"></div>
                        <div class="field"><label>Regeneración de Vida Fuera de Combate (%)</label><input type="number" value="${en.hpRegenPercent !== undefined ? en.hpRegenPercent : 3}" onchange="config.enemyModels['${selectedEnemyId}'].hpRegenPercent = parseFloat(this.value)"></div>
                        <div class="field"><label>Regeneración de Escudo Fuera de Combate (%)</label><input type="number" value="${en.shieldRegenPercent !== undefined ? en.shieldRegenPercent : 5}" onchange="config.enemyModels['${selectedEnemyId}'].shieldRegenPercent = parseFloat(this.value)"></div>
                        <div class="field"><label>Tiempo Espera Fuera de Combate (ms)</label><input type="number" value="${en.regenDelayMs !== undefined ? en.regenDelayMs : (en.regenDelaySec !== undefined ? en.regenDelaySec * 1000 : 5000)}" onchange="config.enemyModels['${selectedEnemyId}'].regenDelayMs = parseInt(this.value); delete config.enemyModels['${selectedEnemyId}'].regenDelaySec;"></div>
                        <div class="field"><label>Intervalo de Regeneración (ms)</label><input type="number" value="${en.regenIntervalMs !== undefined ? en.regenIntervalMs : 1000}" onchange="config.enemyModels['${selectedEnemyId}'].regenIntervalMs = parseInt(this.value)"></div>
                    </div>
                </div>
                <div style="margin-bottom: 1rem; display:flex; justify-content:space-between; align-items:center;">
                    <label style="color:#eab308; font-size: 0.8rem; font-weight:bold;">🏃 CICLO DE MOVIMIENTO</label>
                    <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background:#eab308; box-shadow: 0 4px 15px rgba(234, 179, 8, 0.3);" onclick="addMovementPhase('${selectedEnemyId}'); renderEnemyDetail();">+ AGREGAR FASE</button>
                </div>
                <div id="move-list-${selectedEnemyId}">
                    ${en.movementPhases.map((m, idx) => `
                        <div class="card" style="margin-bottom:1rem; position:relative; padding: 1rem; background: rgba(234, 179, 8, 0.05); border: 1px solid rgba(234, 179, 8, 0.2);">
                            <div style="position:absolute; top:8px; right:8px; display:flex; gap:10px;">
                                <button style="background:none; border:none; color:#eab308; cursor:pointer; font-weight:bold;" onclick="moveMovementPhase('${selectedEnemyId}', ${idx}, -1); renderEnemyDetail();">SUBIR</button>
                                <button style="background:none; border:none; color:#eab308; cursor:pointer; font-weight:bold;" onclick="moveMovementPhase('${selectedEnemyId}', ${idx}, 1); renderEnemyDetail();">BAJAR</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="removeMovementPhase('${selectedEnemyId}', ${idx}); renderEnemyDetail();">✕</button>
                            </div>
                            <div class="field full">
                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;" onchange="updateMovementPhaseType('${selectedEnemyId}', ${idx}, this.value); renderEnemyDetail();">
                                    ${Object.keys(MOVEMENT_LIB).map(type => `<option value="${type}" ${m.type === type ? 'selected' : ''} style="background:#0f172a; color:white;">${MOVEMENT_LIB[type].icon} ${MOVEMENT_LIB[type].label}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-grid" style="margin-top:1rem;">
                                ${(MOVEMENT_LIB[m.type] || MOVEMENT_LIB['chase']).fields.map(f => {
                                    const moveLabels = { speed:"Velocidad (px/s)", stopDist:"Frenado (px)", idealDist:"Rango Seguro (px)", orbitRadius:"Radio Órbita (px)", chargeCooldown: "Recarga Dash (ms)", activationHP: "Activación HP (%)", explosionDamage: "Daño Explosión", duration: "Duración (ms)", cooldown: "Recarga (ms)", startDelay: "Retraso Inicio (ms)", explodeOnDeath: "Explotar al morir", radius: "Radio del Aura (px)", speedBonus: "Bono de Velocidad (px/s)", intervalMs: "Intervalo de Tick (ms)", affectsEnemies: "Afectar a otros Enemigos", affectsBosses: "Afectar a Bosses", patrolRange: "Rango de Patrulla (px)", changeInterval: "Frecuencia del Cambio (ms / px)", amplitude: "Amplitud (px)", frequency: "Frecuencia (Hz)", visionRange: "Rango de Visión (px)", targetPriority: "Prioridad de Objetivo" };
                                    if (f === 'changeTrigger') {
                                        const val = m[f] || 'time';
                                        return `<div class="field"><label>Criterio de Cambio</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].changeTrigger = this.value; renderEnemyDetail();">
                                            <option value="time" ${val === 'time' ? 'selected' : ''}>⏳ Tiempo</option>
                                            <option value="distance" ${val === 'distance' ? 'selected' : ''}>📏 Recorrido</option>
                                        </select></div>`;
                                    }
                                    if (f === 'changeType') {
                                        const val = m[f] || 'random';
                                        return `<div class="field"><label>Tipo de Giro</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].changeType = this.value; renderEnemyDetail();">
                                            <option value="random" ${val === 'random' ? 'selected' : ''}>🔀 Aleatorio</option>
                                            <option value="reverse" ${val === 'reverse' ? 'selected' : ''}>🔄 Invertir Sentido (180°)</option>
                                            <option value="orthogonal" ${val === 'orthogonal' ? 'selected' : ''}>📐 Giro 90°</option>
                                        </select></div>`;
                                    }
                                    if (f === 'targetPriority') {
                                        const val = m[f] || 'all';
                                        return `<div class="field"><label>Prioridad de Objetivo</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].targetPriority = this.value; renderEnemyDetail();">
                                            <option value="all" ${val === 'all' ? 'selected' : ''}>🌐 El más próximo (Jugador o Altar)</option>
                                            <option value="players_only" ${val === 'players_only' ? 'selected' : ''}>👤 Solo Jugadores</option>
                                            <option value="altar_only" ${val === 'altar_only' ? 'selected' : ''}>⛩️ Solo Altar</option>
                                        </select></div>`;
                                    }
                                    if (['explodeOnDeath', 'affectsEnemies', 'affectsBosses'].includes(f)) return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;"><input type="checkbox" ${m[f] ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].${f} = this.checked"><label style="margin:0;">${moveLabels[f]}</label></div>`;
                                    return `<div class="field"><label>${moveLabels[f] || f}</label><input type="number" step="0.1" value="${m[f] || 0}" onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].${f} = parseFloat(this.value)"></div>`;
                                }).join('')}
                            </div>
                            <div style="margin-top: 0.75rem; padding-top: 0.5rem; border-top: 1px dashed rgba(234, 179, 8, 0.3);">
                                <label style="color:#a3a3a3; font-size: 0.65rem; font-weight:bold; letter-spacing:0.5px;">⚡ CONDICIONES DE ACTIVACIÓN (v500)</label>
                                <div style="font-size:0.6rem; color:#666; margin-bottom:0.4rem;">Sin condiciones = fase por defecto (siempre activa). Con condiciones = se activa solo cuando se cumplan TODAS.</div>
                                <div class="form-grid" style="margin-top: 0.4rem; gap: 8px;">
                                    ${MOVEMENT_CONDITION_FIELDS.map(field => {
                                        const val = (m.conditions && m.conditions[field.key] !== undefined) ? m.conditions[field.key] : '';
                                        if (field.type === 'select') {
                                            return `<div class="field"><label style="font-size:0.65rem;">${field.label}</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:3px; font-size:0.7rem;" onchange="updateMovementPhaseCondition('${selectedEnemyId}', ${idx}, '${field.key}', this.value || null); renderEnemyDetail();">
                                                <option value="">Sin restricción</option>
                                                ${field.options.map(o => `<option value="${o.value}" ${val === o.value ? 'selected' : ''}>${o.label}</option>`).join('')}
                                            </select></div>`;
                                        }
                                        return `<div class="field"><label style="font-size:0.65rem;">${field.label}</label><input type="number" min="${field.min || 0}" max="${field.max || 999999}" step="1" placeholder="Sin restric." value="${val}" onchange="updateMovementPhaseCondition('${selectedEnemyId}', ${idx}, '${field.key}', this.value ? parseFloat(this.value) : null); renderEnemyDetail();"></div>`;
                                    }).join('')}
                                </div>
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>
            <div class="col">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                    <label style="color:#ef4444; font-size: 0.8rem; font-weight:bold;">⚔️ MECÁNICAS DE ATAQUE ACTIVAS</label>
                    <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background:#ef4444; box-shadow: 0 4px 15px rgba(239, 68, 68, 0.3);" onclick="addMechanic('${selectedEnemyId}'); renderEnemyDetail();">+ AGREGAR ARMA</button>
                </div>
                <div id="mech-list-${selectedEnemyId}">
                    ${en.mechanics.map((m, idx) => `
                        <div class="card" style="margin-bottom: 1rem; position:relative; padding: 1rem; background: rgba(239, 68, 68, 0.05); border: 1px solid rgba(239, 68, 68, 0.2);">
                            <div style="position:absolute; top:8px; right:8px; display:flex; gap:10px;">
                                <button style="background:none; border:none; color:#ef4444; cursor:pointer; font-weight:bold;" onclick="moveMechanic('${selectedEnemyId}', ${idx}, -1); renderEnemyDetail();">SUBIR</button>
                                <button style="background:none; border:none; color:#ef4444; cursor:pointer; font-weight:bold;" onclick="moveMechanic('${selectedEnemyId}', ${idx}, 1); renderEnemyDetail();">BAJAR</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="removeMechanic('${selectedEnemyId}', ${idx}); renderEnemyDetail();">✕</button>
                            </div>
                            <div class="field full">
                                <select style="background:#0f172a; border:none; color:#ef4444; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;" onchange="updateMechanicType('${selectedEnemyId}', ${idx}, this.value); renderEnemyDetail();">
                                    ${Object.keys(MECHANICS_LIB).map(type => `<option value="${type}" ${m.type === type ? 'selected' : ''} style="background:#0f172a; color:white;">${MECHANICS_LIB[type].icon} ${MECHANICS_LIB[type].label}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-grid" style="margin-top:1rem;">
                                ${(MECHANICS_LIB[m.type] || MECHANICS_LIB['laser']).fields.map(f => {
const fieldLabelsMap = { 
                                           bulletDamage: m.type === 'melee_slash' ? "Daño del Hachazo (pts)" : (m.type === 'bomb' ? "Daño de Explosión (pts)" : (m.type === 'worm_boomerang' ? "Daño de Ida (pts)" : (m.type === 'wind_wall' ? "Daño al Arrollar (pts)" : (m.type === 'burrow' ? "Daño al Emerger (pts)" : (m.type === 'meteor' ? "Daño del Meteorito (pts)" : (m.type === 'ascension' ? "Daño al Aterrizar (pts)" : "Daño (pts)")))))), 
                                           bulletSpeed: m.type === 'bomb' ? "Velocidad de Bomba (px/s)" : (m.type === 'wind_wall' ? "Vel. Pared de Viento (px/s)" : (m.type === 'burrow' ? "Vel. de Zambullida (px/s)" : (m.type === 'mine' ? "Vel. de la Mina (px/s)" : "Vel. Bala (px/s)"))), 
                                           fireRange: m.type === 'melee_slash' ? "Alcance del Golpe (px)" : (m.type === 'bomb' ? "Alcance de Lanzamiento (px)" : (m.type === 'circle_cast' ? "Radio de Explosión (px)" : (m.type === 'reflect' ? "Alcance de Activación (px)" : (m.type === 'survival_dome' ? "Radio de la Explosión (px)" : (m.type === 'wind_wall' ? "Alcance de la Pared (px)" : (m.type === 'burrow' ? "Alcance de Selección de Objetivo (px)" : "Alcance (px)")))))),
                                           arcAngle: "Ángulo del Arco (° grados)",
                                           fullCircle: "¿Giro Completo 360°? (Sí/No)",
                                          fireRate: "Cadencia (ms)", 
                                      burstShots: "Proyectiles por Ráfaga (uds)", 
                                          slowAmount: "Ralentización (pts)", 
                                          slowDuration: "Duración de Ralentización (ms)", 
                                          startDelay: "Delay Inicio (ms)", 
                                          lifetimeMs: "Combustible (ms)", 
                                          turnSpeed: "Agilidad de Giro (rad/s)", 
                                          chargeTimeMs: "Tiempo de Carga (ms)", 
                                          lockTimeMs: m.type === 'circle_cast' ? "Tiempo Fijo / Estático (ms)" : "Tiempo de Bloqueo (ms)", 
                                          isHoming: "Seguimiento (Homing)",
                                          orbitSpeed: "Vel. de Giro (rad/s)",
                                          circleCount: "Cant. de Círculos (uds)",
                                          orbitRadius: "Radio de Órbita (px)",
                                          orbitDuration: "Tiempo de Giro (ms)",
                                          staticTime: "Tiempo Estático (ms)",
                                           radius: m.type === 'spin_ring' ? "Radio del Círculo (px)" : (m.type === 'bomb' ? "Radio de Explosión (px)" : (m.type === 'wall_dome' ? "Radio del Domo (px)" : (m.type === 'burrow' ? "Radio del Círculo de Daño (px)" : (m.type === 'ascension' ? "Radio del Área de Caída (px)" : "Radio del Aura (px)")))),
                                          damage: m.type === 'survival_dome' ? "Daño de la Explosión (pts)" : "Daño (pts)",
                                          intervalMs: "Intervalo de Tick (ms)",
                                          duration: m.type === 'sleep' ? "Duración del Sueño (ms)" : (m.type === 'reflect' ? "Duración del Escudo (ms)" : "Duración Total (ms)"),
                                          cooldown: "Enfriamiento (CD) (ms)",
                                          pullSpeed: "Vel. Atracción (px/s)",
                                          stunDuration: "Duración de Stun (ms)",
                                           safeRadius: "Radio del Domo Seguro (px)",
                                           maxOffset: "Radio Máximo de Dispersión (px)",
                                            castTimeMs: "Casteo (ms)",
                                           postCastWaitMs: "Espera Post-Explosión del Enemigo (ms)",
                                          applyBleed: "Aplicar Debuff: Sangrado",
                                          bleedDurationMs: "Duración del Sangrado (ms)",
                                          bleedDps: "Daño por Segundo de Sangrado (pts/s)",
                                          applyStun: "Aplicar Debuff: Parálisis",
                                          stunDurationMs: "Duración de la Parálisis (ms)",
                                          applyPoison: "Aplicar Debuff: Veneno",
                                          poisonDurationMs: "Duración del Veneno (ms)",
                                          poisonDps: "Daño por Segundo de Veneno (pts/s)",
                                          postHookWaitMs: "Espera Post-Gancho (ms)",
                                          hookMissWaitMs: "Espera por Fallo (ms)",
                                           bulletCount: m.type === 'polymorph' ? "Cantidad de Cubos (uds)" : "Cantidad de Proyectiles (uds)",
                                           isPointAndClick: m.type === 'polymorph' ? "Apuntado y Disparado (Sí/No)" : "Apuntado y Disparado",
                                           polyDuration: "Duración del Polimorfismo (ms)",
                                           canMove: "Puede Moverse (Sí/No)",
                                           canUseSkills: "Puede Usar Habilidades (Sí/No)",
                                           meteorCount: m.type === 'meteor' ? "Cantidad de Meteoritos (uds)" : "Cantidad de Meteoritos (uds)",
                                           fallHeight: "Altura de Caída (px)",
                                           fallSpeed: "Velocidad de Caída (px/s)",
                                           meteorSize: "Tamaño del Meteorito (px)",
                                           explosionRadius: m.type === 'mine' ? "Radio de Explosión de Mina (px)" : "Radio de Explosión (px)",
                                           warnTimeMs: m.type === 'burrow' ? "Duración del Círculo de Aviso (ms)" : (m.type === 'meteor' ? "Tiempo de Aviso en el Piso (ms)" : (m.type === 'ascension' ? "Tiempo Marcando el Área de Caída (ms)" : "Tiempo de Aviso (ms)")),
                                           persistentZone: m.type === 'meteor' ? "¿Dejar Zona Persistente en el Piso? (Sí/No)" : "¿Zona Persistente? (Sí/No)",
                                           zoneDamage: "Daño por Tick de Zona (pts)",
                                           zoneTickMs: "Intervalo de Tick de Zona (ms)",
                                            zoneDuration: "Duración de la Zona en el Piso (ms)",
                                            targetCount: "Cantidad de Players Objetivo (uds)",
                                            airTimeMs: "Tiempo en el Aire (ms)",
                                            warnDelayMs: "Tiempo de Espera del Área de Caída (ms)",
                                            bulletSpeed: "Vel. Calavera (px/s)",
                                            targetMode: "Modo de Selección de Objetivo",
                                            targetSphereColor: "Color de Esfera (apunta al que m�s tenga de ese color)",
                                            stealAmount: "Cantidad Robada (pts)",
                                            stealIntervalMs: "Intervalo de Robo (ms)",
                                            stealMode: "Modo de Robo",
                                            giveToEnemy: "¿Transferir al Enemigo? (Sí/No)",
                                            activationHP: "Activación por HP (%)",
                                          reductionPercentage: "Reducción de Daño (%)",
                                          shieldRegen: "Regen. de Escudo (pts/s)",
                                           healAmount: "Curación por Pulso (pts)",
                                           speedBonus: "Bono de Velocidad (px/s)",
                                           explosionDamage: "Daño de Explosión (pts)",
                                           deceleration: "Desaceleración (x)",
                                            castTimeMs: "Casteo (ms)",
                                           castSpeed: "Velocidad de Casteo (x)",
                                          coneAngle: "Ángulo del Cono (grados)",
                                          coneFollow: "Seguimiento Dinámico (Homing)",
                                          lockTimeMs: m.type === 'circle_cast' ? "Tiempo Fijo / Estático (ms)" : "Tiempo de Bloqueo (ms)",
                                          aimDelayMs: "Espera de Apuntado (ms)",
                                          bombCount: "Cantidad de Bombas (uds)",
                                          bombDelayMs: "Espera entre Bombas (ms)",
                                          fuseTimeMs: "Retardo de Explosión (ms)",
                                          targetCount: "Cantidad de Objetivos (uds)",
                                          slowPercentage: m.slowIsPercentage ? "Porcentaje de Ralentización (%)" : "Ralentización Fija (pts)",
                                          damagePerSecond: "Daño por Segundo (pts/s)",
                                          nightmareMultiplier: "Multiplicador de Pesadilla (x)",
                                          wakeOnDamage: "Despierta al Recibir Daño (Sí/No)",
                                          reflect_mult: "Multiplicador de Reflejo (x)",
                                          spinSpeed: "Velocidad de Giro (rad/s)",
                                          speedBuffAmount: "Bono Velocidad Movimiento Dueño (px/s)",
                                          speedBuffDuration: "Duración Bono Velocidad Dueño (ms)",
                                          applySlow: "Aplicar Ralentización al Enemigo",
                                          slowIsPercentage: "Ralentización es Porcentual (si no, es Fija)",
                                          slowDuration: "Duración de Ralentización (ms)",
                                          activationMode: "Modo de Activación",
                                          activationHPs: "Activadores de Vida (%)",
                                          activationIntervalMs: "Intervalo de Activación en Combate (ms)",
                                          summonCount: "Cantidad de Invocaciones (uds)",
                                          spawnRadius: "Radio de Invocación (px)",
                                          summonDurationMode: "Modo de Duración de Invocación",
                                          summonDurationMs: "Tiempo de Vida de Invocación (ms)",
                                           summonsList: "Lista de Esbirros Invocados",
                                            tick_interval: "Intervalo de Tick (ms)",
                                            damage_per_tick: "Daño por Tick (pts)",
                                            slow_amount: "Ralentización (0-1)",
                                            projectileCount: "Cantidad de Gusanos (uds)",
                                            spreadAngle: "Ángulo del Abanico (grados)",
                                            parkTimeMs: "Tiempo Quieto en el Extremo (ms)",
                                            returnDamage: "Daño de Vuelta (pts)",
                                             wallWidth: "Ancho de la Pared (px)",
                                             wallStartOffset: "Spawn Adelante del Enemigo (px)",
                                             pushForce: "Distancia de Expulsión (px)",
                                             burrowSpeed: "Vel. Viaje Subterráneo (px/s)",
                                             undergroundMs: "Tiempo Bajo Tierra en el Destino (ms)",
                                             burstMode: "Modo del Círculo de Daño",
                                             zoneDuration: "Duración de Zona Persistente (ms)",
                                             zoneTickMs: "Intervalo de Tick de Zona (ms)",
                                             zoneDamage: "Daño por Tick de Zona (pts)"
                                        };
                                     if (f === 'activationMode') {
                                         const mode = m.activationMode || 'time';
                                         // Normalizar defaults al seleccionar modo para mantener estética y no romper HP fix
                                         if (m.activationMode === undefined) m.activationMode = 'time';
                                         if (mode === 'time' && m.activationIntervalMs === undefined) m.activationIntervalMs = 0;
                                         if (mode === 'hp' && m.activationHPs === undefined) m.activationHPs = [50];
                                         return `
                                             <div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.05); padding: 10px; border-radius: 8px; border: 1px solid rgba(239, 68, 68, 0.2); display: flex; flex-direction: column; gap: 8px;">
                                                 <label style="color:#ef4444; font-weight:bold; font-size:0.75rem;">MODO DE ACTIVACIÓN</label>
                                                 <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationMode = this.value; if(this.value === 'time') { if(config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationIntervalMs===undefined) config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationIntervalMs=0; delete config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationHPs; } else { if(!config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationHPs) config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationHPs=[50]; delete config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationIntervalMs; } renderEnemyDetail();">
                                                     <option value="hp" ${mode === 'hp' ? 'selected' : ''}>🩸 Por Porcentaje de Vida (HP)</option>
                                                     <option value="time" ${mode === 'time' ? 'selected' : ''}>⏳ Por Tiempo en Combate</option>
                                                 </select>
                                             </div>
                                         `;
                                     }
                                     if (f === 'activationHPs') {
                                         if (m.activationMode === 'time') return '';
                                         const hps = m.activationHPs || [50];
                                         m.activationHPs = hps;
                                         return `
                                             <div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.02); padding: 10px; border-radius: 8px; border: 1px dashed rgba(239, 68, 68, 0.2); display: flex; flex-direction: column; gap: 10px;">
                                                 <div style="display:flex; justify-content:space-between; align-items:center;">
                                                     <label style="color:#ef4444; font-size:0.75rem;">ACTIVADORES DE VIDA (%)</label>
                                                     <button class="btn btn-primary" style="padding: 2px 8px; font-size: 0.65rem; background:#ef4444;" onclick="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationHPs.push(50); renderEnemyDetail();">+ AGREGAR HP</button>
                                                 </div>
                                                 <div style="display:flex; flex-wrap:wrap; gap:8px;">
                                                     ${hps.map((hpVal, hpIdx) => `
                                                         <div style="display:flex; align-items:center; gap:4px; background:#0f172a; padding:4px 8px; border-radius:4px; border:1px solid #334155;">
                                                             <input type="number" value="${hpVal}" style="width:55px; background:transparent; border:none; color:white; text-align:center; padding:0; font-size:0.8rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationHPs[${hpIdx}] = parseFloat(this.value)">
                                                             <span style="color:var(--text-dim); font-size:0.8rem;">%</span>
                                                             <button style="background:none; border:none; color:#ef4444; font-weight:bold; cursor:pointer; font-size:0.8rem; margin-left:4px;" onclick="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationHPs.splice(${hpIdx}, 1); renderEnemyDetail();">✕</button>
                                                         </div>
                                                     `).join('')}
                                                 </div>
                                             </div>
                                         `;
                                     }
                                     if (f === 'activationIntervalMs') {
                                         if (m.activationMode !== 'time') return '';
                                         const interval = (m.activationIntervalMs !== undefined && m.activationIntervalMs !== null && m.activationIntervalMs !== '') ? Number(m.activationIntervalMs) : 0;
                                         m.activationIntervalMs = interval;
                                         return `
                                             <div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.02); padding: 10px; border-radius: 8px; border: 1px dashed rgba(239, 68, 68, 0.15);">
                                                 <label>Intervalo de Activación en Combate (ms) <span style="font-weight:normal; color:#94a3b8; font-size:0.65rem;">— 0 = inmediato (respeta Retraso Inicio + Recarga)</span></label>
                                                 <input type="number" value="${interval}" placeholder="0" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationIntervalMs = parseInt(this.value) || 0">
                                             </div>
                                         `;
                                     }
                                     if (f === 'summonDurationMode') {
                                         const mode = m.summonDurationMode || 'until_death';
                                         return `
                                             <div class="field" style="grid-column: 1 / -1;"><label>Modo de Duración de Refuerzos</label>
                                                 <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].summonDurationMode = this.value; renderEnemyDetail();">
                                                     <option value="until_death" ${mode === 'until_death' ? 'selected' : ''}>🧟 Hasta ser destruidos</option>
                                                     <option value="timed" ${mode === 'timed' ? 'selected' : ''}>⏳ Por tiempo limitado</option>
                                                 </select>
                                             </div>
                                         `;
                                     }
                                     if (f === 'summonDurationMs') {
                                         if (m.summonDurationMode !== 'timed') return '';
                                         return `<div class="field"><label>Tiempo de Vida de Invocación (ms)</label><input type="number" value="${m.summonDurationMs || 10000}" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].summonDurationMs = parseInt(this.value)"></div>`;
                                     }
                                     if (f === 'summonsList') {
                                         const count = parseInt(m.summonCount) || 1;
                                         if (!m.summonsList) m.summonsList = [];
                                         while (m.summonsList.length < count) {
                                             m.summonsList.push("random_base");
                                         }
                                         if (m.summonsList.length > count) {
                                             m.summonsList.splice(count);
                                         }
                                         
                                         return `
                                             <div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.02); padding: 10px; border-radius: 8px; border: 1px dashed rgba(239, 68, 68, 0.2); display: flex; flex-direction: column; gap: 10px;">
                                                 <label style="color:#ef4444; font-size:0.75rem; font-weight:bold;">CONFIGURACIÓN INDIVIDUAL DE ESBIRROS</label>
                                                 <div class="form-grid" style="display:grid; grid-template-columns: 1fr; gap:8px;">
                                                     ${m.summonsList.map((choice, sIdx) => {
                                                         return `
                                                             <div style="display:flex; flex-direction:column; gap:4px; background:#0f172a; padding:8px; border-radius:6px; border:1px solid #334155;">
                                                                 <label style="font-size:0.65rem; color:var(--text-dim);">Esbirro #${sIdx + 1}</label>
                                                                 <select style="background:#0f172a; border:none; color:white; font-size:0.8rem; width:100%;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].summonsList[${sIdx}] = this.value; renderEnemyDetail();">
                                                                     <option value="random_base" ${choice === 'random_base' ? 'selected' : ''}>🔀 Servidor (Cualquier Regular Base)</option>
                                                                     <option value="random_boss" ${choice === 'random_boss' ? 'selected' : ''}>💀 Servidor (Cualquier Boss)</option>
                                                                     <option value="random_tier_a" ${choice === 'random_tier_a' ? 'selected' : ''}>⭐ Servidor (Cualquier Tier A)</option>
                                                                     <option value="random_tier_b" ${choice === 'random_tier_b' ? 'selected' : ''}>⭐⭐ Servidor (Cualquier Tier B)</option>
                                                                     <option value="random_tier_c" ${choice === 'random_tier_c' ? 'selected' : ''}>⭐⭐⭐ Servidor (Cualquier Tier C)</option>
                                                                     <option value="random_tier_d" ${choice === 'random_tier_d' ? 'selected' : ''}>⭐⭐⭐⭐ Servidor (Cualquier Tier D)</option>
                                                                     <option value="random" ${choice === 'random' ? 'selected' : ''}>🌀 Servidor (Cualquier Enemigo)</option>
                                                                     ${Object.keys(config.enemyModels || {}).map(id => {
                                                                         const enName = config.enemyModels[id].name || 'Enemigo';
                                                                         return `<option value="${id}" ${choice === id ? 'selected' : ''}>${enName} (#${id})</option>`;
                                                                     }).join('')}
                                                                 </select>
                                                             </div>
                                                         `;
                                                     }).join('')}
                                                 </div>
                                             </div>
                                         `;
                                     }
                                     if (f === 'isHoming') return `<div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.05); padding: 10px; border-radius: 8px; flex-direction: column; gap: 12px; border: 1px solid rgba(239, 68, 68, 0.2);"><div style="display:flex; align-items:center; gap:12px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:20px; height:20px; cursor:pointer;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].isHoming = this.checked; renderEnemyDetail();"><label style="margin:0; font-size: 0.85rem; color: #ef4444; cursor:pointer;">ACTIVAR SEGUIMIENTO AL OBJETIVO</label></div>${m.isHoming ? `<div style="padding-top: 10px; border-top: 1px solid rgba(239, 68, 68, 0.2);"><label style="font-size: 0.65rem; color: var(--text-dim);">AGILIDAD DE GIRO (RAD/S)</label><input type="number" step="0.1" value="${m.turnSpeed || 2.5}" style="background:rgba(0,0,0,0.3); margin-top:5px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].turnSpeed = parseFloat(this.value)"></div>` : ''}</div>`;
                                     if (f === 'coneFollow') return `<div class="field" style="display:flex; flex-direction:column; gap:8px;"><label>${fieldLabelsMap[f] || f}</label><div style="display:flex; align-items:center; height:40px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].coneFollow = this.checked; renderEnemyDetail();"></div></div>`;
                                     if (f === 'wakeOnDamage') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] !== false ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].wakeOnDamage = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                     if (f === 'applySlow') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].applySlow = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
if (f === 'slowIsPercentage') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].slowIsPercentage = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                      if (f === 'fullCircle') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].fullCircle = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                      if (f === 'isPointAndClick') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].isPointAndClick = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                      if (f === 'canMove') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].canMove = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                       if (f === 'canUseSkills') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].canUseSkills = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                        if (f === 'persistentZone') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:10px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].persistentZone = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                        if (f === 'castInterruptible') {
                                            const isDefCast = typeof DEFENSE_LIB !== 'undefined' && DEFENSE_LIB[m.type] !== undefined;
                                            if (isDefCast) {
                                                return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:rgba(16,185,129,0.08); padding:10px; border-radius:8px; margin-top:10px;"><input type="checkbox" ${m[f] !== false ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].castInterruptible = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer; font-weight:bold; color:#10b981;">Se interrumpe con CC</label></div>`;
                                            } else {
                                                return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:rgba(239,68,68,0.08); padding:10px; border-radius:8px; margin-top:10px;"><input type="checkbox" ${m[f] !== false ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].castInterruptible = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer; font-weight:bold; color:#ef4444;">Se interrumpe con CC</label></div>`;
                                            }
                                        }
                                       
                                        if (f === 'debuffsList') {
                                          if (!m.debuffsList) m.debuffsList = [];
                                          return `
                                              <div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.02); padding: 10px; border-radius: 8px; border: 1px dashed rgba(239, 68, 68, 0.2); display: flex; flex-direction: column; gap: 10px;">
                                                  <div style="display:flex; justify-content:space-between; align-items:center;">
                                                       <label style="color:#ef4444; font-size:0.75rem; font-weight:bold;">EFECTOS ALTERADOS (DEBUFFS) ${m.type === 'worm_boomerang' ? 'AL IMPACTAR EN LA VUELTA' : (m.type === 'wind_wall' ? 'AL ARROLLAR AL JUGADOR' : (m.type === 'burrow' ? 'AL EMERGER / EN LA ZONA' : (m.type === 'meteor' ? 'AL IMPACTAR EL METEORITO' : 'AL EXPLOTAR')))}</label>
                                                      <div style="display:flex; gap:5px;">
                                                          <select id="new-debuff-select-${idx}" style="background:#0f172a; color:white; font-size:0.75rem; border-radius:4px; padding:2px 4px; border:1px solid #334155;">
                                                              <option value="bleed">🩸 Sangrado</option>
                                                              <option value="poison">🤢 Veneno</option>
                                                              <option value="stun">⚡ Parálisis</option>
                                                              <option value="slow">🐢 Ralentización (Slow)</option>
                                                          </select>
                                                          <button class="btn btn-primary" style="padding: 2px 8px; font-size: 0.65rem; background:#ef4444;" onclick="const type = document.getElementById('new-debuff-select-${idx}').value; const debuffDefaults = { bleed: { type: 'bleed', dps: 30, duration: 4000, tickInterval: 1000 }, poison: { type: 'poison', dps: 20, duration: 4000, tickInterval: 1000 }, stun: { type: 'stun', duration: 1500 }, slow: { type: 'slow', amount: 50, duration: 2500, isPercentage: true } }; config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList.push(JSON.parse(JSON.stringify(debuffDefaults[type]))); renderEnemyDetail();">+ AGREGAR DEBUFF</button>
                                                      </div>
                                                  </div>
                                                  <div style="display:grid; grid-template-columns: 1fr; gap:8px;">
                                                      ${m.debuffsList.map((d, dIdx) => {
                                                          let fieldsHtml = '';
                                                          if (d.type === 'bleed' || d.type === 'poison') {
                                                              fieldsHtml = `
                                                                  <div style="display:grid; grid-template-columns: 1fr 1fr 1fr; gap:8px; width:100%;">
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Daño (pts/tick)</label>
                                                                          <input type="number" value="${d.dps || 20}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].dps = parseInt(this.value)">
                                                                      </div>
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Duración (ms)</label>
                                                                          <input type="number" value="${d.duration || 4000}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].duration = parseInt(this.value)">
                                                                      </div>
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Intervalo Tick (ms)</label>
                                                                          <input type="number" value="${d.tickInterval || 1000}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].tickInterval = parseInt(this.value)">
                                                                      </div>
                                                                  </div>
                                                              `;
                                                          } else if (d.type === 'stun') {
                                                              fieldsHtml = `
                                                                  <div style="display:grid; grid-template-columns: 1fr; gap:8px; width:100%;">
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Duración de Parálisis (ms)</label>
                                                                          <input type="number" value="${d.duration || 1500}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].duration = parseInt(this.value)">
                                                                      </div>
                                                                  </div>
                                                              `;
                                                          } else if (d.type === 'slow') {
                                                              fieldsHtml = `
                                                                  <div style="display:grid; grid-template-columns: 1fr 1fr 1fr; gap:8px; width:100%;">
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Cantidad de Ralentización</label>
                                                                          <input type="number" value="${d.amount || 50}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].amount = parseInt(this.value)">
                                                                      </div>
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Duración (ms)</label>
                                                                          <input type="number" value="${d.duration || 2500}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].duration = parseInt(this.value)">
                                                                      </div>
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Tipo de Ralentización</label>
                                                                          <select style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].isPercentage = this.value === 'percent';">
                                                                              <option value="percent" ${d.isPercentage !== false ? 'selected' : ''}>% Porcentaje</option>
                                                                              <option value="fixed" ${d.isPercentage === false ? 'selected' : ''}>🔢 Fijo (px/s)</option>
                                                                          </select>
                                                                      </div>
                                                                  </div>
                                                              `;
                                                          }

                                                          return `
                                                              <div style="display:flex; flex-direction:column; gap:6px; background:#0f172a; padding:8px; border-radius:6px; border:1px solid #334155; position:relative;">
                                                                  <div style="display:flex; justify-content:space-between; align-items:center; border-bottom: 1px solid #1e293b; padding-bottom: 4px;">
                                                                      <span style="font-size:0.75rem; font-weight:bold; color:#ef4444;">
                                                                          ${d.type === 'bleed' ? '🩸 Sangrado' : (d.type === 'poison' ? '🤢 Veneno' : (d.type === 'stun' ? '⚡ Parálisis' : '🐢 Ralentización (Slow)'))}
                                                                      </span>
                                                                      <button style="background:none; border:none; color:#ef4444; font-weight:bold; cursor:pointer; font-size:0.8rem;" onclick="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList.splice(${dIdx}, 1); renderEnemyDetail();">✕</button>
                                                                  </div>
                                                                  ${fieldsHtml}
                                                              </div>
                                                          `;
                                                      }).join('')}
                                                  </div>
                                              </div>
                                          `;
                                      }
                                     
if (f === 'targetMode') {
                                          const val = m[f] || 'proximity';
                                          if (m.type === 'burrow' || m.type === 'meteor') {
                                              return `<div class="field"><label>${m.type === 'meteor' ? 'Criterio de Selección de Objetivos' : 'Selección de Objetivo'}</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].targetMode = this.value; renderEnemyDetail();">
                                              <option value="proximity" ${val === 'proximity' ? 'selected' : ''}>📏 Proximidad (Más cercano)</option>
                                              <option value="random" ${val === 'random' ? 'selected' : ''}>🔀 Aleatorio</option>
                                              <option value="farthest" ${val === 'farthest' ? 'selected' : ''}>📐 Más Lejano</option>
                                              <option value="lowest_hp" ${val === 'lowest_hp' ? 'selected' : ''}>❤️ Menos Vida</option>
                                              <option value="highest_hp" ${val === 'highest_hp' ? 'selected' : ''}>💪 Más Vida</option>
                                              <option value="highest_damage" ${val === 'highest_damage' ? 'selected' : ''}>⚔️ Mayor Daño Causado</option>
                                              <option value="highest_heal" ${val === 'highest_heal' ? 'selected' : ''}>💚 Mayor Curación</option>
                                              <option value="sphere_color" ${val === 'sphere_color' ? 'selected' : ''}>🔮 Mayor Cantidad de Esferas de un Color</option>
                                          </select></div>`;
                                          }
                                         return `<div class="field"><label>Criterio de Selección</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].targetMode = this.value; renderEnemyDetail();">
                                             <option value="proximity" ${val === 'proximity' ? 'selected' : ''}>📏 Proximidad (Más cercano)</option>
                                             <option value="random" ${val === 'random' ? 'selected' : ''}>🔀 Aleatorio</option>
                                             <option value="max_hp" ${val === 'max_hp' ? 'selected' : ''}>❤️ Vida Máxima Mayor</option>
                                             <option value="missing_hp" ${val === 'missing_hp' ? 'selected' : ''}>💔 Vida Faltante Mayor</option>
                                             <option value="sphere_color" ${val === 'sphere_color' ? 'selected' : ''}>🔮 Mayor Cantidad de Esferas de un Color</option>
                                         </select></div>`;
                                      }
                                      if (f === 'targetSphereColor') {
                                          // Solo se muestra si el criterio es "Por Color de Esfera"
                                          if ((m.targetMode || 'proximity') !== 'sphere_color') return '';
                                          const cval = m[f] || '';
                                          return `<div class="field"><label>Color de Esfera (apunta al que m�s tenga de ese color)</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].targetSphereColor = this.value; renderEnemyDetail();">
                                              <option value="" ${cval === '' || cval === 'any' ? 'selected' : ''}>🌈 Cualquier Color</option>
                                              <option value="roja" ${cval === 'roja' ? 'selected' : ''}>🔴 Roja (Ataque)</option>
                                              <option value="azul" ${cval === 'azul' ? 'selected' : ''}>🔵 Azul (Defensa)</option>
                                              <option value="verde" ${cval === 'verde' ? 'selected' : ''}>🟢 Verde (Curación)</option>
                                              <option value="amarilla" ${cval === 'amarilla' ? 'selected' : ''}>🟡 Amarilla (Utilidad)</option>
                                          </select></div>`;
                                      }
                                     if (f === 'burstMode') {
                                         const val = m[f] || 'burst';
                                         return `<div class="field"><label>Modo del Círculo de Daño</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].burstMode = this.value; renderEnemyDetail();">
                                             <option value="burst" ${val === 'burst' ? 'selected' : ''}>💥 Golpe Único al Emerger</option>
                                             <option value="zone" ${val === 'zone' ? 'selected' : ''}>🌀 Zona Persistente (Daño en el Piso)</option>
                                         </select></div>`;
                                     }
                                      if (f === 'turnSpeed' && m.type !== 'execution') return '';
                                      if ((f === 'zoneTickMs' || f === 'zoneDuration' || f === 'zoneDamage') && (m.burstMode || 'burst') !== 'zone' && !m.persistentZone) return '';
                                     return `<div class="field"><label>${fieldLabelsMap[f] || f}</label><input type="number" step="0.1" value="${m[f] || 0}" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].${f} = parseFloat(this.value); if ('${f}' === 'summonCount') renderEnemyDetail();"></div>`;
                                }).join('')}
                            </div>
                        </div>
                    `).join('')}
                </div>

                <div style="display:flex; justify-content:space-between; align-items:center; margin-top:2rem; margin-bottom:1rem;">
                    <label style="color:#3b82f6; font-size: 0.8rem; font-weight:bold;">🛡️ MECÁNICAS DE DEFENSA ACTIVAS</label>
                    <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background: #3b82f6; box-shadow: 0 4px 15px rgba(59, 130, 246, 0.3);" onclick="addDefenseMechanic('${selectedEnemyId}')">+ AGREGAR DEFENSA</button>
                </div>
                <div id="defense-mech-list-${selectedEnemyId}">
                    ${en.defenseMechanics.map((m, idx) => `
                        <div class="card" style="margin-bottom: 1rem; position:relative; padding: 1rem; background: rgba(59, 130, 246, 0.05); border: 1px solid rgba(59, 130, 246, 0.2);">
                            <div style="position:absolute; top:8px; right:8px; display:flex; gap:10px;">
                                <button style="background:none; border:none; color:#3b82f6; cursor:pointer; font-weight:bold;" onclick="moveDefenseMechanic('${selectedEnemyId}', ${idx}, -1)">SUBIR</button>
                                <button style="background:none; border:none; color:#3b82f6; cursor:pointer; font-weight:bold;" onclick="moveDefenseMechanic('${selectedEnemyId}', ${idx}, 1)">BAJAR</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="removeDefenseMechanic('${selectedEnemyId}', ${idx})">✕</button>
                            </div>
                            <div class="field full">
                                <select style="background:#0f172a; border:none; color:#3b82f6; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;" onchange="updateDefenseMechanicType('${selectedEnemyId}', ${idx}, this.value)">
                                    ${Object.keys(DEFENSE_LIB).map(type => `<option value="${type}" ${m.type === type ? 'selected' : ''} style="background:#0f172a; color:white;">${DEFENSE_LIB[type].icon} ${DEFENSE_LIB[type].label}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-grid" style="margin-top:1rem;">
                                ${(DEFENSE_LIB[m.type] || DEFENSE_LIB['basic_defense']).fields.map(f => {
                                    const defLabels = { 
                                        reductionPercentage: "Reducción (%)", 
                                        shieldRegen: "Regen. Escudo (pts/s)", 
                                        duration: "Duración (ms)", 
                                        cooldown: "Recarga (ms)", 
                                        startDelay: "Retraso Inicio (ms)",
                                        reflect_mult: "Multiplicador de Reflejo (x)",
                                        activationMode: "Modo de Activación",
                                        activationHPs: "Activadores de Vida (%)",
                                        activationIntervalMs: "Intervalo de Activación en Combate (ms)",
                                        radius: m.type === 'wall_dome' ? "Radio del Domo (px)" : "Radio del Aura (px)",
                                        healAmount: "Cura por Pulso (pts)",
                                        intervalMs: "Intervalo de Tick (ms)",
                                        activationHP: "Activación por HP (%)",
                                        affectsEnemies: "Afectar a otros Enemigos", 
                                        affectsBosses: "Afectar a Bosses",
                                        pillarCount: "Cantidad de Pilares (uds)",
                                        pillarType: "Tipo de Pilar (ID)",
                                        pillarHp: "Vida del Pilar (pts)",
                                        pillarShield: "Escudo del Pilar (pts)",
                                        pillarName: "Nombre del Pilar",
                                        spawnRadius: "Distancia de Spawn (px)",
                                        healIntervalMs: "Intervalo Curación (ms)",
                                        healPercentPerTick: "Curación por Tick (%)",
                                        healPercentPerPillarOnExpiry: "Curación por Pilar Restante (%)",
                                        orbCount: "Cantidad de Orbes (uds)",
                                        orbSpeed: "Velocidad de Orbes (px/s)",
                                        playerDamage: "Daño al Jugador (HP)",
                                        bossHealPercent: "Curación al Boss por Orbe (%)",
                                        invisType: "Tipo de Ocultamiento",
                                        keepAttacking: "Ataca Invisible",
                                        changeSpeed: "Modificar Velocidad",
                                        invisSpeedMultiplier: "Multiplicador de Velocidad (x)",
                                        cloneCount: "Cantidad de Clones (uds)",
                                        cloneHp: "Vida de Clones (pts)",
                                        cloneShield: "Escudo de Clones (pts)",
                                        cloneSpeed: "Velocidad de Clones (px/s)",
                                        cloneDuration: "Duración de Clones (ms)",
                                        cloneExplosionDamage: "Daño de Explosión (pts)",
                                        cloneHealAmount: "Curación al original (pts)",
                                        cloneExplodeOnExpiry: "Perseguir y explotar al expirar",
                                        fireRange: "Distancia de Disparo (px)",
                                        bulletSpeed: "Velocidad del Proyectil (px/s)",
                                        bulletDamage: "Daño del Proyectil (pts)",
                                        stealMode: "Modo de Robo",
                                        stealAmount: "Cantidad de Robo",
                                        stealIntervalMs: "Intervalo de Robo (ms)",
                                        targetMode: "Selección del Objetivo",
                                        targetSphereColor: "Color de Esfera (apunta al que m�s tenga de ese color)",
                                        giveToEnemy: m.type === 'life_steal' ? "Transferir Vida Robada al Enemigo" : "Transferir Escudo Robado al Enemigo"
                                    };
                                    if (f === 'invisType') {
                                        const type = m.invisType || 'invisibility';
                                        m.invisType = type;
                                        return `
                                            <div class="field" style="grid-column: 1 / -1;"><label>Tipo de Ocultamiento</label>
                                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].invisType = this.value; renderEnemyDetail();">
                                                    <option value="invisibility" ${type === 'invisibility' ? 'selected' : ''}>👤 Invisibilidad (Totalmente Oculto)</option>
                                                    <option value="camouflage" ${type === 'camouflage' ? 'selected' : ''}>👻 Camuflaje (Transparente)</option>
                                                </select>
                                            </div>
                                        `;
                                    }
                                    if (f === 'keepAttacking') {
                                        const checked = m.keepAttacking !== false;
                                        if (m.keepAttacking === undefined) m.keepAttacking = true;
                                        return `
                                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;">
                                                <input type="checkbox" ${checked ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].keepAttacking = this.checked">
                                                <label style="margin:0;">Seguir atacando mientras está invisible</label>
                                            </div>
                                        `;
                                    }
                                    if (f === 'changeSpeed') {
                                        const checked = !!m.changeSpeed;
                                        if (m.changeSpeed === undefined) m.changeSpeed = false;
                                        return `
                                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;">
                                                <input type="checkbox" ${checked ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].changeSpeed = this.checked; renderEnemyDetail();">
                                                <label style="margin:0;">Modificar velocidad de movimiento</label>
                                            </div>
                                        `;
                                    }
                                    if (f === 'invisSpeedMultiplier') {
                                        if (!m.changeSpeed) return '';
                                        const mult = m.invisSpeedMultiplier !== undefined ? m.invisSpeedMultiplier : 1.0;
                                        m.invisSpeedMultiplier = mult;
                                        return `
                                            <div class="field"><label>Multiplicador de Velocidad (x)</label>
                                                <input type="number" step="0.1" value="${mult}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].invisSpeedMultiplier = parseFloat(this.value)">
                                            </div>
                                        `;
                                    }
                                    if (f === 'activationMode') {
                                        const mode = m.activationMode || 'time';
                                        if (m.activationMode === undefined) m.activationMode = 'time';
                                        if (mode === 'time' && m.activationIntervalMs === undefined) m.activationIntervalMs = 0;
                                        if (mode === 'hp' && m.activationHPs === undefined) m.activationHPs = [50];
                                        return `
                                            <div class="field" style="grid-column: 1 / -1; background: rgba(59, 130, 246, 0.05); padding: 10px; border-radius: 8px; border: 1px solid rgba(59, 130, 246, 0.2); display: flex; flex-direction: column; gap: 8px;">
                                                <label style="color:#60a5fa; font-weight:bold; font-size:0.75rem;">MODO DE ACTIVACIÓN</label>
                                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationMode = this.value; if(this.value === 'time') { if(config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationIntervalMs===undefined) config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationIntervalMs=0; delete config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationHPs; } else { if(!config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationHPs) config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationHPs=[50]; delete config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationIntervalMs; } renderEnemyDetail();">
                                                    <option value="hp" ${mode === 'hp' ? 'selected' : ''}>🩸 Por Porcentaje de Vida (HP)</option>
                                                    <option value="time" ${mode === 'time' ? 'selected' : ''}>⏳ Por Tiempo en Combate</option>
                                                </select>
                                            </div>
                                        `;
                                    }
                                    if (f === 'activationHPs') {
                                        if (m.activationMode === 'time') return '';
                                        const hps = m.activationHPs || [70];
                                        m.activationHPs = hps;
                                        return `
                                            <div class="field" style="grid-column: 1 / -1; background: rgba(59, 130, 246, 0.02); padding: 10px; border-radius: 8px; border: 1px dashed rgba(59, 130, 246, 0.2); display: flex; flex-direction: column; gap: 10px;">
                                                <div style="display:flex; justify-content:space-between; align-items:center;">
                                                    <label style="color:#60a5fa; font-size:0.75rem;">ACTIVADORES DE VIDA (%)</label>
                                                    <button class="btn btn-primary" style="padding: 2px 8px; font-size: 0.65rem; background:#3b82f6;" onclick="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationHPs.push(50); renderEnemyDetail();">+ AGREGAR HP</button>
                                                </div>
                                                <div style="display:flex; flex-wrap:wrap; gap:8px;">
                                                    ${hps.map((hpVal, hpIdx) => `
                                                        <div style="display:flex; align-items:center; gap:4px; background:#0f172a; padding:4px 8px; border-radius:4px; border:1px solid #334155;">
                                                            <input type="number" value="${hpVal}" style="width:55px; background:transparent; border:none; color:white; text-align:center; padding:0; font-size:0.8rem;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationHPs[${hpIdx}] = parseFloat(this.value)">
                                                            <span style="color:var(--text-dim); font-size:0.8rem;">%</span>
                                                            <button style="background:none; border:none; color:#ef4444; font-weight:bold; cursor:pointer; font-size:0.8rem; margin-left:4px;" onclick="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationHPs.splice(${hpIdx}, 1); renderEnemyDetail();">✕</button>
                                                        </div>
                                                    `).join('')}
                                                </div>
                                            </div>
                                        `;
                                    }
                                    if (f === 'activationIntervalMs') {
                                        if (m.activationMode !== 'time') return '';
                                        const interval = (m.activationIntervalMs !== undefined && m.activationIntervalMs !== null && m.activationIntervalMs !== '') ? Number(m.activationIntervalMs) : 0;
                                        m.activationIntervalMs = interval;
                                        return `
                                            <div class="field" style="grid-column: 1 / -1; background: rgba(59, 130, 246, 0.02); padding: 10px; border-radius: 8px; border: 1px dashed rgba(59, 130, 246, 0.15);">
                                                <label>Intervalo de Activación en Combate (ms) <span style="font-weight:normal; color:#94a3b8; font-size:0.65rem;">— 0 = inmediato (respeta Retraso Inicio + Recarga)</span></label>
                                                <input type="number" value="${interval}" placeholder="0" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationIntervalMs = parseInt(this.value) || 0">
                                            </div>
                                        `;
                                    }
                                    if (f === 'pillarType') {
                                         const curVal = String(m.pillarType !== undefined ? m.pillarType : '200');
                                         return `
                                             <div class="field" style="grid-column: 1 / -1;">
                                                 <label>🗼 Tipo de Pilar (Asset Visual)</label>
                                                 <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].pillarType = parseInt(this.value); renderEnemyDetail();">
                                                     <option value="200" ${curVal === '200' ? 'selected' : ''}>Pilar Protector 3D (Pilar1.glb) (#200)</option>
                                                 </select>
                                             </div>
                                         `;
                                     }
                                    if (['affectsEnemies', 'affectsBosses', 'cloneExplodeOnExpiry'].includes(f)) {
                                         const checked = f === 'cloneExplodeOnExpiry' ? m[f] !== false : !!m[f];
                                         return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;"><input type="checkbox" ${checked ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].${f} = this.checked"><label style="margin:0;">${defLabels[f]}</label></div>`;
                                    }
                                    if (f === 'pillarName') return `<div class="field" style="grid-column: 1 / -1;"><label>${defLabels[f] || f}</label><input type="text" value="${m[f] || 'Pilar Protector'}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].${f} = this.value"></div>`;
                                    if (f === 'stealMode') {
                                        const mode = m.stealMode || 'flat';
                                        const isLife = m.type === 'life_steal';
                                        return `
                                            <div class="field" style="grid-column: 1 / -1;"><label>${isLife ? 'Modo de Robo de Vida' : 'Modo de Robo de Escudo'}</label>
                                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].stealMode = this.value; renderEnemyDetail();">
                                                    <option value="flat" ${mode === 'flat' ? 'selected' : ''}>📏 Plano (pts por tick)</option>
                                                    <option value="percent" ${mode === 'percent' ? 'selected' : ''}>📊 Porcentual (${isLife ? 'de la vida max del jugador' : 'del escudo max del jugador'})</option>
                                                </select>
                                            </div>
                                        `;
                                    }
                                    if (f === 'targetMode') {
                                        const tmode = m.targetMode || 'proximity';
                                        return `
                                            <div class="field" style="grid-column: 1 / -1;"><label>Selección del Objetivo</label>
                                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].targetMode = this.value; renderEnemyDetail();">
                                                    <option value="proximity" ${tmode === 'proximity' ? 'selected' : ''}>📍 Más Cercano</option>
                                                    <option value="random" ${tmode === 'random' ? 'selected' : ''}>🎲 Aleatorio</option>
                                                    <option value="lowest_hp" ${tmode === 'lowest_hp' ? 'selected' : ''}>🥶 Menor Vida (%)</option>
                                                    <option value="highest_hp" ${tmode === 'highest_hp' ? 'selected' : ''}>🫀 Mayor Vida (%)</option>
                                                    <option value="highest_shield" ${tmode === 'highest_shield' ? 'selected' : ''}>💠 Mayor Escudo</option>
                                                    <option value="highest_damage" ${tmode === 'highest_damage' ? 'selected' : ''}>⚔️ Mayor Daño Causado</option>
                                                    <option value="sphere_color" ${tmode === 'sphere_color' ? 'selected' : ''}>🔮 Mayor Cantidad de Esferas de un Color</option>
                                                </select>
                                            </div>
                                        `;
                                    }
                                    if (f === 'targetSphereColor') {
                                        // Solo se muestra si el criterio es "Por Color de Esfera"
                                        if ((m.targetMode || 'proximity') !== 'sphere_color') return '';
                                        const cval = m.targetSphereColor || '';
                                        return `
                                            <div class="field" style="grid-column: 1 / -1;"><label>Color de Esfera (apunta al que m�s tenga de ese color)</label>
                                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].targetSphereColor = this.value; renderEnemyDetail();">
                                                    <option value="" ${cval === '' || cval === 'any' ? 'selected' : ''}>🌈 Cualquier Color</option>
                                                    <option value="roja" ${cval === 'roja' ? 'selected' : ''}>🔴 Roja (Ataque)</option>
                                                    <option value="azul" ${cval === 'azul' ? 'selected' : ''}>🔵 Azul (Defensa)</option>
                                                    <option value="verde" ${cval === 'verde' ? 'selected' : ''}>🟢 Verde (Curación)</option>
                                                    <option value="amarilla" ${cval === 'amarilla' ? 'selected' : ''}>🟡 Amarilla (Utilidad)</option>
                                                </select>
                                            </div>
                                        `;
                                    }
                                    if (f === 'giveToEnemy') {
                                        const checked = m.giveToEnemy !== false;
                                        if (m.giveToEnemy === undefined) m.giveToEnemy = true;
                                        return `
                                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;">
                                                <input type="checkbox" ${checked ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].giveToEnemy = this.checked">
                                                <label style="margin:0;">${m.type === 'life_steal' ? 'Transferir Vida Robada al Enemigo' : 'Transferir Escudo Robado al Enemigo'}</label>
                                            </div>
                                        `;
                                    }
                                    if (f === 'isPointAndClick') {
                                        const checked = m.isPointAndClick === true;
                                        return `
                                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; grid-column: 1 / -1;">
                                                <input type="checkbox" ${checked ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].isPointAndClick = this.checked">
                                                <label style="margin:0; cursor:pointer;">Apuntado Directo (Point & Click / Inesquivable)</label>
                                            </div>
                                        `;
                                    }
                                    return `<div class="field"><label>${defLabels[f] || f}</label><input type="number" step="0.1" value="${m[f] || 0}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].${f} = parseFloat(this.value)"></div>`;
                                }).join('')}
                            </div>
                            ${m.type === 'duplicado' ? (function() {
                                 if (!m.clonesList) m.clonesList = [];
                                 const cloneCount = parseInt(m.cloneCount) || 1;
                                 while (m.clonesList.length < cloneCount) {
                                     m.clonesList.push({
                                         hp: 1000,
                                         shield: 200,
                                         role: "damage",
                                         value: 500
                                     });
                                 }
                                 if (m.clonesList.length > cloneCount) {
                                     m.clonesList.splice(cloneCount);
                                 }
                                 return `
                                     <div style="margin-top:1.5rem; padding-top:1rem; border-top:1px dashed rgba(59, 130, 246, 0.3);">
                                         <h5 style="color:#60a5fa; font-size:0.8rem; font-weight:bold; margin-bottom:1rem;">👥 CONFIGURACIÓN INDIVIDUAL DE CLONES</h5>
                                         <div style="display:flex; flex-direction:column; gap:10px;">
                                             ${m.clonesList.map((c, cloneIdx) => `
                                                 <div style="background:rgba(59, 130, 246, 0.02); padding:10px; border-radius:6px; border:1px solid rgba(59, 130, 246, 0.15);">
                                                     <div style="font-weight:bold; font-size:0.75rem; color:#93c5fd; margin-bottom:8px;">Clon #${cloneIdx + 1}</div>
                                                     <div class="form-grid" style="display:grid; grid-template-columns:1fr 1fr 1fr 1fr 1fr; gap:8px;">
                                                         <div class="field" style="margin:0;"><label style="font-size:0.65rem;">HP (pts)</label>
                                                             <input type="number" value="${c.hp || 1000}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].clonesList[${cloneIdx}].hp = parseInt(this.value) || 0">
                                                         </div>
                                                         <div class="field" style="margin:0;"><label style="font-size:0.65rem;">Escudo (pts)</label>
                                                             <input type="number" value="${c.shield || 200}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].clonesList[${cloneIdx}].shield = parseInt(this.value) || 0">
                                                         </div>
                                                         <div class="field" style="margin:0;"><label style="font-size:0.65rem;">Rol / Función</label>
                                                             <select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].clonesList[${cloneIdx}].role = this.value; renderEnemyDetail();">
                                                                 <option value="damage" ${c.role === 'damage' ? 'selected' : ''}>💥 Daño</option>
                                                                 <option value="heal" ${c.role === 'heal' ? 'selected' : ''}>💚 Curación</option>
                                                             </select>
                                                         </div>
                                                         <div class="field" style="margin:0;"><label style="font-size:0.65rem;">${c.role === 'heal' ? 'Cura al original' : 'Daño explosión'}</label>
                                                             <input type="number" value="${c.value || 500}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].clonesList[${cloneIdx}].value = parseInt(this.value) || 0">
                                                         </div>
                                                         <div class="field" style="margin:0;"><label style="font-size:0.65rem;">Recarga Ataque (ms)</label>
                                                             <input type="number" value="${c.attackCooldownMs || 2000}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].clonesList[${cloneIdx}].attackCooldownMs = parseInt(this.value) || 2000">
                                                         </div>
                                                     </div>
                                                 </div>
                                             `).join('')}
                                         </div>
                                     </div>
                                 `;
                             })() : ''}
                        </div>
                    `).join('')}
                </div>

                <div style="display:flex; justify-content:space-between; align-items:center; margin-top:2rem; margin-bottom:1rem;">
                    <label style="color:var(--accent); font-size: 0.8rem; font-weight:bold;">🎁 CONFIGURACIÓN DE BOTÍN (LOOT DROPS)</label>
                    <div style="display: flex; gap: 10px; align-items: center;">
                        <button class="btn btn-primary" style="padding: 4px 10px; font-size: 0.65rem;" onclick="showLootTabForEnemy('${selectedEnemyId}')">🔍 Balancear en pantalla completa</button>
                        <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background: var(--accent); border-color: var(--accent); box-shadow: 0 4px 15px rgba(6, 182, 212, 0.3);" onclick="addLootDropFromComponent('${selectedEnemyId}', 'loot-table-component-threats')">+ AGREGAR DROP</button>
                    </div>
                </div>
                <div id="loot-table-component-threats" style="background: rgba(255,255,255,0.01); padding: 10px; border-radius: 8px;">
                    <!-- Rendered dynamically by component -->
                </div>
            </div>
        </div>
    `;
    setTimeout(() => {
        window.renderLootTableComponent(selectedEnemyId, 'loot-table-component-threats');
    }, 50);
    // v900.0: inyectar sonidos hybrid post-render (DOM) - dentro de renderEnemyDetail
    setTimeout(() => {
        try {
            const mechList = document.getElementById(`mech-list-${selectedEnemyId}`);
            if (mechList) {
                [...mechList.children].forEach((card, idx) => {
                    if (card.querySelector('.mech-sound-override')) return;
                    const m = config.enemyModels[selectedEnemyId]?.mechanics?.[idx];
                    if (!m) return;
                    card.insertAdjacentHTML('beforeend', mechanicSoundOverrideHtml(selectedEnemyId, 'mechanics', idx, m));
                });
            }
            const dList = document.getElementById(`defense-mech-list-${selectedEnemyId}`);
            if (dList) {
                [...dList.children].forEach((card, idx) => {
                    if (card.querySelector('.mech-sound-override')) return;
                    const m = config.enemyModels[selectedEnemyId]?.defenseMechanics?.[idx];
                    if (!m) return;
                    card.insertAdjacentHTML('beforeend', mechanicSoundOverrideHtml(selectedEnemyId, 'defenseMechanics', idx, m));
                });
            }
            const movList = document.getElementById(`move-list-${selectedEnemyId}`);
            if (movList) {
                [...movList.children].forEach((card, idx) => {
                    if (card.querySelector('.mech-sound-override')) return;
                    const m = config.enemyModels[selectedEnemyId]?.movementPhases?.[idx];
                    if (!m) return;
                    card.insertAdjacentHTML('beforeend', mechanicSoundOverrideHtml(selectedEnemyId, 'movementPhases', idx, m));
                });
            }
        } catch(e) { console.warn('sound inject', e); }
    }, 0);
}
