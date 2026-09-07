// AdminDash/js/renderers/renderMechanics.js
function renderMechanicsLib() {
    const MECHANICS_LIB = config.mechanicsLib || DEFAULT_MECHANICS_LIB;
    const MOVEMENT_LIB = config.movementLib || DEFAULT_MOVEMENT_LIB;
    const DEFENSE_LIB = config.defenseLib || DEFAULT_DEFENSE_LIB;

    const grid = document.getElementById('mechanics-lib-grid'); if(!grid) return;
    grid.innerHTML = '';
    const f = getFilter();
    const fieldLabels = { 
        "bulletDamage": "Daño", 
        "bulletSpeed": "Velocidad", 
        "fireRange": "Alcance (px)", 
        "fireRate": "Cadencia", 
        "burstShots": "Proyectiles por Ráfaga (uds)", 
        "staticTime": "Tiempo Estático",
        "reductionPercentage": "Reducción Daño",
        "shieldRegen": "Regen. Escudo",
        "duration": "Duración (ms)",
        "cooldown": "Enfriamiento (CD) (ms)",
        "radius": "Radio de Acción (px)",
        "damage": "Daño (pts)",
        "healAmount": "Cura por Pulso (pts)",
        "speedBonus": "Bono Velocidad (px/s)",
        "intervalMs": "Intervalo (ms)",
        "castTimeMs": "Casteo (ms)",
        "castSpeed": "Velocidad de Casteo (x)",
        "coneAngle": "Ángulo del Cono (grados)",
        "stunDuration": "Duración de Stun (ms)",
        "coneFollow": "Seguimiento Dinámico (Homing)",
        "lockTimeMs": "Tiempo de Bloqueo (ms)",
        "aimDelayMs": "Espera de Apuntado (ms)",
        "reflect_mult": "Multiplicador de Reflejo (x)",
        "activationMode": "Modo de Activación",
        "activationHPs": "Activadores de Vida (%)",
        "activationIntervalMs": "Intervalo de Activación en Combate (ms)",
        "summonCount": "Cantidad de Invocaciones (uds)",
        "spawnRadius": "Radio de Invocación (px)",
        "summonDurationMode": "Modo de Duración de Invocación",
        "summonDurationMs": "Tiempo de Vida de Invocación (ms)",
        "summonsList": "Lista de Esbirros Invocados",
        "tick_interval": "Intervalo de Tick (ms)",
        "damage_per_tick": "Daño por Tick (pts)",
        "slow_amount": "Ralentización (0-1)",
        "radius": "Radio (px)",
        "projectileCount": "Cantidad de Gusanos (uds)",
        "spreadAngle": "Ángulo del Abanico (grados)",
        "parkTimeMs": "Tiempo Quieto en el Extremo (ms)",
        "returnDamage": "Daño de Vuelta (pts)",
        "wallWidth": "Ancho de la Pared (px)",
        "wallStartOffset": "Spawn Adelante del Enemigo (px)",
        "pushForce": "Distancia de Expulsión (px)"
    };

    if (currentMechTab === 'attack') {
        for(let type in MECHANICS_LIB) {
            const m = MECHANICS_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f) && !JSON.stringify(m).toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            const mechSoundWeb = resolveAssetWebUrl(m.sound || '');
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Nombre Público</label><input type="text" value="${m.label}" onchange="config.mechanicsLib['${type}'].label = this.value; renderAll();"></div><div class="field full" style="margin-top:0.5rem;"><label>Descripción</label><input type="text" value="${m.desc || ''}" onchange="config.mechanicsLib['${type}'].desc = this.value"></div>
            <div style="margin-top:0.8rem; padding:0.8rem; background:rgba(168,85,247,0.06); border:1px solid rgba(168,85,247,0.15); border-radius:6px;">
                <label style="color:#a855f7; font-size:0.6rem; font-weight:bold;">SONIDO POR DEFECTO (assets/Sonidos/Mecanicas/)</label>
                <div style="display:flex; gap:6px; align-items:center; margin-top:0.4rem;">
                    <input type="text" placeholder="res://assets/Sonidos/Mecanicas/ej.ogg" value="${m.sound || ''}" style="flex:1; font-size:0.65rem;" onchange="config.mechanicsLib['${type}'].sound = this.value; renderMechanicsLib();">
                    <button class="btn" style="padding:4px 8px; font-size:0.6rem; background:rgba(168,85,247,0.12); border:1px solid rgba(168,85,247,0.25); color:#a855f7;" onclick="triggerAssetUpload('${type}', 'mechanic_sound')">SONIDO</button>
                    ${m.sound ? `<button class="btn" style="padding:2px 6px; font-size:0.55rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060;" onclick="config.mechanicsLib['${type}'].sound=''; renderMechanicsLib();">X</button>` : ''}
                </div>
                ${mechSoundWeb ? `<audio controls preload="none" src="${mechSoundWeb}" style="width:100%; height:26px; margin-top:0.4rem;"></audio>` : ''}
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:0.4rem;">
                    <div class="field"><label>Volumen <input type="number" id="mech-vol-input-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.mechanicsLib['${type}'].soundVolumePercent=v; let s=document.getElementById('mech-vol-slider-${type}'); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.mechanicsLib['${type}'].soundVolumePercent=v; let s=document.getElementById('mech-vol-slider-${type}'); if(s) s.value=v;"> %</label><input type="range" id="mech-vol-slider-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" oninput="config.mechanicsLib['${type}'].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById('mech-vol-input-${type}'); if(inp) inp.value=this.value;"></div>
                    <div class="field"><label>Dist Max (px)</label><input type="number" step="50" value="${m.soundMaxDist || 1200}" onchange="config.mechanicsLib['${type}'].soundMaxDist = parseInt(this.value) || 1200"></div>
                </div>
            </div>
            <div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => fieldLabels[fl] || fl).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    } else if (currentMechTab === 'defense') {
        for(let type in DEFENSE_LIB) {
            const m = DEFENSE_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f) && !JSON.stringify(m).toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            const defSoundWeb = resolveAssetWebUrl(m.sound || '');
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Nombre Público</label><input type="text" value="${m.label}" onchange="config.defenseLib['${type}'].label = this.value; renderAll();"></div><div class="field full" style="margin-top:0.5rem;"><label>Descripción</label><input type="text" value="${m.desc || ''}" onchange="config.defenseLib['${type}'].desc = this.value"></div>
            <div style="margin-top:0.8rem; padding:0.8rem; background:rgba(16,185,129,0.06); border:1px solid rgba(16,185,129,0.15); border-radius:6px;">
                <label style="color:#10b981; font-size:0.6rem; font-weight:bold;">SONIDO DEFENSIVO</label>
                <div style="display:flex; gap:6px; align-items:center; margin-top:0.4rem;">
                    <input type="text" placeholder="res://assets/Sonidos/Mecanicas/ej.ogg" value="${m.sound || ''}" style="flex:1; font-size:0.65rem;" onchange="config.defenseLib['${type}'].sound = this.value; renderMechanicsLib();">
                    <button class="btn" style="padding:4px 8px; font-size:0.6rem; background:rgba(16,185,129,0.12); border:1px solid rgba(16,185,129,0.25); color:#10b981;" onclick="triggerAssetUpload('${type}', 'defense_sound')">SONIDO</button>
                    ${m.sound ? `<button class="btn" style="padding:2px 6px; font-size:0.55rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060;" onclick="config.defenseLib['${type}'].sound=''; renderMechanicsLib();">X</button>` : ''}
                </div>
                ${defSoundWeb ? `<audio controls preload="none" src="${defSoundWeb}" style="width:100%; height:26px; margin-top:0.4rem;"></audio>` : ''}
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:0.4rem;">
                    <div class="field"><label>Volumen <input type="number" id="def-vol-input-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.defenseLib['${type}'].soundVolumePercent=v; let s=document.getElementById('def-vol-slider-${type}'); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.defenseLib['${type}'].soundVolumePercent=v; let s=document.getElementById('def-vol-slider-${type}'); if(s) s.value=v;"> %</label><input type="range" id="def-vol-slider-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" oninput="config.defenseLib['${type}'].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById('def-vol-input-${type}'); if(inp) inp.value=this.value;"></div>
                    <div class="field"><label>Dist Max (px)</label><input type="number" step="50" value="${m.soundMaxDist || 800}" onchange="config.defenseLib['${type}'].soundMaxDist = parseInt(this.value) || 800"></div>
                </div>
            </div>
            <div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => fieldLabels[fl] || fl).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    } else if (currentMechTab === 'ammo') {
        for(let type in AMMO_MECH_LIB) {
            const m = AMMO_MECH_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Efecto Proyectil</label><input type="text" value="${m.label}" onchange="AMMO_MECH_LIB['${type}'].label = this.value; renderAll();"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">PARÁMETROS AFECTADOS:</strong> ${m.fields.map(fl => { const labels = { bulletDamage: "Daño", bulletSpeed: "Velocidad", fireRange: "Rango", fireRate: "Cadencia", startDelay: "Retraso", lifetimeMs: "Combustible (ms)", slowAmount: "Ralentización", slowDuration: "Duración Slow (ms)", turnSpeed: "Agilidad de Giro (rad/s)", chargeTimeMs: "Tiempo Carga (ms)" }; return labels[fl] || fl; }).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    } else if (currentMechTab === 'ambience') {
        for(let type in AMBIENCE_LIB) {
            const m = AMBIENCE_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            const al = { damagePerSecond: "Daño/Seg", slowPercentage: "Slow Ambient", visibility: "Visibilidad", dashPenalty: "Penalidad Dash", damageMult: "Mult. Daño", speedMult: "Mult. Velocidad", healthMult: "Mult. Vida", respawnSpeedBonus: "Velocidad Respawn (%)" };
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Efecto de Ambiente</label><input type="text" value="${m.label}" onchange="AMBIENCE_LIB['${type}'].label = this.value; renderAll();"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">PARÁMETROS AFECTADOS:</strong> ${m.fields.map(fl => {
                const labels = { 
                    damage: "Daño (pts)", 
                    intervalMs: "Intervalo (ms)", 
                    slowPercentage: "Slow (%)", 
                    visibility: "Visibilidad (px)", 
                    dashPenalty: "Penalidad Dash (%)", 
                    lifetimeMs: "Combustible (ms)", 
                    damageMult: "Mult. Daño (x)", 
                    speedMult: "Mult. Velocidad (x)", 
                    healthMult: "Mult. Vida/Escudo (x)", 
                    respawnSpeedBonus: "Velocidad Respawn (%)",
                    spawnInterval: "Frecuencia/Cadencia (ms)",
                    duration: "Duración Efecto (ms)",
                    pullForce: "Fuerza Atracción (px/s)",
                    damageInterval: "Intervalo Daño (ms)",
                    radius: "Radio Acción/Visión (px)",
                    multiplier: "Multiplicador General (x)"
                };
                return labels[fl] || fl;
            }).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    } else {
        for(let type in MOVEMENT_LIB) {
            const m = MOVEMENT_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            const ml = { speed:"Velocidad", stopDist:"Frenado", idealDist:"Rango", orbitRadius:"Órbita", chargeCooldown: "Dash", activationHP: "Activación HP (%)", explosionDamage: "Daño Explosión", duration: "Duración", explodeOnDeath: "Auto-Detonar" };
            const movSoundWeb = resolveAssetWebUrl(m.sound || '');
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Nombre Público</label><input type="text" value="${m.label}" onchange="config.movementLib['${type}'].label = this.value; renderAll();"></div>
            <div style="margin-top:0.8rem; padding:0.8rem; background:rgba(234,179,8,0.06); border:1px solid rgba(234,179,8,0.15); border-radius:6px;">
                <label style="color:#eab308; font-size:0.6rem; font-weight:bold;">SONIDO MOVIMIENTO</label>
                <div style="display:flex; gap:6px; align-items:center; margin-top:0.4rem;">
                    <input type="text" placeholder="res://assets/Sonidos/Mecanicas/ej.ogg" value="${m.sound || ''}" style="flex:1; font-size:0.65rem;" onchange="config.movementLib['${type}'].sound = this.value; renderMechanicsLib();">
                    <button class="btn" style="padding:4px 8px; font-size:0.6rem; background:rgba(234,179,8,0.12); border:1px solid rgba(234,179,8,0.25); color:#eab308;" onclick="triggerAssetUpload('${type}', 'movement_sound')">SONIDO</button>
                    ${m.sound ? `<button class="btn" style="padding:2px 6px; font-size:0.55rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060;" onclick="config.movementLib['${type}'].sound=''; renderMechanicsLib();">X</button>` : ''}
                </div>
                ${movSoundWeb ? `<audio controls preload="none" src="${movSoundWeb}" style="width:100%; height:26px; margin-top:0.4rem;"></audio>` : ''}
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:0.4rem;">
                    <div class="field"><label>Volumen <input type="number" id="mov-vol-input-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.movementLib['${type}'].soundVolumePercent=v; let s=document.getElementById('mov-vol-slider-${type}'); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.movementLib['${type}'].soundVolumePercent=v; let s=document.getElementById('mov-vol-slider-${type}'); if(s) s.value=v;"> %</label><input type="range" id="mov-vol-slider-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" oninput="config.movementLib['${type}'].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById('mov-vol-input-${type}'); if(inp) inp.value=this.value;"></div>
                    <div class="field"><label>Dist Max (px)</label><input type="number" step="50" value="${m.soundMaxDist || 800}" onchange="config.movementLib['${type}'].soundMaxDist = parseInt(this.value) || 800"></div>
                </div>
            </div>
            <div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => ml[fl] || fl).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    }
}
