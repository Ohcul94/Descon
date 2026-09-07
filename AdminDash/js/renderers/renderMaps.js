// AdminDash/js/renderers/renderMaps.js
function renderMapDetail() {
    const container = document.getElementById('map-detail-container');
    const m = config.mapsConfig[selectedMapId];
    if(!m) return;
    if(!m.ambience) m.ambience = [];

    container.innerHTML = `
        <div style="display: grid; grid-template-columns: 1fr 1.2fr 1.2fr; gap: 1.5rem; align-items: start;">
            <div class="col">
                <div class="card" style="width:100%;">
                    <div style="display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:1rem;">
                        <div class="field" style="flex:1; margin:0;"><label>NOMBRE DE LA ZONA</label><input type="text" value="${m.name}" style="font-size: 1.5rem; color:var(--accent);" onchange="config.mapsConfig['${selectedMapId}'].name = this.value; updateSidebar();"></div>
                        <button onclick="toggleMapVisibility('${selectedMapId}'); renderMapDetail();" 
                                title="${m.visible !== false ? 'Mapa Activo (Visible en Godot)' : 'Mapa Inactivo (Oculto en Godot)'}"
                                style="background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); color:${m.visible !== false ? 'var(--primary)' : '#64748b'}; cursor:pointer; font-size:1.4rem; padding:10px 14px; border-radius:8px; margin-top:20px; transition:all 0.2s; display:flex; align-items:center; justify-content:center; height:50px;">
                            ${m.visible !== false ? '👁️' : '🕶️'}
                        </button>
                    </div>
                    <div class="field full" style="margin-top:1rem;"><label>DESCRIPCIÓN DE HISTORIA</label><textarea onchange="config.mapsConfig['${selectedMapId}'].desc = this.value" style="height:100px; width:100%; background:rgba(0,0,0,0.2); border:1px solid #333; color:white; padding:10px; border-radius:8px;">${m.desc || ''}</textarea></div>
                    <div class="form-grid" style="margin-top:1rem;">
                        <div class="field"><label>Nivel Mín. (lvl)</label><input type="number" value="${m.minLevel}" oninput="config.mapsConfig['${selectedMapId}'].minLevel = parseInt(this.value) || 0"></div>
                        <div class="field"><label>Costo Warp (Hubs)</label><input type="number" value="${m.warpCost}" oninput="config.mapsConfig['${selectedMapId}'].warpCost = parseInt(this.value) || 0"></div>
                        <div class="field"><label>Color de Radar</label><input type="color" value="${m.color || '#00d2ff'}" oninput="config.mapsConfig['${selectedMapId}'].color = this.value; updateSidebar();" style="height:40px;"></div>
                        <div class="field"><label>Multiplicador de Drop (x)</label><input type="number" step="0.1" min="0" value="${m.dropMultiplier !== undefined ? m.dropMultiplier : 1}" oninput="config.mapsConfig['${selectedMapId}'].dropMultiplier = parseFloat(this.value) || 1"></div>
                        <div class="field"><label>🛸 Punto de Aparición X (Warp / VIAJAR)</label><input type="number" value="${m.spawnX !== undefined ? m.spawnX : ''}" placeholder="Centro del mapa" oninput="if(this.value === ''){ delete config.mapsConfig['${selectedMapId}'].spawnX; } else { config.mapsConfig['${selectedMapId}'].spawnX = parseInt(this.value) || 0; }"></div>
                        <div class="field"><label>🛸 Punto de Aparición Y (Warp / VIAJAR)</label><input type="number" value="${m.spawnY !== undefined ? m.spawnY : ''}" placeholder="Centro del mapa" oninput="if(this.value === ''){ delete config.mapsConfig['${selectedMapId}'].spawnY; } else { config.mapsConfig['${selectedMapId}'].spawnY = parseInt(this.value) || 0; }"></div>
                        <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; grid-column: span 2; margin-top:4px;">
                            <input type="checkbox" id="map-unlock-required" ${m.unlockRequired === true ? 'checked' : ''} onchange="config.mapsConfig['${selectedMapId}'].unlockRequired = this.checked; renderMapDetail();">
                            <label style="margin:0; cursor:pointer;" for="map-unlock-required">🔒 Requiere desbloqueo por misión (el portal queda sellado hasta que una misión otorgue el desbloqueo del mapa)</label>
                        </div>
                    </div>
                    <div style="margin-top: 1.5rem; padding-top: 1.2rem; border-top: 1px solid rgba(255,255,255,0.05);">
                        <label style="color:var(--accent); font-size: 0.65rem; font-weight:bold; letter-spacing:1px; display:block; margin-bottom:0.8rem;">⚔️ CONFIGURACIÓN DE PVP Y SEGURIDAD</label>
                        <div class="form-grid">
                            <div class="field" style="grid-column: span 2;">
                                <label>Modo de PvP</label>
                                <select onchange="config.mapsConfig['${selectedMapId}'].pvpMode = this.value; renderMapDetail();" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.8rem; border-radius:4px; padding:6px; margin-top:4px;">
                                    <option value="tranquila" ${m.pvpMode === 'tranquila' || !m.pvpMode ? 'selected' : ''}>🕊️ Zona Tranquila (PVP Opcional)</option>
                                    <option value="mandatory" ${m.pvpMode === 'mandatory' ? 'selected' : ''}>⚔️ PVP Obligatorio</option>
                                    <option value="partial_drop" ${m.pvpMode === 'partial_drop' ? 'selected' : ''}>🎒 PVP Obligatorio + Partial Drop (Inventario)</option>
                                    <option value="full_drop" ${m.pvpMode === 'full_drop' ? 'selected' : ''}>💀 PVP Obligatorio + Full Drop</option>
                                    <option value="inferno" ${m.pvpMode === 'inferno' ? 'selected' : ''}>🔥 INFIERNO - Pierdes TODO + Nave destruida</option>
                                </select>
                            </div>
                            ${(m.pvpMode === 'tranquila' || !m.pvpMode) ? `
                            <div class="field" style="grid-column: span 2;">
                                <label>Cooldown Cambio de Combate (ms)</label>
                                <input type="number" min="0" value="${m.pvpToggleCooldown !== undefined ? m.pvpToggleCooldown : 30000}" oninput="config.mapsConfig['${selectedMapId}'].pvpToggleCooldown = parseInt(this.value) || 0">
                            </div>
                            ` : ''}
                            ${(m.pvpMode === 'mandatory' || m.pvpMode === 'full_drop' || m.pvpMode === 'partial_drop' || m.pvpMode === 'inferno') ? `
                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; grid-column: span 2; margin-top:8px;">
                                <input type="checkbox" id="give-invul-entry" ${m.giveInvulnerabilityOnEntry ? 'checked' : ''} onchange="config.mapsConfig['${selectedMapId}'].giveInvulnerabilityOnEntry = this.checked; renderMapDetail();">
                                <label style="margin:0; cursor:pointer;" for="give-invul-entry">🛡️ Dar invulnerabilidad al entrar</label>
                            </div>
                            ${m.giveInvulnerabilityOnEntry ? `
                            <div class="field" style="grid-column: span 2;">
                                <label>Tiempo de Invulnerabilidad (ms)</label>
                                <input type="number" min="1" value="${m.invulnerabilityDuration || 5000}" oninput="config.mapsConfig['${selectedMapId}'].invulnerabilityDuration = parseInt(this.value) || 5000">
                            </div>
                            ` : ''}
                            ` : ''}
                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; grid-column: span 2; margin-top:8px; padding:8px; border-radius:6px; background:rgba(255,193,7,0.06); border:1px solid rgba(255,193,7,0.15);">
                                <input type="checkbox" id="friendly-fire-toggle" ${m.friendlyFire ? 'checked' : ''} onchange="config.mapsConfig['${selectedMapId}'].friendlyFire = this.checked">
                                <label style="margin:0; cursor:pointer;" for="friendly-fire-toggle">🎯 Permitir fuego amigo en party (si está desactivado, la party no se hace daño, solo buffs/curas)</label>
                            </div>
                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; grid-column: span 2; margin-top:8px; padding:8px; border-radius:6px; background:rgba(255,193,7,0.06); border:1px solid rgba(255,193,7,0.15);">
                                <input type="checkbox" id="friendly-fire-clan-toggle" ${m.friendlyFireClan ? 'checked' : ''} onchange="config.mapsConfig['${selectedMapId}'].friendlyFireClan = this.checked">
                                <label style="margin:0; cursor:pointer;" for="friendly-fire-clan-toggle">🛡️ Permitir fuego amigo en clan (si está desactivado, el clan no se hace daño, solo buffs/curas)</label>
                            </div>
                        </div>
                    </div>
                    <div style="margin-top: 1.5rem; padding-top: 1.2rem; border-top: 1px solid rgba(255,255,255,0.05);">
                        <label style="color:var(--accent); font-size: 0.65rem; font-weight:bold; letter-spacing:1px; display:block; margin-bottom:0.8rem;">📐 DIMENSIONES DEL MAPA EN PÍXELES</label>
                        <div class="form-grid">
                            <div class="field"><label>Ancho (Width - px)</label><input type="number" value="${m.width || 10000}" oninput="config.mapsConfig['${selectedMapId}'].width = parseInt(this.value)"></div>
                            <div class="field"><label>Alto (Height - px)</label><input type="number" value="${m.height || 10000}" oninput="config.mapsConfig['${selectedMapId}'].height = parseInt(this.value)"></div>
                        </div>
                    </div>
                    ${(() => {
                        // Normalizar datos: migrar formato antiguo → nuevo
                        const hours = (m.allowedHours || []).map(g => {
                            if (g.hours) return g; // ya en formato nuevo
                            return {
                                days: g.days || [0,1,2,3,4,5,6],
                                hours: [{ start: g.start || "00:00", end: g.end || "00:00" }]
                            };
                        });
                        const dayLabels = ['DO','LU','MA','MI','JU','VI','SA'];
                        const dayValues = [0,1,2,3,4,5,6];
                        return `
                    <div style="margin-top: 1.5rem; padding-top: 1.2rem; border-top: 1px solid rgba(255,255,255,0.05);">
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.8rem;">
                            <label style="color:var(--accent); font-size: 0.65rem; font-weight:bold; letter-spacing:1px; margin:0;">🕒 RESTRICCIÓN DE HORARIOS (SERVER)</label>
                            <div style="display:flex; align-items:center; gap:8px;">
                                <input type="checkbox" id="time-restrictions-enabled" ${m.timeRestrictionsEnabled ? 'checked' : ''} 
                                       onchange="toggleTimeRestrictions('${selectedMapId}', this.checked)" style="width:16px; height:16px; cursor:pointer; accent-color:var(--accent);">
                                <label for="time-restrictions-enabled" style="margin:0; cursor:pointer; font-size:0.75rem; color:var(--text-dim);">Activar</label>
                            </div>
                        </div>
                        ${m.timeRestrictionsEnabled ? `
                        <div style="background:rgba(0,0,0,0.25); padding:1rem; border-radius:10px; border:1px solid rgba(255,255,255,0.05); margin-bottom:1rem;">
                            <div id="allowed-hours-list" style="display:flex; flex-direction:column; gap:10px; margin-bottom:1.2rem; max-height:320px; overflow-y:auto;">
                                ${hours.length === 0 ? '<span style="font-size:0.75rem; color:#64748b; font-style:italic;">No hay horarios configurados. El sector será inaccesible.</span>' : ''}
                                ${hours.map((group, gIdx) => {
                                    const days = group.days || [0,1,2,3,4,5,6];
                                    const isAllDays = days.length === 7;
                                    const isEditing = window._editingGroupIndex === gIdx;
                                    if (isEditing) {
                                        return `
                                        <div style="display:flex; flex-direction:column; gap:6px; background:rgba(0,0,0,0.3); padding:8px 12px; border-radius:6px; border:1px solid var(--primary);">
                                            <div style="display:flex; justify-content:space-between; align-items:center;">
                                                <span style="color:var(--accent); font-size:0.6rem; font-weight:bold; letter-spacing:1px;">EDITAR GRUPO</span>
                                                <div style="display:flex; gap:6px;">
                                                    <button style="background:none; border:none; color:#00ff88; cursor:pointer; font-weight:bold; font-size:1rem; padding:2px 6px;" 
                                                            title="Confirmar Grupo" onclick="saveScheduleGroup('${selectedMapId}', ${gIdx})">✓</button>
                                                    <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-weight:bold; font-size:0.95rem; padding:2px 6px;" 
                                                            title="Cancelar" onclick="cancelScheduleGroupEdit()">✕</button>
                                                </div>
                                            </div>
                                            <div style="display:flex; align-items:center; gap:4px; flex-wrap:wrap;">
                                                ${dayValues.map(d => `
                                                    <label style="display:flex; align-items:center; gap:2px; cursor:pointer; font-size:0.65rem; color:${days.includes(d) ? 'var(--accent)' : '#64748b'}; font-weight:${days.includes(d) ? 'bold' : 'normal'}; padding:2px 4px; border-radius:4px; background:${days.includes(d) ? 'rgba(6,182,212,0.15)' : 'transparent'}; border:1px solid ${days.includes(d) ? 'var(--accent)' : 'rgba(255,255,255,0.05)'};">
                                                        <input type="checkbox" class="edit-grp-day-${gIdx}" value="${d}" ${days.includes(d) ? 'checked' : ''} 
                                                               onchange="window._updateGroupDays(${gIdx})" style="width:12px; height:12px; margin:0; accent-color:var(--accent);">
                                                        ${dayLabels[d]}
                                                    </label>
                                                `).join('')}
                                                <label style="display:flex; align-items:center; gap:2px; cursor:pointer; font-size:0.65rem; color:${isAllDays ? 'var(--accent)' : '#64748b'}; font-weight:${isAllDays ? 'bold' : 'normal'}; padding:2px 6px; border-radius:4px; background:${isAllDays ? 'rgba(6,182,212,0.15)' : 'transparent'}; border:1px solid ${isAllDays ? 'var(--accent)' : 'rgba(255,255,255,0.05)'}; margin-left:4px;">
                                                    <input type="checkbox" class="edit-grp-all-${gIdx}" ${isAllDays ? 'checked' : ''} 
                                                           onchange="window._toggleGroupAllDays(${gIdx})" style="width:12px; height:12px; margin:0; accent-color:var(--accent);">
                                                    TODOS
                                                </label>
                                            </div>
                                            <div style="display:flex; flex-direction:column; gap:4px; padding-left:8px; border-left:2px solid rgba(6,182,212,0.2);">
                                                ${(group.hours || []).map((hr, hIdx) => `
                                                    <div style="display:flex; align-items:center; gap:6px; background:rgba(255,255,255,0.03); padding:4px 8px; border-radius:4px;">
                                                        <span style="font-size:0.55rem; color:#888; min-width:60px;">RANGO ${hIdx+1}</span>
                                                        <input type="time" id="edit-hr-start-${gIdx}-${hIdx}" value="${hr.start}" style="padding:2px 4px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.75rem; width:90px; font-family:'JetBrains Mono', monospace;">
                                                        <span style="color:var(--text-dim); font-size:0.75rem;">➔</span>
                                                        <input type="time" id="edit-hr-end-${gIdx}-${hIdx}" value="${hr.end}" style="padding:2px 4px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.75rem; width:90px; font-family:'JetBrains Mono', monospace;">
                                                        <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.8rem; padding:0 4px;" 
                                                                title="Eliminar Horario" onclick="removeGroupHour('${selectedMapId}', ${gIdx}, ${hIdx})">✕</button>
                                                    </div>
                                                `).join('')}
                                                <div style="display:flex; align-items:center; gap:6px; margin-top:2px;">
                                                    <input type="time" id="edit-new-hr-start-${gIdx}" style="padding:2px 4px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.7rem; width:90px; font-family:'JetBrains Mono', monospace;">
                                                    <span style="color:var(--text-dim); font-size:0.7rem;">➔</span>
                                                    <input type="time" id="edit-new-hr-end-${gIdx}" style="padding:2px 4px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.7rem; width:90px; font-family:'JetBrains Mono', monospace;">
                                                    <button style="background:none; border:none; color:#00ff88; cursor:pointer; font-size:0.7rem; padding:2px 6px; border:1px solid rgba(0,255,136,0.3); border-radius:4px;" 
                                                            title="Añadir Horario a Grupo" onclick="addHourToGroup('${selectedMapId}', ${gIdx})">+ HORARIO</button>
                                                </div>
                                            </div>
                                        </div>
                                        `;
                                    } else {
                                        return `
                                        <div style="display:flex; flex-direction:column; gap:6px; background:rgba(255,255,255,0.02); padding:8px 12px; border-radius:6px; border:1px solid rgba(255,255,255,0.03);">
                                            <div style="display:flex; justify-content:space-between; align-items:flex-start;">
                                                <div style="display:flex; align-items:center; gap:4px; flex-wrap:wrap;">
                                                    ${isAllDays 
                                                        ? '<span style="font-size:0.6rem; color:var(--accent); font-weight:bold; letter-spacing:0.5px; padding:2px 6px; border-radius:4px; background:rgba(6,182,212,0.1); border:1px solid rgba(6,182,212,0.2);">TODOS LOS DÍAS</span>'
                                                        : dayLabels.map((label, i) => `
                                                            <span style="font-size:0.6rem; color:${days.includes(i) ? 'var(--accent)' : '#334155'}; font-weight:${days.includes(i) ? 'bold' : 'normal'}; padding:2px 5px; border-radius:3px; background:${days.includes(i) ? 'rgba(6,182,212,0.1)' : 'transparent'}; border:1px solid ${days.includes(i) ? 'rgba(6,182,212,0.2)' : 'rgba(255,255,255,0.03)'};">${label}</span>
                                                        `).join('')
                                                    }
                                                </div>
                                                <div style="display:flex; gap:4px;">
                                                    <button style="background:none; border:none; color:#ffb000; cursor:pointer; font-weight:bold; font-size:0.85rem; padding:2px 6px;" 
                                                            title="Editar Grupo" onclick="editScheduleGroup('${selectedMapId}', ${gIdx})">✏️</button>
                                                    <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-weight:bold; font-size:0.85rem; padding:2px 6px;" 
                                                            title="Eliminar Grupo" onclick="removeScheduleGroup('${selectedMapId}', ${gIdx})">✕</button>
                                                </div>
                                            </div>
                                            <div style="display:flex; flex-direction:column; gap:3px; padding-left:8px; border-left:2px solid rgba(255,255,255,0.06);">
                                                ${(group.hours || []).map(hr => `
                                                    <span style="font-size:0.75rem; font-family:'JetBrains Mono', monospace; color:var(--primary); font-weight:bold;">${hr.start} ➔ ${hr.end}</span>
                                                `).join('')}
                                            </div>
                                        </div>
                                        `;
                                    }
                                }).join('')}
                            </div>
                            <div style="display:flex; flex-direction:column; gap:8px; padding-top:0.8rem; border-top:1px solid rgba(255,255,255,0.05);">
                                <span style="color:var(--accent); font-size:0.6rem; font-weight:bold; letter-spacing:1px;">NUEVO GRUPO DE DÍAS</span>
                                <div style="display:flex; align-items:center; gap:4px; flex-wrap:wrap;">
                                    ${dayLabels.map((label, i) => `
                                        <label style="display:flex; align-items:center; gap:2px; cursor:pointer; font-size:0.65rem; color:#64748b; padding:2px 4px; border-radius:4px; border:1px solid rgba(255,255,255,0.05);">
                                            <input type="checkbox" id="new-day-${i}" value="${i}" style="width:12px; height:12px; margin:0; accent-color:var(--accent);">
                                            ${label}
                                        </label>
                                    `).join('')}
                                    <label style="display:flex; align-items:center; gap:2px; cursor:pointer; font-size:0.65rem; color:#64748b; padding:2px 6px; border-radius:4px; border:1px solid rgba(255,255,255,0.05); margin-left:4px;">
                                        <input type="checkbox" id="new-day-all" style="width:12px; height:12px; margin:0; accent-color:var(--accent);" onchange="window._toggleNewAllDays()">
                                        TODOS
                                    </label>
                                </div>
                                <div style="display:flex; gap:10px; align-items:flex-end;">
                                    <div class="field" style="margin:0; flex:1;"><label style="font-size:0.6rem; color:#888;">INICIO</label><input type="time" id="new-range-start" style="padding:6px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.8rem; width:100%;"></div>
                                    <div class="field" style="margin:0; flex:1;"><label style="font-size:0.6rem; color:#888;">FIN</label><input type="time" id="new-range-end" style="padding:6px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.8rem; width:100%;"></div>
                                    <button class="btn btn-primary" style="padding:6px 12px; font-size:0.7rem; height:32px; margin:0;" onclick="addScheduleGroup('${selectedMapId}')">+ AÑADIR GRUPO</button>
                                </div>
                            </div>
                        </div>
                        ` : ''}
                    </div>
                    `;
                    })()}
                </div>
            </div>
            
            <div class="col">
                <div class="card" style="width:100%; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px;">
                    <label style="color:var(--accent); font-size: 0.75rem; font-weight:bold; letter-spacing:1px; width:100%; text-align:left;">🛰️ RADAR TÁCTICO DEL MAPA</label>
                    <div id="map-radar-container" style="position:relative; width:100%; aspect-ratio: 1; background:#000; border:2px solid var(--accent); border-radius:10px; overflow:hidden; cursor:crosshair; box-shadow: 0 0 20px rgba(6, 182, 212, 0.15);">
                        <canvas id="map-radar-canvas" style="width: 100%; height: 100%; display: block;"></canvas>
                    </div>
                    <div style="display:flex; gap:10px; width:100%;">
                        <div class="field" style="flex:1;"><label>Radar X</label><input type="number" id="map-radar-x" value="0" readonly></div>
                        <div class="field" style="flex:1;"><label>Radar Y</label><input type="number" id="map-radar-y" value="0" readonly></div>
                    </div>
                    <div id="map-radar-mode-hint" style="font-size:0.65rem; color:#888; text-align:center; width:100%;">
                        🖱️ Arrastrá puertas/spawns para moverlos. Hacé clic para fijar coordenadas. Agregá con "+ AGREGAR", duplicá lo seleccionado con <strong style="color:var(--accent);">CTRL+D</strong> y eliminá lo seleccionado con la tecla <strong style="color:#ff4444;">SUPR</strong>.
                    </div>
                </div>
            </div>

            <div class="col">
                ${(() => {
                    if (!m.music) m.music = { enabled: false, path: '', volumePercent: 60 };
                    const music = m.music;
                    const musicFileName = music.path ? music.path.split('/').pop() : '';
                    const previewUrl = music.path ? (SERVER_URLS[activeEnv] + '/' + music.path.replace(/^res:\/\//, '')) : '';
                    return `
                <div class="card" style="width:100%; margin-bottom:1rem; border-color: ${music.enabled && music.path ? 'rgba(0,255,136,0.25)' : 'rgba(255,255,255,0.1)'};">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.8rem;">
                        <label style="color:var(--accent); font-size: 0.8rem; font-weight:bold; display:flex; align-items:center; gap:8px; margin:0;">
                            🎵 MÚSICA DE LA ZONA (LOOP)
                            <span style="font-size:0.6rem; color:#64748b; font-weight:normal; padding:2px 8px; border:1px solid rgba(255,255,255,0.15); border-radius:4px;">GLOBAL</span>
                        </label>
                        <div style="display:flex; align-items:center; gap:8px;">
                            <label style="display:flex; align-items:center; gap:6px; cursor:pointer; font-size:0.75rem; color:var(--text-dim); margin:0;">
                                <input type="checkbox" ${music.enabled ? 'checked' : ''} onchange="toggleMapMusic('${selectedMapId}', this.checked)" style="width:16px; height:16px; cursor:pointer; accent-color:var(--accent);">
                                Activa
                            </label>
                            ${music.path ? `<button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.95rem; padding:0 2px;" title="Quitar música de esta zona" onclick="removeMapMusic('${selectedMapId}')">✕</button>` : ''}
                        </div>
                    </div>
                    <div style="display:flex; gap:10px; align-items:center; margin-bottom:0.8rem;">
                        <button class="btn btn-primary" style="padding:6px 14px; font-size:0.72rem; white-space:nowrap;" onclick="pickMapMusic('${selectedMapId}')">📁 SELECCIONAR ARCHIVO</button>
                        <span style="font-size:0.72rem; color:${music.path ? 'var(--success)' : '#64748b'}; font-family:'JetBrains Mono', monospace; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;" title="${music.path || ''}">
                            ${music.path ? '✓ ' + musicFileName : 'Ningún archivo seleccionado (el archivo debe estar dentro de descon/assets)'}
                        </span>
                    </div>
                    ${music.path ? `
                    <div style="margin-bottom:0.8rem;">
                        <label style="font-size:0.65rem; color:#888; display:flex; align-items:center; gap:6px; margin-bottom:6px;">VOLUMEN: <input type="number" id="map-music-vol-input-${selectedMapId}" min="0" max="100" value="${music.volumePercent}" style="width:55px; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; setMapMusicVolume('${selectedMapId}', v); let s=document.getElementById('map-music-vol-slider-${selectedMapId}'); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; setMapMusicVolume('${selectedMapId}', v); let s=document.getElementById('map-music-vol-slider-${selectedMapId}'); if(s) s.value=v;"> % <span id="map-music-vol-label" style="display:none;">${music.volumePercent}%</span></label>
                        <input type="range" id="map-music-vol-slider-${selectedMapId}" min="0" max="100" value="${music.volumePercent}" oninput="setMapMusicVolume('${selectedMapId}', this.value); let inp=document.getElementById('map-music-vol-input-${selectedMapId}'); if(inp) inp.value=this.value;" style="width:100%; accent-color:var(--accent); cursor:pointer;">
                        <div style="display:flex; justify-content:space-between; font-size:0.55rem; color:#555; font-family:'JetBrains Mono', monospace;"><span>SILENCIO</span><span>SUAVE</span><span>MEDIO</span><span>FULL</span></div>
                    </div>
                    <audio controls loop preload="none" style="width:100%; height:32px;" src="${previewUrl}"></audio>
                    <div style="font-size:0.6rem; color:#64748b; margin-top:6px; line-height:1.4;">La música se reproduce en <strong style="color:var(--accent);">bucle infinito</strong> mientras los jugadores estén en este sector. Cambiá de zona y la música cambia automáticamente.</div>
                    ` : `
                    <div style="font-size:0.62rem; color:#64748b; line-height:1.5;">Los archivos de audio van en <strong style="color:var(--accent); font-family:'JetBrains Mono';">descon/assets/Musica/</strong> (WAV, OGG o MP3). Seleccioná el archivo desde el botón y configurá su volumen.</div>
                    `}
                </div>
                    `;
                })()}
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;"><label style="color:var(--accent); font-size: 0.8rem; font-weight:bold;">☢️ MECÁNICAS DE AMBIENTE (HAZARDS)</label><button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem;" onclick="openMapAddModal('ambience')">+ AGREGAR EFECTO</button></div>
                        <div id="ambience-list" style="margin-bottom: 2rem;">
                    ${m.ambience.map((a, idx) => {
                        const lib = AMBIENCE_LIB[a.type || 'radiation'] || { label: a.type || 'Desconocido', icon: '🌍', fields: [] };
                        const isOpen = isMapCardExpanded(`amb-${idx}`);
                        return `
                        <div class="card" id="card-map-amb-${idx}" style="margin-bottom:0.6rem; padding:0; position:relative; border-color: rgba(255,255,255,0.1); overflow:visible; cursor:pointer;">
                            <div style="display:flex; align-items:center; gap:10px; padding:0.6rem 0.9rem; border-bottom: ${isOpen ? '1px solid rgba(255,255,255,0.06)' : 'none'};"
                                 onclick="selectMapItem('ambience', ${idx}); toggleMapCard('amb-${idx}')">
                                <span style="font-size:1rem;">${lib.icon || '🌍'}</span>
                                <span style="flex:1; color:var(--accent); font-weight:bold; font-size:0.85rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${lib.label || a.type}</span>
                                <span style="font-size:0.6rem; color:#64748b; padding:2px 6px; border:1px solid rgba(255,255,255,0.15); border-radius:4px; white-space:nowrap;">GLOBAL</span>
                                <span style="color:var(--accent); font-size:0.7rem;">${isOpen ? '▼' : '▶'}</span>
                                <button style="background:none; border:none; color:var(--accent); cursor:pointer; font-size:0.9rem; padding:0 2px;" title="Duplicar (Ctrl+D)" onclick="event.stopPropagation(); duplicateMapItem('ambience', ${idx})">⧉</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.9rem; padding:0 2px;" title="Eliminar (Supr)" onclick="event.stopPropagation(); requestMapDelete('ambience', ${idx})">✕</button>
                            </div>
                            ${isOpen ? `
                            <div style="padding:1rem;">
                                <div class="field full">
                                    <label style="font-size: 0.6rem; color: #888;">TIPO DE EFECTO</label>
                                    <select style="background:#0f172a; border:none; color:var(--accent); font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;"
                                            onchange="updateAmbienceType('${selectedMapId}', ${idx}, this.value)">
                                        ${Object.keys(AMBIENCE_LIB).map(type => `<option value="${type}" ${a.type === type ? 'selected' : ''}>${AMBIENCE_LIB[type].icon} ${AMBIENCE_LIB[type].label}</option>`).join('')}
                                    </select>
                                </div>
                                <div class="form-grid" style="margin-top:1rem;">
                                    ${lib.fields.map(f => {
                                        const isBlind = a.type === 'blindness_hazard';
                                        const isInter = a.type === 'interferencia_hazard';
                                        const labels = {
                                            damage: "Daño (HP)", intervalMs: "Intervalo (ms)",
                                            spawnInterval: "Cadencia (ms)",
                                            duration: isBlind ? "Duración Ceguera (ms)" : "Duración Efecto (ms)",
                                            radius: isBlind ? "Radio Visión (px)" : "Tamaño Vórtice (px)",
                                            pullForce: "Fuerza Atracción (px/s)",
                                            damageInterval: "Intervalo Daño (ms)",
                                            shakeIntensity: "Potencia Temblor Cámara",
                                            staticIntensity: "Fuerza Rayas Pantalla",
                                            slowPercentage: "Reducción por % (0-100)",
                                            slowFixed: "Reducción Fija (PX/S)",
                                            damageMult: "Multiplicador de Daño (x)",
                                            speedMult: "Multiplicador de Velocidad (x)",
                                            healthMult: "Multiplicador de Vida (x)",
                                            respawnSpeedBonus: "Bono de Respawn (ms)",
                                            multiplier: "Multiplicador General (x)",
                                            penaltyPercentage: "Penalización Curación (%)",
                                            penaltyFixed: "Penalización Curación Fija"
                                        };
                                        let val = a[f];
                                        if (val === undefined) {
                                            // Inicializar si no existe
                                            if (f === 'spawnInterval') val = 10000;
                                            else if (f === 'duration') val = 5000;
                                            else if (f === 'radius') val = 250;
                                            else if (f === 'penaltyPercentage') val = 50;
                                            else if (f === 'penaltyFixed') val = 0;
                                            else val = 0;
                                            config.mapsConfig[selectedMapId].ambience[idx][f] = val;
                                        }
                                        return `
                                        <div class="field">
                                            <label>${labels[f] || f}</label>
                                            <input type="number" step="0.1" value="${val}"
                                                   oninput="config.mapsConfig['${selectedMapId}'].ambience[${idx}].${f} = parseFloat(this.value) || 0">
                                        </div>`
                                    }).join('')}
                                </div>
                            </div>` : ''}
                        </div>`;
                    }).join('')}
                </div>
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;"><label style="color:var(--success); font-size: 0.8rem; font-weight:bold;">👾 ECOSISTEMA DE ENEMIGOS</label><button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background:var(--success);" onclick="openMapAddModal('enemy')">+ AÑADIR ESPECIE</button></div>
                <div id="spawns-list">
                    ${(m.spawns || []).map((s, idx) => {
                        const sEnemy = s.type ? config.enemyModels[s.type] : null;
                        const sName = sEnemy ? `[ID ${s.type}] ${sEnemy.name}` : (s.type ? `ID ${s.type}` : 'Sin enemigo asignado');
                        const isRandomMode = s.spawnMode === 'random' || s.spawnMode === 'random_global' || s.spawnMode === 'random_zone';
                        const sMode = isRandomMode ? (s.radius > 0 ? '⭕ Área' : '🌍 Global') : '📍 Fijo';
                        const isOpen = isMapCardExpanded(`spawn-${idx}`);
                        return `
                        <div class="card" id="card-map-spawn-${idx}" style="margin-bottom:0.6rem; padding:0; position:relative; border-color: rgba(16, 185, 129, 0.2); overflow:visible; cursor:pointer;">
                            <div style="display:flex; align-items:center; gap:10px; padding:0.6rem 0.9rem; border-bottom: ${isOpen ? '1px solid rgba(255,255,255,0.06)' : 'none'};"
                                 onclick="selectMapItem('spawn', ${idx}); toggleMapCard('spawn-${idx}')">
                                <span style="font-size:1rem;">👾</span>
                                <span id="spawn-name-${idx}" style="flex:1; color:var(--success); font-weight:bold; font-size:0.8rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${sName}</span>
                                <span style="font-size:0.6rem; color:#64748b; padding:2px 6px; border:1px solid rgba(255,255,255,0.15); border-radius:4px; white-space:nowrap;">${sMode} ×${s.count}</span>
                                <span style="color:var(--success); font-size:0.7rem;">${isOpen ? '▼' : '▶'}</span>
                                <button style="background:none; border:none; color:var(--success); cursor:pointer; font-size:0.9rem; padding:0 2px;" title="Duplicar (Ctrl+D)" onclick="event.stopPropagation(); duplicateMapItem('spawn', ${idx})">⧉</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.9rem; padding:0 2px;" title="Eliminar (Supr)" onclick="event.stopPropagation(); requestMapDelete('spawn', ${idx})">✕</button>
                            </div>
                            ${isOpen ? `
                            <div style="padding:1rem;">
                                <div class="form-grid" style="overflow: visible;">
                                    <div class="field" style="grid-column: span 2; overflow: visible;">
                                        <label>Tipo de Enemigo</label>
                                        ${renderSearchableEnemySelect(s.type, (newId) => {
                                            config.mapsConfig[selectedMapId].spawns[idx].type = newId;
                                            const model = config.enemyModels[newId];
                                            const el = document.getElementById(`spawn-name-${idx}`);
                                            if (el) el.textContent = model ? `[ID ${newId}] ${model.name}` : `ID ${newId}`;
                                        }, 'var(--success)', `map-spawn-${idx}`)}
                                    </div>
                                    <div class="field">
                                        <label>Cant. Máx (slots)</label>
                                        <input type="number" value="${s.count}" oninput="config.mapsConfig['${selectedMapId}'].spawns[${idx}].count = parseInt(this.value) || 0">
                                    </div>
                                    <div class="field">
                                        <label>Intervalo Respawn (ms)</label>
                                        <input type="number" value="${s.intervalMs}" oninput="config.mapsConfig['${selectedMapId}'].spawns[${idx}].intervalMs = parseInt(this.value) || 0">
                                    </div>
                                    <div class="field" style="grid-column: span 2;">
                                        <label>Modo de Aparición (Respawn)</label>
                                        <select style="background:#0f172a; border:none; color:var(--success); font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;"
                                                onchange="const val = this.value;
                                                          const s = config.mapsConfig['${selectedMapId}'].spawns[${idx}];
                                                          if (val === 'random_global') { s.spawnMode = 'random'; s.radius = 0; }
                                                          else if (val === 'random_zone') { s.spawnMode = 'random'; if (!s.radius || s.radius === 0) s.radius = 500; }
                                                          else if (val === 'fixed') { s.spawnMode = 'fixed'; }
                                                          renderMapDetail();">
                                            <option value="random_global" ${(s.spawnMode === 'random_global') || (s.spawnMode === 'random' && (!s.radius || s.radius === 0)) ? 'selected' : ''}>🌍 Aleatorio (En todo el mapa)</option>
                                            <option value="random_zone" ${(s.spawnMode === 'random_zone') || (s.spawnMode === 'random' && s.radius > 0) ? 'selected' : ''}>⭕ Aleatorio en un área (Centro + Radio)</option>
                                            <option value="fixed" ${s.spawnMode === 'fixed' ? 'selected' : ''}>📍 Fijo (Coordenadas Exactas)</option>
                                        </select>
                                    </div>
                                    ${s.spawnMode === 'fixed' || s.spawnMode === 'random_zone' || (s.spawnMode === 'random' && s.radius > 0) ? `
                                    <div class="field">
                                        <label>Coordenada Centro X</label>
                                        <input type="number" value="${s.x !== undefined ? s.x : 1000}" oninput="config.mapsConfig['${selectedMapId}'].spawns[${idx}].x = parseInt(this.value) || 0">
                                    </div>
                                    <div class="field">
                                        <label>Coordenada Centro Y</label>
                                        <input type="number" value="${s.y !== undefined ? s.y : 1000}" oninput="config.mapsConfig['${selectedMapId}'].spawns[${idx}].y = parseInt(this.value) || 0">
                                    </div>
                                    ` : ''}
                                    ${(s.spawnMode === 'random' || s.spawnMode === 'random_zone') && s.radius > 0 ? `
                                    <div class="field" style="grid-column: span 2;">
                                        <label>Radio de Área de Spawn (px)</label>
                                        <input type="number" value="${s.radius}" oninput="config.mapsConfig['${selectedMapId}'].spawns[${idx}].radius = parseInt(this.value) || 0">
                                    </div>
                                    ` : ''}
                                </div>
                            </div>` : ''}
                        </div>
                    `; }).join('')}
                </div>

                <!-- ========== CONFIGURADOR DE PUERTAS / WARPS ========== -->
                <div style="margin-top: 2rem; padding-top: 1.5rem; border-top: 1px solid rgba(0,210,255,0.1);">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
                        <label style="color:#00d2ff; font-size: 0.8rem; font-weight:bold;">🚪 CONFIGURADOR DE PUERTAS / WARPS</label>
                        <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background:var(--accent); border-color:var(--accent);" onclick="openMapAddModal('door')">+ AGREGAR PUERTA</button>
                    </div>
                    <div style="font-size:0.65rem; color:#64748b; margin-bottom:1rem;">
                        Paredes, baúles, torres y demás objetos se colocan y escalan en el editor 3D de Godot (MapEditor3D) e importan aquí como referencia visual en el radar.
                    </div>
                    <div id="map-objects-list">
                    ${(m.objects || []).map((obj, idx) => obj.type !== 'door' ? '' : (() => {
                        const oName = obj.label || 'Puerta sin nombre';
                        const oTargetZone = obj.targetZoneId ? config.mapsConfig[obj.targetZoneId]?.name || obj.targetZoneId : null;
                        const isOpen = isMapCardExpanded(`door-${idx}`);
                        return `
                        <div class="card" id="card-map-obj-${idx}" style="margin-bottom:0.6rem; padding:0; position:relative;
                            border-left: 3px solid #00d2ff40; background: rgba(0,0,0,0.2); cursor:pointer;">
                            <div style="display:flex; align-items:center; gap:10px; padding:0.6rem 0.9rem; border-bottom: ${isOpen ? '1px solid rgba(255,255,255,0.06)' : 'none'};"
                                 onclick="selectMapItem('door', ${idx}); toggleMapCard('door-${idx}')">
                                <span style="font-size:1rem;">🚪</span>
                                <span style="flex:1; color:#00d2ff; font-weight:bold; font-size:0.8rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${oName}</span>
                                <span style="font-size:0.6rem; color:#64748b; padding:2px 6px; border:1px solid rgba(255,255,255,0.15); border-radius:4px; white-space:nowrap;">X ${obj.x || 0}, Y ${obj.y || 0}</span>
                                ${oTargetZone ? `<span style="font-size:0.6rem; color:#00d2ff; padding:2px 6px; border:1px solid rgba(0,210,255,0.3); border-radius:4px; white-space:nowrap;">→ ${oTargetZone}</span>` : ''}
                                <span style="color:#00d2ff; font-size:0.7rem;">${isOpen ? '▼' : '▶'}</span>
                                <button style="background:none; border:none; color:#00d2ff; cursor:pointer; font-size:0.9rem; padding:0 2px;" title="Duplicar (Ctrl+D)" onclick="event.stopPropagation(); duplicateMapItem('door', ${idx})">⧉</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.9rem; padding:0 2px;" title="Eliminar (Supr)" onclick="event.stopPropagation(); requestMapDelete('door', ${idx})">✕</button>
                            </div>
                            ${isOpen ? `
                            <div style="padding:1rem;">
                            <div style="font-size:0.65rem; color:#00d2ff; font-weight:bold; letter-spacing:1px; margin-bottom:0.7rem;">🚪 PUERTA/WARP</div>
                            <div class="form-grid">
                                <div class="field" style="grid-column:span 2;">
                                    <label>Etiqueta</label>
                                    <input type="text" value="${obj.label || ''}" placeholder="Nombre de la puerta"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].label = this.value">
                                </div>
                                <div class="field">
                                    <label>Pos X</label>
                                    <input type="number" id="map-obj-x-${idx}" value="${obj.x || 0}"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].x = parseInt(this.value) || 0">
                                </div>
                                <div class="field">
                                    <label>Pos Y</label>
                                    <input type="number" id="map-obj-y-${idx}" value="${obj.y || 0}"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].y = parseInt(this.value) || 0">
                                </div>
                                <div class="field" style="grid-column:span 2;">
                                    <label>Asset (ruta .glb)</label>
                                    <div style="display:flex; gap:6px; align-items:center;">
                                        <input type="text" value="${obj.assetPath || 'res://assets/Puertas/3D/Puerta2/Puerta2.glb'}" placeholder="Ruta al archivo .glb del asset"
                                               oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].assetPath = this.value" style="flex:1; margin:0;">
                                        <button class="btn btn-primary" style="padding:5px 10px; font-size:0.65rem; flex-shrink:0; background:var(--accent); border-color:var(--accent);" onclick="triggerMapObjAssetPick('${selectedMapId}', ${idx})">📁</button>
                                    </div>
                                </div>
                                <div class="field" style="grid-column:span 2; border-top:1px solid rgba(0,210,255,0.2); padding-top:0.7rem; margin-top:0.3rem;">
                                    <label style="color:#00d2ff; font-size:0.6rem; font-weight:bold;">🌀 CONFIGURACIÓN DE WARP</label>
                                </div>
                                <div class="field" style="grid-column:span 2;">
                                    <label>Zona Destino</label>
                                    <select style="background:#0f172a; border:none; color:#00d2ff; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;"
                                            onchange="config.mapsConfig['${selectedMapId}'].objects[${idx}].targetZoneId = this.value">
                                        <option value="">-- Seleccionar Zona --</option>
                                        ${Object.keys(config.mapsConfig)
                                            .filter(id => id !== selectedMapId && (config.mapsConfig[id].visible !== false || (obj.targetZoneId || '') == id))
                                            .map(id => `<option value="${id}" ${(obj.targetZoneId || '') == id ? 'selected' : ''}>${config.mapsConfig[id].name} (ID: ${id})</option>`)
                                            .join('')}
                                    </select>
                                </div>
                                <div class="field">
                                    <label>Warp X destino</label>
                                    <input type="number" value="${obj.targetX || 5000}" placeholder="5000"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].targetX = parseInt(this.value) || 0">
                                </div>
                                <div class="field">
                                    <label>Warp Y destino</label>
                                    <input type="number" value="${obj.targetY || 5000}" placeholder="5000"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].targetY = parseInt(this.value) || 0">
                                </div>
                                <div class="field" style="grid-column:span 2;">
                                    <label>Y Offset (altura sobre el suelo)</label>
                                    <input type="number" step="0.1" value="${obj.yOffset !== undefined ? obj.yOffset : 2.5}" placeholder="2.5"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].yOffset = parseFloat(this.value) || 0">
                                </div>
                            </div>
                            </div>` : ''}
                        </div>`;
                    })()
                    ).join('')}
                    </div>
                </div>

                <!-- ========== CONFIGURADOR DE MERCADOS / SUBASTAS ========== -->
                <div style="margin-top: 2rem; padding-top: 1.5rem; border-top: 1px solid rgba(255,215,0,0.25);">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
                        <label style="color:#ffd700; font-size: 0.8rem; font-weight:bold;">🛒 TERMINALES DE MERCADO / SUBASTAS</label>
                        <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background:#ffd700; border-color:#ffd700; color:#000; font-weight:bold;" onclick="openMapAddModal('market')">+ AGREGAR MERCADO</button>
                    </div>
                    <div style="font-size:0.65rem; color:#64748b; margin-bottom:1rem;">
                        Aquí podés gestionar las terminales donde los jugadores acceden a la Casa de Subastas Galáctica en esta zona.
                    </div>
                    <div id="map-markets-list">
                    ${(m.objects || []).map((obj, idx) => obj.type !== 'market' ? '' : (() => {
                        const oName = obj.label || 'Mercado sin nombre';
                        const isOpen = isMapCardExpanded(`market-${idx}`);
                        return `
                        <div class="card" id="card-map-obj-${idx}" style="margin-bottom:0.6rem; padding:0; position:relative;
                            border-left: 3px solid #ffd70080; background: rgba(0,0,0,0.2); cursor:pointer;">
                            <div style="display:flex; align-items:center; gap:10px; padding:0.6rem 0.9rem; border-bottom: ${isOpen ? '1px solid rgba(255,255,255,0.06)' : 'none'};"
                                 onclick="selectMapItem('market', ${idx}); toggleMapCard('market-${idx}')">
                                <span style="font-size:1rem;">🛒</span>
                                <span style="flex:1; color:#ffd700; font-weight:bold; font-size:0.8rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${oName}</span>
                                <span style="font-size:0.6rem; color:#64748b; padding:2px 6px; border:1px solid rgba(255,255,255,0.15); border-radius:4px; white-space:nowrap;">X ${obj.x || 0}, Y ${obj.y || 0}</span>
                                <span style="color:#ffd700; font-size:0.7rem;">${isOpen ? '▼' : '▶'}</span>
                                <button style="background:none; border:none; color:#ffd700; cursor:pointer; font-size:0.9rem; padding:0 2px;" title="Duplicar (Ctrl+D)" onclick="event.stopPropagation(); duplicateMapItem('market', ${idx})">⧉</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.9rem; padding:0 2px;" title="Eliminar (Supr)" onclick="event.stopPropagation(); requestMapDelete('market', ${idx})">✕</button>
                            </div>
                            ${isOpen ? `
                            <div style="padding:1rem;">
                            <div style="font-size:0.65rem; color:#ffd700; font-weight:bold; letter-spacing:1px; margin-bottom:0.7rem;">🛒 TERMINAL DE MERCADO</div>
                            <div class="form-grid">
                                <div class="field" style="grid-column:span 2;">
                                    <label>Etiqueta</label>
                                    <input type="text" value="${obj.label || ''}" placeholder="Nombre de la terminal"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].label = this.value">
                                </div>
                                <div class="field">
                                    <label>Pos X</label>
                                    <input type="number" id="map-obj-x-${idx}" value="${obj.x || 0}"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].x = parseInt(this.value) || 0">
                                </div>
                                <div class="field">
                                    <label>Pos Y</label>
                                    <input type="number" id="map-obj-y-${idx}" value="${obj.y || 0}"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].y = parseInt(this.value) || 0">
                                </div>
                                <div class="field" style="grid-column:span 2;">
                                    <label>Asset (ruta .glb)</label>
                                    <div style="display:flex; gap:6px; align-items:center;">
                                        <input type="text" value="${obj.assetPath || 'res://assets/Mapas/Mapa1/Estructuras/3D/Decorativo3/Decorativo3.glb'}" placeholder="Ruta al archivo .glb del asset"
                                               oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].assetPath = this.value" style="flex:1; margin:0;">
                                        <button class="btn btn-primary" style="padding:5px 10px; font-size:0.65rem; flex-shrink:0; background:#ffd700; border-color:#ffd700; color:#000;" onclick="triggerMapObjAssetPick('${selectedMapId}', ${idx})">📁</button>
                                    </div>
                                </div>
                                <div class="field" style="grid-column:span 2;">
                                    <label>Y Offset (altura sobre el suelo)</label>
                                    <input type="number" step="0.1" value="${obj.yOffset !== undefined ? obj.yOffset : 0.0}" placeholder="0.0"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].yOffset = parseFloat(this.value) || 0">
                                </div>
                            </div>
                            </div>` : ''}
                        </div>`;
                    })()
                    ).join('')}
                    </div>
                </div>
            </div>
        </div>
    `;
    setTimeout(initMapRadar, 100);
}

