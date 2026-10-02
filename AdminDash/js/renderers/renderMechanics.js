// AdminDash/js/renderers/renderMechanics.js
function renderMechanicsLib() {
    const MECHANICS_LIB = config.mechanicsLib || DEFAULT_MECHANICS_LIB;
    const MOVEMENT_LIB = config.movementLib || DEFAULT_MOVEMENT_LIB;
    const DEFENSE_LIB = config.defenseLib || DEFAULT_DEFENSE_LIB;

    const grid = document.getElementById('mechanics-lib-grid'); if(!grid) return;
    grid.innerHTML = '';
    const f = getFilter();
    const fieldLabels = { 
        "bulletDamage": "Daño del Proyectil (pts)", 
        "bulletSpeed": "Velocidad del Proyectil (px/s)", 
        "fireRange": "Alcance / Rango (px)", 
        "fireRate": "Cadencia de Disparo (ms)", 
        "burstShots": "Proyectiles por Ráfaga (uds)", 
        "staticTime": "Tiempo Estático (ms)",
        "reductionPercentage": "Reducción de Daño (%)",
        "shieldRegen": "Regeneración de Escudo (pts/s)",
        "duration": "Duración Total (ms)",
        "cooldown": "Enfriamiento (CD) (ms)",
        "radius": "Radio / Tamaño (px)",
        "damage": "Daño (pts)",
        "healAmount": "Curación por Pulso (pts)",
        "healMode": "Modo de Curación",
        "healAlliesEnabled": "¿Curar Aliados Cercanos? (Sí/No)",
        "healRange": "Radio de Curación (px)",
        "damageEnabled": "¿Activar Daño en la Explosión? (Sí/No)",
        "explosionRadius": "Radio de Explosión (px)",
        "affectsEnemies": "¿Afectar a otros Enemigos? (Sí/No)",
        "affectsBosses": "¿Afectar a Bosses? (Sí/No)",
        "speedBonus": "Bono de Velocidad (px/s)",
        "intervalMs": "Intervalo entre Ticks (ms)",
        "castTimeMs": "Tiempo de Casteo (ms)",
        "castSpeed": "Velocidad de Casteo (x)",
        "coneAngle": "Ángulo del Cono (grados)",
        "stunDuration": "Duración de Parálisis (ms)",
        "coneFollow": "Seguimiento Dinámico (Homing) (Sí/No)",
        "lockTimeMs": "Tiempo de Bloqueo (ms)",
        "aimDelayMs": "Espera de Apuntado (ms)",
        "reflect_mult": "Multiplicador de Reflejo (x)",
        "activationMode": "Modo de Activación",
        "activationHPs": "Activadores de Vida (%)",
        "activationIntervalMs": "Tiempo en Combate para Activar (ms)",
        "summonCount": "Cantidad de Invocaciones (uds)",
        "spawnRadius": "Radio de Invocación (px)",
        "summonDurationMode": "Modo de Duración de Invocación",
        "summonDurationMs": "Tiempo de Vida de Invocación (ms)",
        "summonsList": "Lista de Esbirros Invocados",
        "tick_interval": "Intervalo entre Ticks (ms)",
        "damage_per_tick": "Daño por Tick (pts)",
        "slow_amount": "Ralentización (px/s o %)",
        "slowDuration": "Duración de Ralentización (ms)",
        "slowIsPercentage": "Ralentización Porcentual (%)",
        "projectileCount": "Cantidad de Gusanos (uds)",
        "spreadAngle": "Ángulo del Abanico (grados)",
        "parkTimeMs": "Tiempo Quieto en el Extremo (ms)",
        "returnDamage": "Daño de Vuelta (pts)",
        "wallWidth": "Ancho de la Pared (px)",
        "beamWidth": "Ancho del Rayo (px)",
        "wallStartOffset": "Spawn Adelante del Enemigo (px)",
        "pushForce": "Distancia / Fuerza de Expulsión (px)",
        "speed": "Velocidad (px/s)",
        "warnTimeMs": "Tiempo de Aviso (ms)",
        "pushOnHit": "¿Expulsar al Colisionar? (Sí/No)",
        // v901.0: Bola de Fuego Dinámica
        "areaRadius": "Radio del Área de Deambulación (px)",
        "areaMode": "Ubicación del Área ('enemy' o 'target')",
        // v901.1: Atracción hacia la Bola de Fuego
        "pullEnabled": "¿Activar Atracción de Rayos? (Sí/No)",
        "pullRadius": "Radio de Atracción de Rayos (px)",
        "pullStrength": "Fuerza de Atracción hacia la Bola (px/s)",
        "ray_damage": "Daño por Tick de Rayos (pts)",
        // v415.0: Látigo Dominante
        "hits": "Cantidad de Azotes (golpes)",
        "cadence": "Cadencia entre Latigazos (ms)",
        "castInterruptible": "¿Se Interrumpe con CC? (Sí/No)",
        "startDelay": "Retraso de Inicio (ms)",
        "turnSpeed": "Agilidad de Giro (rad/s)",
        "chargeTimeMs": "Tiempo de Carga (ms)",
        "isHoming": "Seguimiento (Homing) (Sí/No)",
        "orbitSpeed": "Velocidad de Giro (rad/s)",
        "circleCount": "Cantidad de Círculos (uds)",
        "orbitRadius": "Radio de Órbita (px)",
        "orbitDuration": "Tiempo de Giro (ms)",
        "safeRadius": "Radio del Domo Seguro (px)",
        "maxOffset": "Radio Máximo de Dispersión (px)",
        "postCastWaitMs": "Espera Post-Explosión (ms)",
        "postHookWaitMs": "Espera Post-Gancho (ms)",
        "hookMissWaitMs": "Espera por Fallo (ms)",
        "bulletCount": "Cantidad de Proyectiles (uds)",
        "isPointAndClick": "¿Apuntado Directo? (Sí/No)",
        "polyDuration": "Duración de Polimorfismo (ms)",
        "canMove": "¿Puede Moverse? (Sí/No)",
        "canUseSkills": "¿Puede Usar Habilidades? (Sí/No)",
        "meteorCount": "Cantidad de Meteoritos (uds)",
        "fallHeight": "Altura de Caída (px)",
        "fallSpeed": "Velocidad de Caída (px/s)",
        "meteorSize": "Tamaño del Meteorito (px)",
        "explosionRadius": "Radio de Explosión (px)",
        "persistentZone": "¿Zona Persistente? (Sí/No)",
        "zoneDamage": "Daño por Tick de Zona (pts)",
        "zoneTickMs": "Intervalo de Tick de Zona (ms)",
        "zoneDuration": "Duración de Zona Persistente (ms)",
        "targetCount": "Cantidad de Objetivos (uds)",
        "airTimeMs": "Tiempo en el Aire (ms)",
        "warnDelayMs": "Tiempo de Espera del Área (ms)",
        "targetMode": "Criterio de Selección de Objetivo",
        "targetSphereColor": "Color de Esfera",
        "stealAmount": "Cantidad de Robo (pts o %)",
        "stealIntervalMs": "Intervalo de Robo (ms)",
        "stealMode": "Modo de Robo",
        "giveToEnemy": "¿Transferir al Enemigo? (Sí/No)",
        "activationHP": "Activación por HP (%)",
        "bombCount": "Cantidad de Bombas (uds)",
        "bombDelayMs": "Espera entre Bombas (ms)",
        "fuseTimeMs": "Retardo de Explosión (ms)",
        "damagePerSecond": "Daño por Segundo (pts/s)",
        "nightmareMultiplier": "Multiplicador de Pesadilla (x)",
        "wakeOnDamage": "¿Despierta al Recibir Daño? (Sí/No)",
        "spinSpeed": "Velocidad de Giro (rad/s)",
        "speedBuffAmount": "Bono de Velocidad al Dueño (px/s)",
        "speedBuffDuration": "Duración Bono de Velocidad (ms)",
        "applySlow": "Aplicar Ralentización (Sí/No)",
        "arcAngle": "Ángulo del Arco Melee (grados)",
        "fullCircle": "¿Giro Completo 360°? (Sí/No)",
        "range": "Distancia de Embestida (px)",
        "lifetimeMs": "Tiempo de Vida (ms)",
        "slowAmount": "Cantidad de Ralentización (px/s)",
        // v902.0: Enraizada
        "trapRadius": "Radio de las Raíces (px)",
        "rootDuration": "Duración del Enraizamiento (ms)",
        "trapDamage": "Daño al Atrapar (pts)",
        "rootDps": "Daño por Tick mientras está Enraizado (pts/s, 0 = sin daño)",
        "rootTickInterval": "Intervalo de Tick del Root (ms)"
    };

    if (currentMechTab === 'attack') {
        for(let type of Object.keys(MECHANICS_LIB).sort((a,b)=>MECHANICS_LIB[a].label.localeCompare(MECHANICS_LIB[b].label))) {
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
        for(let type of Object.keys(DEFENSE_LIB).sort((a,b)=>DEFENSE_LIB[a].label.localeCompare(DEFENSE_LIB[b].label))) {
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
        for(let type of Object.keys(AMMO_MECH_LIB).sort((a,b)=>AMMO_MECH_LIB[a].label.localeCompare(AMMO_MECH_LIB[b].label))) {
            const m = AMMO_MECH_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Efecto Proyectil</label><input type="text" value="${m.label}" onchange="AMMO_MECH_LIB['${type}'].label = this.value; renderAll();"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">PARÁMETROS AFECTADOS:</strong> ${m.fields.map(fl => { const labels = { bulletDamage: "Daño", bulletSpeed: "Velocidad", fireRange: "Rango", fireRate: "Cadencia", startDelay: "Retraso", lifetimeMs: "Combustible (ms)", slowAmount: "Ralentización", slowDuration: "Duración Slow (ms)", turnSpeed: "Agilidad de Giro (rad/s)", chargeTimeMs: "Tiempo Carga (ms)" }; return labels[fl] || fl; }).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    } else if (currentMechTab === 'ambience') {
        for(let type of Object.keys(AMBIENCE_LIB).sort((a,b)=>AMBIENCE_LIB[a].label.localeCompare(AMBIENCE_LIB[b].label))) {
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
    } else if (currentMechTab === 'aggro') {
        if (!config.aggroConfig) {
            config.aggroConfig = {
                enabled: true,
                damageThreatMultiplier: 1.0,
                healingThreatMultiplier: 0.5,
                tankDamageTakenMultiplier: 1.5,
                tankRoleThreatMultiplier: 2.5,
                sphereBlueThreatBonus: 0.50,
                sphereRedThreatBonus: 0.15,
                sphereGreenThreatBonus: 0.25,
                sphereYellowThreatBonus: 0.10,
                meleePeelThreshold: 1.10,
                rangedPeelThreshold: 1.30,
                meleeRangeThreshold: 250,
                threatDecayRatePercent: 5,
                threatDecayDelayMs: 5000,
                tauntBonusPercent: 10,
                initialPullThreat: 100,
                altarBaseThreat: 500
            };
        }
        const ac = config.aggroConfig;
        const card = document.createElement('div');
        card.className = 'card';
        card.style.gridColumn = '1 / -1';
        card.style.background = 'linear-gradient(135deg, rgba(234, 179, 8, 0.05), rgba(168, 85, 247, 0.05), rgba(6, 182, 212, 0.05))';
        card.style.border = '1px solid rgba(234, 179, 8, 0.35)';
        card.style.borderRadius = '12px';
        card.style.padding = '1.8rem';
        card.style.boxShadow = '0 10px 30px rgba(0,0,0,0.5)';

        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid rgba(234,179,8,0.25); padding-bottom:1rem; margin-bottom:1.5rem; flex-wrap:wrap; gap:12px;">
                <div>
                    <h2 style="color:#eab308; margin:0; font-size:1.4rem; display:flex; align-items:center; gap:8px;">
                        <span>👑</span> SISTEMA DE AGRO Y AMENAZA (BALANCE GLOBAL)
                    </h2>
                    <p style="color:#999; font-size:0.85rem; margin:4px 0 0;">Configuración de amenaza para Tanques (Esferas Azules), Sanadores (Esferas Verdes) y Dañadores (Esferas Rojas).</p>
                </div>
                <div>
                    <label style="display:flex; align-items:center; gap:10px; cursor:pointer; color:white; font-size:0.9rem; font-weight:bold; background:rgba(0,0,0,0.45); padding:8px 16px; border-radius:6px; border:1px solid rgba(255,255,255,0.15);">
                        <input type="checkbox" ${ac.enabled !== false ? 'checked' : ''} onchange="config.aggroConfig.enabled = this.checked; renderMechanicsLib();">
                        <span>Sistema de Agro Activo</span>
                    </label>
                </div>
            </div>

            <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(320px, 1fr)); gap:1.5rem;">
                <!-- TARJETA 1: ESFERAS Y ROL TANQUE -->
                <div style="background:rgba(0,0,0,0.35); border:1px solid rgba(59,130,246,0.35); border-radius:10px; padding:1.3rem;">
                    <h4 style="color:#60a5fa; margin:0 0 0.5rem; font-size:0.95rem; display:flex; align-items:center; gap:8px;">
                        🔮 AGRO POR ESFERAS EQUIPADAS Y ROL TANQUE
                    </h4>
                    <p style="color:#aaa; font-size:0.75rem; margin:0 0 1.2rem; line-height:1.4;">
                        Cada esfera orbital equipada suma amenaza pasiva. <strong>El jugador con más esferas azules del grupo es consagrado como el Tanque oficial</strong> y recibe el multiplicador de tanque.
                    </p>
                    <div style="display:flex; flex-direction:column; gap:14px;">
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#93c5fd;">🔵 Esfera Azul (Defensa)</span>
                                <span style="color:#60a5fa; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">+${Math.round((ac.sphereBlueThreatBonus !== undefined ? ac.sphereBlueThreatBonus : 0.50) * 100)}% de Agro</span>
                            </label>
                            <input type="number" step="0.05" min="0" max="5.0" value="${ac.sphereBlueThreatBonus !== undefined ? ac.sphereBlueThreatBonus : 0.50}" onchange="config.aggroConfig.sphereBlueThreatBonus = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Bono por cada esfera azul equipada (0.50 = +50% de amenaza acumulable).</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#fca5a5;">🔴 Esfera Roja (Ataque)</span>
                                <span style="color:#f87171; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">+${Math.round((ac.sphereRedThreatBonus !== undefined ? ac.sphereRedThreatBonus : 0.15) * 100)}% de Agro</span>
                            </label>
                            <input type="number" step="0.05" min="0" max="5.0" value="${ac.sphereRedThreatBonus !== undefined ? ac.sphereRedThreatBonus : 0.15}" onchange="config.aggroConfig.sphereRedThreatBonus = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Bono por cada esfera roja equipada (0.15 = +15% de amenaza acumulable).</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#86efac;">🟢 Esfera Verde (Curación)</span>
                                <span style="color:#4ade80; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">+${Math.round((ac.sphereGreenThreatBonus !== undefined ? ac.sphereGreenThreatBonus : 0.25) * 100)}% de Agro</span>
                            </label>
                            <input type="number" step="0.05" min="0" max="5.0" value="${ac.sphereGreenThreatBonus !== undefined ? ac.sphereGreenThreatBonus : 0.25}" onchange="config.aggroConfig.sphereGreenThreatBonus = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Bono por cada esfera verde equipada (0.25 = +25% de amenaza acumulable).</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#fde047;">🟡 Esfera Amarilla (Utilidad)</span>
                                <span style="color:#facc15; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">+${Math.round((ac.sphereYellowThreatBonus !== undefined ? ac.sphereYellowThreatBonus : 0.10) * 100)}% de Agro</span>
                            </label>
                            <input type="number" step="0.05" min="0" max="5.0" value="${ac.sphereYellowThreatBonus !== undefined ? ac.sphereYellowThreatBonus : 0.10}" onchange="config.aggroConfig.sphereYellowThreatBonus = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Bono por cada esfera amarilla equipada (0.10 = +10% de amenaza acumulable).</small>
                        </div>
                        <div class="field" style="border-top:1px dashed rgba(234,179,8,0.3); padding-top:10px; margin-top:4px;">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:bold; color:#eab308;">🛡️ Multiplicador para el Tanque del Grupo</span>
                                <span style="color:#eab308; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.95rem;">${ac.tankRoleThreatMultiplier !== undefined ? ac.tankRoleThreatMultiplier : 2.5}x</span>
                            </label>
                            <input type="number" step="0.1" min="1" max="50" value="${ac.tankRoleThreatMultiplier !== undefined ? ac.tankRoleThreatMultiplier : 2.5}" onchange="config.aggroConfig.tankRoleThreatMultiplier = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#eab308; font-size:0.7rem;">Multiplicador otorgado automáticamente al miembro con más esferas azules (mínimo 1).</small>
                        </div>
                    </div>
                </div>

                <!-- TARJETA 2: GENERACIÓN BASE DE AMENAZA -->
                <div style="background:rgba(0,0,0,0.35); border:1px solid rgba(239,68,68,0.35); border-radius:10px; padding:1.3rem;">
                    <h4 style="color:#f87171; margin:0 0 0.5rem; font-size:0.95rem; display:flex; align-items:center; gap:8px;">
                        ⚔️ GENERACIÓN BASE DE AGRO (PESOS)
                    </h4>
                    <p style="color:#aaa; font-size:0.75rem; margin:0 0 1.2rem; line-height:1.4;">
                        Equivalencia base entre las acciones de combate y la amenaza generada hacia los enemigos.
                    </p>
                    <div style="display:flex; flex-direction:column; gap:14px;">
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#fca5a5;">Agro por Daño Infligido (DPS)</span>
                                <span style="color:#f87171; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">${ac.damageThreatMultiplier !== undefined ? ac.damageThreatMultiplier : 1.0}x</span>
                            </label>
                            <input type="number" step="0.1" min="0" max="100" value="${ac.damageThreatMultiplier !== undefined ? ac.damageThreatMultiplier : 1.0}" onchange="config.aggroConfig.damageThreatMultiplier = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">1 de daño genera X puntos de amenaza (funciona a cualquier distancia).</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#86efac;">Agro por Curación Realizada (Healer)</span>
                                <span style="color:#4ade80; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">${ac.healingThreatMultiplier !== undefined ? ac.healingThreatMultiplier : 0.5}x</span>
                            </label>
                            <input type="number" step="0.05" min="0" max="100" value="${ac.healingThreatMultiplier !== undefined ? ac.healingThreatMultiplier : 0.5}" onchange="config.aggroConfig.healingThreatMultiplier = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">1 de curación genera X puntos de amenaza repartidos entre enemigos en combate.</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#93c5fd;">Agro por Mitigación / Daño Recibido</span>
                                <span style="color:#60a5fa; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">${ac.tankDamageTakenMultiplier !== undefined ? ac.tankDamageTakenMultiplier : 1.5}x</span>
                            </label>
                            <input type="number" step="0.1" min="0" max="100" value="${ac.tankDamageTakenMultiplier !== undefined ? ac.tankDamageTakenMultiplier : 1.5}" onchange="config.aggroConfig.tankDamageTakenMultiplier = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Amenaza base generada por el tanque al recibir y resistir ataques del enemigo.</small>
                        </div>
                    </div>
                </div>

                <!-- TARJETA 3: HISTÉRESIS Y VISIÓN DE AGRO -->
                <div style="background:rgba(0,0,0,0.35); border:1px solid rgba(6,182,212,0.35); border-radius:10px; padding:1.3rem;">
                    <h4 style="color:#22d3ee; margin:0 0 0.5rem; font-size:0.95rem; display:flex; align-items:center; gap:8px;">
                        🎯 CONTROL DE TARGET Y DESPEGUE (ANTI-PING-PONG)
                    </h4>
                    <p style="color:#aaa; font-size:0.75rem; margin:0 0 1.2rem; line-height:1.4;">
                        Evita que el mob cambie erráticamente de objetivo ante pequeñas variaciones de daño entre jugadores.
                    </p>
                    <div style="display:flex; flex-direction:column; gap:14px;">
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#a5f3fc;">Robo de Agro en Cuerpo a Cuerpo</span>
                                <span style="color:#22d3ee; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">${Math.round((ac.meleePeelThreshold || 1.10) * 100)}%</span>
                            </label>
                            <input type="number" step="0.05" min="1.0" max="3.0" value="${ac.meleePeelThreshold !== undefined ? ac.meleePeelThreshold : 1.10}" onchange="config.aggroConfig.meleePeelThreshold = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">1.10 = 110%. Un atacante melee debe superar en un 10% la amenaza del tanque actual.</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#a5f3fc;">Robo de Agro a Distancia (Rango)</span>
                                <span style="color:#22d3ee; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">${Math.round((ac.rangedPeelThreshold || 1.30) * 100)}%</span>
                            </label>
                            <input type="number" step="0.05" min="1.0" max="3.0" value="${ac.rangedPeelThreshold !== undefined ? ac.rangedPeelThreshold : 1.30}" onchange="config.aggroConfig.rangedPeelThreshold = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">1.30 = 130%. Un tirador lejano debe superar en un 30% la amenaza para robar el objetivo.</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#a5f3fc;">Distancia Cuerpo a Cuerpo (Píxeles)</span>
                                <span style="color:#22d3ee; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">${ac.meleeRangeThreshold || 250} px</span>
                            </label>
                            <input type="number" step="10" min="50" max="1000" value="${ac.meleeRangeThreshold !== undefined ? ac.meleeRangeThreshold : 250}" onchange="config.aggroConfig.meleeRangeThreshold = parseInt(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Distancia en píxeles por debajo de la cual se considera rango cuerpo a cuerpo.</small>
                        </div>
                        <div style="background:rgba(6,182,212,0.08); border:1px solid rgba(6,182,212,0.25); border-radius:6px; padding:0.7rem;">
                            <span style="color:#22d3ee; font-size:0.75rem; font-weight:bold;">👁️ PERCEPCIÓN DINÁMICA POR VISIÓN DEL ENEMIGO:</span>
                            <p style="color:#aaa; font-size:0.7rem; margin:4px 0 0; line-height:1.35;">La detección de curaciones y ataques utiliza el área de visión individual de cada mob o boss, impidiendo que jugadores a distancia curen o ataquen impunemente.</p>
                        </div>
                    </div>
                </div>

                <!-- TARJETA 4: PROVOCACIÓN, PULL Y DECAIMIENTO -->
                <div style="background:rgba(0,0,0,0.35); border:1px solid rgba(168,85,247,0.35); border-radius:10px; padding:1.3rem;">
                    <h4 style="color:#c084fc; margin:0 0 0.5rem; font-size:0.95rem; display:flex; align-items:center; gap:8px;">
                        📢 PROVOCACIÓN (TAUNT), PULL Y PÉRDIDA DE AGRO
                    </h4>
                    <p style="color:#aaa; font-size:0.75rem; margin:0 0 1.2rem; line-height:1.4;">
                        Mecánicas de fijación obligatoria y reducción de amenaza por inactividad prolongada.
                    </p>
                    <div style="display:flex; flex-direction:column; gap:14px;">
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#e9d5ff;">Bono Extra de Provocación (Taunt)</span>
                                <span style="color:#c084fc; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">+${ac.tauntBonusPercent !== undefined ? ac.tauntBonusPercent : 10}%</span>
                            </label>
                            <input type="number" step="1" min="0" max="100" value="${ac.tauntBonusPercent !== undefined ? ac.tauntBonusPercent : 10}" onchange="config.aggroConfig.tauntBonusPercent = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Porcentaje extra otorgado al tanque por encima de la amenaza máxima al usar Taunt.</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#e9d5ff;">Agro Inicial al Avistar Jugador (Pull)</span>
                                <span style="color:#c084fc; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">${ac.initialPullThreat || 100} pts</span>
                            </label>
                            <input type="number" step="10" min="0" max="10000" value="${ac.initialPullThreat !== undefined ? ac.initialPullThreat : 100}" onchange="config.aggroConfig.initialPullThreat = parseInt(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Amenaza base otorgada al primer jugador que entra en la visión del enemigo agresivo.</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#e9d5ff;">Pérdida de Agro por Inactividad (% / seg)</span>
                                <span style="color:#c084fc; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">${ac.threatDecayRatePercent !== undefined ? ac.threatDecayRatePercent : 5}%</span>
                            </label>
                            <input type="number" step="1" min="0" max="100" value="${ac.threatDecayRatePercent !== undefined ? ac.threatDecayRatePercent : 5}" onchange="config.aggroConfig.threatDecayRatePercent = parseFloat(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Porcentaje de pérdida de amenaza por segundo si el jugador deja de atacar o curar.</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#e9d5ff;">Tiempo de Espera para Perder Agro</span>
                                <span style="color:#c084fc; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">${(ac.threatDecayDelayMs !== undefined ? ac.threatDecayDelayMs : 5000) / 1000} seg</span>
                            </label>
                            <input type="number" step="500" min="1000" max="60000" value="${ac.threatDecayDelayMs !== undefined ? ac.threatDecayDelayMs : 5000}" onchange="config.aggroConfig.threatDecayDelayMs = parseInt(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Milisegundos de inactividad antes de que la amenaza comience a degradarse (5000 ms = 5 seg).</small>
                        </div>
                        <div class="field">
                            <label style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-weight:600; color:#fde047;">Agro Base del Altar (Modo Invasión)</span>
                                <span style="color:#eab308; font-family:'JetBrains Mono'; font-weight:bold; font-size:0.85rem;">${ac.altarBaseThreat || 500} pts</span>
                            </label>
                            <input type="number" step="50" min="0" max="100000" value="${ac.altarBaseThreat !== undefined ? ac.altarBaseThreat : 500}" onchange="config.aggroConfig.altarBaseThreat = parseInt(this.value); renderMechanicsLib();">
                            <small style="color:#888; font-size:0.7rem;">Amenaza base del Altar para que los jugadores puedan rescatarlo haciendo daño o con Taunt.</small>
                        </div>
                    </div>
                </div>
            </div>
        `;
        grid.appendChild(card);
    } else {
        for(let type of Object.keys(MOVEMENT_LIB).sort((a,b)=>MOVEMENT_LIB[a].label.localeCompare(MOVEMENT_LIB[b].label))) {
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