function renderMaps() {
    const grid = document.getElementById('maps-grid'); grid.innerHTML = '';
    const f = getFilter();
    for(let id in config.mapsConfig) {
        const m = config.mapsConfig[id];
        // Mapas 10 y 11 ahora visibles en cartografía
        if (f && !m.name.toLowerCase().includes(f)) continue;
        
        const isVisible = m.visible !== false;
        const eyeColor = isVisible ? 'var(--primary)' : '#64748b';
        const eyeTitle = isVisible ? 'Mapa Activo (Visible en Godot)' : 'Mapa Inactivo (Oculto en Godot)';
        const cardOpacity = isVisible ? '1' : '0.5';

        const card = document.createElement('div'); card.className = 'card';
        card.style.cursor = 'pointer'; card.onclick = () => selectMap(id);
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
                <div class="card-tag" style="margin:0;">#ID ${id}</div>
                <button onclick="event.stopPropagation(); toggleMapVisibility('${id}')" 
                        title="${eyeTitle}" 
                        style="background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); color:${eyeColor}; cursor:pointer; font-size:1rem; padding:4px 8px; border-radius:6px; transition:all 0.2s; display:flex; align-items:center; gap:4px;">
                    ${isVisible ? '👁️' : '🕶️'}
                </button>
            </div>
            <div style="width:100%; height:4px; background:${m.color}; margin-bottom:1rem; border-radius:2px; opacity:${cardOpacity};"></div>
            <h3 style="opacity:${cardOpacity};">${m.name}</h3>
            <p style="font-size:0.8rem; opacity:${isVisible ? '0.6' : '0.35'};">${m.desc || 'Sin descripción'}</p>
            <div style="margin-top:1rem; color:var(--accent); font-weight:bold; font-size:0.7rem; opacity:${cardOpacity};">Configurar Zona</div>
        `;
        grid.appendChild(card);
    }
}

window.toggleMapVisibility = function(id) {
    if (!config || !config.mapsConfig || !config.mapsConfig[id]) return;
    const m = config.mapsConfig[id];
    m.visible = (m.visible === false) ? true : false;
    saveConfig();
    renderMaps();
    updateSidebar();
};
