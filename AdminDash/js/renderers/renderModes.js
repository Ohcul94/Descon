// AdminDash/js/renderers/renderModes.js
function renderModes() {
    if (!config.gameModes) {
        config.gameModes = {
            hunting: { enabled: true, targets: [], rewardMult: 1.2 },
            extraction: { enabled: true, zones: [], difficulty: 1 },
            arenas: { enabled: true, maps: [], minPlayers: 2 }
        };
    }
    if (!config.gameModes.altar_defense) {
        config.gameModes.altar_defense = {
            enabled: true,
            maxPlayers: 4,
            altarHp: 10000,
            altarShield: 5000,
            maps: [],
            altarPos: { x: 5000, y: 5000 },
            spawnPoints: [],
            spawners: [],
            waves: [],
            width: 10000,
            height: 10000
        };
    }

    const content = document.getElementById('modes-content');
    if (!content) return;

    if (currentModeTab === 'hunting') {
        content.innerHTML = `
            <div class="card" style="grid-column: span 2;">
                <h3 style="color:var(--accent); margin-bottom: 0.5rem;">🔫 MODO CACERÍA</h3>
                <p style="opacity:0.7; margin-bottom:1.5rem;">Configuración de eventos de eliminación de objetivos prioritarios.</p>
                <div class="form-grid">
                    <div class="field">
                        <label>Estado del Modo</label>
                        <select onchange="config.gameModes.hunting.enabled = this.value === 'true'">
                            <option value="true" ${config.gameModes.hunting.enabled ? 'selected' : ''}>Activo</option>
                            <option value="false" ${!config.gameModes.hunting.enabled ? 'selected' : ''}>Inactivo</option>
                        </select>
                    </div>
                    <div class="field">
                        <label>Multiplicador de Recompensa</label>
                        <input type="number" step="0.1" value="${config.gameModes.hunting.rewardMult}" 
                               onchange="config.gameModes.hunting.rewardMult = parseFloat(this.value)">
                    </div>
                </div>
            </div>
            <div class="card">
                <h4 style="color:var(--primary); margin-bottom: 1rem;">🎯 OBJETIVOS PRIORITARIOS</h4>
                <p style="font-size:0.8rem; opacity:0.6;">Lista de IDs de enemigos que activan el bono de cacería.</p>
                <input type="text" placeholder="Ej: 101, 102, 103" value="${config.gameModes.hunting.targets.join(', ')}"
                       onchange="config.gameModes.hunting.targets = this.value.split(',').map(v => v.trim())"
                       style="margin-top:10px;">
            </div>
        `;
    } else if (currentModeTab === 'extraction') {
        if (!config.gameModes.extraction.minPlayers) config.gameModes.extraction.minPlayers = 2;
        if (!config.gameModes.extraction.startCountdown) config.gameModes.extraction.startCountdown = 30000;
        if (!config.gameModes.extraction.maxPlayers) config.gameModes.extraction.maxPlayers = 21;
        if (!config.gameModes.extraction.countdownTime) config.gameModes.extraction.countdownTime = 600000;
        if (!config.gameModes.extraction.extractRadius) config.gameModes.extraction.extractRadius = 150;
        if (!config.gameModes.extraction.spawnLockTime) config.gameModes.extraction.spawnLockTime = 10000;
        if (!config.gameModes.extraction.maps) config.gameModes.extraction.maps = [10];
        if (!config.gameModes.extraction.spawners) config.gameModes.extraction.spawners = [];
        if (!config.gameModes.extraction.spawnPoints) config.gameModes.extraction.spawnPoints = [];
        if (!config.gameModes.extraction.mechanics) config.gameModes.extraction.mechanics = [];
        config.gameModes.extraction.mechanics = config.gameModes.extraction.mechanics.filter(Boolean);
        if (!config.gameModes.extraction.extractPoints) {
            config.gameModes.extraction.extractPoints = [
                { x: 1500, y: 1500, label: "Punto Alfa" },
                { x: 8500, y: 1500, label: "Punto Beta" }
            ];
        }

        content.innerHTML = `
            <div style="grid-column: 1 / -1; display:flex; flex-direction:column; gap:20px; width:100%; padding-bottom:40px;">
                
                <!-- NIVEL 1: REGLAS Y MAPAS -->
                <div style="display:grid; grid-template-columns: 1fr 1fr; gap:20px;">
                    <!-- REGLAS MAESTRAS -->
                    <div class="card" style="margin:0;">
                        <h3 style="color:var(--primary); margin-bottom: 0.5rem;">📦 MODO EXTRACCIÓN (REGLAS MAESTRAS)</h3>
                        <p style="opacity:0.7; margin-bottom:1.5rem;">Configuración del emparejador y tiempos globales.</p>
                        <div class="form-grid" style="grid-template-columns: repeat(4, 1fr);">
                            <div class="field"><label>Estado</label>
                                <select onchange="config.gameModes.extraction.enabled = this.value === 'true'">
                                    <option value="true" ${config.gameModes.extraction.enabled ? 'selected' : ''}>ACTIVO</option>
                                    <option value="false" ${!config.gameModes.extraction.enabled ? 'selected' : ''}>DESACTIVADO</option>
                                </select>
                            </div>
                            <div class="field"><label>Mín. Pilotos</label><input type="number" value="${config.gameModes.extraction.minPlayers}" onchange="config.gameModes.extraction.minPlayers = parseInt(this.value)"></div>
                            <div class="field"><label>Máx. Pilotos</label><input type="number" value="${config.gameModes.extraction.maxPlayers}" onchange="config.gameModes.extraction.maxPlayers = parseInt(this.value)"></div>
                            <div class="field"><label>Inicio (ms)</label><input type="number" step="1000" value="${config.gameModes.extraction.startCountdown}" onchange="config.gameModes.extraction.startCountdown = parseInt(this.value)"></div>
                            <div class="field"><label>Extracción (ms)</label><input type="number" step="1000" value="${config.gameModes.extraction.countdownTime}" onchange="config.gameModes.extraction.countdownTime = parseInt(this.value)"></div>
                            <div class="field"><label>Bloqueo Spawn (ms)</label><input type="number" step="1000" value="${config.gameModes.extraction.spawnLockTime}" onchange="config.gameModes.extraction.spawnLockTime = parseInt(this.value)" style="color:var(--accent); font-weight:bold;"></div>
                            <div class="field"><label>Radio Ext. (px)</label><input type="number" value="${config.gameModes.extraction.extractRadius}" onchange="config.gameModes.extraction.extractRadius = parseInt(this.value)"></div>
                        </div>
                    </div>

                    <!-- MAPAS HABILITADOS -->
                    <div class="card" style="margin:0;">
                        <h3 style="color:var(--primary); margin-bottom: 0.5rem;">🗺️ MAPAS PARA EXTRACCIÓN</h3>
                        <p style="opacity:0.6; margin-bottom:1.5rem;">Selecciona los mapas donde el modo estará activo.</p>
                        <div style="display:flex; gap:10px; margin-bottom:15px;">
                            <select id="add-ext-map-select" style="font-size:0.8rem; flex:1;">
                                <option value="" disabled selected hidden>🔍 Seleccionar mapa...</option>
                                ${Object.keys(config.mapsConfig).map(id => `<option value="${id}">${config.mapsConfig[id].name}</option>`).join('')}
                            </select>
                            <button class="btn btn-primary" style="padding:4px 15px; font-size:0.7rem;" onclick="addExtractionMap()">+ AÑADIR MAPA</button>
                        </div>
                        <div style="display:flex; flex-wrap:wrap; gap:8px; max-height:100px; overflow-y:auto;">
                            ${config.gameModes.extraction.maps.map((mapId, idx) => `
                                <div style="background:rgba(255,255,255,0.05); padding:6px 12px; border-radius:20px; border:1px solid rgba(255,255,255,0.1); display:flex; align-items:center; gap:10px; font-size:0.75rem;">
                                    <span>${config.mapsConfig[mapId]?.name || 'ID '+mapId}</span>
                                    <button onclick="config.gameModes.extraction.maps.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                </div>

                <!-- NIVEL 2: 4 COLUMNAS -->
                <div style="display:grid; grid-template-columns: repeat(4, 1fr); gap:20px;">
                    <!-- SPAWN POINTS (PLAYERS) -->
                    <div class="card" style="margin:0; border-top: 3px solid var(--accent);">
                        <h4 style="color:var(--accent); margin-bottom:1rem;">📍 SPAWN DE JUGADORES</h4>
                        <div style="display:flex; flex-direction:column; gap:8px; max-height:300px; overflow-y:auto; padding-right:5px;">
                            ${(config.gameModes.extraction.spawnPoints || []).map((p, idx) => `
                                <div id="card-spawn-${idx}" onclick="highlightCard('spawn', ${idx})" style="background:rgba(6,182,212,0.05); border:1px solid rgba(6,182,212,0.2); border-radius:8px; padding:10px; transition: all 0.3s ease; cursor:pointer;">
                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                        <input type="text" value="${p.label || 'Punto #'+(idx+1)}" onchange="config.gameModes.extraction.spawnPoints[${idx}].label = this.value" style="background:none; border:none; color:var(--accent); font-weight:bold; font-size:0.7rem; width:70%;">
                                        <button onclick="config.gameModes.extraction.spawnPoints.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px;">
                                        <div class="field"><label>X</label><input type="number" id="spw-x-${idx}" value="${p.x}" onchange="config.gameModes.extraction.spawnPoints[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Y</label><input type="number" id="spw-y-${idx}" value="${p.y}" onchange="config.gameModes.extraction.spawnPoints[${idx}].y = parseInt(this.value)"></div>
                                    </div>
                                    <div class="field" style="margin-top:5px;"><label>Radio Burbuja</label><input type="number" value="${p.radius}" onchange="config.gameModes.extraction.spawnPoints[${idx}].radius = parseInt(this.value)"></div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <!-- PUNTOS DE ESCAPE -->
                    <div class="card" style="margin:0;">
                        <h4 style="color:var(--primary); margin-bottom:1rem;">🛰️ PUNTOS DE ESCAPE</h4>
                        <div style="display:flex; flex-direction:column; gap:8px; max-height:300px; overflow-y:auto; padding-right:5px;">
                            ${config.gameModes.extraction.extractPoints.map((p, idx) => `
                                <div id="card-extract-${idx}" onclick="highlightCard('extract', ${idx})" style="background:rgba(0,210,255,0.05); border:1px solid rgba(0,210,255,0.2); border-radius:8px; padding:10px; transition: all 0.3s ease; cursor:pointer; overflow: visible;">
                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                        <input type="text" value="${p.label}" onchange="config.gameModes.extraction.extractPoints[${idx}].label = this.value" style="background:none; border:none; color:var(--primary); font-weight:bold; font-size:0.75rem; width:70%;">
                                        <button onclick="config.gameModes.extraction.extractPoints.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px; margin-bottom:8px;">
                                        <div class="field"><label>Coord X (px)</label><input type="number" id="ep-x-${idx}" value="${p.x}" onchange="config.gameModes.extraction.extractPoints[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Coord Y (px)</label><input type="number" id="ep-y-${idx}" value="${p.y}" onchange="config.gameModes.extraction.extractPoints[${idx}].y = parseInt(this.value)"></div>
                                    </div>
                                    <div class="field" style="margin-bottom:8px; overflow: visible; width: 100%;">
                                        <label>Mapa de Destino</label>
                                        ${renderSearchableMapSelect(p.targetZone || "1", (newId) => {
                                            config.gameModes.extraction.extractPoints[idx].targetZone = newId;
                                        }, 'var(--primary)', `ext-map-${idx}`)}
                                    </div>
                                    <div class="field">
                                        <label>Radio de Proximidad (px)</label>
                                        <input type="number" value="${p.proximityRadius || 300}" onchange="config.gameModes.extraction.extractPoints[${idx}].proximityRadius = parseInt(this.value)">
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <!-- AMENAZAS -->
                    <div class="card" style="margin:0;">
                        <h4 style="color:var(--danger); margin-bottom:1rem;">👾 AMENAZAS DESPLEGADAS</h4>
                        <div style="display:flex; flex-direction:column; gap:10px; max-height:300px; overflow-y:auto; padding-right:5px;">
                            ${config.gameModes.extraction.spawners.map((s, idx) => `
                                <div id="card-spawner-${idx}" onclick="highlightCard('spawner', ${idx})" style="background:rgba(255,49,49,0.05); border:1px solid rgba(255,49,49,0.2); border-radius:8px; padding:10px; overflow: visible; transition: all 0.3s ease; cursor:pointer;">
                                    <div style="display:flex; flex-direction:column; gap:8px; margin-bottom:8px; overflow: visible;">
                                        <div style="display:flex; justify-content:space-between; align-items:center;">
                                            <input type="text" value="${s.label || 'Zona '+ (idx+1)}" onchange="config.gameModes.extraction.spawners[${idx}].label = this.value; renderModes();" style="background:none; border:none; color:var(--danger); font-weight:bold; font-size:0.75rem; width:85%;">
                                            <button onclick="config.gameModes.extraction.spawners.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                        </div>
                                        <div style="overflow: visible; width: 100%;">
                                            ${renderSearchableEnemySelect(s.enemyId, (newId) => {
                                                config.gameModes.extraction.spawners[idx].enemyId = newId;
                                                renderModes();
                                            }, 'var(--danger)', `ext-spawn-${idx}`)}
                                        </div>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px;">
                                        <div class="field"><label>Cant.</label><input type="number" value="${s.count}" onchange="config.gameModes.extraction.spawners[${idx}].count = parseInt(this.value)"></div>
                                        <div class="field"><label>Radio</label><input type="number" value="${s.radius}" onchange="config.gameModes.extraction.spawners[${idx}].radius = parseInt(this.value)"></div>
                                        <div class="field"><label>Coord X</label><input type="number" id="sp-x-${idx}" value="${s.x}" onchange="config.gameModes.extraction.spawners[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Coord Y</label><input type="number" id="sp-y-${idx}" value="${s.y}" onchange="config.gameModes.extraction.spawners[${idx}].y = parseInt(this.value)"></div>
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <!-- MECÁNICAS -->
                    <div class="card" style="margin:0;">
                        <h4 style="color:var(--accent); margin-bottom:1rem;">🌍 MECÁNICAS</h4>
                        <p style="opacity:0.6; font-size:0.7rem; margin-bottom:1rem;">Efectos de ambiente de tu librería.</p>
                        <div style="display:flex; gap:10px; margin-bottom:15px;">
                            <select id="add-ext-mech-select" style="font-size:0.7rem; flex:1;">
                                ${Object.keys(AMBIENCE_LIB).map(type => `<option value="${type}">${AMBIENCE_LIB[type].icon || '🌍'} ${AMBIENCE_LIB[type].label}</option>`).join('')}
                            </select>
                            <button class="btn btn-primary" style="padding:4px 10px; font-size:0.6rem;" onclick="addExtractionMechanic()">+ ACTIVAR</button>
                        </div>
                        <div style="display:flex; flex-direction:column; gap:8px;">
                            ${(config.gameModes.extraction.mechanics || []).map((m, idx) => `
                                <div style="background:rgba(6,182,212,0.1); border:1px solid var(--accent); padding:10px; border-radius:8px; display:flex; justify-content:space-between; align-items:center;">
                                    <span style="color:var(--accent); font-weight:bold; font-size:0.7rem;">${AMBIENCE_LIB[m]?.icon || ''} ${(AMBIENCE_LIB[m]?.label || m).toUpperCase()}</span>
                                    <button onclick="config.gameModes.extraction.mechanics.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                </div>

                <!-- NIVEL 3: RADAR GLOBAL -->
                <div class="card" style="margin:0;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1.5rem;">
                        <div style="display:flex; align-items:center; gap:20px;">
                            <h4 style="color:var(--primary); margin:0;">🛰️ RADAR DE POSICIONAMIENTO GLOBAL</h4>
                            <div style="display:flex; align-items:center; gap:10px; background:rgba(255,255,255,0.03); padding:4px 12px; border-radius:8px; border:1px solid rgba(255,255,255,0.05);">
                                <label style="font-size:0.65rem; color:var(--accent); font-weight:bold; letter-spacing:1px; margin:0;">DIMENSIONES MUNDO (PX):</label>
                                <div style="display:flex; align-items:center; gap:5px;">
                                    <span style="font-size:0.65rem; opacity:0.6;">W:</span>
                                    <input type="number" value="${config.gameModes.extraction.width || 10000}" 
                                           onchange="config.gameModes.extraction.width = parseInt(this.value); renderModes();" 
                                           style="width:70px; background:rgba(0,0,0,0.3); border:1px solid #333; color:white; font-size:0.75rem; text-align:center; padding:2px; border-radius:4px; font-weight:bold; font-family:'JetBrains Mono',monospace;">
                                </div>
                                <div style="display:flex; align-items:center; gap:5px; margin-left:10px;">
                                    <span style="font-size:0.65rem; opacity:0.6;">H:</span>
                                    <input type="number" value="${config.gameModes.extraction.height || 10000}" 
                                           onchange="config.gameModes.extraction.height = parseInt(this.value); renderModes();" 
                                           style="width:70px; background:rgba(0,0,0,0.3); border:1px solid #333; color:white; font-size:0.75rem; text-align:center; padding:2px; border-radius:4px; font-weight:bold; font-family:'JetBrains Mono',monospace;">
                                </div>
                            </div>
                        </div>
                        <div style="display:flex; gap:10px;">
                            <button id="btn-radar-spawn" class="btn ${radarMode === 'spawn' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('spawn')">MODO SPAWN</button>
                            <button id="btn-radar-spawner" class="btn ${radarMode === 'spawner' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('spawner')">MODO AMENAZA</button>
                            <button id="btn-radar-extract" class="btn ${radarMode === 'extract' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('extract')">MODO ESCAPE</button>
                        </div>
                    </div>
                    
                    <div style="display:flex; flex-wrap:wrap; justify-content:center; gap:30px; width:100%;">
                        <div id="radar-container" style="position:relative; width:600px; height:600px; background:#000; border:2px solid var(--primary); border-radius:10px; overflow:hidden; cursor:crosshair; box-shadow: 0 0 20px rgba(0, 210, 255, 0.15);">
                            <canvas id="radar-canvas" width="600" height="600" style="width: 100%; height: 100%; display: block;"></canvas>
                        </div>
                        
                        <div style="flex:1; min-width:350px; display:flex; flex-direction:column; gap:15px; background:rgba(255,255,255,0.02); padding:25px; border-radius:10px; overflow: visible;">
                            <label style="color:var(--accent); font-size:0.85rem; margin-bottom:15px; display:block; border-bottom:1px solid rgba(255,255,255,0.1); padding-bottom:10px; font-weight:bold; overflow: visible;">🛠️ HERRAMIENTA DE DESPLIEGUE</label>
                            <div style="display:grid; grid-template-columns: 1fr 1fr; gap:15px;">
                                <div class="field"><label>Coord X</label><input type="number" id="radar-x" value="0"></div>
                                <div class="field"><label>Coord Y</label><input type="number" id="radar-y" value="0"></div>
                            </div>
                            <div id="radar-spawn-opts" style="display:${radarMode === 'spawn' ? 'block' : 'none'}">
                                <div class="field" style="margin-top:10px;"><label>Nombre</label><input type="text" id="radar-spawn-label" value="Punto Spawn"></div>
                                <div class="field" style="margin-top:5px;"><label>Radio Burbuja</label><input type="number" id="radar-spawn-radius" value="500"></div>
                            </div>
                            <div id="radar-spawner-opts" style="display:${radarMode === 'spawner' ? 'block' : 'none'}; overflow: visible;">
                                <div class="field" style="margin-top:10px;"><label>Nombre Zona</label><input type="text" id="radar-spawner-label" value="Zona de Amenaza"></div>
                                <div class="field" style="margin-top:10px; overflow: visible;">
                                    <label>Enemigo</label>
                                    <input type="hidden" id="spawner-enemy-select" value="${config.gameModes.extraction.spawners[0]?.enemyId || '1'}">
                                    ${renderSearchableEnemySelect(config.gameModes.extraction.spawners[0]?.enemyId || '1', (newId) => {
                                        document.getElementById('spawner-enemy-select').value = newId;
                                    }, 'var(--accent)', 'radar-spawn-select')}
                                </div>
                                <div class="field" style="margin-top:10px;"><label>Cantidad</label><input type="number" id="radar-count" value="10"></div>
                                <div class="field" style="margin-top:10px;"><label>Radio</label><input type="number" id="radar-radius" value="500"></div>
                            </div>
                            <div id="radar-extract-opts" style="display:${radarMode === 'extract' ? 'block' : 'none'}">
                                <div class="field" style="margin-top:10px;"><label>Etiqueta</label><input type="text" id="radar-label" value="Punto Nuevo"></div>
                            </div>
                            <button class="btn btn-primary" style="width:100%; margin-top:20px; padding:15px; font-weight:bold;" onclick="addFromRadar()">FIJAR EN EL MAPA</button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        setTimeout(initRadar, 100);
    } else if (currentModeTab === 'altar_defense') {
        const ad = config.gameModes.altar_defense;
        if (!ad.maxPlayers) ad.maxPlayers = 4;
        if (!ad.minPlayers) ad.minPlayers = 2;
        if (!ad.altarHp) ad.altarHp = 10000;
        if (!ad.altarShield) ad.altarShield = 5000;
        if (!ad.partyAcceptTimeout) ad.partyAcceptTimeout = 10000;
        if (ad.waveInterval === undefined) ad.waveInterval = 30000;
        if (ad.spawnLockTime === undefined) ad.spawnLockTime = 10000;
        if (ad.matchDuration === undefined) ad.matchDuration = 600000;
        if (ad.loseLootOnDeath === undefined) ad.loseLootOnDeath = true;
        if (!ad.maps) ad.maps = [];
        // v770.4: altarPos y exitPortals ahora se manejan exclusivamente desde el Editor 3D (mapsConfig.objects), no desde AdminDash
        if (!ad.spawnPoints) ad.spawnPoints = [];
        if (!ad.spawners) ad.spawners = [];
        if (!ad.waves) ad.waves = [];

        content.innerHTML = `
            <div style="grid-column: 1 / -1; display:flex; flex-direction:column; gap:20px; width:100%; padding-bottom:40px;">
                
                <!-- NIVEL 1: REGLAS Y MAPAS -->
                <div style="display:grid; grid-template-columns: 1.2fr 0.8fr; gap:20px;">
                    <!-- REGLAS MAESTRAS -->
                    <div class="card" style="margin:0;">
                        <h3 style="color:var(--primary); margin-bottom: 0.5rem;">🛡️ DEFENSA DEL ALTAR (REGLAS MAESTRAS)</h3>
                        <p style="opacity:0.7; margin-bottom:1.5rem;">Configura las reglas básicas y temporizadores del modo de juego.</p>
                        <div class="form-grid" style="grid-template-columns: repeat(5, 1fr); gap: 15px;">
                            <div class="field"><label>Estado</label>
                                <select onchange="config.gameModes.altar_defense.enabled = this.value === 'true'">
                                    <option value="true" ${ad.enabled ? 'selected' : ''}>ACTIVO</option>
                                    <option value="false" ${!ad.enabled ? 'selected' : ''}>DESACTIVADO</option>
                                </select>
                            </div>
                            <div class="field"><label>Mín. Pilotos Party</label><input type="number" value="${ad.minPlayers}" onchange="config.gameModes.altar_defense.minPlayers = parseInt(this.value)"></div>
                            <div class="field"><label>Máx. Pilotos Party</label><input type="number" value="${ad.maxPlayers}" onchange="config.gameModes.altar_defense.maxPlayers = parseInt(this.value)"></div>
                            <div class="field"><label>Vida del Altar</label><input type="number" value="${ad.altarHp}" onchange="config.gameModes.altar_defense.altarHp = parseInt(this.value)"></div>
                            <div class="field"><label>Escudo del Altar</label><input type="number" value="${ad.altarShield}" onchange="config.gameModes.altar_defense.altarShield = parseInt(this.value)"></div>
                            
                            <div class="field"><label>Tiempo Aceptar (ms)</label><input type="number" step="1000" value="${ad.partyAcceptTimeout}" onchange="config.gameModes.altar_defense.partyAcceptTimeout = parseInt(this.value)"></div>
                            <div class="field"><label>Intervalo Oleadas (ms)</label><input type="number" step="1000" value="${ad.waveInterval}" onchange="config.gameModes.altar_defense.waveInterval = parseInt(this.value)"></div>
                            <div class="field"><label>Bloqueo de Spawn (ms)</label><input type="number" step="1000" value="${ad.spawnLockTime}" onchange="config.gameModes.altar_defense.spawnLockTime = parseInt(this.value)"></div>
                            <div class="field"><label>Duración Partida (ms)</label><input type="number" step="5000" value="${ad.matchDuration}" onchange="config.gameModes.altar_defense.matchDuration = parseInt(this.value)"></div>
                            <div></div> <!-- Celda vacía para completar la fila de 5 -->
                            
                            <div class="field" style="grid-column: span 5; display: flex; align-items: center; gap: 15px; background: rgba(255,255,255,0.02); padding: 10px 15px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.05); margin-top: 5px;">
                                <label style="margin: 0; cursor: pointer; display: flex; align-items: center; gap: 10px; font-weight: bold; color: var(--text);">
                                    <input type="checkbox" ${ad.loseLootOnDeath ? 'checked' : ''} onchange="config.gameModes.altar_defense.loseLootOnDeath = this.checked" style="width: 18px; height: 18px; cursor: pointer;">
                                    💀 Perder Loot al morir (Modo Hardcore)
                                </label>
                                <span style="font-size: 0.75rem; opacity: 0.6; flex: 1;">Si está desactivado, los jugadores mantendrán su loot temporal al morir o fallar (ideal para aprender las mecánicas).</span>
                            </div>
                        </div>
                    </div>

                    <!-- MAPAS HABILITADOS -->
                    <div class="card" style="margin:0;">
                        <h3 style="color:var(--primary); margin-bottom: 0.5rem;">🗺️ MAPAS PARA DEFENSA DEL ALTAR</h3>
                        <p style="opacity:0.6; margin-bottom:1.5rem;">Selecciona los mapas donde se habilitará esta mecánica.</p>
                        <div style="display:flex; gap:10px; margin-bottom:15px;">
                            <select id="add-ad-map-select" style="font-size:0.8rem; flex:1;">
                                <option value="" disabled selected hidden>🔍 Seleccionar mapa...</option>
                                ${Object.keys(config.mapsConfig).map(id => `<option value="${id}">${config.mapsConfig[id].name}</option>`).join('')}
                            </select>
                            <button class="btn btn-primary" style="padding:4px 15px; font-size:0.7rem;" onclick="addAltarDefenseMap()">+ AÑADIR MAPA</button>
                        </div>
                        <div style="display:flex; flex-wrap:wrap; gap:8px; max-height:140px; overflow-y:auto;">
                            ${ad.maps.map((mapId, idx) => `
                                <div style="background:rgba(255,255,255,0.05); padding:6px 12px; border-radius:20px; border:1px solid rgba(255,255,255,0.1); display:flex; align-items:center; gap:10px; font-size:0.75rem;">
                                    <span>${config.mapsConfig[mapId]?.name || 'ID '+mapId}</span>
                                    <button onclick="config.gameModes.altar_defense.maps.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                </div>

                <!-- NIVEL 2: CONFIGURACIÓN DE POSICIONAMIENTOS -->
                <!-- v770.4: ALTAR y PUERTAS ahora se editan solo en Editor 3D (mapsConfig.objects), no aquí -->
                <div style="display:grid; grid-template-columns: repeat(2, 1fr); gap:20px;">
                    <!-- SPAWN POINTS (PLAYERS) -->
                    <div class="card" style="margin:0; border-top: 3px solid var(--accent);">
                        <h4 style="color:var(--accent); margin-bottom:1rem;">📍 SPAWN DE JUGADORES</h4>
                        <p style="opacity:0.5; font-size:0.7rem; margin-bottom:10px;">Editables aquí. Para Altar/Puertas usa el Editor 3D.</p>
                        <div style="display:flex; flex-direction:column; gap:8px; max-height:280px; overflow-y:auto; padding-right:5px;">
                            ${(ad.spawnPoints || []).map((p, idx) => `
                                <div id="card-ad-spawn-${idx}" onclick="highlightCard('ad-spawn', ${idx})" style="background:rgba(6,182,212,0.05); border:1px solid rgba(6,182,212,0.2); border-radius:8px; padding:10px; transition: all 0.3s ease; cursor:pointer;">
                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                        <input type="text" value="${p.label || 'Punto #'+(idx+1)}" onchange="config.gameModes.altar_defense.spawnPoints[${idx}].label = this.value" style="background:none; border:none; color:var(--accent); font-weight:bold; font-size:0.7rem; width:70%;">
                                        <button onclick="config.gameModes.altar_defense.spawnPoints.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px;">
                                        <div class="field"><label>X</label><input type="number" id="ad-spw-x-${idx}" value="${p.x}" onchange="config.gameModes.altar_defense.spawnPoints[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Y</label><input type="number" id="ad-spw-y-${idx}" value="${p.y}" onchange="config.gameModes.altar_defense.spawnPoints[${idx}].y = parseInt(this.value)"></div>
                                    </div>
                                    <div class="field" style="margin-top:5px;"><label>Radio Burbuja</label><input type="number" value="${p.radius || 200}" onchange="config.gameModes.altar_defense.spawnPoints[${idx}].radius = parseInt(this.value)"></div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <!-- AMENAZAS / ENEMIGOS - v770.12: Gestionado exclusivamente via Editor 3D Puerta3 -->
                    <div class="card" style="margin:0; border-top: 3px solid var(--danger); opacity:0.95;">
                        <h4 style="color:var(--danger); margin-bottom:0.5rem;">👾 SPAWNERS DE ENEMIGOS (PUERTA3)</h4>
                        <p style="font-size:0.7rem; opacity:0.7; margin-bottom:10px; line-height:1.4;">Gestionado <b>exclusivamente</b> desde <code>res://tools/MapEditor3D_Evento_2_Defensa_Altar.tscn</code> → objetos tipo <b>spawner</b> con <code>res://assets/Puertas/3D/Puerta3/3D/Puerta3.glb</code><br>Coloca puertas <b>Puerta3</b> donde quieras que aparezcan enemigos, edita <code>enemyId / count / radius</code> en el inspector y pulsa <b>Save to Server</b>.</p>
                        <div style="background:rgba(255,49,49,0.08); border:1px solid rgba(255,49,49,0.2); border-radius:8px; padding:10px; font-size:0.7rem;">
                            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
                                <span>Spawners detectados (gameModes): <b>${(ad.spawners||[]).length}</b></span>
                                <span style="opacity:0.6; font-size:0.65rem;">(sincronizado desde Editor 3D)</span>
                            </div>
                            ${(ad.spawners||[]).length === 0 ? `<div style="opacity:0.5; font-style:italic;">Sin spawners. Abre el Editor 3D, añade objetos tipo spawner y guarda.</div>` : (ad.spawners||[]).map((s, idx) => `
                                <div style="display:flex; justify-content:space-between; align-items:center; padding:4px 0; border-bottom:1px solid rgba(255,255,255,0.05);">
                                    <span style="max-width:140px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">[${idx}] ${s.label || 'Spawner'} — ${s.enemyId || '1'} x${s.count||0}</span>
                                    <span style="opacity:0.7;">(${s.x},${s.y}) r:${s.radius}</span>
                                </div>
                            `).join('')}
                        </div>
                        <div style="margin-top:8px; font-size:0.65rem; opacity:0.5;">Edición deshabilitada aquí. Usa el Editor 3D para mover/editar.</div>
                    </div>
                </div>

                <!-- NIVEL 3: CONFIGURACIÓN DE OLEADAS (WAVES) -->
                <div class="card" style="margin:0; border-top: 3px solid var(--accent);">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1.5rem;">
                        <h4 style="color:var(--accent); margin:0;">🌊 CONFIGURACIÓN DE OLEADAS (WAVES)</h4>
                        <button class="btn btn-primary" style="padding: 5px 20px; font-size:0.75rem;" onclick="addAltarDefenseWave()">+ AÑADIR OLEADA</button>
                    </div>
                    <div style="display:flex; flex-direction:column; gap:20px; max-height:500px; overflow-y:auto; padding-right:5px;">
                        ${ad.waves.map((w, idx) => {
                            const isCollapsed = window.collapsedWaves && window.collapsedWaves[idx];
                            return `
                            <div class="card" style="background:rgba(255,255,255,0.02); border:1px solid rgba(255,255,255,0.05); border-radius:10px; padding:15px; margin:0; position:relative; overflow: visible;">
                                <div style="display:flex; justify-content:space-between; align-items:center; cursor:pointer;" onclick="toggleWaveCollapse(${idx})">
                                    <div style="display:flex; align-items:center; gap:10px; width:80%;">
                                        <span style="font-size:0.8rem; color:var(--text-dim);">${isCollapsed ? '▶' : '▼'}</span>
                                        <input type="text" value="${w.name || 'Oleada ' + (idx + 1)}" onchange="config.gameModes.altar_defense.waves[${idx}].name = this.value; event.stopPropagation();" onclick="event.stopPropagation();" style="background:none; border:none; color:var(--primary); font-weight:bold; font-size:0.95rem; width:80%;">
                                    </div>
                                    <div style="display:flex; align-items:center; gap:10px;">
                                        <button onclick="config.gameModes.altar_defense.waves.splice(${idx},1); renderModes(); event.stopPropagation();" style="background:none; border:none; color:var(--danger); cursor:pointer; font-size:1.1rem;">✕</button>
                                    </div>
                                </div>
                                
                                <div style="display: ${isCollapsed ? 'none' : 'flex'}; flex-direction:column; gap:15px; margin-top:15px; overflow: visible;">
                                    <div style="display:grid; grid-template-columns: 1fr; gap:10px;">
                                        <div class="field">
                                            <label>Delay de Inicio de Oleada (ms)</label>
                                            <input type="number" step="1000" value="${w.delayMs || 5000}" onchange="config.gameModes.altar_defense.waves[${idx}].delayMs = parseInt(this.value)">
                                        </div>
                                    </div>
                                    
                                    <!-- FASES DENTRO DE LA OLEADA -->
                                    <div style="border-top: 1px solid rgba(255,255,255,0.05); padding-top:10px;">
                                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
                                            <h5 style="color:var(--text); margin:0; font-size:0.85rem;">Fases de la Oleada</h5>
                                            <button class="btn btn-secondary" style="padding: 2px 10px; font-size:0.65rem;" onclick="addAltarDefensePhase(${idx})">+ AÑADIR FASE</button>
                                        </div>
                                        <div style="display:flex; flex-direction:column; gap:12px;">
                                            ${(w.phases || []).map((ph, phIdx) => {
                                                if (!ph.spawnerDistribution) {
                                                    ph.spawnerDistribution = {};
                                                }
                                                // Calcular cantidad total sumando la distribución
                                                let totalCount = 0;
                                                for (let key in ph.spawnerDistribution) {
                                                    totalCount += ph.spawnerDistribution[key] || 0;
                                                }
                                                ph.count = totalCount;

                                                return `
                                                <div style="background:rgba(255,255,255,0.01); border:1px solid rgba(255,255,255,0.03); border-radius:8px; padding:12px; position:relative; overflow: visible;">
                                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                                        <input type="text" value="${ph.name || 'Fase ' + (phIdx + 1)}" onchange="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].name = this.value" style="background:none; border:none; color:var(--accent); font-weight:bold; font-size:0.8rem; width:70%;">
                                                        <button onclick="config.gameModes.altar_defense.waves[${idx}].phases.splice(${phIdx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer; font-size:0.9rem;">✕</button>
                                                    </div>
                                                    
                                                    <div style="display:flex; flex-direction:column; gap:10px; overflow: visible;">
                                                        <div style="overflow: visible; width: 100%;">
                                                            <label style="font-size:0.7rem; color:var(--text-dim); display:block; margin-bottom:4px;">Enemigo a Spawnear</label>
                                                            ${renderSearchableEnemySelect(ph.enemyId || '', (newId) => {
                                                                config.gameModes.altar_defense.waves[idx].phases[phIdx].enemyId = newId;
                                                            }, 'var(--accent)', `ad-wave-${idx}-phase-${phIdx}`)}
                                                        </div>
                                                        
                                                        <div style="display:grid; grid-template-columns: ${ph.spawnType === 'staggered' ? '1fr 1fr 1fr' : '1fr 1fr'}; gap:10px;">
                                                            <div class="field">
                                                                <label>Tipo Spawn</label>
                                                                <select onchange="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].spawnType = this.value; renderModes();">
                                                                    <option value="together" ${ph.spawnType === 'together' ? 'selected' : ''}>Todos juntos</option>
                                                                    <option value="staggered" ${ph.spawnType === 'staggered' ? 'selected' : ''}>Escalonados</option>
                                                                </select>
                                                            </div>
                                                            <div class="field">
                                                                <label>Delay Inicio Fase (ms)</label>
                                                                <input type="number" step="100" value="${ph.startDelayMs || 0}" onchange="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].startDelayMs = parseInt(this.value)">
                                                            </div>
                                                            ${ph.spawnType === 'staggered' ? `
                                                            <div class="field">
                                                                <label>Delay Escalonamiento (ms)</label>
                                                                <input type="number" step="100" value="${ph.staggerDelayMs || 500}" onchange="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].staggerDelayMs = parseInt(this.value)">
                                                            </div>
                                                            ` : ''}
                                                        </div>

                                                        <!-- DISTRIBUCIÓN DE SPAWNERS -->
                                                        <div style="background:rgba(0,0,0,0.2); padding:8px; border-radius:6px; border:1px solid rgba(255,255,255,0.03);">
                                                            <label style="font-size:0.7rem; color:var(--accent); font-weight:bold; display:block; margin-bottom:6px;">Distribución de Enemigos por Spawner</label>
                                                            <div style="display:flex; flex-direction:column; gap:6px;">
                                                                <!-- Random Pool -->
                                                                <div style="display:flex; justify-content:space-between; align-items:center;">
                                                                    <span style="font-size:0.7rem; opacity:0.8;">Random (Cualquier zona)</span>
                                                                    <input type="number" min="0" value="${ph.spawnerDistribution.random || 0}" 
                                                                           oninput="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].spawnerDistribution.random = parseInt(this.value) || 0; updateAdPhaseTotal(${idx}, ${phIdx});"
                                                                           style="width:60px; text-align:center; font-size:0.75rem; background:rgba(0,0,0,0.5); border:1px solid #333; color:white; border-radius:4px; padding:2px;">
                                                                </div>
                                                                <!-- Spawners específicos -->
                                                                ${ad.spawners.map((sp, spIdx) => {
                                                                    const val = ph.spawnerDistribution[spIdx] || 0;
                                                                    return `
                                                                    <div style="display:flex; justify-content:space-between; align-items:center;">
                                                                        <span style="font-size:0.7rem; opacity:0.8; max-width:180px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">[${spIdx}] ${sp.label || 'Zona ' + (spIdx + 1)}</span>
                                                                        <input type="number" min="0" value="${val}" 
                                                                               oninput="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].spawnerDistribution[${spIdx}] = parseInt(this.value) || 0; updateAdPhaseTotal(${idx}, ${phIdx});"
                                                                               style="width:60px; text-align:center; font-size:0.75rem; background:rgba(0,0,0,0.5); border:1px solid #333; color:white; border-radius:4px; padding:2px;">
                                                                    </div>
                                                                    `;
                                                                }).join('')}
                                                            </div>
                                                            <div style="margin-top:8px; border-top:1px solid rgba(255,255,255,0.05); padding-top:4px; display:flex; justify-content:space-between; align-items:center;">
                                                                <span style="font-size:0.7rem; font-weight:bold; color:var(--text);">Total Enemigos en Fase:</span>
                                                                <span id="ad-phase-total-${idx}-${phIdx}" style="font-size:0.75rem; font-weight:bold; color:var(--success);">${totalCount}</span>
                                                            </div>
                                                        </div>

                                                    </div>
                                                </div>
                                                `;
                                            }).join('')}
                                        </div>
                                    </div>
                                </div>
                            </div>
                            `;
                        }).join('')}
                    </div>
                </div>

                <!-- NIVEL 4: RADAR GLOBAL -->
                <div class="card" style="margin:0;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1.5rem;">
                        <div style="display:flex; align-items:center; gap:20px;">
                            <h4 style="color:var(--primary); margin:0;">🛰️ RADAR DE POSICIONAMIENTO GLOBAL (ALTAR)</h4>
                            <div style="display:flex; align-items:center; gap:10px; background:rgba(255,255,255,0.03); padding:4px 12px; border-radius:8px; border:1px solid rgba(255,255,255,0.05);">
                                <label style="font-size:0.65rem; color:var(--accent); font-weight:bold; letter-spacing:1px; margin:0;">DIMENSIONES MUNDO (PX):</label>
                                <div style="display:flex; align-items:center; gap:5px;">
                                    <span style="font-size:0.65rem; opacity:0.6;">W:</span>
                                    <input type="number" value="${ad.width || 10000}" 
                                           onchange="config.gameModes.altar_defense.width = parseInt(this.value); renderModes();" 
                                           style="width:70px; background:rgba(0,0,0,0.3); border:1px solid #333; color:white; font-size:0.75rem; text-align:center; padding:2px; border-radius:4px; font-weight:bold; font-family:'JetBrains Mono',monospace;">
                                </div>
                                <div style="display:flex; align-items:center; gap:5px; margin-left:10px;">
                                    <span style="font-size:0.65rem; opacity:0.6;">H:</span>
                                    <input type="number" value="${ad.height || 10000}" 
                                           onchange="config.gameModes.altar_defense.height = parseInt(this.value); renderModes();" 
                                           style="width:70px; background:rgba(0,0,0,0.3); border:1px solid #333; color:white; font-size:0.75rem; text-align:center; padding:2px; border-radius:4px; font-weight:bold; font-family:'JetBrains Mono',monospace;">
                                </div>
                            </div>
                        </div>
                        <div style="display:flex; gap:10px; align-items:center;">
                            <button id="btn-radar-ad-spawn" class="btn ${radarMode === 'ad-spawn' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('ad-spawn')">MODO SPAWN</button>
                            <span style="font-size:0.65rem; opacity:0.5; background:rgba(255,49,49,0.08); border:1px solid rgba(255,49,49,0.2); padding:4px 8px; border-radius:4px;">👾 AMENAZA → Editor 3D (Puerta3)</span>
                        </div>
                    </div>
                    
                    <div style="display:flex; flex-wrap:wrap; justify-content:center; gap:30px; width:100%;">
                        <div id="radar-container" style="position:relative; width:600px; height:600px; background:#000; border:2px solid var(--primary); border-radius:10px; overflow:hidden; cursor:crosshair; box-shadow: 0 0 20px rgba(0, 210, 255, 0.15);">
                            <canvas id="radar-canvas" width="600" height="600" style="width: 100%; height: 100%; display: block;"></canvas>
                        </div>
                        
                        <div style="flex:1; min-width:350px; display:flex; flex-direction:column; gap:15px; background:rgba(255,255,255,0.02); padding:25px; border-radius:10px; overflow: visible;">
                            <label style="color:var(--accent); font-size:0.85rem; margin-bottom:15px; display:block; border-bottom:1px solid rgba(255,255,255,0.1); padding-bottom:10px; font-weight:bold; overflow: visible;">🛠️ HERRAMIENTA DE DESPLIEGUE</label>
                            <div style="display:grid; grid-template-columns: 1fr 1fr; gap:15px;">
                                <div class="field"><label>Coord X</label><input type="number" id="radar-x" value="0"></div>
                                <div class="field"><label>Coord Y</label><input type="number" id="radar-y" value="0"></div>
                            </div>
                            <div id="radar-ad-spawn-opts" style="display:${radarMode === 'ad-spawn' ? 'block' : 'none'}">
                                <div class="field" style="margin-top:10px;"><label>Nombre</label><input type="text" id="radar-ad-spawn-label" value="Punto Spawn"></div>
                                <div class="field" style="margin-top:5px;"><label>Radio Burbuja</label><input type="number" id="radar-ad-spawn-radius" value="200"></div>
                            </div>
                            <div id="radar-ad-spawner-opts" style="display:${radarMode === 'ad-spawner' ? 'block' : 'none'}; overflow: visible;">
                                <div class="field" style="margin-top:10px;"><label>Nombre Zona</label><input type="text" id="radar-ad-spawner-label" value="Zona de Invasión"></div>
                                <div class="field" style="margin-top:10px; overflow: visible;">
                                    <label>Enemigo</label>
                                    <input type="hidden" id="ad-spawner-enemy-select" value="${ad.spawners[0]?.enemyId || '1'}">
                                    ${renderSearchableEnemySelect(ad.spawners[0]?.enemyId || '1', (newId) => {
                                        document.getElementById('ad-spawner-enemy-select').value = newId;
                                    }, 'var(--accent)', 'radar-ad-spawn-select')}
                                </div>
                                <div class="field" style="margin-top:10px;"><label>Cantidad</label><input type="number" id="radar-ad-count" value="10"></div>
                                <div class="field" style="margin-top:10px;"><label>Radio</label><input type="number" id="radar-ad-radius" value="500"></div>
                            </div>

                            <button class="btn btn-primary" style="width:100%; margin-top:20px; padding:15px; font-weight:bold;" onclick="addFromRadar()">FIJAR EN EL MAPA</button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        setTimeout(initRadar, 100);
    } else if (currentModeTab === 'arenas') {
        if (!config.gameModes.arenas) {
            config.gameModes.arenas = { enabled: true, maps: [], minPlayers: 2 };
        }
        if (!config.gameModes.arenas.maps) config.gameModes.arenas.maps = [];
        if (!config.gameModes.arenas.mapConfigs) config.gameModes.arenas.mapConfigs = {};

        // Sincronizar mapa activo si no está fijado
        if (!activeArenaMapId && config.gameModes.arenas.maps.length > 0) {
            activeArenaMapId = config.gameModes.arenas.maps[0];
        }
        const mapCfg = activeArenaMapId ? config.gameModes.arenas.mapConfigs[activeArenaMapId] : null;

        let leftColPillarsHtml = '';
        let pillarDetailHtml = '';
        let leftColSpawnsHtml = '';
        let spawnDetailHtml = '';

        if (mapCfg) {
            if (!mapCfg.pillars) mapCfg.pillars = [];
            if (!mapCfg.spawns) mapCfg.spawns = [];
            
            leftColPillarsHtml = mapCfg.pillars.map((p, idx) => `
                <div onclick="selectArenaPillar(${idx})" style="background:${activeArenaPillarIndex === idx ? 'rgba(6,182,212,0.15)' : 'rgba(255,255,255,0.02)'}; border:1px solid ${activeArenaPillarIndex === idx ? 'var(--accent)' : 'rgba(255,255,255,0.06)'}; border-radius:8px; padding:10px; cursor:pointer; margin-bottom:8px; transition:all 0.2s;">
                    <div style="display:flex; justify-content:space-between; align-items:center;">
                        <span style="color:${p.team === 'red' ? '#ff3131' : '#31b6ff'}; font-weight:bold; font-size:0.8rem;">${p.name}</span>
                        <button onclick="event.stopPropagation(); removeArenaPillar(${idx});" style="background:none; border:none; color:var(--danger); cursor:pointer; font-size:0.9rem;">✕</button>
                    </div>
                    <div style="font-size:0.7rem; opacity:0.6; margin-top:4px;">
                        Pos: (${p.x}, ${p.y}) | Rango: ${p.range}
                    </div>
                </div>
            `).join('');

            leftColSpawnsHtml = mapCfg.spawns.map((s, idx) => `
                <div onclick="selectArenaSpawn(${idx})" style="background:${activeArenaSpawnIndex === idx ? 'rgba(236,72,153,0.15)' : 'rgba(255,255,255,0.02)'}; border:1px solid ${activeArenaSpawnIndex === idx ? 'var(--pink)' : 'rgba(255,255,255,0.06)'}; border-radius:8px; padding:10px; cursor:pointer; margin-bottom:8px; transition:all 0.2s;">
                    <div style="display:flex; justify-content:space-between; align-items:center;">
                        <span style="color:${s.team === 'red' ? '#ff3131' : '#31b6ff'}; font-weight:bold; font-size:0.8rem;">${s.name || 'Spawn ' + (idx + 1)}</span>
                        <button onclick="event.stopPropagation(); removeArenaSpawn(${idx});" style="background:none; border:none; color:var(--danger); cursor:pointer; font-size:0.9rem;">✕</button>
                    </div>
                    <div style="font-size:0.7rem; opacity:0.6; margin-top:4px;">
                        Pos: (${s.x}, ${s.y}) | Radio: ${s.radius}px
                    </div>
                </div>
            `).join('');

            if (activeArenaPillarIndex !== null && mapCfg.pillars[activeArenaPillarIndex]) {
                const pil = mapCfg.pillars[activeArenaPillarIndex];
                pillarDetailHtml = `
                    <div class="card" style="margin:0; border-top:3px solid var(--accent);">
                        <h4 style="color:var(--accent); margin-bottom:1rem;">🗼 DETALLES DEL PILAR</h4>
                        <div class="form-grid" style="grid-template-columns:1fr; gap:10px;">
                            <div class="field"><label>Nombre del Pilar</label>
                                <input type="text" value="${pil.name}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].name = this.value; renderModes();">
                            </div>
                            <div class="field"><label>Equipo Propietario</label>
                                <select onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].team = this.value; renderModes();">
                                    <option value="red" ${pil.team === 'red' ? 'selected' : ''}>Rojo (Red)</option>
                                    <option value="blue" ${pil.team === 'blue' ? 'selected' : ''}>Azul (Blue)</option>
                                </select>
                            </div>
                            <div style="display:grid; grid-template-columns:1fr 1fr; gap:10px;">
                                <div class="field"><label>Coord X</label><input type="number" id="pillar-x" value="${pil.x}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].x = parseInt(this.value); renderModes();"></div>
                                <div class="field"><label>Coord Y</label><input type="number" id="pillar-y" value="${pil.y}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].y = parseInt(this.value); renderModes();"></div>
                            </div>
                            <div style="display:grid; grid-template-columns:1fr 1fr; gap:10px;">
                                <div class="field"><label>Daño por Disparo</label><input type="number" value="${pil.damage}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].damage = parseInt(this.value); renderModes();"></div>
                                <div class="field"><label>Rango de Ataque</label><input type="number" value="${pil.range}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].range = parseInt(this.value); renderModes();"></div>
                            </div>
                            <div class="field"><label>Tipo de Munición</label>
                                <select onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].ammoType = this.value; renderModes();">
                                    <option value="laser" ${pil.ammoType === 'laser' ? 'selected' : ''}>🔦 Láser</option>
                                    <option value="missile" ${pil.ammoType === 'missile' ? 'selected' : ''}>🚀 Misil</option>
                                    <option value="mine" ${pil.ammoType === 'mine' ? 'selected' : ''}>💣 Mina</option>
                                </select>
                            </div>
                            <div class="field"><label>Tipo de Ataque</label>
                                <select onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].attackType = this.value; renderModes();">
                                    <option value="fast" ${pil.attackType === 'fast' ? 'selected' : ''}>⚡ Rápido (1s CD)</option>
                                    <option value="heavy" ${pil.attackType === 'heavy' ? 'selected' : ''}>💥 Pesado (2s CD)</option>
                                    <option value="area" ${pil.attackType === 'area' ? 'selected' : ''}>🌀 Área (1.5s CD)</option>
                                </select>
                            </div>
                        </div>
                    </div>
                `;
            } else {
                pillarDetailHtml = `
                    <div class="card" style="margin:0; opacity:0.6; display:flex; align-items:center; justify-content:center; height:100%; border:1px dashed rgba(255,255,255,0.1);">
                        <p style="text-align:center; font-style:italic; font-size:0.85rem;">Selecciona un pilar de la lista o el Canvas para editar sus propiedades.</p>
                    </div>
                `;
            }

            if (activeArenaSpawnIndex !== null && mapCfg.spawns[activeArenaSpawnIndex]) {
                const sp = mapCfg.spawns[activeArenaSpawnIndex];
                spawnDetailHtml = `
                    <div class="card" style="margin:0; border-top:3px solid var(--pink);">
                        <h4 style="color:var(--pink); margin-bottom:1rem;">📍 DETALLES DEL SPAWN</h4>
                        <div class="form-grid" style="grid-template-columns:1fr; gap:10px;">
                            <div class="field"><label>Nombre del Spawn</label>
                                <input type="text" value="${sp.name || ''}" placeholder="Ej: Spawn Rojo 1" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].spawns[activeArenaSpawnIndex].name = this.value; renderModes();">
                            </div>
                            <div class="field"><label>Equipo Destinatario</label>
                                <select onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].spawns[activeArenaSpawnIndex].team = this.value; renderModes();">
                                    <option value="red" ${sp.team === 'red' ? 'selected' : ''}>Rojo (Red)</option>
                                    <option value="blue" ${sp.team === 'blue' ? 'selected' : ''}>Azul (Blue)</option>
                                </select>
                            </div>
                            <div style="display:grid; grid-template-columns:1fr 1fr; gap:10px;">
                                <div class="field"><label>Coord X</label><input type="number" id="spawn-x" value="${sp.x}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].spawns[activeArenaSpawnIndex].x = parseInt(this.value); renderModes();"></div>
                                <div class="field"><label>Coord Y</label><input type="number" id="spawn-y" value="${sp.y}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].spawns[activeArenaSpawnIndex].y = parseInt(this.value); renderModes();"></div>
                            </div>
                            <div class="field">
                                <label>Radio en Píxeles (Burbuja)</label>
                                <input type="number" value="${sp.radius || 200}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].spawns[activeArenaSpawnIndex].radius = parseInt(this.value); renderModes();">
                            </div>
                        </div>
                    </div>
                `;
            } else {
                spawnDetailHtml = `
                    <div class="card" style="margin:0; opacity:0.6; display:flex; align-items:center; justify-content:center; height:100%; border:1px dashed rgba(255,255,255,0.1);">
                        <p style="text-align:center; font-style:italic; font-size:0.85rem;">Selecciona un spawn de la lista o el Canvas para editar sus propiedades.</p>
                    </div>
                `;
            }

            content.innerHTML = `
            <!-- PARTE 1: REGLAS Y MAPAS -->
            <div style="grid-column: 1 / -1; display:grid; grid-template-columns: 1.2fr 0.8fr; gap:20px;">
                <div class="card" style="margin:0;">
                    <h3 style="color:#ff3131; margin-bottom: 0.5rem;">⚔️ MODO ARENAS (PVP)</h3>
                    <p style="opacity:0.7; margin-bottom:1.5rem;">Configura el emparejamiento básico y tiempos del modo arenas.</p>
                    <div class="form-grid" style="grid-template-columns: repeat(4, 1fr); gap:10px;">
                        <div class="field">
                            <label>Estado del Modo</label>
                            <select onchange="config.gameModes.arenas.enabled = this.value === 'true'">
                                <option value="true" ${config.gameModes.arenas.enabled ? 'selected' : ''}>Activo</option>
                                <option value="false" ${!config.gameModes.arenas.enabled ? 'selected' : ''}>Inactivo</option>
                            </select>
                        </div>
                        <div class="field">
                            <label>Pilotos Mínimos</label>
                            <input type="number" value="${config.gameModes.arenas.minPlayers || 2}" onchange="config.gameModes.arenas.minPlayers = parseInt(this.value)">
                        </div>
                        <div class="field">
                            <label>Pilotos Máximos</label>
                            <input type="number" value="${config.gameModes.arenas.maxPlayers || 6}" onchange="config.gameModes.arenas.maxPlayers = parseInt(this.value)">
                        </div>
                        <div class="field">
                            <label>Selección Respawn</label>
                            <select onchange="config.gameModes.arenas.spawnMode = this.value">
                                <option value="random" ${config.gameModes.arenas.spawnMode === 'random' ? 'selected' : ''}>🎲 Aleatorio (Random)</option>
                                <option value="closest" ${config.gameModes.arenas.spawnMode === 'closest' ? 'selected' : ''}>📍 Más Cercano (Closest)</option>
                                <option value="first" ${config.gameModes.arenas.spawnMode === 'first' ? 'selected' : ''}>1️⃣ Primer Spawn (First)</option>
                            </select>
                        </div>
                        <div class="field">
                            <label>Duración Partida (ms)</label>
                            <input type="number" step="1000" value="${config.gameModes.arenas.matchDuration || 600000}" onchange="config.gameModes.arenas.matchDuration = parseInt(this.value)">
                        </div>
                        <div class="field">
                            <label>Bloqueo Spawn (ms)</label>
                            <input type="number" step="1000" value="${config.gameModes.arenas.spawnLockTime || 10000}" onchange="config.gameModes.arenas.spawnLockTime = parseInt(this.value)">
                        </div>
                        <div class="field">
                            <label>Invul. al Revivir (ms)</label>
                            <input type="number" step="500" value="${config.gameModes.arenas.respawnInvulnerabilityMs || 3000}" onchange="config.gameModes.arenas.respawnInvulnerabilityMs = parseInt(this.value)">
                        </div>
                    </div>
                </div>

                <div class="card" style="margin:0;">
                    <h3 style="color:var(--primary); margin-bottom: 0.5rem;">🏟️ MAPAS DE ARENAS</h3>
                    <p style="opacity:0.6; margin-bottom:1.5rem;">Selecciona y añade mapas PvP competitivos.</p>
                    <div style="display:flex; gap:10px; margin-bottom:15px;">
                        <select id="arena-map-select-add" style="font-size:0.8rem; flex:1;">
                            <option value="" disabled selected hidden>🔍 Seleccionar mapa...</option>
                            ${Object.keys(config.mapsConfig).map(id => `<option value="${id}">${config.mapsConfig[id].name} (ID ${id})</option>`).join('')}
                        </select>
                        <button class="btn btn-primary" style="padding:4px 15px; font-size:0.7rem;" onclick="addArenaMap(document.getElementById('arena-map-select-add').value)">+ AÑADIR MAPA</button>
                    </div>
                    
                    <div style="display:flex; gap:10px; align-items:center;">
                        <label style="font-weight:bold; font-size:0.8rem;">Mapa Activo para Configurar:</label>
                        <select onchange="selectArenaMap(this.value)" style="font-size:0.8rem; flex:1; max-width:200px;">
                            <option value="">Ninguno</option>
                            ${config.gameModes.arenas.maps.map(id => `<option value="${id}" ${activeArenaMapId === id ? 'selected' : ''}>${config.mapsConfig[id]?.name || 'ID '+id}</option>`).join('')}
                        </select>
                    </div>
                </div>
            </div>

            <!-- PARTE 2: CONFIGURACIÓN ESPECÍFICA DEL MAPA -->
            ${mapCfg ? `
                <div style="grid-column: 1 / -1; display:grid; grid-template-columns: 1fr 1.2fr; gap:20px; margin-top:10px;">
                    <div class="card" style="margin:0; max-height: 520px; overflow-y: auto;">
                        <h4 style="color:#ff3131; margin-bottom:1rem;">📐 DIMENSIONES (MAPA ${activeArenaMapId})</h4>
                        <div class="form-grid" style="grid-template-columns:1fr 1fr; gap:10px; margin-bottom:15px;">
                            <div class="field"><label>Ancho (W px)</label><input type="number" value="${mapCfg.width || 10000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].width = parseInt(this.value); renderModes();"></div>
                            <div class="field"><label>Alto (H px)</label><input type="number" value="${mapCfg.height || 10000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].height = parseInt(this.value); renderModes();"></div>
                        </div>

                        <!-- NEXO ROJO -->
                        <h5 style="color:#ff3131; border-bottom:1px solid rgba(255,49,49,0.2); padding-bottom:4px; margin-bottom:10px;">🔴 NEXO ROJO (RED)</h5>
                        <div class="form-grid" style="grid-template-columns:1fr 1fr; gap:10px; margin-bottom:15px;">
                            <div class="field"><label>Vida Máx</label><input type="number" value="${mapCfg.nexusRed?.hp || 10000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusRed.hp = parseInt(this.value)"></div>
                            <div class="field"><label>Escudo Máx</label><input type="number" value="${mapCfg.nexusRed?.shield || 5000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusRed.shield = parseInt(this.value)"></div>
                            <div class="field"><label>Posición X</label><input type="number" id="nexus-red-x" value="${mapCfg.nexusRed?.x || 2000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusRed.x = parseInt(this.value); renderModes();"></div>
                            <div class="field"><label>Posición Y</label><input type="number" id="nexus-red-y" value="${mapCfg.nexusRed?.y || 5000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusRed.y = parseInt(this.value); renderModes();"></div>
                        </div>

                        <!-- NEXO AZUL -->
                        <h5 style="color:#31b6ff; border-bottom:1px solid rgba(49,182,255,0.2); padding-bottom:4px; margin-bottom:10px; margin-top:10px;">🔵 NEXO AZUL (BLUE)</h5>
                        <div class="form-grid" style="grid-template-columns:1fr 1fr; gap:10px; margin-bottom:15px;">
                            <div class="field"><label>Vida Máx</label><input type="number" value="${mapCfg.nexusBlue?.hp || 10000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusBlue.hp = parseInt(this.value)"></div>
                            <div class="field"><label>Escudo Máx</label><input type="number" value="${mapCfg.nexusBlue?.shield || 5000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusBlue.shield = parseInt(this.value)"></div>
                            <div class="field"><label>Posición X</label><input type="number" id="nexus-blue-x" value="${mapCfg.nexusBlue?.x || 8000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusBlue.x = parseInt(this.value); renderModes();"></div>
                            <div class="field"><label>Posición Y</label><input type="number" id="nexus-blue-y" value="${mapCfg.nexusBlue?.y || 5000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusBlue.y = parseInt(this.value); renderModes();"></div>
                        </div>

                        <!-- CONFIGURACIÓN DE RECURSOS 3D -->
                        <h5 style="color:var(--accent); border-bottom:1px solid rgba(6,182,212,0.2); padding-bottom:4px; margin-bottom:10px; margin-top:15px;">📦 ASSETS 3D AUTORITATIVOS</h5>
                        <div class="form-grid" style="grid-template-columns:1fr; gap:10px;">
                            <div class="field"><label>Ruta Asset Nexos (.glb)</label>
                                <input type="text" value="${mapCfg.nexusAsset || 'E:\\\\Descon\\\\descon\\\\assets\\\\Arenas PVP\\\\3D\\\\Nexos\\\\Nexo1\\\\Nexo1.glb'}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusAsset = this.value">
                            </div>
                            <div class="field"><label>Ruta Asset Pilares/Torres (.glb)</label>
                                <input type="text" value="${mapCfg.pillarAsset || 'E:\\\\Descon\\\\descon\\\\assets\\\\Arenas PVP\\\\3D\\\\Torres\\\\Torre1\\\\Torre1.glb'}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillarAsset = this.value">
                            </div>
                        </div>
                    </div>

                    <div class="card" style="margin:0; display:flex; flex-direction:column; justify-content:center; align-items:center;">
                        <h4 style="color:var(--primary); margin-bottom:1rem; align-self:flex-start;">🗺️ RADAR INTERACTIVO DE LA ARENA</h4>
                        <div id="arena-radar-container" style="position:relative; width:100%; max-width:480px; height:330px; background:#000; border:2px solid var(--primary); border-radius:10px; overflow:hidden; cursor:crosshair; box-shadow: 0 0 20px rgba(0, 210, 255, 0.15);">
                            <canvas id="arena-radar-canvas" style="width: 100%; height: 100%; display: block;"></canvas>
                        </div>
                        <div style="display:flex; gap:15px; margin-top:10px; font-size:0.75rem;">
                            <span>🔴 Nexo Rojo</span>
                            <span>🔵 Nexo Azul</span>
                            <span>⚪ Torres</span>
                            <span>🛡️ Spawns</span>
                        </div>
                    </div>
                </div>

                <!-- SECCIÓN DE CONFIGURACIÓN DE PILARES DE DEFENSA -->
                <div style="grid-column: 1 / -1; display:grid; grid-template-columns: 1fr 1.2fr 1fr; gap:20px; margin-top:20px; border-top:1px solid rgba(255,255,255,0.05); padding-top:20px;">
                    <!-- LISTADO DE PILARES -->
                    <div class="card" style="margin:0;">
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                            <h4 style="color:var(--primary); margin:0;">🗼 PILARES DE DEFENSA</h4>
                            <button class="btn btn-primary" style="padding:4px 10px; font-size:0.65rem;" onclick="addArenaPillar()">+ AÑADIR PILAR</button>
                        </div>
                        <div style="max-height:300px; overflow-y:auto; padding-right:5px;">
                            ${leftColPillarsHtml || '<p style="font-style:italic; font-size:0.8rem; opacity:0.6;">No hay pilares creados aún.</p>'}
                        </div>
                    </div>

                    <!-- EXPLICACIÓN RADAR -->
                    <div class="card" style="margin:0; display:flex; flex-direction:column; justify-content:center; align-items:center;">
                        <div style="font-size:0.8rem; text-align:center; padding:10px;">
                            <p style="font-weight:bold; color:var(--accent); font-size:0.95rem; margin-bottom:10px;">💡 CÓMO USAR EL RADAR DE ARENAS</p>
                            <p style="opacity:0.8; margin-bottom:5px;">1. **Arrastra** los Nexos Rojo y Azul para ubicarlos en el plano 2D.</p>
                            <p style="opacity:0.8; margin-bottom:5px;">2. **Añade** pilares y spawns, y **arrástralos** a su posición ideal en el Canvas.</p>
                            <p style="opacity:0.8; margin-bottom:5px;">3. Selecciona cualquier pilar o spawn para editar sus propiedades avanzadas.</p>
                        </div>
                    </div>

                    <!-- EDICIÓN DE PILAR DETALLE -->
                    <div style="display:flex; flex-direction:column;">
                        ${pillarDetailHtml}
                    </div>
                </div>

                <!-- SECCIÓN DE CONFIGURACIÓN DE PUNTOS DE RESPAWN -->
                <div style="grid-column: 1 / -1; display:grid; grid-template-columns: 1fr 1.2fr 1fr; gap:20px; margin-top:20px; border-top:1px solid rgba(255,255,255,0.05); padding-top:20px;">
                    <!-- LISTADO DE SPAWNS -->
                    <div class="card" style="margin:0;">
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                            <h4 style="color:var(--pink); margin:0;">📍 PUNTOS DE RESPAWN</h4>
                            <button class="btn btn-primary" style="padding:4px 10px; font-size:0.65rem; background:var(--pink); border-color:var(--pink);" onclick="addArenaSpawn()">+ AÑADIR SPAWN</button>
                        </div>
                        <div style="max-height:300px; overflow-y:auto; padding-right:5px;">
                            ${leftColSpawnsHtml || '<p style="font-style:italic; font-size:0.8rem; opacity:0.6;">No hay spawns creados aún.</p>'}
                        </div>
                    </div>

                    <div class="card" style="margin:0; opacity:0.4; display:flex; align-items:center; justify-content:center; height:100%; border:1px dashed rgba(255,255,255,0.1);">
                        <p style="text-align:center; font-style:italic; font-size:0.85rem;">Puedes crear múltiples zonas de reaparición para cada facción.</p>
                    </div>

                    <!-- EDICIÓN DE SPAWN DETALLE -->
                    <div style="display:flex; flex-direction:column;">
                        ${spawnDetailHtml}
                    </div>
                </div>
            ` : `
                <div class="card" style="grid-column: span 2; margin-top:10px; text-align:center; padding:40px; border:1px dashed rgba(255,255,255,0.1);">
                    <p style="font-style:italic; opacity:0.7;">Por favor, añade o selecciona un mapa de arena de la lista superior para comenzar a configurar.</p>
                </div>
            `}
        `;

        if (mapCfg) {
            setTimeout(initArenaRadar, 100);
        }
    }
}
}

function initArenaRadar() {
    const canvas = document.getElementById('arena-radar-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const container = document.getElementById('arena-radar-container');
    
    if (!activeArenaMapId) return;
    const mapCfg = config.gameModes.arenas.mapConfigs[activeArenaMapId];
    if (!mapCfg) return;

    const worldW = mapCfg.width || 10000;
    const worldH = mapCfg.height || 10000;

    let isDragging = false;
    let dragItem = null; // { type: 'nexus_red' | 'nexus_blue' | 'pillar' | 'spawn', index: idx }

    const updateCanvasSize = () => {
        const w = container.clientWidth;
        const h = container.clientHeight;
        if (w > 0 && h > 0) {
            canvas.width = w;
            canvas.height = h;
        }
    };
    updateCanvasSize();

    const worldToCanvas = (wx, wy) => ({
        x: (wx / worldW) * canvas.width,
        y: (wy / worldH) * canvas.height
    });

    const canvasToWorld = (cx, cy) => ({
        wx: (cx / canvas.width) * worldW,
        wy: (cy / canvas.height) * worldH
    });

    const draw = () => {
        ctx.fillStyle = '#05070a';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        // Draw grid
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
        ctx.lineWidth = 1;
        const gridCount = 10;
        for (let i = 1; i < gridCount; i++) {
            // vertical
            const x = (i / gridCount) * canvas.width;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, canvas.height);
            ctx.stroke();

            // horizontal
            const y = (i / gridCount) * canvas.height;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(canvas.width, y);
            ctx.stroke();
        }

        // Draw Spawns
        if (mapCfg.spawns) {
            mapCfg.spawns.forEach((s, idx) => {
                const pos = worldToCanvas(s.x, s.y);
                const isSelected = activeArenaSpawnIndex === idx;
                const rad = ((s.radius || 200) / worldW) * canvas.width;
                
                ctx.fillStyle = s.team === 'red' ? 'rgba(255, 49, 49, 0.05)' : 'rgba(49, 182, 255, 0.05)';
                ctx.strokeStyle = isSelected ? '#ffffff' : (s.team === 'red' ? 'rgba(255, 49, 49, 0.4)' : 'rgba(49, 182, 255, 0.4)');
                ctx.lineWidth = isSelected ? 2 : 1;
                ctx.setLineDash([2, 5]);
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, rad, 0, Math.PI * 2);
                ctx.fill();
                ctx.stroke();
                ctx.setLineDash([]);

                ctx.fillStyle = s.team === 'red' ? '#ff3131' : '#31b6ff';
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, 4, 0, Math.PI * 2);
                ctx.fill();

                ctx.fillStyle = '#ffffff';
                ctx.font = '8px sans-serif';
                ctx.textAlign = 'center';
                ctx.fillText(s.name || `Spawn ${idx + 1}`, pos.x, pos.y - 8);
            });
        }

        // Draw Red Nexus
        if (mapCfg.nexusRed) {
            const pos = worldToCanvas(mapCfg.nexusRed.x, mapCfg.nexusRed.y);
            ctx.fillStyle = 'rgba(255, 49, 49, 0.2)';
            ctx.strokeStyle = '#ff3131';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, 15, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            ctx.fillStyle = '#ff3131';
            ctx.font = 'bold 9px sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('NEXO ROJO', pos.x, pos.y - 20);
        }

        // Draw Blue Nexus
        if (mapCfg.nexusBlue) {
            const pos = worldToCanvas(mapCfg.nexusBlue.x, mapCfg.nexusBlue.y);
            ctx.fillStyle = 'rgba(49, 182, 255, 0.2)';
            ctx.strokeStyle = '#31b6ff';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, 15, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            ctx.fillStyle = '#31b6ff';
            ctx.font = 'bold 9px sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('NEXO AZUL', pos.x, pos.y - 20);
        }

        // Draw Pillars
        if (mapCfg.pillars) {
            mapCfg.pillars.forEach((p, idx) => {
                const pos = worldToCanvas(p.x, p.y);
                const isSelected = activeArenaPillarIndex === idx;
                
                ctx.strokeStyle = p.team === 'red' ? 'rgba(255, 49, 49, 0.25)' : 'rgba(49, 182, 255, 0.25)';
                ctx.lineWidth = isSelected ? 2 : 1;
                if (isSelected) {
                    ctx.setLineDash([4, 4]);
                } else {
                    ctx.setLineDash([]);
                }
                ctx.beginPath();
                const canvasRange = (p.range / worldW) * canvas.width;
                ctx.arc(pos.x, pos.y, canvasRange, 0, Math.PI * 2);
                ctx.stroke();
                ctx.setLineDash([]);

                if (isSelected) {
                    ctx.fillStyle = p.team === 'red' ? 'rgba(255, 49, 49, 0.03)' : 'rgba(49, 182, 255, 0.03)';
                    ctx.beginPath();
                    ctx.arc(pos.x, pos.y, canvasRange, 0, Math.PI * 2);
                    ctx.fill();
                }

                ctx.fillStyle = p.team === 'red' ? 'rgba(255, 49, 49, 0.4)' : 'rgba(49, 182, 255, 0.4)';
                ctx.strokeStyle = isSelected ? '#ffffff' : (p.team === 'red' ? '#ff3131' : '#31b6ff');
                ctx.lineWidth = isSelected ? 3 : 1.5;
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, 8, 0, Math.PI * 2);
                ctx.fill();
                ctx.stroke();

                ctx.fillStyle = '#ffffff';
                ctx.font = '8px monospace';
                ctx.textAlign = 'center';
                ctx.fillText(p.name, pos.x, pos.y - 12);
            });
        }
    };

    draw();

    canvas.onmousedown = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        // Check if clicked Red Nexus
        if (mapCfg.nexusRed) {
            const pos = worldToCanvas(mapCfg.nexusRed.x, mapCfg.nexusRed.y);
            if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 15) {
                isDragging = true;
                dragItem = { type: 'nexus_red' };
                canvas.style.cursor = 'grabbing';
                return;
            }
        }

        // Check if clicked Blue Nexus
        if (mapCfg.nexusBlue) {
            const pos = worldToCanvas(mapCfg.nexusBlue.x, mapCfg.nexusBlue.y);
            if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 15) {
                isDragging = true;
                dragItem = { type: 'nexus_blue' };
                canvas.style.cursor = 'grabbing';
                return;
            }
        }

        // Check if clicked a Pillar
        if (mapCfg.pillars) {
            for (let i = 0; i < mapCfg.pillars.length; i++) {
                const p = mapCfg.pillars[i];
                const pos = worldToCanvas(p.x, p.y);
                if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 12) {
                    isDragging = true;
                    dragItem = { type: 'pillar', index: i };
                    activeArenaPillarIndex = i;
                    activeArenaSpawnIndex = null;
                    canvas.style.cursor = 'grabbing';
                    draw();
                    return;
                }
            }
        }

        // Check if clicked a Spawn
        if (mapCfg.spawns) {
            for (let i = 0; i < mapCfg.spawns.length; i++) {
                const s = mapCfg.spawns[i];
                const pos = worldToCanvas(s.x, s.y);
                if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 12) {
                    isDragging = true;
                    dragItem = { type: 'spawn', index: i };
                    activeArenaSpawnIndex = i;
                    activeArenaPillarIndex = null;
                    canvas.style.cursor = 'grabbing';
                    draw();
                    return;
                }
            }
        }
    };

    canvas.onmousemove = (e) => {
        if (!isDragging || !dragItem) return;
        const rect = canvas.getBoundingClientRect();
        const mouseX = Math.max(0, Math.min(canvas.width, e.clientX - rect.left));
        const mouseY = Math.max(0, Math.min(canvas.height, e.clientY - rect.top));
        const world = canvasToWorld(mouseX, mouseY);

        if (dragItem.type === 'nexus_red') {
            mapCfg.nexusRed.x = Math.round(world.wx);
            mapCfg.nexusRed.y = Math.round(world.wy);
            const ix = document.getElementById('nexus-red-x');
            const iy = document.getElementById('nexus-red-y');
            if (ix) ix.value = mapCfg.nexusRed.x;
            if (iy) iy.value = mapCfg.nexusRed.y;
        } 
        else if (dragItem.type === 'nexus_blue') {
            mapCfg.nexusBlue.x = Math.round(world.wx);
            mapCfg.nexusBlue.y = Math.round(world.wy);
            const ix = document.getElementById('nexus-blue-x');
            const iy = document.getElementById('nexus-blue-y');
            if (ix) ix.value = mapCfg.nexusBlue.x;
            if (iy) iy.value = mapCfg.nexusBlue.y;
        } 
        else if (dragItem.type === 'pillar') {
            const p = mapCfg.pillars[dragItem.index];
            if (p) {
                p.x = Math.round(world.wx);
                p.y = Math.round(world.wy);
                const ix = document.getElementById('pillar-x');
                const iy = document.getElementById('pillar-y');
                if (ix) ix.value = p.x;
                if (iy) iy.value = p.y;
            }
        }
        else if (dragItem.type === 'spawn') {
            const s = mapCfg.spawns[dragItem.index];
            if (s) {
                s.x = Math.round(world.wx);
                s.y = Math.round(world.wy);
                const ix = document.getElementById('spawn-x');
                const iy = document.getElementById('spawn-y');
                if (ix) ix.value = s.x;
                if (iy) iy.value = s.y;
            }
        }
        draw();
    };

    const stopDrag = () => {
        if (isDragging) {
            isDragging = false;
            dragItem = null;
            canvas.style.cursor = 'crosshair';
            renderModes();
        }
    };

    canvas.onmouseup = stopDrag;
    canvas.onmouseleave = stopDrag;
}
window.initArenaRadar = initArenaRadar;

window.renderHousing = function() {
    if (!config.housingConfig) {
        config.housingConfig = JSON.parse(JSON.stringify(DEFAULT_HOUSING_CONFIG));
    }
    const hc = config.housingConfig;
    
    // Rellenar campos globales
    const minLvlInput = document.getElementById('housing-min-level');
    if (minLvlInput) minLvlInput.value = hc.levelRequired || 1;
    
    const costInput = document.getElementById('housing-cost');
    if (costInput) costInput.value = hc.cost || 0;
    
    const currencySelect = document.getElementById('housing-currency');
    if (currencySelect) currencySelect.value = hc.currency || 'hubs';
    
    const gridSizeInput = document.getElementById('housing-grid-size');
    if (gridSizeInput) gridSizeInput.value = hc.gridSize || 10;
    
    // Render catálogo de items
    const list = document.getElementById('housing-items-list');
    if (!list) return;
    list.innerHTML = '';
    
    const f = getFilter();
    
    (hc.placeableItems || []).forEach((item, idx) => {
        if (f && !item.name.toLowerCase().includes(f) && !item.id.toLowerCase().includes(f)) return;
        
        const div = document.createElement('div');
        div.className = 'card';
        div.style.background = 'rgba(255,255,255,0.02)';
        div.style.padding = '1.5rem';
        div.style.border = '1px solid rgba(255,255,255,0.05)';
        div.style.position = 'relative';
        
        div.innerHTML = `
            <div style="position:absolute; top:15px; right:15px;">
                <button class="btn btn-secondary" style="background:var(--danger); border:none; padding:4px 10px;" onclick="removeHousingItem(${idx})">✕ ELIMINAR</button>
            </div>
            <div class="form-grid" style="display:grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap:15px;">
                <div class="field"><label>ID Objeto</label><input type="text" value="${item.id}" onchange="config.housingConfig.placeableItems[${idx}].id = this.value"></div>
                <div class="field"><label>Nombre</label><input type="text" value="${item.name}" onchange="config.housingConfig.placeableItems[${idx}].name = this.value"></div>
                <div class="field"><label>Costo</label><input type="number" value="${item.cost}" onchange="config.housingConfig.placeableItems[${idx}].cost = parseInt(this.value)"></div>
                <div class="field">
                    <label>Moneda</label>
                    <select onchange="config.housingConfig.placeableItems[${idx}].currency = this.value" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%; cursor:pointer;">
                        <option value="hubs" ${item.currency === 'hubs' ? 'selected' : ''}>HUBS</option>
                        <option value="ohcu" ${item.currency === 'ohcu' ? 'selected' : ''}>OHCU</option>
                    </select>
                </div>
            </div>
            
            <div class="field full" style="margin-top:15px;">
                <label>Ruta Modelo 3D (.glb)</label>
                <div style="display:flex; gap:8px; align-items:center; width:100%;">
                    <input type="text" value="${item.model}" onchange="config.housingConfig.placeableItems[${idx}].model = this.value" style="font-family:'JetBrains Mono'; flex-grow:1; margin:0;">
                    <button class="btn btn-primary" style="padding:8px 12px; font-size:0.75rem; flex-shrink:0; background:var(--accent); border-color:var(--accent);" onclick="triggerAssetUpload(${idx}, 'housing_glb')">📁 SELECCIONAR GLB</button>
                </div>
            </div>

            <h5 style="color:var(--accent); margin:15px 0 5px; font-size:0.75rem; border-bottom:1px solid rgba(6,182,212,0.15); padding-bottom:2px;">⚙️ ROTACIÓN 3D INICIAL</h5>
            <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr 1fr; gap:10px; margin-bottom:15px; display:grid; align-items:center;">
                <div class="field"><label>Rotación X (grados)</label><input type="number" value="${item.rotX || 0}" onchange="config.housingConfig.placeableItems[${idx}].rotX = parseFloat(this.value) || 0"></div>
                <div class="field"><label>Rotación Y (grados)</label><input type="number" value="${item.rotY || 0}" onchange="config.housingConfig.placeableItems[${idx}].rotY = parseFloat(this.value) || 0"></div>
                <div class="field"><label>Rotación Z (grados)</label><input type="number" value="${item.rotZ || 0}" onchange="config.housingConfig.placeableItems[${idx}].rotZ = parseFloat(this.value) || 0"></div>
                <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px; padding:0;">
                    <input type="checkbox" id="item-light-${idx}" ${item.isLight ? 'checked' : ''} onchange="config.housingConfig.placeableItems[${idx}].isLight = this.checked">
                    <label for="item-light-${idx}" style="margin-bottom:0; cursor:pointer; font-weight:bold;">¿Luz Dinámica?</label>
                </div>
            </div>
        `;
        list.appendChild(div);
    });
};

window.addHousingItem = function() {
    if (!config.housingConfig.placeableItems) config.housingConfig.placeableItems = [];
    config.housingConfig.placeableItems.push({
        id: "decor_" + Date.now().toString().slice(-4),
        name: "Nuevo Objeto 3D",
        cost: 100,
        currency: "hubs",
        model: "res://assets/3d/decor.glb",
        rotX: 0,
        rotY: 0,
        rotZ: 0,
        isLight: false
    });
    renderHousing();
};

window.removeHousingItem = function(idx) {
    if (!config.housingConfig.placeableItems) return;
    config.housingConfig.placeableItems.splice(idx, 1);
    renderHousing();
};

if (!window._questCollapsed) window._questCollapsed = {};
window.toggleQuestCollapse = function(idx) {
    window._questCollapsed[idx] = !window._questCollapsed[idx];
    const chevron = document.getElementById('qchevron-' + idx);
    const body = document.getElementById('qbody-' + idx);
    if (chevron) chevron.classList.toggle('collapsed', !!window._questCollapsed[idx]);
    if (body) body.classList.toggle('collapsed', !!window._questCollapsed[idx]);
};
window.toggleAllQuests = function(collapse) {
    config.questsConfig.forEach((_, i) => { window._questCollapsed[i] = collapse; });
    renderQuests();
};

window.renderQuests = function() {
    if (!config.questsConfig) {
        config.questsConfig = JSON.parse(JSON.stringify(DEFAULT_QUESTS_CONFIG));
    }
    if (!config.questsGlobalConfig) {
        config.questsGlobalConfig = JSON.parse(JSON.stringify(DEFAULT_QUESTS_GLOBAL_CONFIG));
    }

    const maxActiveInput = document.getElementById('quests-max-active');
    if (maxActiveInput) {
        maxActiveInput.value = config.questsGlobalConfig.maxActiveQuests || 3;
    }
    
    const list = document.getElementById('quests-list');
    if (!list) return;
    list.innerHTML = '';
    
    const catOptionsHTML = window.getItemPickerCategoryOptions();
    
    const f = getFilter();
    
    config.questsConfig.forEach((quest, idx) => {
        if (f && !quest.name.toLowerCase().includes(f) && !quest.id.toLowerCase().includes(f) && !quest.desc.toLowerCase().includes(f)) return;
        
        const isCollapsed = !!window._questCollapsed[idx];
        
        const div = document.createElement('div');
        div.className = 'card';
        div.style.background = 'rgba(255,255,255,0.02)';
        div.style.padding = '0';
        div.style.border = '1px solid rgba(255,255,255,0.05)';
        div.style.position = 'relative';
        
        // Items render helper
        if (!quest.reward) quest.reward = { exp: 0, hubs: 0, ohcu: 0, items: [], unlocks: [] };
        if (!quest.reward.items) quest.reward.items = [];
        if (!quest.reward.unlocks) quest.reward.unlocks = [];
        if (quest.portalGate === undefined) quest.portalGate = "";

        // Estado del desplegable inline de ítems para esta misión
        const ip = window._inlineItemPicker;
        const ipOpen = !!(ip && ip.open && ip.idx === idx);
        const ipQuery = ipOpen ? (ip.query || '') : '';
        
        let rewardItemsHTML = (quest.reward.items || []).map((item, itemIdx) => {
            const iname = getItemCatalogName(item.id);
            const isKnown = window.getMasterItemCatalog().some(c => c.id === String(item.id));
            const isEditingThis = !!(ip && ip.open && ip.idx === idx && ip.itemIdx === itemIdx);
            return `
            <div style="display:flex; gap:8px; align-items:center; margin-bottom:5px; background:${isEditingThis ? 'rgba(0,210,255,0.12)' : 'rgba(255,255,255,0.02)'}; padding:5px; border-radius:6px; border:1px solid ${isEditingThis ? 'rgba(0,210,255,0.35)' : 'transparent'};">
                <div onclick="toggleInlineItemPicker(${idx}, ${itemIdx})" title="Clic para cambiar este ítem" style="flex:2; min-width:0; cursor:pointer; border-radius:6px; padding:4px 6px; transition:background 0.15s; ${isEditingThis ? 'background:rgba(0,210,255,0.08);' : ''}" onmouseover="if(!${isEditingThis}) this.style.background='rgba(0,210,255,0.08)'" onmouseout="if(!${isEditingThis}) this.style.background='transparent'">
                    <div style="font-size:0.78rem; color:#fff; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${iname}</div>
                    <div style="font-size:0.62rem; color:${isKnown ? '#5fd' : '#e88'}; font-family:'JetBrains Mono';">${item.id || '(sin id)'}</div>
                </div>
                <div class="field" style="margin:0; flex:1;" onclick="event.stopPropagation()"><label style="font-size:9px;">Cant.</label><input type="number" min="1" value="${item.qty}" style="font-size:0.75rem; padding:4px;" onchange="config.questsConfig[${idx}].reward.items[${itemIdx}].qty = Math.floor(Math.max(1, parseInt(this.value) || 1))"></div>
                <button class="btn" style="background:var(--danger); border:none; padding:4px 8px; font-size:10px; margin-top:15px; cursor:pointer;" onclick="event.stopPropagation(); config.questsConfig[${idx}].reward.items.splice(${itemIdx}, 1); renderQuests();" title="Quitar ítem">✕</button>
            </div>`;
        }).join('');

        // v600.0: Render de desbloqueos de recompensa (🔓)
        let unlockRowsHTML = (quest.reward.unlocks || []).map((u, uIdx) => {
            const uType = String(u.type || 'generic').toLowerCase();
            let targetField = '';
            if (uType === 'map') {
                let opts = `<option value="" ${!u.targetId ? 'selected' : ''}>-- Mapa --</option>`;
                for (let mid in config.mapsConfig) {
                    opts += `<option value="${mid}" ${String(u.targetId) === String(mid) ? 'selected' : ''}>[Sector ${mid}] ${config.mapsConfig[mid].name}</option>`;
                }
                targetField = `<select style="flex:2; min-width:130px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:4px; font-size:0.7rem;" onchange="config.questsConfig[${idx}].reward.unlocks[${uIdx}].targetId = this.value">${opts}</select>`;
            } else if (uType === 'skill') {
                let opts = `<option value="" ${!u.targetId ? 'selected' : ''}>-- Habilidad --</option>`;
                for (let sName in config.skillsData) {
                    opts += `<option value="${reqAttrEscape(sName)}" ${String(u.targetId) === String(sName) ? 'selected' : ''}>${reqAttrEscape((config.skillsData[sName].name || sName))}</option>`;
                }
                targetField = `<select style="flex:2; min-width:130px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:4px; font-size:0.7rem;" onchange="config.questsConfig[${idx}].reward.unlocks[${uIdx}].targetId = this.value">${opts}</select>`;
            } else if (uType === 'talent') {
                const lockedTalents = (config.talentsLockedConfig || []);
                if (lockedTalents.length > 0) {
                    let opts = `<option value="" ${!u.targetId ? 'selected' : ''}>-- Talento sellado --</option>`;
                    lockedTalents.forEach((t, ti) => {
                        const tKey = `${t.category}:${t.index}`;
                        opts += `<option value="${tKey}" ${String(u.targetId) === tKey ? 'selected' : ''}>⭐ ${reqAttrEscape(t.name || tKey)} (${tKey})</option>`;
                    });
                    targetField = `<select style="flex:2; min-width:130px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:4px; font-size:0.7rem;" onchange="config.questsConfig[${idx}].reward.unlocks[${uIdx}].targetId = this.value">${opts}</select>`;
                } else {
                    targetField = `<input type="text" value="${reqAttrEscape(u.targetId || '')}" placeholder="categoria:indice (ej: combat:0)" title="Primero declara talentos sellados en la pestaña Talentos" style="flex:2; min-width:130px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:4px; font-size:0.7rem;" onchange="config.questsConfig[${idx}].reward.unlocks[${uIdx}].targetId = this.value">`;
                }
            } else {
                const ph = (uType === 'item') ? 'ID del ítem (ej: w_laser_1)' : 'Clave personalizada';
                targetField = `<input type="text" value="${reqAttrEscape(u.targetId || '')}" placeholder="${ph}" style="flex:2; min-width:130px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:4px; font-size:0.7rem;" onchange="config.questsConfig[${idx}].reward.unlocks[${uIdx}].targetId = this.value">`;
            }
            const typeOptions = Object.keys(UNLOCK_TYPES_LIB).map(k => `<option value="${k}" ${uType === k ? 'selected' : ''}>${UNLOCK_TYPES_LIB[k].label}</option>`).join('');
            return `
                <div style="display:flex; gap:8px; align-items:center; margin-bottom:6px; background:rgba(255,255,255,0.02); padding:6px; border-radius:6px; flex-wrap:wrap;">
                    <select style="flex:1; min-width:120px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:4px; font-size:0.7rem;" onchange="config.questsConfig[${idx}].reward.unlocks[${uIdx}].type = this.value; config.questsConfig[${idx}].reward.unlocks[${uIdx}].targetId = ''; renderQuests();">${typeOptions}</select>
                    ${targetField}
                    <input type="text" value="${reqAttrEscape(u.label || '')}" placeholder="Nombre visible" title="Nombre que verá el jugador" style="flex:1; min-width:110px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:4px; font-size:0.7rem;" onchange="config.questsConfig[${idx}].reward.unlocks[${uIdx}].label = this.value">
                    <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:11px;" title="Quitar desbloqueo" onclick="config.questsConfig[${idx}].reward.unlocks.splice(${uIdx}, 1); renderQuests();">✕</button>
                </div>`;
        }).join('');

        // Generar Select HTML para Objetivo según el tipo
        let targetSelectorHTML = '';
        if (quest.targetType === 'explore') {
            let mapOptions = `<option value="" ${!quest.targetId ? 'selected' : ''}>-- Seleccionar Mapa --</option>`;
            for (let mapId in config.mapsConfig) {
                mapOptions += `<option value="${mapId}" ${String(quest.targetId).trim().toLowerCase() === String(mapId).trim().toLowerCase() ? 'selected' : ''}>[Sector ${mapId}] ${config.mapsConfig[mapId].name}</option>`;
            }
            targetSelectorHTML = `
                <div class="field">
                    <label>Mapa a Explorar</label>
                    <select onchange="config.questsConfig[${idx}].targetId = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                        ${mapOptions}
                    </select>
                </div>
                <div class="form-grid" style="grid-template-columns: 1fr 1fr; gap:10px; width: 100%;">
                    <div class="field"><label>Coordenada X (Opcional)</label><input type="number" value="${quest.targetX !== undefined ? quest.targetX : ''}" placeholder="Ej: 2000" onchange="config.questsConfig[${idx}].targetX = this.value ? Math.floor(parseInt(this.value)) : undefined"></div>
                    <div class="field"><label>Coordenada Y (Opcional)</label><input type="number" value="${quest.targetY !== undefined ? quest.targetY : ''}" placeholder="Ej: 2000" onchange="config.questsConfig[${idx}].targetY = this.value ? Math.floor(parseInt(this.value)) : undefined"></div>
                </div>
            `;
        } else if (quest.targetType === 'kill') {
            let enemyOptions = `<option value="" ${!quest.targetId ? 'selected' : ''}>-- Seleccionar Enemigo --</option>`;
            for (let enemyId in config.enemyModels) {
                // Traer absolutamente todos los monstruos incluyendo sub-tiers (1-D, 2-C, etc)
                enemyOptions += `<option value="${enemyId}" ${String(quest.targetId).trim().toLowerCase() === String(enemyId).trim().toLowerCase() ? 'selected' : ''}>[ID ${enemyId}] ${config.enemyModels[enemyId].name}</option>`;
            }
            targetSelectorHTML = `
                <div class="field">
                    <label>Monstruo / Enemigo</label>
                    <select onchange="config.questsConfig[${idx}].targetId = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                        ${enemyOptions}
                    </select>
                </div>
            `;
        } else if (quest.targetType === 'event') {
            const eventOptions = `
                <option value="" ${!quest.targetId ? 'selected' : ''}>-- Seleccionar Evento --</option>
                <option value="extraction_win" ${String(quest.targetId).trim().toLowerCase() === 'extraction_win' ? 'selected' : ''}>🏆 Ganar Extracción (F2)</option>
                <option value="altar_defense_win" ${String(quest.targetId).trim().toLowerCase() === 'altar_defense_win' ? 'selected' : ''}>🗼 Completar Defensa del Altar</option>
                <option value="arena_win" ${String(quest.targetId).trim().toLowerCase() === 'arena_win' ? 'selected' : ''}>⚔️ Ganar Arena PVP</option>
            `;
            targetSelectorHTML = `
                <div class="field">
                    <label>Evento Requerido</label>
                    <select onchange="config.questsConfig[${idx}].targetId = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                        ${eventOptions}
                    </select>
                </div>
            `;
        } else if (quest.targetType === 'housing') {
            let housingOptions = `<option value="" ${!quest.targetId ? 'selected' : ''}>-- Seleccionar Objeto --</option>`;
            if (config.housingConfig && Array.isArray(config.housingConfig.placeableItems)) {
                config.housingConfig.placeableItems.forEach(item => {
                    housingOptions += `<option value="${item.id}" ${String(quest.targetId).trim().toLowerCase() === String(item.id).trim().toLowerCase() ? 'selected' : ''}>🏠 ${item.name} (ID: ${item.id})</option>`;
                });
            }
            targetSelectorHTML = `
                <div class="field">
                    <label>Objeto de Housing</label>
                    <select onchange="config.questsConfig[${idx}].targetId = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                        ${housingOptions}
                    </select>
                </div>
            `;
        } else {
            // Recolectar items o genérico
            targetSelectorHTML = `
                <div class="field">
                    <label>ID del Ítem</label>
                    <input type="text" value="${quest.targetId || ''}" placeholder="Ej: w_laser_1" onchange="config.questsConfig[${idx}].targetId = this.value">
                </div>
            `;
        }

        // v600.2: Portal específico a sellar — formato "zona|etiqueta" (ej: "2|Puerta Norte")
        // Si no hay "|" → sella TODO el acceso al sector (compatibilidad con v600.1)
        const pgRaw = String(quest.portalGate || '');
        const pgParts = pgRaw.split('|');
        const pgZone = pgParts[0] || '';
        const pgLabel = pgParts.length > 1 ? pgParts.slice(1).join('|') : '';

        let pgZoneOptions = `<option value="" ${!pgZone ? 'selected' : ''}>-- Sector donde está el portal --</option>`;
        for (let mapId in config.mapsConfig) {
            pgZoneOptions += `<option value="${mapId}" ${String(pgZone) === String(mapId) ? 'selected' : ''}>[Sector ${mapId}] ${config.mapsConfig[mapId].name}</option>`;
        }

        let pgPortalOptions = '<option value="" disabled>Primero elegí el sector</option>';
        let pgDest = '';
        if (pgZone) {
            const zoneDoors = (config.mapsConfig[pgZone]?.objects || []).filter(o => o && o.type === 'door');
            const pgZoneOnlyMatch = (pgRaw === String(pgZone) || pgRaw === String(pgZone) + '|');
            pgPortalOptions = `<option value="${pgZone}" ${pgZoneOnlyMatch && !pgLabel ? 'selected' : ''}>🚫 Todo el acceso al Sector ${pgZone}</option>`;
            zoneDoors.forEach((d, di) => {
                const dLabel = String(d.label || ('Puerta ' + (di + 1)));
                const dDestName = d.targetZoneId ? `[Sector ${d.targetZoneId}] ${(config.mapsConfig[d.targetZoneId]?.name || '')}` : '?';
                const dVal = `${pgZone}|${dLabel}`;
                pgPortalOptions += `<option value="${dVal}" ${pgRaw === dVal ? 'selected' : ''}>🚪 ${dLabel} → ${dDestName}</option>`;
            });
            if (pgLabel) {
                const sealedDoor = zoneDoors.find(d => String(d.label || '') === pgLabel);
                if (sealedDoor && sealedDoor.targetZoneId) pgDest = String(sealedDoor.targetZoneId);
            }
            if (zoneDoors.length === 0) pgPortalOptions += '<option value="" disabled>⚠️ No hay portales (puertas) en este sector</option>';
        }

        let portalGateHint = 'El portal queda SELLADO SIEMPRE mientras exista esta misión configurada, y se desbloquea al COMPLETARLA (no hace falta aceptarla). Elegí "Todo el acceso" para bloquear todo el sector, o un portal específico para sellar SOLO ese portal (los demás siguen funcionando). Si quitás el portalGate, el portal queda libre.';
        if (pgLabel) portalGateHint = `🔒 Sella SIEMPRE el portal "${pgLabel}" del Sector ${pgZone} (los demás portales del sector siguen funcionando). Se desbloquea solo al completar esta misión.`;
        else if (pgZone) portalGateHint = `🔒 Sella SIEMPRE todo el acceso al Sector ${pgZone}. Se desbloquea solo al completar esta misión.`;
        if (quest.targetType === 'explore' && pgDest && String(quest.targetId) === pgDest) {
            portalGateHint = '⚠️ El objetivo de la misión es explorar el mismo destino del portal sellado: se permitirá la entrada (no se auto-bloquea).';
        }

        const targetTypeLabels = { kill: '⚔️ Matar', collect: '📦 Recolectar', explore: '🗺️ Explorar', event: '🏆 Evento', housing: '🏠 Housing' };
        const targetTypeLabel = targetTypeLabels[quest.targetType] || quest.targetType;
        const targetSummary = quest.targetId ? `${targetTypeLabel} ${quest.targetAmount || 1}x ${quest.targetId}` : targetTypeLabel;

        div.innerHTML = `
            <div class="quest-card-header" onclick="toggleQuestCollapse(${idx})">
                <span id="qchevron-${idx}" class="quest-card-chevron ${isCollapsed ? 'collapsed' : ''}">▼</span>
                <div class="quest-card-summary">
                    <span class="qcs-id">${quest.id || '?'}</span>
                    <span class="qcs-name">${quest.name || 'Sin nombre'}</span>
                    <span class="qcs-type" data-type="${quest.type}">${quest.type === 'story' ? 'Historia' : quest.type === 'daily' ? 'Diaria' : 'Semanal'}</span>
                    <span class="qcs-target">${targetSummary}</span>
                </div>
                <button class="btn btn-secondary" style="background:var(--danger); border:none; padding:4px 10px; font-size:0.7rem; white-space:nowrap; pointer-events:auto;" onclick="event.stopPropagation(); removeQuest(${idx})">✕ ELIMINAR</button>
            </div>
            <div id="qbody-${idx}" class="quest-card-body ${isCollapsed ? 'collapsed' : ''}" style="padding: 0 1.5rem 1.5rem 1.5rem;">
                <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:15px;">
                    <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr; gap:15px; flex:1;">
                        <div class="field"><label>ID Misión</label><input type="text" value="${quest.id}" onchange="config.questsConfig[${idx}].id = this.value"></div>
                        <div class="field"><label>Nombre</label><input type="text" value="${quest.name}" onchange="config.questsConfig[${idx}].name = this.value"></div>
                        <div class="field">
                            <label>Clasificación</label>
                            <select onchange="config.questsConfig[${idx}].type = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                                <option value="story" ${quest.type === 'story' ? 'selected' : ''}>Historia 📖</option>
                                <option value="daily" ${quest.type === 'daily' ? 'selected' : ''}>Diaria ⏳</option>
                                <option value="weekly" ${quest.type === 'weekly' ? 'selected' : ''}>Semanal 📅</option>
                            </select>
                        </div>
                    </div>
                </div>

                <div class="field" style="margin-top:12px;"><label>Descripción</label><input type="text" value="${quest.desc}" onchange="config.questsConfig[${idx}].desc = this.value"></div>

                <div style="display:grid; grid-template-columns: 1.15fr 1fr; gap:1.5rem; margin-top:1.5rem;">
                    <!-- ══ COLUMNA IZQUIERDA ══ -->
                    <div style="display:flex; flex-direction:column; gap:1.2rem;">
                        <!-- 🎯 OBJETIVO -->
                        <div style="border:1px solid rgba(0,210,255,0.15); border-radius:12px; padding:1rem 1.2rem; background:rgba(0,210,255,0.03);">
                            <h4 style="color:var(--accent); font-size:0.8rem; font-weight:bold; margin-bottom:12px;">🎯 OBJETIVO DE LA MISIÓN</h4>
                            <div class="form-grid" style="grid-template-columns: 1fr; gap:12px;">
                                <div class="field">
                                    <label>Tipo de Objetivo</label>
                                    <select onchange="config.questsConfig[${idx}].targetType = this.value; config.questsConfig[${idx}].targetId = ''; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                                        <option value="kill" ${quest.targetType === 'kill' ? 'selected' : ''}>⚔️ Matar Enemigos</option>
                                        <option value="collect" ${quest.targetType === 'collect' ? 'selected' : ''}>📦 Recolectar Ítems</option>
                                        <option value="explore" ${quest.targetType === 'explore' ? 'selected' : ''}>🗺️ Explorar Zona</option>
                                        <option value="event" ${quest.targetType === 'event' ? 'selected' : ''}>🏆 Evento Especial</option>
                                        <option value="housing" ${quest.targetType === 'housing' ? 'selected' : ''}>🏠 Colocar Housing</option>
                                    </select>
                                </div>
                                ${targetSelectorHTML}
                                <div class="field">
                                    <label>Cantidad Requerida</label>
                                    <input type="number" value="${quest.targetAmount || 1}" onchange="config.questsConfig[${idx}].targetAmount = Math.floor(Math.max(1, parseInt(this.value) || 1))">
                                </div>
                            </div>
                        </div>

                    </div>

                    <!-- ══ COLUMNA DERECHA: RECOMPENSAS ══ -->
                    <div style="border:1px solid rgba(0,255,170,0.15); border-radius:12px; padding:1rem 1.2rem; background:rgba(0,255,170,0.03); align-self:start;">
                        <h4 style="color:var(--success); font-size:0.8rem; font-weight:bold; margin-bottom:12px;">🎁 RECOMPENSAS</h4>
                        <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr; gap:10px; margin-bottom:15px;">
                            <div class="field"><label>EXP</label><input type="number" value="${quest.reward.exp}" onchange="config.questsConfig[${idx}].reward.exp = Math.floor(Math.max(0, parseInt(this.value) || 0))"></div>
                            <div class="field"><label>HUBS</label><input type="number" value="${quest.reward.hubs}" onchange="config.questsConfig[${idx}].reward.hubs = Math.floor(Math.max(0, parseInt(this.value) || 0))"></div>
                            <div class="field"><label>OHCU</label><input type="number" value="${quest.reward.ohcu}" onchange="config.questsConfig[${idx}].reward.ohcu = Math.floor(Math.max(0, parseInt(this.value) || 0))"></div>
                        </div>

                        <div>
                            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                <label style="font-size:0.75rem; color:#aaa; font-weight:bold;">📦 Ítems Recompensa</label>
                                <button class="btn btn-primary" style="padding:3px 10px; font-size:0.7rem;" onclick="toggleInlineItemPicker(${idx})">+ Agregar Ítem</button>
                            </div>
                            <div style="max-height:120px; overflow-y:auto; padding-right:5px;">
                                ${rewardItemsHTML}
                            </div>
                            <div id="item-inline-picker-${idx}" style="display:${ipOpen ? 'block' : 'none'}; margin-top:8px; border:1px solid rgba(0,210,255,0.25); border-radius:10px; padding:10px; background:rgba(0,210,255,0.05);">
                                <div id="item-inline-mode-${idx}" style="display:none; font-size:0.72rem; color:#9fe; font-weight:bold; margin-bottom:8px; padding:6px 10px; background:rgba(0,210,255,0.1); border-radius:6px;"></div>
                                <input id="item-inline-search-${idx}" type="text" placeholder="🔍 Buscar por nombre o ID (ej: Arma Laser)..." value="${ipQuery}" oninput="updateInlineItemPickerQuery(${idx}, this.value)" style="width:100%; box-sizing:border-box; background:rgba(255,255,255,0.06); border:1px solid rgba(255,255,255,0.14); border-radius:8px; padding:10px 14px; color:white; font-size:0.9rem; outline:none; margin-bottom:8px;">
                                <select id="item-inline-cat-${idx}" onchange="updateInlineItemPickerCat(${idx}, this.value)" style="width:100%; box-sizing:border-box; background:#0b0f19; border:1px solid rgba(255,255,255,0.12); color:white; padding:8px 12px; border-radius:8px; font-size:0.85rem; cursor:pointer; margin-bottom:8px;">
                                    ${catOptionsHTML}
                                </select>
                                <div id="item-inline-list-${idx}" style="max-height:240px; overflow-y:auto; display:flex; flex-direction:column; gap:6px; padding-right:4px;"></div>
                                <div style="margin-top:8px; text-align:right;">
                                    <button class="btn btn-secondary" style="padding:4px 14px; font-size:0.72rem;" onclick="toggleInlineItemPicker(${idx}, ${(ip && ip.itemIdx !== null && ip.itemIdx !== undefined) ? ip.itemIdx : 'null'})">CERRAR</button>
                                </div>
                            </div>
                            <div style="margin-top:10px; padding-top:10px; border-top:1px dashed rgba(255,255,255,0.1);">
                                <div style="display:flex; align-items:center; justify-content:space-between; gap:8px;">
                                    <label style="font-size:0.72rem; color:#9fe; font-weight:bold;">🎯 ¿Cuántos ítems puede elegir el usuario?</label>
                                    <input type="number" min="0" value="${quest.reward.selectableCount || 0}" style="width:64px; background:#0f172a; border:1px solid rgba(0,210,255,0.25); border-radius:6px; padding:4px 6px; color:white; font-size:0.78rem; text-align:center;" onchange="config.questsConfig[${idx}].reward.selectableCount = Math.max(0, parseInt(this.value) || 0); renderQuests();">
                                </div>
                                <div style="font-size:0.64rem; color:#889; margin-top:5px; line-height:1.45;">0 = se entregan <b>TODOS</b> automáticamente. Si ponés un número menor a la cantidad de ítems, al cobrar la misión el jugador elegirá esa cantidad (recompensa por elección).</div>
                            </div>
                        </div>

                        <div style="margin-top:1.2rem;">
                            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                <label style="font-size:0.75rem; color:#ffd700; font-weight:bold;">🔓 DESBLOQUEOS DE RECOMPENSA</label>
                                <button class="btn btn-primary" style="padding:2px 8px; font-size:9px; background:rgba(255,215,0,0.1); border:1px solid rgba(255,215,0,0.3);" onclick="config.questsConfig[${idx}].reward.unlocks.push({type:'map', targetId:'', label:''}); renderQuests();">+ Añadir Desbloqueo</button>
                            </div>
                            <div style="font-size:0.68rem; color:#888; margin-bottom:6px;">Habilita portales, armas, habilidades o talentos al completar la misión. Ej: 🗺️ Portal al Sector 2, 🔫 Cañón de Plasma, ⭐ Talento sellado.</div>
                            <div style="max-height:150px; overflow-y:auto; padding-right:5px;">
                                ${unlockRowsHTML || '<div style="font-size:0.68rem; opacity:0.45;">Sin desbloqueos: solo EXP, HUBS, OHCU e ítems.</div>'}
                            </div>
                        </div>

                        <!-- 🔒 PORTAL SELLADO (dentro de recompensas) -->
                        <div style="margin-top:1.2rem; padding-top:1rem; border-top:1px solid rgba(255,255,255,0.05);">
                            <label style="font-size:0.75rem; color:#ffb347; font-weight:bold; display:flex; align-items:center; gap:5px; margin-bottom:8px;">
                                <span style="font-size:10px;">🔒</span> PORTAL SELLADO (opcional)
                            </label>
                            <div class="form-grid" style="grid-template-columns: 1fr; gap:8px;">
                                <div class="field">
                                    <label>Sector donde está el portal</label>
                                    <select onchange="config.questsConfig[${idx}].portalGate = this.value === '' ? '' : this.value + '|'; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                                        ${pgZoneOptions}
                                    </select>
                                </div>
                                <div class="field">
                                    <label>Portal a sellar</label>
                                    <select onchange="config.questsConfig[${idx}].portalGate = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;" ${!pgZone ? 'disabled' : ''}>
                                        ${pgPortalOptions}
                                    </select>
                                </div>
                                <div style="font-size:9px; color:#888; margin-top:2px; line-height:1.5; padding:6px 8px; background:rgba(255,170,0,0.06); border-radius:6px;">${portalGateHint}</div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
        list.appendChild(div);
    });

    // Poblar el listado del desplegable inline si quedó abierto
    if (window._inlineItemPicker && window._inlineItemPicker.open) {
        window.renderInlineItemPickerList(window._inlineItemPicker.idx);
    }
};

window.addNewQuest = function() {
    if (!config.questsConfig) config.questsConfig = [];
    config.questsConfig.push({
        id: "quest_" + Date.now().toString().slice(-4),
        name: "Nueva Misión Galáctica",
        desc: "Descripción de la misión.",
        type: "story",
        targetType: "kill",
        targetId: "",
        targetAmount: 5,
        portalGate: "",
        reward: {
            exp: 100,
            hubs: 500,
            ohcu: 1,
            items: [],
            unlocks: []
        }
    });
    renderQuests();
};

window.removeQuest = function(idx) {
    if (!config.questsConfig) return;
    config.questsConfig.splice(idx, 1);
    renderQuests();
};

window.triggerAssetUpload = function(idx, type = 'resource') {
    const input = document.createElement('input');
    input.type = 'file';

    // Tipos que NO deben copiar el archivo — solo resuelven la ruta res://
    const resolveOnlyTypes = ['resource', 'recipe', 'ship_glb', 'ship_icon', 'housing_glb', 'skill_icon', 'skill_sound', 'talent_icon', 'weapon_icon', 'shield_icon', 'engine_icon', 'ammo_icon', 'ammo_sound', 'enemy_icon', 'enemy_glb', 'mechanic_sound', 'defense_sound', 'movement_sound', 'mechanic_instance_sound'];
    const isResolveOnly = resolveOnlyTypes.includes(type);

    if (type === 'ship_glb' || type === 'housing_glb' || type === 'enemy_glb') {
        input.accept = '.glb';
    } else if (type.includes('sound')) {
        input.accept = '.ogg,.wav,.mp3,audio/*';
    } else {
        input.accept = 'image/*';
    }

    input.onchange = async (e) => {
        const file = e.target.files[0];
        if (!file) return;

        const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';

        // ── MODO RESOLVE-ONLY: Solo buscar el archivo en el proyecto, sin copiarlo ──
        if (isResolveOnly) {
            try {
                const response = await fetch(`${activeURL}/api/find-asset?fileName=${encodeURIComponent(file.name)}`);
                const result = await response.json();

                if (result.success && result.path) {
                    if (type === 'resource') {
                        config.shopItems.resources[idx].icon = result.path;
                    } else if (type === 'recipe') {
                        config.craftingRecipes[idx].icon = result.path;
                    } else if (type === 'ship_icon') {
                        config.shipModels[idx].icon = result.path;
                    } else if (type === 'ship_glb') {
                        config.shipModels[idx].assetPath = result.path;
                    } else if (type === 'enemy_icon') {
                        config.enemyModels[idx].icon = result.path;
                    } else if (type === 'enemy_glb') {
                        config.enemyModels[idx].assetPath = result.path;
                    } else if (type === 'housing_glb') {
                        config.housingConfig.placeableItems[idx].model = result.path;
                    } else if (type === 'skill_icon') {
                        // idx = skill name (key in skillsData)
                        if (!config.skillsData[idx]) config.skillsData[idx] = {};
                        config.skillsData[idx].icon = result.path;
                    } else if (type === 'weapon_icon') {
                        config.shopItems.weapons[idx].icon = result.path;
                    } else if (type === 'shield_icon') {
                        config.shopItems.shields[idx].icon = result.path;
                    } else if (type === 'engine_icon') {
                        config.shopItems.engines[idx].icon = result.path;
                    } else if (type === 'ammo_icon') {
                        if (!config.shopItems.ammo_icons) config.shopItems.ammo_icons = {};
                        config.shopItems.ammo_icons[idx] = result.path;
                    } else if (type === 'talent_icon') {
                        config.talentsConfig.talents[idx].icon = result.path;
                    } else if (type === 'skill_sound') {
                        if (!config.skillsData[idx]) config.skillsData[idx] = {};
                        config.skillsData[idx].sound = result.path;
                    } else if (type === 'mechanic_sound') {
                        if (config.mechanicsLib && config.mechanicsLib[idx]) config.mechanicsLib[idx].sound = result.path;
                    } else if (type === 'defense_sound') {
                        if (config.defenseLib && config.defenseLib[idx]) config.defenseLib[idx].sound = result.path;
                    } else if (type === 'movement_sound') {
                        if (config.movementLib && config.movementLib[idx]) config.movementLib[idx].sound = result.path;
                    } else if (type === 'ammo_sound') {
                        // idx format "type_idx" e.g. "laser_0"
                        const parts = idx.split('_');
                        const aType = parts[0];
                        const aIdx = parseInt(parts.slice(1).join('_')) || 0;
                        if (config.shopItems?.ammo?.[aType]?.[aIdx]) config.shopItems.ammo[aType][aIdx].sound = result.path;
                    } else if (type === 'mechanic_instance_sound') {
                        // idx format "enemyId_listName_idx" e.g. "1_mechanics_0"
                        const segs = idx.split('_');
                        const mIdx = parseInt(segs.pop());
                        const listName = segs.pop();
                        const enemyId = segs.join('_');
                        if (config.enemyModels[enemyId] && config.enemyModels[enemyId][listName] && config.enemyModels[enemyId][listName][mIdx]) {
                            config.enemyModels[enemyId][listName][mIdx].sound = result.path;
                        }
                    }
                    if (type === 'ship_icon' || type === 'ship_glb') {
                        renderShips();
                    } else if (type === 'enemy_icon' || type === 'enemy_glb') {
                        renderEnemies();
                        renderEnemyDetail();
                    } else if (type === 'housing_glb') {
                        renderHousing();
                    } else if (type === 'weapon_icon') {
                        renderWeapons();
                    } else if (type === 'shield_icon') {
                        renderShields();
                    } else if (type === 'engine_icon') {
                        renderEngines();
                    } else if (type === 'ammo_icon') {
                        renderAmmo();
                    } else if (type === 'ammo_sound') {
                        renderAmmo();
                    } else if (type === 'skill_icon') {
                        renderSkills();
                    } else if (type === 'skill_sound') {
                        renderSkills();
                    } else if (type === 'mechanic_sound' || type === 'defense_sound' || type === 'movement_sound') {
                        renderMechanicsLib();
                    } else if (type === 'mechanic_instance_sound') {
                        renderEnemyDetail();
                    } else if (type === 'talent_icon') {
                        renderTalentCreator();
                    } else if (type === 'resource' || type === 'recipe') {
                        renderCrafting();
                    }
                } else {
                    alert('❌ ' + (result.error || 'No se pudo encontrar el archivo en los assets del proyecto.\n\nAsegurate de que el archivo ya esté copiado dentro de la carpeta descon/assets antes de seleccionarlo.'));
                }
            } catch (err) {
                console.error(err);
                alert('Error al conectar con el servidor local para resolver la ruta del asset.');
            }
            return; // No continuar con el flujo de upload
        }

        // ── MODO UPLOAD: Leer el archivo y copiarlo al servidor (crafteo / recursos) ──
        // v712: Normalizar la imagen a máx 1024px antes de subirla (compatibilidad AdminDash + juego)
        const normalizedFile = await normalizeImageForUpload(file, 1024);
        const reader = new FileReader();
        reader.onload = async () => {
            const base64Data = reader.result.split(',')[1];
            
            try {
                const response = await fetch(`${activeURL}/api/upload-asset`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        fileName: file.name,
                        fileData: base64Data
                    })
                });
                
                const result = await response.json();
                if (result.success && result.path) {
                    if (type === 'resource') {
                        config.shopItems.resources[idx].icon = result.path;
                    } else if (type === 'recipe') {
                        config.craftingRecipes[idx].icon = result.path;
                    }
                    
                    // Solicitar la lista de assets actualizada mediante socket
                    const activeSocket = (activeEnv === 'cloud') ? socketCloud : socketLocal;
                    if (activeSocket && activeSocket.connected) {
                        activeSocket.emit('getAssetFiles');
                    }
                    
                    alert('Asset importado con éxito!');
                    renderCrafting();
                } else {
                    alert('Error al importar el asset: ' + (result.error || 'Desconocido'));
                }
            } catch (err) {
                console.error(err);
                alert('Error al conectar con el servidor para subir el archivo.');
            }
        };
        reader.readAsDataURL(normalizedFile);
    };
    input.click();
};

// v712: Redimensiona una imagen a máx N px (preservando proporción) usando canvas.
// Devuelve un File normalizado (PNG si tenía transparencia, JPEG en caso contrario).
async function normalizeImageForUpload(file, maxDim) {
    if (!file || (file.type !== 'image/png' && file.type !== 'image/jpeg' && file.type !== 'image/webp')) return file;
    try {
        const url = URL.createObjectURL(file);
        const img = new Image();
        await new Promise((resolve, reject) => {
            img.onload = resolve;
            img.onerror = reject;
            img.src = url;
        });
        URL.revokeObjectURL(url);

        const w = img.naturalWidth || img.width;
        const h = img.naturalHeight || img.height;
        if (!w || !h) return file;
        if (Math.max(w, h) <= maxDim) return file;

        const scale = maxDim / Math.max(w, h);
        const nw = Math.max(1, Math.round(w * scale));
        const nh = Math.max(1, Math.round(h * scale));

        const canvas = document.createElement('canvas');
        canvas.width = nw;
        canvas.height = nh;
        const ctx = canvas.getContext('2d');
        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = 'high';
        ctx.drawImage(img, 0, 0, nw, nh);

        const mime = (file.type === 'image/jpeg') ? 'image/jpeg' : 'image/png';
        const blob = await new Promise(resolve => canvas.toBlob(resolve, mime, 0.92));
        if (!blob) return file;
        const baseName = file.name.replace(/\.(png|jpe?g|webp)$/i, '');
        const newName = baseName + (mime === 'image/jpeg' ? '.jpg' : '.png');
        return new File([blob], newName, { type: mime });
    } catch (e) {
        console.warn('[NORMALIZE] No se pudo normalizar, se sube original:', e);
        return file;
    }
}

// ─── ASSET PICKER ───────────────────────────────────────────────────────────
window._assetPickerState = { idx: 0, type: 'resource' };

window.openAssetPicker = function(idx, type) {
    window.triggerAssetUpload(idx, type);
};

window.closeAssetPicker = function() {
    const overlay = document.getElementById('asset-picker-overlay');
    if (overlay) overlay.style.display = 'none';
};

// Seleccionar GLB para un objeto del mundo (chest, door, tower, wall) sin copiar el archivo
window.triggerMapObjAssetPick = async function(mapId, objIdx) {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.glb,.png,.jpg,.webp';
    input.onchange = async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';
        try {
            const response = await fetch(`${activeURL}/api/find-asset?fileName=${encodeURIComponent(file.name)}`);
            const result = await response.json();
            if (result.success && result.path) {
                config.mapsConfig[mapId].objects[objIdx].assetPath = result.path;
                renderMapDetail();
            } else {
                alert('❌ ' + (result.error || 'Archivo no encontrado en los assets del proyecto.\n\nAsegurate de que el archivo ya esté dentro de la carpeta descon/assets.'));
            }
        } catch (err) {
            console.error(err);
            alert('Error al conectar con el servidor local.');
        }
    };
    input.click();
};

// ─── MÚSICA DE LA ZONA (Cartografía) ──────────────────────────────────────────
// Seleccionar el archivo de audio de un mapa (debe existir dentro de descon/assets)
window.pickMapMusic = function(mapId) {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.wav,.ogg,.mp3,.flac,audio/*';
    input.onchange = async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';
        try {
            const response = await fetch(`${activeURL}/api/find-asset?fileName=${encodeURIComponent(file.name)}`);
            const result = await response.json();
            if (result.success && result.path) {
                const m = config.mapsConfig[mapId];
                if (!m.music) m.music = { enabled: false, path: '', volumePercent: 60 };
                m.music.path = result.path;
                renderMapDetail();
            } else {
                alert('❌ ' + (result.error || 'Archivo no encontrado en los assets del proyecto.\n\nAsegurate de que el archivo esté dentro de la carpeta descon/assets (ej: descon/assets/Musica/).'));
            }
        } catch (err) {
            console.error(err);
            alert('Error al conectar con el servidor local.');
        }
    };
    input.click();
};

window.removeMapMusic = function(mapId) {
    const m = config.mapsConfig[mapId];
    if (!m) return;
    if (m.music) m.music.path = '';
    renderMapDetail();
};

window.toggleMapMusic = function(mapId, enabled) {
    const m = config.mapsConfig[mapId];
    if (!m) return;
    if (!m.music) m.music = { enabled: false, path: '', volumePercent: 60 };
    m.music.enabled = enabled;
    renderMapDetail();
};

window.setMapMusicVolume = function(mapId, value) {
    const m = config.mapsConfig[mapId];
    if (!m) return;
    if (!m.music) m.music = { enabled: false, path: '', volumePercent: 60 };
    let v = Math.max(0, Math.min(100, parseInt(value) || 0));
    m.music.volumePercent = v;
    const label = document.getElementById('map-music-vol-label');
    if (label) label.innerText = v + '%';
    const inp = document.getElementById('map-music-vol-input-' + mapId);
    if (inp) inp.value = v;
    const slider = document.getElementById('map-music-vol-slider-' + mapId);
    if (slider) slider.value = v;
};

// Confirm selection from asset picker
window.confirmAssetPicker = function() {
    const select = document.getElementById('asset-picker-select');
    if (!select) return;
    const chosen = select.value;
    if (chosen) {
        selectAssetFromPicker(chosen);
    }
};

window.filterAssetPicker = function() {
    const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';
    const select = document.getElementById('asset-picker-select');
    const countEl = document.getElementById('asset-picker-count');
    if (!select) return;

    const query = (document.getElementById('asset-picker-search')?.value || '').toLowerCase();
    const folderFilter = (document.getElementById('asset-picker-folder')?.value || '').toLowerCase();
    const allFiles = window.allAssetFiles || [];

    const filtered = allFiles.filter(p => {
        const lower = p.toLowerCase();
        const folderMatch = !folderFilter || lower.includes('/' + folderFilter + '/');
        const searchMatch = !query || lower.includes(query);
        return folderMatch && searchMatch;
    });

    if (countEl) countEl.textContent = `${filtered.length} asset${filtered.length !== 1 ? 's' : ''}`;

    // Clear previous options
    select.innerHTML = '';
    if (filtered.length === 0) {
        const opt = document.createElement('option');
        opt.textContent = 'No se encontraron assets';
        opt.disabled = true;
        select.appendChild(opt);
        return;
    }

    filtered.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p;
        const filename = p.split('/').pop();
        opt.textContent = filename;
        select.appendChild(opt);
    });

};

window.selectAssetFromPicker = function(path) {
    const { idx, type } = window._assetPickerState;
    if (type === 'resource') {
        config.shopItems.resources[idx].icon = path;
    } else if (type === 'recipe') {
        config.craftingRecipes[idx].icon = path;
    }
    closeAssetPicker();
    renderCrafting();
};

// ─── CATÁLOGO MAESTRO DE ÍTEMS (para el buscador de recompensas) ─────────────
// Incluye armas, escudos, motores, extras, recursos y municiones del shopItems,
// más la lista de crafteo si existe. Todos los objetos "adquiribles".
window.getMasterItemCatalog = function() {
    const cat = [];
    const seen = {};
    const pushArr = (arr, catName) => {
        if (!Array.isArray(arr)) return;
        arr.forEach(it => {
            if (it && it.id != null && it.id !== '') {
                const idStr = String(it.id);
                if (seen[idStr]) return;
                seen[idStr] = true;
                cat.push({ id: idStr, name: it.name || idStr, category: catName, icon: it.icon || '' });
            }
        });
    };
    if (config && config.shopItems) {
        pushArr(config.shopItems.weapons, 'Armas');
        pushArr(config.shopItems.shields, 'Escudos');
        pushArr(config.shopItems.engines, 'Motores');
        pushArr(config.shopItems.extra, 'Extras');
        pushArr(config.shopItems.resources, 'Recursos');
        const ammo = config.shopItems.ammo || {};
        Object.keys(ammo).forEach(type => pushArr(ammo[type], 'Munición'));
    }
    if (config && Array.isArray(config.craftingResources)) {
        pushArr(config.craftingResources, 'Crafteo');
    }
    if (config && Array.isArray(config.craftingRecipes)) {
        pushArr(config.craftingRecipes, 'Recetas');
    }
    return cat;
};

// Devuelve el nombre visible de un ítem a partir de su ID
window.getItemCatalogName = function(id) {
    if (id === '' || id == null) return '(sin ítem)';
    const cat = window.getMasterItemCatalog();
    const found = cat.find(c => c.id === String(id));
    return found ? found.name : ('Ítem ' + id);
};

// ─── SELECTOR DE ÍTEM (desplegable inline, por nombre) ──────────────────────
// Estado del desplegable inline (un único picker abierto a la vez).
// itemIdx: null = modo "agregar"; número = modo "editar" ese índice.
window._inlineItemPicker = { idx: -1, itemIdx: null, open: false, query: '', cat: '' };

window.getItemPickerCategoryOptions = function() {
    const cats = [...new Set(window.getMasterItemCatalog().map(c => c.category))];
    return '<option value="">📁 Todas las categorías</option>' +
        cats.map(c => `<option value="${c}">${c}</option>`).join('');
};

window.toggleInlineItemPicker = function(idx, itemIdx = null) {
    const cur = window._inlineItemPicker;
    const same = cur.open && cur.idx === idx && cur.itemIdx === itemIdx;
    if (same) {
        window._inlineItemPicker.open = false;
        window._inlineItemPicker.itemIdx = null;
    } else {
        window._inlineItemPicker = { idx: idx, itemIdx: itemIdx, open: true, query: '', cat: '' };
    }
    renderQuests();
};

window.updateInlineItemPickerQuery = function(idx, val) {
    window._inlineItemPicker.idx = idx;
    window._inlineItemPicker.open = true;
    if (window._inlineItemPicker.itemIdx === undefined) window._inlineItemPicker.itemIdx = null;
    window._inlineItemPicker.query = val;
    window.renderInlineItemPickerList(idx);
};

window.updateInlineItemPickerCat = function(idx, val) {
    window._inlineItemPicker.idx = idx;
    window._inlineItemPicker.open = true;
    if (window._inlineItemPicker.itemIdx === undefined) window._inlineItemPicker.itemIdx = null;
    window._inlineItemPicker.cat = val;
    window.renderInlineItemPickerList(idx);
};

window.renderInlineItemPickerList = function(idx) {
    const state = window._inlineItemPicker;
    if (!state || state.idx !== idx || !state.open) return;
    const list = document.getElementById('item-inline-list-' + idx);
    if (!list) return;
    const catSel = document.getElementById('item-inline-cat-' + idx);
    if (catSel) catSel.value = state.cat || '';
    // Indicador de modo (agregar vs editar)
    const modeLabel = document.getElementById('item-inline-mode-' + idx);
    if (modeLabel) {
        if (state.itemIdx !== null && state.itemIdx !== undefined) {
            const curItem = (config.questsConfig[idx]?.reward?.items || [])[state.itemIdx];
            const curName = curItem ? getItemCatalogName(curItem.id) : '';
            modeLabel.textContent = `✏️ Cambiando: ${curName} → seleccioná el nuevo ítem`;
            modeLabel.style.display = 'block';
        } else {
            modeLabel.textContent = '➕ Agregando nuevo ítem — seleccioná uno:';
            modeLabel.style.display = 'block';
        }
    }
    const query = (state.query || '').toLowerCase().trim();
    const catFilter = state.cat || '';
    const catalog = window.getMasterItemCatalog();
    const filtered = catalog.filter(c => {
        const mq = !query || c.name.toLowerCase().includes(query) || c.id.toLowerCase().includes(query);
        const mc = !catFilter || c.category === catFilter;
        return mq && mc;
    });
    list.innerHTML = '';
    if (filtered.length === 0) {
        list.innerHTML = '<div style="padding:1.2rem; text-align:center; color:#777; font-size:0.82rem;">No se encontraron ítems con ese filtro.</div>';
        return;
    }
    filtered.forEach(c => {
        const el = document.createElement('div');
        el.style.cssText = 'display:flex; align-items:center; gap:12px; padding:9px 12px; background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.06); border-radius:8px; cursor:pointer; transition:background 0.15s, border-color 0.15s;';
        el.innerHTML = `
            <span style="font-size:0.62rem; color:#0b0f1a; background:var(--accent); padding:2px 8px; border-radius:20px; white-space:nowrap; font-weight:bold;">${(typeof getCategoryName === 'function' ? getCategoryName(c.category) : c.category)}</span>
            <span style="flex:1; min-width:0; color:#fff; font-size:0.88rem; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${c.name}</span>
            <span style="font-size:0.72rem; color:#888; font-family:'JetBrains Mono';">${c.id}</span>
        `;
        el.onmouseover = () => { el.style.background = 'rgba(0,210,255,0.12)'; el.style.borderColor = 'rgba(0,210,255,0.4)'; };
        el.onmouseout = () => { el.style.background = 'rgba(255,255,255,0.03)'; el.style.borderColor = 'rgba(255,255,255,0.06)'; };
        el.onclick = () => window.selectItemForQuestReward(idx, c.id);
        list.appendChild(el);
    });
};

window.selectItemForQuestReward = function(idx, id) {
    if (!config.questsConfig[idx].reward.items) config.questsConfig[idx].reward.items = [];
    const state = window._inlineItemPicker;
    const editIdx = (state && state.itemIdx !== null && state.itemIdx !== undefined) ? state.itemIdx : null;
    if (editIdx !== null && config.questsConfig[idx].reward.items[editIdx]) {
        config.questsConfig[idx].reward.items[editIdx].id = id;
        window._inlineItemPicker.open = false;
        window._inlineItemPicker.itemIdx = null;
    } else {
        config.questsConfig[idx].reward.items.push({ id: id, qty: 1 });
        // en modo agregar, mantener el picker abierto para seguir agregando
    }
    renderQuests();
};

// compatibilidad: alias del nombre anterior
window.addItemToQuestReward = window.selectItemForQuestReward;

window.showLootTabForEnemy = function(enemyId) {
    window.selectedLootEnemyId = enemyId;
    showTab('enemy-loot');
};

window.renderLootTableComponent = function(enemyId, containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    const en = config.enemyModels[enemyId];
    if (!en) return;
    if (!en.lootDrops) en.lootDrops = [];

    const allItems = [
        ...(config.shopItems?.weapons || []),
        ...(config.shopItems?.shields || []),
        ...(config.shopItems?.engines || []),
        ...(config.shopItems?.extra || []),
        ...(config.shopItems?.resources || []).map(r => ({ ...r, type: 'resource' })),
        ...(config.craftingRecipes || []).map(rc => ({ ...rc, type: 'recipe' }))
    ];

    container.innerHTML = `
        <div style="display: grid; grid-template-columns: 1fr; gap: 10px;">
            ${en.lootDrops.length === 0 ? `
                <div style="color: var(--text-dim); font-size: 0.8rem; padding: 1.5rem; text-align: center; background: rgba(255,255,255,0.01); border-radius: 6px; border: 1px dashed rgba(255,255,255,0.08);">
                    ⚠️ No hay drops configurados para este enemigo. Agregá ítems con el botón.
                </div>
            ` : en.lootDrops.map((ld, idx) => {
                const selectedItem = allItems.find(it => it.id === ld.itemId);
                const chancePercent = Math.round((ld.chance || 0.1) * 100);
                const barColor = chancePercent >= 50 ? 'var(--success)' : (chancePercent >= 20 ? 'var(--primary)' : 'var(--accent)');
                return `
                <div style="background: rgba(255,255,255,0.02); padding: 1rem 1.2rem; border-radius: 10px; border: 1px solid rgba(255,255,255,0.05); display: grid; grid-template-columns: 2fr 1fr 1fr 40px; gap: 15px; align-items: center; transition: all 0.2s;" onmouseenter="this.style.borderColor='rgba(6,182,212,0.3)'; this.style.background='rgba(6,182,212,0.03)'" onmouseleave="this.style.borderColor='rgba(255,255,255,0.05)'; this.style.background='rgba(255,255,255,0.02)'">
                    <div style="display: flex; flex-direction: column; gap: 4px;">
                        <label style="font-size: 0.6rem; color: var(--text-dim); text-transform: uppercase; letter-spacing: 1px;">ÍTEM DE RECOMPENSA</label>
                        <input type="text" placeholder="🔍 Buscar por nombre o ID..." style="background: #0a0e1a; border: 1px solid rgba(255,255,255,0.08); color: white; border-radius: 6px; padding: 6px 10px; font-size: 0.75rem; margin-bottom: 4px;" oninput="
                            const query = this.value.toLowerCase().trim();
                            const select = this.nextElementSibling;
                            for (let opt of select.options) {
                                if (opt.value === '') continue;
                                const text = opt.textContent.toLowerCase();
                                const val = opt.value.toLowerCase();
                                const isMatch = text.includes(query) || val.includes(query);
                                opt.style.display = isMatch ? '' : 'none';
                            }
                        ">
                        <select style="background: #0a0e1a; border: 1px solid rgba(255,255,255,0.08); color: white; font-weight: bold; cursor: pointer; width: 100%; border-radius: 6px; padding: 8px 10px; font-size: 0.85rem;" onchange="updateLootDropItemFromComponent('${enemyId}', ${idx}, this.value, '${containerId}')">
                            <option value="">-- Seleccionar Item --</option>
                            ${allItems.map(it => `<option value="${it.id}" ${ld.itemId === it.id ? 'selected' : ''}>[${(it.type || 'MOD').toUpperCase()}] ${it.name} (${it.id})</option>`).join('')}
                        </select>
                        ${selectedItem ? `<span style="font-size: 0.65rem; color: var(--text-dim);">Tipo: ${(selectedItem.type || 'módulo').toUpperCase()} | Rareza: ${selectedItem.rarity || 0}</span>` : ''}
                    </div>
                    <div style="display: flex; flex-direction: column; gap: 4px;">
                        <label style="font-size: 0.65rem; color: var(--text-dim); text-transform: uppercase; letter-spacing: 1px;">PROBABILIDAD</label>
                        <div style="display: flex; align-items: center; gap: 8px;">
                            <input type="number" min="0" max="100" step="1" value="${chancePercent}" style="background: #0a0e1a; border: 1px solid rgba(255,255,255,0.08); color: white; border-radius: 6px; padding: 8px 10px; width: 80px; font-size: 0.9rem; font-weight: bold;" onchange="updateLootDropChanceFromComponent('${enemyId}', ${idx}, this.value, '${containerId}')">
                            <span style="font-size: 0.85rem; color: var(--text-dim);">%</span>
                        </div>
                        <div style="height: 4px; background: rgba(255,255,255,0.05); border-radius: 2px; overflow: hidden; margin-top: 4px;">
                            <div style="height: 100%; width: ${chancePercent}%; background: ${barColor}; border-radius: 2px; transition: width 0.3s;"></div>
                        </div>
                    </div>
                    <div style="display: flex; flex-direction: column; gap: 4px;">
                        <label style="font-size: 0.65rem; color: var(--text-dim); text-transform: uppercase; letter-spacing: 1px;">CANTIDAD</label>
                        <div style="display: flex; align-items: center; gap: 8px;">
                            <input type="number" min="1" step="1" value="${ld.amount || 1}" style="background: #0a0e1a; border: 1px solid rgba(255,255,255,0.08); color: white; border-radius: 6px; padding: 8px 10px; width: 80px; font-size: 0.9rem; font-weight: bold;" onchange="updateLootDropAmountFromComponent('${enemyId}', ${idx}, this.value, '${containerId}')">
                        </div>
                    </div>
                    <div style="display: flex; flex-direction: column; align-items: center; gap: 2px;">
                        <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size: 1.2rem; font-weight: bold; margin-top: 15px;" onclick="removeLootDropFromComponent('${enemyId}', ${idx}, '${containerId}')">✕</button>
                    </div>
                </div>
                `;
            }).join('')}
        </div>
    `;
};

window.addLootDropFromComponent = function(enemyId, containerId) {
    const en = config.enemyModels[enemyId];
    if (!en) return;
    if (!en.lootDrops) en.lootDrops = [];
    en.lootDrops.push({ itemId: '', chance: 0.1, amount: 1 });
    if (containerId === 'enemy-loot-detail-container') {
        renderEnemyLootDetail();
    } else {
        renderEnemyDetail();
    }
};

window.updateLootDropItemFromComponent = function(enemyId, idx, value, containerId) {
    const en = config.enemyModels[enemyId];
    if (!en || !en.lootDrops[idx]) return;
    en.lootDrops[idx].itemId = value;
    if (containerId === 'enemy-loot-detail-container') {
        renderEnemyLootDetail();
    } else {
        renderEnemyDetail();
    }
};

window.updateLootDropChanceFromComponent = function(enemyId, idx, value, containerId) {
    const en = config.enemyModels[enemyId];
    if (!en || !en.lootDrops[idx]) return;
    en.lootDrops[idx].chance = (parseFloat(value) || 0) / 100;
    if (containerId === 'enemy-loot-detail-container') {
        renderEnemyLootDetail();
    } else {
        renderEnemyDetail();
    }
};

window.updateLootDropAmountFromComponent = function(enemyId, idx, value, containerId) {
    const en = config.enemyModels[enemyId];
    if (!en || !en.lootDrops[idx]) return;
    en.lootDrops[idx].amount = Math.max(1, parseInt(value) || 1);
    if (containerId === 'enemy-loot-detail-container') {
        renderEnemyLootDetail();
    } else {
        renderEnemyDetail();
    }
};
window.removeLootDropFromComponent = function(enemyId, idx, containerId) {
    const en = config.enemyModels[enemyId];
    if (!en || !en.lootDrops) return;
    en.lootDrops.splice(idx, 1);
    if (containerId === 'enemy-loot-detail-container') {
        renderEnemyLootDetail();
    } else {
        renderEnemyDetail();
    }
};

window.renderTalentCreator = function() {
    const grid = document.getElementById('talents-creator-grid');
    if (!grid) return;
    grid.innerHTML = '';

    // Renderizar panel de gestión de ramas dinámicas
    if (typeof renderCategoriesPanel === 'function') {
        renderCategoriesPanel();
    }

    const availableCats = (typeof getCategories === 'function') ? getCategories() : [];

    // Panel de talentos sellados
    if (!config.talentsLockedConfig) config.talentsLockedConfig = [];
    const lockedPanel = document.getElementById('talents-locked-panel');
    if (lockedPanel) {
        const rows = config.talentsLockedConfig.map((t, ti) => `
            <div style="display:flex; gap:8px; align-items:center; margin-bottom:6px; background:rgba(255,255,255,0.02); padding:6px; border-radius:6px; flex-wrap:wrap;">
                <select style="flex:1; min-width:120px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:4px; font-size:0.7rem;" onchange="config.talentsLockedConfig[${ti}].category = this.value">
                    ${availableCats.map(c => `<option value="${c.id}" ${t.category === c.id ? 'selected' : ''}>${c.emoji || '⭐'} ${c.name}</option>`).join('')}
                </select>
                <select style="flex:1; min-width:90px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:4px; font-size:0.7rem;" onchange="config.talentsLockedConfig[${ti}].index = parseInt(this.value)">
                    ${Array.from({length: 8}, (_, i) => `<option value="${i}" ${Number(t.index) === i ? 'selected' : ''}>Ranura ${i+1}</option>`).join('')}
                </select>
                <input type="text" value="${reqAttrEscape(t.name || '')}" placeholder="Nombre del talento sellado" style="flex:2; min-width:140px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:4px; font-size:0.7rem;" onchange="config.talentsLockedConfig[${ti}].name = this.value">
                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:11px;" title="Quitar talento sellado" onclick="config.talentsLockedConfig.splice(${ti}, 1); renderTalentCreator();">✕</button>
            </div>
        `).join('');
        const defaultLockedCat = availableCats[0]?.id || 'combat';
        lockedPanel.innerHTML = `
            <div class="card" style="background:rgba(255,215,0,0.03); border:1px solid rgba(255,215,0,0.2);">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                    <label style="color:#ffd700; font-size:0.8rem; font-weight:bold; letter-spacing:1px;">🔒 TALENTOS SELLADOS (requieren misión para desbloquearse)</label>
                    <button class="btn btn-primary" style="padding:3px 10px; font-size:0.65rem; background:rgba(255,215,0,0.1); border:1px solid rgba(255,215,0,0.3);" onclick="config.talentsLockedConfig.push({category:'${defaultLockedCat}', index:0, name:'Talento Sellado'}); renderTalentCreator();">+ SELLAR TALENTO</button>
                </div>
                <div style="font-size:0.68rem; color:#888; margin-bottom:8px;">Los talentos sellados no se pueden invertir puntos hasta que una misión otorgue su desbloqueo.</div>
                ${rows || '<div style="font-size:0.68rem; opacity:0.45;">Ningún talento sellado.</div>'}
            </div>
        `;
    }

    const f = getFilter();
    const creatorSearch = (document.getElementById('talent-creator-search')?.value || '').toLowerCase();
    const filterTerm = f || creatorSearch;
    const talents = config.talentsConfig.talents || [];
    const nodes = config.talentsConfig.nodes || {};
    const connections = config.talentsConfig.connections || [];

    // ═══════════════════════════════════════════════════
    // RENDERIZAR TALENTOS (agrupados por ramas dinámicas)
    // ═══════════════════════════════════════════════════
    const filteredAll = talents.filter(t => {
        if (filterTerm && !t.name.toLowerCase().includes(filterTerm) && !t.desc.toLowerCase().includes(filterTerm) && !t.id.toLowerCase().includes(filterTerm)) return false;
        return true;
    });

    if (!window._collapsedCats) window._collapsedCats = new Set();

    // Recolectar ramas para agrupar (las configuradas + cualquier rama huérfana en uso)
    const allCatIdsInTalents = [...new Set(talents.map(t => t.category))];
    const allRenderCats = [...availableCats];
    allCatIdsInTalents.forEach(orphanId => {
        if (orphanId && !allRenderCats.some(c => c.id === orphanId)) {
            allRenderCats.push({ id: orphanId, name: orphanId.toUpperCase(), color: '#888888', emoji: '📁' });
        }
    });

    allRenderCats.forEach(catObj => {
        const cat = catObj.id;
        const catColor = catObj.color || '#00d2ff';
        const catEmoji = catObj.emoji || '⭐';
        const catName = catObj.name || cat;
        const catTalentsRaw = filteredAll.filter(t => t.category === cat);
        const catTalents = (typeof window.sortTalentsMappedAndSize === 'function')
            ? window.sortTalentsMappedAndSize(catTalentsRaw, nodes)
            : catTalentsRaw;
        if (catTalents.length === 0) return;

        const collapsed = window._collapsedCats.has(cat);

        // Separador de categoría (clickeable)
        const sep = document.createElement('div');
        sep.style.cssText = 'grid-column: 1 / -1; padding: 6px 12px; margin-top: 8px; border-radius: 6px; background: ' + catColor + '10; border: 1px solid ' + catColor + '30; cursor: pointer; user-select: none; transition: opacity 0.15s;';
        sep.innerHTML = `<span style="font-weight:bold; color:${catColor}; font-size:0.8rem; letter-spacing:1px;">${collapsed ? '▶' : '▼'} ${catEmoji} ${catName.toUpperCase()} (${catTalents.length})</span>`;
        sep.onmouseenter = () => sep.style.opacity = '0.8';
        sep.onmouseleave = () => sep.style.opacity = '1';
        sep.onclick = () => {
            if (window._collapsedCats.has(cat)) window._collapsedCats.delete(cat);
            else window._collapsedCats.add(cat);
            renderTalentCreator();
        };
        grid.appendChild(sep);

        if (collapsed) return;

        catTalents.forEach(t => {
            const idx = talents.indexOf(t);
            if (idx === -1) return;

            const isPlaced = !!nodes[t.id];
            const nd = nodes[t.id] || {};
            const nodeType = nd.nodeType || 'small';
            const nodeTypeLabel = nodeType === 'keystone' ? '🔴 Clave' : nodeType === 'notable' ? '🟡 Notable' : '🟢 Pequeño';
            const nodeTypeColor = nodeType === 'keystone' ? '#ffd700' : nodeType === 'notable' ? '#f0c040' : '#10b981';

            const incomingConns = connections.filter(c => c.to === t.id);
            const outgoingConns = connections.filter(c => c.from === t.id);
            const connectedNames = [...incomingConns, ...outgoingConns].map(c => {
                const otherId = c.from === t.id ? c.to : c.from;
                const other = talents.find(x => x.id === otherId);
                return other ? other.name : otherId;
            });

            const statusBadge = isPlaced
                ? `<span style="background:rgba(16,185,129,0.15); color:#10b981; border:1px solid rgba(16,185,129,0.3); padding:3px 8px; border-radius:4px; font-size:0.72rem; font-weight:bold;">📍 MAPEADO</span>`
                : `<span style="background:rgba(239,68,68,0.15); color:#ef4444; border:1px solid rgba(239,68,68,0.3); padding:3px 8px; border-radius:4px; font-size:0.72rem; font-weight:bold;">⚠️ SIN MAPEAR</span>`;

            const connInfo = connectedNames.length > 0
                ? `<div style="font-size:0.65rem; color:#666; margin-top:4px;">🔗 ${connectedNames.join(', ')}</div>`
                : '';

            const card = document.createElement('div');
            card.className = 'card';
            card.style.borderTop = `3px solid ${catColor}`;
            card.innerHTML = `
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
                    <span style="font-size:0.72rem; font-family:'JetBrains Mono'; color:#888;">ID: ${t.id}</span>
                    <div style="display:flex; gap:6px; align-items:center;">
                        ${statusBadge}
                        <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:14px;" onclick="deleteTalent('${t.id}')" title="Eliminar talento">🗑️</button>
                    </div>
                </div>

                <div style="display:flex; gap:10px; align-items:center; margin-bottom:10px;">
                    <div style="width:50px; text-align:center;">
                        <input type="text" value="${t.icon || '🌳'}" style="font-size:1.5rem; text-align:center; width:100%;" onchange="config.talentsConfig.talents[${idx}].icon = this.value; renderTalentCreator();">
                    </div>
                    <div style="flex:1;">
                        <div style="margin-bottom:6px;">
                            <label style="font-size:0.7rem; color:#aaa;">Nombre</label>
                            <input type="text" value="${t.name}" onchange="config.talentsConfig.talents[${idx}].name = this.value" style="width:100%;">
                        </div>
                        <div>
                            <label style="font-size:0.7rem; color:#aaa;">Descripción</label>
                            <textarea rows="2" style="width:100%; background:var(--surface); border:1px solid rgba(255,255,255,0.1); border-radius:6px; color:white; padding:6px; font-size:0.78rem;" onchange="config.talentsConfig.talents[${idx}].desc = this.value">${t.desc}</textarea>
                        </div>
                    </div>
                </div>

                <div style="display:grid; grid-template-columns: 1fr 1fr 1fr; gap:10px; margin-top:10px;">
                    <div>
                        <label style="font-size:0.7rem; color:#aaa;">Rama / Categoría</label>
                        <select onchange="config.talentsConfig.talents[${idx}].category = this.value; renderTalentCreator();" style="width:100%; background:var(--surface); border:1px solid rgba(255,255,255,0.1); border-radius:6px; color:white; padding:8px; font-size:0.78rem;">
                            ${availableCats.map(c => `<option value="${c.id}" ${t.category === c.id ? 'selected' : ''}>${c.emoji || '⭐'} ${c.name}</option>`).join('')}
                        </select>
                    </div>
                    <div>
                        <label style="font-size:0.7rem; color:#aaa;">Nivel Máximo</label>
                        <input type="number" value="${t.maxLevel || 5}" onchange="config.talentsConfig.talents[${idx}].maxLevel = parseInt(this.value)" style="width:100%;">
                    </div>
                    <div>
                        <label style="font-size:0.7rem; color:#aaa;">🏷️ Tipo de Nodo</label>
                        <select onchange="updateTalentCreatorNodeType('${t.id}', this.value)" style="width:100%; background:var(--surface); border:1px solid ${nodeTypeColor}40; border-radius:6px; color:${nodeTypeColor}; padding:8px; font-size:0.78rem; font-weight:bold;">
                            <option value="small" ${nodeType==='small'?'selected':''}>🟢 Pequeño</option>
                            <option value="notable" ${nodeType==='notable'?'selected':''}>🟡 Notable</option>
                            <option value="keystone" ${nodeType==='keystone'?'selected':''}>🔴 Clave</option>
                        </select>
                    </div>
                </div>

                ${connInfo}

                <div style="margin-top:12px; border-top:1px solid #333; padding-top:10px;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                        <label style="color:var(--accent); font-size:0.73rem; font-weight:bold;">⚡ EFECTOS POR NIVEL</label>
                        <button class="btn btn-primary" style="padding:2px 8px; font-size:0.65rem;" onclick="addTalentEffect(${idx})">+ EFECTO</button>
                    </div>
                    <div style="display:flex; flex-direction:column; gap:5px;">
                        ${(() => {
                            const effectsEntries = Object.entries(t.effects || {});
                            // Agrupar efectos de habilidad por skillId: skill:SK_ID:attr
                            const skillGroups = {};
                            const otherEntries = [];

                            effectsEntries.forEach(([key, val]) => {
                                if (_isSkillEffect(key)) {
                                    const parsed = _parseDynamicKey(key);
                                    if (parsed && parsed.id) {
                                        if (!skillGroups[parsed.id]) skillGroups[parsed.id] = [];
                                        skillGroups[parsed.id].push({ key, val, attr: parsed.attr });
                                        return;
                                    }
                                }
                                otherEntries.push([key, val]);
                            });

                            let htmlStr = '';

                            // 1. Renderizar Bloques de Habilidades
                            Object.entries(skillGroups).forEach(([skId, items]) => {
                                const sk = (typeof config !== 'undefined' && config.skillsData) ? config.skillsData[skId] : null;
                                const skName = sk ? (sk.name || skId) : skId;
                                const skIconHtml = assetIconHtml((sk && sk.icon) ? sk.icon : '', {
                                    size: 26,
                                    fallback: '🌀',
                                    emojiSize: '18px',
                                    emptyHtml: '<span style="font-size:1.1rem;">🌀</span>'
                                });

                                htmlStr += `
                                <div style="background:rgba(249,115,22,0.06); border:1px solid rgba(249,115,22,0.3); border-radius:10px; padding:8px 10px; margin-bottom:6px;">
                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px; border-bottom:1px solid rgba(249,115,22,0.15); padding-bottom:5px;">
                                        <div style="display:flex; align-items:center; gap:6px;">
                                            ${skIconHtml}
                                            <span style="font-size:0.8rem; font-weight:bold; color:#f97316;">${skName}</span>
                                            <span style="font-size:0.6rem; color:#888; font-family:'JetBrains Mono';">(${skId})</span>
                                        </div>
                                        <div style="display:flex; gap:6px; align-items:center;">
                                            <button type="button" class="btn" onclick="openSkillParamPickerModal(${idx}, '${skId.replace(/'/g, "\\'")}')" style="padding:2px 7px; font-size:0.62rem; background:rgba(249,115,22,0.2); border:1px solid #f97316; color:#f97316; border-radius:4px; font-weight:bold; cursor:pointer;" title="Agregar modificador de parámetro a esta habilidad">+ PARÁMETRO</button>
                                            <button type="button" style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.85rem; padding:1px 4px;" onclick="deleteTalentSkillGroup(${idx}, '${skId.replace(/'/g, "\\'")}')" title="Quitar todos los efectos de esta habilidad">✕</button>
                                        </div>
                                    </div>
                                    <div style="display:flex; flex-direction:column; gap:4px; padding-left:4px;">
                                        ${items.map(it => {
                                            const key = it.key;
                                            const val = it.val;
                                            const meta = (t.effectsMeta && t.effectsMeta[key]) ? t.effectsMeta[key] : { flat: false };
                                            const isFlat = meta.flat;
                                            const attrMeta = window.SKILL_ATTRS ? window.SKILL_ATTRS[it.attr] : null;
                                            const attrLabel = attrMeta ? attrMeta.label : it.attr;
                                            const attrIcon = attrMeta ? (attrMeta.icon || '⚡') : '⚡';
                                            const displayVal = isFlat ? (typeof formatCleanNumber === 'function' ? formatCleanNumber(val, 2) : val) : (typeof formatCleanNumber === 'function' ? formatCleanNumber(val * 100, 2) : (val * 100));
                                            const unitLabel = isFlat ? (attrMeta?.unit || 'pts') : '%';

                                            return `
                                            <div style="display:flex; gap:6px; align-items:center; background:rgba(0,0,0,0.25); padding:4px 8px; border-radius:6px; border:1px solid rgba(255,255,255,0.06);">
                                                <span style="font-size:0.9rem;">${attrIcon}</span>
                                                <div style="flex:1; min-width:0;">
                                                    <span style="font-size:0.73rem; font-weight:bold; color:#ddd;">${attrLabel}</span>
                                                    <span style="font-size:0.58rem; color:#777; font-family:'JetBrains Mono'; margin-left:4px;">${it.attr}</span>
                                                </div>
                                                <button type="button" onclick="toggleEffectFlat(${idx}, '${key}')" style="flex-shrink:0; padding:2px 6px; border-radius:4px; font-size:0.6rem; font-weight:bold; cursor:pointer; border:1px solid ${isFlat ? 'rgba(255,150,50,0.4)' : 'rgba(0,210,255,0.4)'}; background:${isFlat ? 'rgba(255,150,50,0.12)' : 'rgba(0,210,255,0.12)'}; color:${isFlat ? '#ff9632' : '#00d2ff'};" title="Alternar fijo / %">${isFlat ? 'FIJO' : '%'}</button>
                                                <input type="number" step="0.01" value="${displayVal}" style="width:75px; text-align:center; font-size:0.75rem; padding:3px 5px; border-radius:4px; background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.12); color:white; font-family:'JetBrains Mono';" onchange="config.talentsConfig.talents[${idx}].effects['${key}'] = (${isFlat || false}) ? parseFloat(this.value) : (parseFloat(this.value) / 100)">
                                                <span style="font-size:0.6rem; color:#888; min-width:26px;">${unitLabel}</span>
                                                <button type="button" style="background:none; border:none; color:#ff6666; cursor:pointer; font-size:0.8rem; padding:1px 4px;" onclick="deleteTalentEffect(${idx}, '${key}')" title="Quitar parámetro">✕</button>
                                            </div>`;
                                        }).join('')}
                                    </div>
                                </div>`;
                            });

                            // 2. Renderizar Otros Efectos (Estadísticas, Desbloqueos, Armas, etc.)
                            htmlStr += otherEntries.map(([key, val]) => {
                                const meta = (t.effectsMeta && t.effectsMeta[key]) ? t.effectsMeta[key] : { flat: false };
                                const isFlat = meta.flat;
                                const isUnlock = _isUnlockEffect(key);
                                const isWeaponFx = _isWeaponEffect(key);
                                const isAmmoFx = _isAmmoEffect(key);
                                const cat = TALENT_EFFECTS_CATALOG[key];

                                let label = key;
                                let icon = '✨';
                                let catCol = '#888';

                                if (cat) {
                                    label = cat.label;
                                    icon = cat.icon;
                                    catCol = _effectCatColor(cat.cat);
                                } else if (isWeaponFx) {
                                    const parsed = _parseDynamicKey(key);
                                    const weps = config && config.shopItems && config.shopItems.weapons ? config.shopItems.weapons : [];
                                    const w = weps.find(x => x.id === parsed.id);
                                    const attrMeta = window.WEAPON_ATTRS ? window.WEAPON_ATTRS[parsed.attr] : null;
                                    label = `${w ? w.name : parsed.id} → ${attrMeta ? attrMeta.label : parsed.attr}`;
                                    icon = '🔫';
                                    catCol = '#ef4444';
                                } else if (isAmmoFx) {
                                    const parsed = _parseDynamicKey(key);
                                    const attrMeta = window.AMMO_ATTRS ? window.AMMO_ATTRS[parsed.attr] : null;
                                    label = `Munición ${parsed.id} → ${attrMeta ? attrMeta.label : parsed.attr}`;
                                    icon = '💥';
                                    catCol = '#ef4444';
                                }

                                const displayVal = isUnlock ? '' : (isFlat ? (typeof formatCleanNumber === 'function' ? formatCleanNumber(val, 2) : val) : (typeof formatCleanNumber === 'function' ? formatCleanNumber(val * 100, 2) : (val * 100)));
                                const unitLabel = isUnlock ? 'SIEMPRE' : (isFlat ? '(fijo)' : '(%)');

                                return `
                                <div style="display:flex; gap:6px; align-items:center; margin-bottom:5px; background:rgba(255,255,255,0.02); padding:6px 10px; border-radius:8px; border:1px solid ${catCol}30; transition:all 0.15s;">
                                    <span style="font-size:1.1rem; flex-shrink:0;">${icon}</span>
                                    <div style="flex:1; min-width:0;">
                                        <div style="font-size:0.75rem; font-weight:bold; color:${catCol}; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${label}</div>
                                        <div style="font-size:0.6rem; color:#888; font-family:'JetBrains Mono';">${key}</div>
                                    </div>
                                    ${isUnlock ? `
                                        <span style="font-size:0.65rem; padding:2px 8px; border-radius:4px; background:rgba(168,85,247,0.15); color:#a855f7; border:1px solid rgba(168,85,247,0.3); font-weight:bold;">🔓 DESBLOQUEO</span>
                                    ` : `
                                        <button onclick="toggleEffectFlat(${idx}, '${key}')" style="flex-shrink:0; padding:3px 8px; border-radius:4px; font-size:0.65rem; font-weight:bold; cursor:pointer; border:1px solid ${isFlat ? 'rgba(255,150,50,0.4)' : 'rgba(0,210,255,0.4)'}; background:${isFlat ? 'rgba(255,150,50,0.12)' : 'rgba(0,210,255,0.12)'}; color:${isFlat ? '#ff9632' : '#00d2ff'};" title="Clic para alternar entre fijo y porcentual">${isFlat ? 'FIJO' : '%'}</button>
                                        <input type="number" step="0.01" value="${displayVal}" style="width:80px; text-align:center; font-size:0.8rem; padding:4px 6px; border-radius:4px; background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.12); color:white; font-family:'JetBrains Mono';" onchange="config.talentsConfig.talents[${idx}].effects['${key}'] = (${isFlat || false}) ? parseFloat(this.value) : (parseFloat(this.value) / 100)">
                                        <span style="font-size:0.65rem; color:#888; min-width:28px;">${unitLabel}</span>
                                    `}
                                    <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.9rem; flex-shrink:0; padding:2px 6px;" onclick="deleteTalentEffect(${idx}, '${key}')" title="Eliminar efecto">✕</button>
                                </div>`;
                            }).join('');

                            return htmlStr;
                        })()}
                    </div>
                </div>
            `;
            grid.appendChild(card);
        });
    });

    if (filteredAll.length === 0) {
        grid.innerHTML += '<div style="grid-column:1/-1; text-align:center; padding:2rem; color:var(--text-dim); font-size:0.85rem;">No se encontraron talentos.</div>';
    }
};

// Actualizar nodeType desde el Creador (sincroniza con Mapper)
window.updateTalentCreatorNodeType = function(talentId, newType) {
    if (!config.talentsConfig.nodes) config.talentsConfig.nodes = {};
    if (!config.talentsConfig.nodes[talentId]) {
        config.talentsConfig.nodes[talentId] = { x: 100, y: 100 };
    }
    config.talentsConfig.nodes[talentId].nodeType = newType;
    renderTalentCreator();
    if (typeof renderTalentMapper === 'function') renderTalentMapper();
};

// ═══════════════════════════════════════════════════════════
// CATÁLOGO UNIFICADO DE EFECTOS DE TALENTOS
// ═══════════════════════════════════════════════════════════
window.TALENT_EFFECTS_CATALOG = {
    // ── COMBATE ──
    laser_dmg_pct:       { label: 'Daño Láser',               icon: '🔫', cat: 'combate',   defaultValue: 0.01 },
    dmg_pct:             { label: 'Daño Total',               icon: '💥', cat: 'combate',   defaultValue: 0.01 },
    fire_rate_pct:       { label: 'Cadencia de Fuego',        icon: '⚔️', cat: 'combate',   defaultValue: 0.01 },
    ignore_shield_pct:   { label: 'Perforación de Escudo',    icon: '⚡', cat: 'combate',   defaultValue: 0.01 },
    ammo_bonus_pct:      { label: 'Munición Extra',           icon: '💣', cat: 'combate',   defaultValue: 0.01 },
    // ── DEFENSA ──
    hp_pct:              { label: 'Vida Máxima',              icon: '🛡️', cat: 'defensa',   defaultValue: 0.01 },
    hp_regen:            { label: 'Regen. Vida',              icon: '🔧', cat: 'defensa',   defaultValue: 0.01 },
    shield_regen:        { label: 'Regen. Escudo',            icon: '🔋', cat: 'defensa',   defaultValue: 0.01 },
    stability:           { label: 'Estabilidad',              icon: '🛸', cat: 'defensa',   defaultValue: 0.01 },
    // ── CURACIÓN ──
    heal_pct:            { label: 'Curación',                 icon: '💚', cat: 'curación',  defaultValue: 0.01 },
    // ── UTILIDAD ──
    speed_pct:           { label: 'Velocidad',                icon: '🚀', cat: 'utilidad',  defaultValue: 0.01 },
    cooldown_reduction:  { label: 'Reducción CD Global',      icon: '❄️', cat: 'utilidad',  defaultValue: 0.01 },
    cast_time_reduction: { label: 'Reducción Cast Time Global',icon: '⏱️', cat: 'utilidad',  defaultValue: 0.01 },
    dash_distance:       { label: 'Distancia Dash',           icon: '🌀', cat: 'utilidad',  defaultValue: 0.01 },
    minimap_range:       { label: 'Rango Radar',              icon: '📡', cat: 'utilidad',  defaultValue: 0.01 },
    energy_efficiency:   { label: 'Eficiencia Energía',       icon: '⚛️', cat: 'utilidad',  defaultValue: 0.01 },
    // ── ECONOMÍA ──
    ohcu_kill_bonus:     { label: 'Bonus OHCU por Bajas',     icon: '💎', cat: 'economía',  defaultValue: 0.01 },
    shop_discount:       { label: 'Descuento Tiendas',        icon: '🏪', cat: 'economía',  defaultValue: 0.01 },
    repair_cost_reduction:{ label: 'Costo Reparación',        icon: '💸', cat: 'economía',  defaultValue: 0.01 },
    boss_loot_bonus:     { label: 'Loot Bosses',              icon: '👑', cat: 'economía',  defaultValue: 0.01 },
    group_bonus:         { label: 'Bonus Escuadrón',          icon: '👥', cat: 'economía',  defaultValue: 0.01 },
};

// Helpers de efectos
function _isUnlockEffect(key) { return key && key.startsWith('unlock:'); }
function _isSkillEffect(key) { return key && key.startsWith('skill:'); }
function _isWeaponEffect(key) { return key && key.startsWith('weapon:'); }
function _isAmmoEffect(key) { return key && key.startsWith('ammo:'); }
function _isDynamicEffect(key) { return _isSkillEffect(key) || _isWeaponEffect(key) || _isAmmoEffect(key); }

function _parseDynamicKey(key) {
    if (!key) return null;
    const parts = key.split(':');
    if (parts.length >= 3 && ['skill','weapon','ammo'].includes(parts[0])) {
        return { type: parts[0], id: parts[1], attr: parts.slice(2).join(':') };
    }
    return null;
}

window.SKILL_ATTRS = {
    cd:              { label: 'Cooldown',         unit: 'ms',   icon: '⏱️' },
    castTimeMs:      { label: 'Casteo',           unit: 'ms',   icon: '⏳' },
    amount:          { label: 'Poder (pts)',       unit: 'pts',  icon: '💪' },
    range:           { label: 'Rango',            unit: 'px',   icon: '📏' },
    duration:        { label: 'Duración',         unit: 'ms',   icon: '⏳' },
    radius:          { label: 'Radio/Área',       unit: 'px',   icon: '⭕' },
    speed:           { label: 'Velocidad',        unit: 'px/s', icon: '🚀' },
    width:           { label: 'Ancho',            unit: 'px',   icon: '↔️' },
    heal_amount:     { label: 'Sanación',         unit: 'pts',  icon: '💚' },
    pulse_interval:  { label: 'Int. Pulso',       unit: 'ms',   icon: '〰️' },
    tickInterval:    { label: 'Int. Tick',        unit: 'ms',   icon: '⏱️' },
    taunt_duration:  { label: 'Provocación',      unit: 'ms',   icon: '💢' },
    breakRange:      { label: 'Rango Ruptura',    unit: 'px',   icon: '💥' },
    revive_hp_pct:   { label: 'Vida Revivir',     unit: '%',    icon: '❤️' },
    revive_shield_pct:{ label: 'Escudo Revivir',  unit: '%',    icon: '🛡️' }
};

window.WEAPON_ATTRS = {
    base:            { label: 'Daño Base',        unit: 'pts',  icon: '💥' },
    speedMod:        { label: 'Mod. Velocidad',   unit: 'x',    icon: '🚀' },
};

window.AMMO_ATTRS = {
    cooldown:        { label: 'Cadencia',         unit: 'ms',   icon: '⏱️' },
    bulletSpeed:     { label: 'Vel. Proyectil',   unit: 'px/s', icon: '🚀' },
    range:           { label: 'Alcance',          unit: 'px',   icon: '📏' },
    castTimeMs:      { label: 'Casteo',           unit: 'ms',   icon: '⏳' },
};

function _effectCatColor(cat) {
    const m = { combate:'#ff3131', defensa:'#00d2ff', utilidad:'#f0c040', economía:'#10b981', 'curación':'#4ade80', unlock:'#a855f7', desbloqueo:'#a855f7', skill:'#f97316', skills:'#f97316', weapon:'#ef4444', armas:'#ef4444', ammo:'#f43f5e', custom:'#38bdf8' };
    return m[cat] || '#888';
}

// ═══════════════════════════════════════════════════════════
// MODAL UNIFICADO Y DINÁMICO DE SELECCIÓN DE EFECTOS
// ═══════════════════════════════════════════════════════════
window._effectModalTalentIdx = null;
window._effectModalCallback = null;
window._effectModalFilter = '';
window._effectModalCategory = 'all';

window.openEffectPickerModal = function(talentIdxOrNull, onSelectCallback = null) {
    window._effectModalTalentIdx = talentIdxOrNull;
    window._effectModalCallback = onSelectCallback;
    window._effectModalFilter = '';
    window._effectModalCategory = 'all';
    _renderEffectPickerModal();
};

window._renderEffectPickerModal = function() {
    const idx = window._effectModalTalentIdx;
    const cb = window._effectModalCallback;
    if (idx === null && !cb) return;

    let existingKeys = [];
    if (idx !== null && config?.talentsConfig?.talents?.[idx]) {
        existingKeys = Object.keys(config.talentsConfig.talents[idx].effects || {});
    } else if (Array.isArray(window._cmEffects)) {
        existingKeys = window._cmEffects.map(e => e.key);
    }

    const filter = (window._effectModalFilter || '').toLowerCase().trim();
    const activeCategory = window._effectModalCategory || 'all';

    // Compilar todas las opciones disponibles
    const allItems = [];

    // 1. Estadísticas fijas del catálogo
    for (const [key, meta] of Object.entries(window.TALENT_EFFECTS_CATALOG || {})) {
        allItems.push({
            key: key,
            label: meta.label,
            icon: meta.icon,
            cat: meta.cat,
            sub: `Atributo • ${meta.cat}`,
            defaultValue: meta.defaultValue || 0.01,
            isFlat: false
        });
    }

    // 2. Habilidades dinámicas (se listan como Habilidad individual, los parámetros se agregan luego)
    const cfg = (typeof config !== 'undefined' ? config : (window.config || {})) || {};
    const skills = cfg.skillsData || {};
    for (const [skId, sk] of Object.entries(skills)) {
        const skName = sk.name || skId;
        allItems.push({
            key: `skill_group:${skId}`,
            skillId: skId,
            label: skName,
            icon: sk.icon || '🌀',
            cat: 'skill',
            sub: `Habilidad • ID: ${skId} • Configurar parámetros`,
            defaultValue: 0,
            isFlat: false,
            isSkillGroup: true
        });
    }

    // 3. Armas
    const weapons = (cfg.shopItems && cfg.shopItems.weapons) ? cfg.shopItems.weapons : [];
    weapons.forEach(w => {
        const wName = w.name || w.id;
        for (const [attrKey, attrMeta] of Object.entries(window.WEAPON_ATTRS || {})) {
            allItems.push({
                key: `weapon:${w.id}:${attrKey}`,
                label: `${wName} → ${attrMeta.label}`,
                icon: attrMeta.icon || '🔫',
                cat: 'weapon',
                sub: `Arma • ID: ${w.id} • Unidad: ${attrMeta.unit}`,
                defaultValue: attrKey === 'base' ? 5 : 0.05,
                isFlat: attrKey === 'base'
            });
        }
    });

    // 4. Municiones
    const ammo = (cfg.shopItems && cfg.shopItems.ammo) ? cfg.shopItems.ammo : {};
    for (const [ammoType, ammoData] of Object.entries(ammo)) {
        const ammoName = ammoType.charAt(0).toUpperCase() + ammoType.slice(1);
        for (const [attrKey, attrMeta] of Object.entries(window.AMMO_ATTRS || {})) {
            allItems.push({
                key: `ammo:${ammoType}:${attrKey}`,
                label: `Munición ${ammoName} → ${attrMeta.label}`,
                icon: attrMeta.icon || '💥',
                cat: 'ammo',
                sub: `Munición • ${ammoType} • Unidad: ${attrMeta.unit}`,
                defaultValue: attrKey === 'bulletSpeed' ? 50 : 0.05,
                isFlat: attrKey === 'bulletSpeed' || attrKey === 'range'
            });
        }
    }

    // 5. Desbloqueos
    weapons.forEach(w => {
        allItems.push({
            key: `unlock:weapon:${w.id}`,
            label: `Desbloquear Arma: ${w.name || w.id}`,
            icon: '🔫',
            cat: 'unlock',
            sub: `Desbloqueo • Arma ID: ${w.id}`,
            defaultValue: 1,
            isFlat: true
        });
    });
    const shields = (cfg.shopItems && cfg.shopItems.shields) ? cfg.shopItems.shields : [];
    shields.forEach(s => {
        allItems.push({
            key: `unlock:shield:${s.id}`,
            label: `Desbloquear Escudo: ${s.name || s.id}`,
            icon: '🛡️',
            cat: 'unlock',
            sub: `Desbloqueo • Escudo ID: ${s.id}`,
            defaultValue: 1,
            isFlat: true
        });
    });
    const engines = (cfg.shopItems && cfg.shopItems.engines) ? cfg.shopItems.engines : [];
    engines.forEach(e => {
        allItems.push({
            key: `unlock:engine:${e.id}`,
            label: `Desbloquear Motor: ${e.name || e.id}`,
            icon: '🚀',
            cat: 'unlock',
            sub: `Desbloqueo • Motor ID: ${e.id}`,
            defaultValue: 1,
            isFlat: true
        });
    });
    const ships = (cfg.shipModels) ? cfg.shipModels : [];
    ships.forEach(ship => {
        allItems.push({
            key: `unlock:ship:${ship.id}`,
            label: `Desbloquear Nave: ${ship.name || ship.id}`,
            icon: '🛸',
            cat: 'unlock',
            sub: `Desbloqueo • Nave ID: ${ship.id}`,
            defaultValue: 1,
            isFlat: true
        });
    });
    for (const [skId, sk] of Object.entries(skills)) {
        allItems.push({
            key: `unlock:skill:${skId}`,
            label: `Desbloquear Habilidad: ${sk.name || skId}`,
            icon: '🌀',
            cat: 'unlock',
            sub: `Desbloqueo • Habilidad ID: ${skId}`,
            defaultValue: 1,
            isFlat: true
        });
    }

    // Filtrar elementos ya existentes en el talento
    const availableItems = allItems.filter(item => {
        if (item.isSkillGroup) {
            // Solo ocultar la habilidad si ya tiene TODOS los atributos de SKILL_ATTRS agregados
            const allAttrKeys = Object.keys(window.SKILL_ATTRS || {});
            const hasAll = allAttrKeys.length > 0 && allAttrKeys.every(ak => existingKeys.includes(`skill:${item.skillId}:${ak}`));
            return !hasAll;
        }
        return !existingKeys.includes(item.key);
    });

    // Filtrar por categoría activa
    let filteredItems = availableItems;
    if (activeCategory !== 'all' && activeCategory !== 'custom') {
        filteredItems = availableItems.filter(item => {
            if (activeCategory === 'skill') {
                return item.cat === 'skill' || (item.cat === 'unlock' && item.key.startsWith('unlock:skill:'));
            }
            if (activeCategory === 'weapon') {
                return item.cat === 'weapon' || (item.cat === 'unlock' && item.key.startsWith('unlock:weapon:'));
            }
            return item.cat === activeCategory;
        });
    }

    // Filtrar por término de búsqueda
    if (filter) {
        filteredItems = filteredItems.filter(item => 
            item.label.toLowerCase().includes(filter) ||
            item.key.toLowerCase().includes(filter) ||
            item.sub.toLowerCase().includes(filter)
        );
    }

    const categoryTabs = [
        { id: 'all', label: '✨ Todas' },
        { id: 'combate', label: '⚔️ Combate', color: '#ff3131' },
        { id: 'defensa', label: '🛡️ Defensa', color: '#00d2ff' },
        { id: 'curación', label: '💚 Curación', color: '#4ade80' },
        { id: 'utilidad', label: '🚀 Utilidad', color: '#f0c040' },
        { id: 'economía', label: '💰 Economía', color: '#10b981' },
        { id: 'skill', label: '🌀 Habilidades', color: '#f97316' },
        { id: 'weapon', label: '🔫 Armas', color: '#ef4444' },
        { id: 'ammo', label: '💥 Munición', color: '#f43f5e' },
        { id: 'unlock', label: '🔓 Desbloqueos', color: '#a855f7' },
        { id: 'custom', label: '⚙️ Personalizado', color: '#38bdf8' }
    ];

    let contentHtml = '';

    if (activeCategory === 'custom') {
        // Vista de Efecto Personalizado
        contentHtml = `
            <div style="background:rgba(255,255,255,0.02); border:1px solid rgba(0,210,255,0.2); border-radius:12px; padding:20px; display:flex; flex-direction:column; gap:16px;">
                <div style="display:flex; align-items:center; gap:10px;">
                    <span style="font-size:1.6rem;">⚙️</span>
                    <div>
                        <h4 style="margin:0; color:var(--primary); font-size:1rem; letter-spacing:0.5px;">Crear Efecto Personalizado Libre</h4>
                        <div style="font-size:0.72rem; color:#888; margin-top:2px;">Podés vincular cualquier clave de estadística, modificador especial o desbloqueo sin límites.</div>
                    </div>
                </div>

                <div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;">
                    <div>
                        <label style="font-size:0.7rem; color:#aaa; display:block; margin-bottom:4px; font-weight:bold;">CLAVE INTERNA (KEY) *</label>
                        <input type="text" id="custom-effect-key" placeholder="ej: stealth_duration, crit_multiplier, bonus_xp" style="width:100%; font-family:'JetBrains Mono'; background:rgba(0,0,0,0.3); border:1px solid rgba(255,255,255,0.15); border-radius:6px; padding:8px 10px; color:white; font-size:0.8rem;">
                    </div>
                    <div>
                        <label style="font-size:0.7rem; color:#aaa; display:block; margin-bottom:4px; font-weight:bold;">NOMBRE VISIBLE / ETIQUETA *</label>
                        <input type="text" id="custom-effect-label" placeholder="ej: Duración de Sigilo, Multiplicador Crítico" style="width:100%; background:rgba(0,0,0,0.3); border:1px solid rgba(255,255,255,0.15); border-radius:6px; padding:8px 10px; color:white; font-size:0.8rem;">
                    </div>
                </div>

                <div style="display:grid; grid-template-columns:80px 1fr 1fr; gap:12px; align-items:flex-end;">
                    <div>
                        <label style="font-size:0.7rem; color:#aaa; display:block; margin-bottom:4px; font-weight:bold;">ICONO</label>
                        <input type="text" id="custom-effect-icon" value="✨" style="width:100%; text-align:center; font-size:1.4rem; background:rgba(0,0,0,0.3); border:1px solid rgba(255,255,255,0.15); border-radius:6px; padding:4px;">
                    </div>
                    <div>
                        <label style="font-size:0.7rem; color:#aaa; display:block; margin-bottom:4px; font-weight:bold;">VALOR BASE POR NIVEL</label>
                        <input type="number" step="0.01" id="custom-effect-val" value="0.05" style="width:100%; font-family:'JetBrains Mono'; background:rgba(0,0,0,0.3); border:1px solid rgba(255,255,255,0.15); border-radius:6px; padding:8px 10px; color:white; font-size:0.8rem;">
                    </div>
                    <div>
                        <label style="font-size:0.7rem; color:#aaa; display:block; margin-bottom:4px; font-weight:bold;">TIPO DE CÁLCULO</label>
                        <div style="display:flex; gap:6px;">
                            <button type="button" id="btn-custom-flat" onclick="window._customEffectFlat=true; document.getElementById('btn-custom-flat').style.background='rgba(255,150,50,0.2)'; document.getElementById('btn-custom-flat').style.borderColor='#ff9632'; document.getElementById('btn-custom-pct').style.background='rgba(255,255,255,0.05)'; document.getElementById('btn-custom-pct').style.borderColor='rgba(255,255,255,0.1)';" style="flex:1; padding:8px; font-size:0.75rem; font-weight:bold; border-radius:6px; border:1px solid rgba(255,255,255,0.1); background:rgba(255,255,255,0.05); color:#ff9632; cursor:pointer;">FIJO (pts)</button>
                            <button type="button" id="btn-custom-pct" onclick="window._customEffectFlat=false; document.getElementById('btn-custom-pct').style.background='rgba(0,210,255,0.2)'; document.getElementById('btn-custom-pct').style.borderColor='#00d2ff'; document.getElementById('btn-custom-flat').style.background='rgba(255,255,255,0.05)'; document.getElementById('btn-custom-flat').style.borderColor='rgba(255,255,255,0.1)';" style="flex:1; padding:8px; font-size:0.75rem; font-weight:bold; border-radius:6px; border:1px solid #00d2ff; background:rgba(0,210,255,0.2); color:#00d2ff; cursor:pointer;">% (Porcentual)</button>
                        </div>
                    </div>
                </div>

                <div style="display:flex; justify-content:flex-end; margin-top:10px;">
                    <button type="button" class="btn btn-primary" onclick="submitCustomEffect()" style="padding:10px 24px; font-size:0.85rem; font-weight:bold;">➕ AGREGAR ESTE EFECTO AL TALENTO</button>
                </div>
            </div>
        `;
    } else {
        // Lista de efectos disponibles
        if (filteredItems.length === 0) {
            contentHtml = `
                <div style="text-align:center; padding:3rem 1rem; color:#777;">
                    <div style="font-size:2rem; margin-bottom:8px;">🔍</div>
                    <div style="font-size:0.9rem; color:#aaa;">No se encontraron efectos coincidentes.</div>
                    <div style="font-size:0.75rem; margin-top:4px;">Podés buscar otra palabra o usar la pestaña <b>⚙️ Personalizado</b> para crear uno nuevo.</div>
                </div>
            `;
        } else {
            contentHtml = `
                <div style="display:grid; grid-template-columns:repeat(auto-fill, minmax(320px, 1fr)); gap:8px;">
                    ${filteredItems.map(item => {
                        const col = _effectCatColor(item.cat);
                        const isUnlock = item.cat === 'unlock';
                        return `
                        <div onclick="selectEffectFromPicker('${item.key}', ${item.defaultValue}, ${item.isFlat}, '${item.label.replace(/'/g, "\\'")}', '${item.icon.replace(/'/g, "\\'")}')" 
                             style="display:flex; align-items:center; gap:12px; padding:10px 14px; border-radius:10px; cursor:pointer; background:rgba(255,255,255,0.02); border:1px solid ${col}25; transition:all 0.15s;"
                             onmouseover="this.style.background='${col}12'; this.style.borderColor='${col}80'; this.style.transform='translateY(-1px);'"
                             onmouseout="this.style.background='rgba(255,255,255,0.02)'; this.style.borderColor='${col}25'; this.style.transform='none';">
                            <span style="font-size:1.6rem; flex-shrink:0; display:inline-flex; width:28px; height:28px; align-items:center; justify-content:center;">${assetIconHtml(item.icon, { size: 28, fallback: '🌀', emojiSize: '22px', emptyHtml: '🌀' })}</span>
                            <div style="flex:1; min-width:0;">
                                <div style="font-size:0.82rem; font-weight:bold; color:var(--text); white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${item.label}</div>
                                <div style="font-size:0.65rem; color:#888; font-family:'JetBrains Mono'; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${item.key}</div>
                                <div style="font-size:0.6rem; color:${col}; margin-top:2px;">${item.sub}</div>
                            </div>
                            <div style="flex-shrink:0;">
                                ${item.isSkillGroup 
                                    ? `<span style="font-size:0.65rem; font-weight:bold; padding:3px 8px; border-radius:4px; background:rgba(249,115,22,0.15); color:#f97316; border:1px solid rgba(249,115,22,0.4);">HABILIDAD ⚙️</span>`
                                    : (isUnlock 
                                        ? `<span style="font-size:0.6rem; font-weight:bold; padding:2px 8px; border-radius:4px; background:rgba(168,85,247,0.15); color:#a855f7; border:1px solid rgba(168,85,247,0.3);">DESBLOQUEO</span>`
                                        : `<span style="font-size:0.65rem; font-weight:bold; padding:2px 6px; border-radius:4px; background:${item.isFlat ? 'rgba(255,150,50,0.12)' : 'rgba(0,210,255,0.12)'}; color:${item.isFlat ? '#ff9632' : '#00d2ff'}; border:1px solid ${item.isFlat ? 'rgba(255,150,50,0.3)' : 'rgba(0,210,255,0.3)'};">${item.isFlat ? 'FIJO' : '%'}</span>`
                                    )
                                }
                            </div>
                        </div>`;
                    }).join('')}
                </div>
            `;
        }
    }

    let html = `
    <div id="effect-picker-overlay" style="position:fixed; inset:0; background:rgba(0,0,0,0.85); backdrop-filter:blur(10px); z-index:100001; display:flex; align-items:center; justify-content:center; padding:1.5rem;" onclick="if(event.target===this)closeEffectPickerModal()">
        <div style="width:100%; max-width:760px; max-height:88vh; display:flex; flex-direction:column; background:#0b0f1a; border:1px solid rgba(0,210,255,0.3); border-radius:18px; box-shadow:0 30px 90px rgba(0,0,0,0.85); overflow:hidden;">
            <!-- Cabecera -->
            <div style="padding:1.2rem 1.6rem; border-bottom:1px solid rgba(255,255,255,0.06); display:flex; justify-content:space-between; align-items:center; background:rgba(0,210,255,0.04);">
                <div style="display:flex; align-items:center; gap:10px;">
                    <span style="font-size:1.4rem;">⚡</span>
                    <div>
                        <h3 style="color:var(--primary); font-size:1.15rem; margin:0; letter-spacing:0.04em;">SELECTOR DINÁMICO DE EFECTOS</h3>
                        <div style="font-size:0.7rem; color:#888;">Elegí o creá un efecto para este talento (${availableItems.length} disponibles)</div>
                    </div>
                </div>
                <button onclick="closeEffectPickerModal()" style="background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); color:#aaa; cursor:pointer; width:32px; height:32px; border-radius:8px; font-size:1rem; display:flex; align-items:center; justify-content:center; transition:all 0.15s;" onmouseover="this.style.color='#fff'; this.style.borderColor='rgba(255,255,255,0.3)'" onmouseout="this.style.color='#aaa'; this.style.borderColor='rgba(255,255,255,0.1)'">✕</button>
            </div>

            <!-- Buscador + Categorías -->
            <div style="padding:1rem 1.6rem; border-bottom:1px solid rgba(255,255,255,0.05); background:rgba(0,0,0,0.25); display:flex; flex-direction:column; gap:10px;">
                <input type="text" id="effect-picker-search" placeholder="🔍 Buscar por nombre, atributo, arma o habilidad..." value="${filter}" oninput="window._effectModalFilter=this.value; _renderEffectPickerModal()" style="width:100%; background:rgba(255,255,255,0.04); border:1px solid rgba(0,210,255,0.25); border-radius:8px; padding:10px 14px; color:white; font-size:0.85rem; outline:none; box-sizing:border-box;">
                
                <!-- Chips de Categoría -->
                <div style="display:flex; gap:6px; flex-wrap:wrap; overflow-x:auto; padding-bottom:2px;">
                    ${categoryTabs.map(cat => {
                        const isActive = activeCategory === cat.id;
                        const col = cat.color || 'var(--primary)';
                        return `
                        <button onclick="window._effectModalCategory='${cat.id}'; _renderEffectPickerModal()" style="padding:4px 10px; font-size:0.7rem; border-radius:6px; cursor:pointer; font-weight:${isActive ? 'bold' : 'normal'}; border:1px solid ${isActive ? col : 'rgba(255,255,255,0.1)'}; background:${isActive ? col + '22' : 'rgba(255,255,255,0.03)'}; color:${isActive ? col : '#aaa'}; transition:all 0.15s; white-space:nowrap;">
                            ${cat.label}
                        </button>`;
                    }).join('')}
                </div>
            </div>

            <!-- Contenido Scrollable -->
            <div style="flex:1; overflow-y:auto; padding:1.2rem 1.6rem;">
                ${contentHtml}
            </div>
        </div>
    </div>`;

    const existing = document.getElementById('effect-picker-overlay');
    if (existing) existing.remove();
    document.body.insertAdjacentHTML('beforeend', html);

    if (activeCategory !== 'custom') {
        setTimeout(() => {
            const s = document.getElementById('effect-picker-search');
            if (s) { s.focus(); s.setSelectionRange(s.value.length, s.value.length); }
        }, 50);
    }
};

window.submitCustomEffect = function() {
    const keyInput = document.getElementById('custom-effect-key');
    const labelInput = document.getElementById('custom-effect-label');
    const iconInput = document.getElementById('custom-effect-icon');
    const valInput = document.getElementById('custom-effect-val');

    if (!keyInput || !keyInput.value.trim()) {
        if (keyInput) { keyInput.focus(); keyInput.style.borderColor = '#ff4444'; }
        return;
    }

    const key = keyInput.value.trim().toLowerCase().replace(/\s+/g, '_');
    const label = labelInput ? (labelInput.value.trim() || key) : key;
    const icon = iconInput ? (iconInput.value.trim() || '✨') : '✨';
    const isFlat = (window._customEffectFlat !== undefined) ? window._customEffectFlat : false;
    const val = parseFloat(valInput ? valInput.value : 0.05) || 0.01;

    selectEffectFromPicker(key, val, isFlat, label, icon);
};

window.closeEffectPickerModal = function() {
    const el = document.getElementById('effect-picker-overlay');
    if (el) el.remove();
    window._effectModalTalentIdx = null;
    window._effectModalCallback = null;
};

window.selectEffectFromPicker = function(key, defaultVal, isFlat, label, icon) {
    const idx = window._effectModalTalentIdx;
    const cb = window._effectModalCallback;
    const val = (typeof defaultVal === 'number') ? defaultVal : 0.01;
    const flat = !!isFlat;

    // Si es un grupo de habilidad, abrimos directamente el selector de parámetros para esa habilidad
    if (key.startsWith('skill_group:')) {
        const skId = key.replace('skill_group:', '');
        closeEffectPickerModal();
        if (idx !== null) {
            openSkillParamPickerModal(idx, skId);
        }
        return;
    }

    if (cb) {
        cb({ key, val, flat, label, icon });
    } else if (idx !== null && config?.talentsConfig?.talents?.[idx]) {
        const t = config.talentsConfig.talents[idx];
        if (!t.effects) t.effects = {};
        if (!t.effectsMeta) t.effectsMeta = {};
        t.effects[key] = val;
        t.effectsMeta[key] = { flat: flat };
        renderTalentCreator();
    }
    closeEffectPickerModal();
};

// ═══════════════════════════════════════════════════════════
// SELECTOR DE PARÁMETROS ESPECÍFICOS DE HABILIDAD
// ═══════════════════════════════════════════════════════════
window.openSkillParamPickerModal = function(talentIdx, skId) {
    const cfg = (typeof config !== 'undefined' ? config : (window.config || {})) || {};
    const skills = cfg.skillsData || {};
    const sk = skills[skId] || {};
    const skName = sk.name || skId;
    const t = cfg.talentsConfig?.talents?.[talentIdx];
    if (!t) return;

    const existingEffects = t.effects || {};
    const availableAttrs = Object.entries(window.SKILL_ATTRS || {}).filter(([attrKey]) => {
        return existingEffects[`skill:${skId}:${attrKey}`] === undefined;
    });

    let itemsHtml = '';
    if (availableAttrs.length === 0) {
        itemsHtml = `
            <div style="text-align:center; padding:2rem 1rem; color:#888;">
                <div style="font-size:2rem; margin-bottom:8px;">✅</div>
                <div style="font-size:0.9rem; color:#aaa;">Esta habilidad ya tiene todos los parámetros configurados en este talento.</div>
            </div>
        `;
    } else {
        itemsHtml = `
            <div style="display:grid; grid-template-columns:repeat(auto-fill, minmax(280px, 1fr)); gap:10px;">
                ${availableAttrs.map(([attrKey, attrMeta]) => {
                    const defaultVal = attrKey === 'cd' ? -0.1 : 0.05;
                    const isFlat = false;
                    return `
                    <div onclick="addSkillParamToTalent(${talentIdx}, '${skId.replace(/'/g, "\\'")}', '${attrKey}', ${defaultVal}, ${isFlat})"
                         style="display:flex; align-items:center; gap:12px; padding:12px 14px; border-radius:10px; cursor:pointer; background:rgba(249,115,22,0.05); border:1px solid rgba(249,115,22,0.25); transition:all 0.15s;"
                         onmouseover="this.style.background='rgba(249,115,22,0.15)'; this.style.borderColor='rgba(249,115,22,0.8)'; this.style.transform='translateY(-1px)';"
                         onmouseout="this.style.background='rgba(249,115,22,0.05)'; this.style.borderColor='rgba(249,115,22,0.25)'; this.style.transform='none';">
                        <span style="font-size:1.8rem; flex-shrink:0;">${attrMeta.icon || '⚡'}</span>
                        <div style="flex:1; min-width:0;">
                            <div style="font-size:0.85rem; font-weight:bold; color:white;">${attrMeta.label}</div>
                            <div style="font-size:0.68rem; color:#f97316; font-family:'JetBrains Mono'; margin-top:2px;">skill:${skId}:${attrKey}</div>
                            <div style="font-size:0.62rem; color:#888; margin-top:1px;">Unidad base: ${attrMeta.unit || 'pts'}</div>
                        </div>
                        <span style="font-size:1rem; color:#f97316;">➕</span>
                    </div>`;
                }).join('')}
            </div>
        `;
    }

    const modalHtml = `
    <div id="skill-param-picker-overlay" style="position:fixed; inset:0; background:rgba(0,0,0,0.85); backdrop-filter:blur(10px); z-index:100002; display:flex; align-items:center; justify-content:center; padding:1.5rem;" onclick="if(event.target===this)closeSkillParamPickerModal()">
        <div style="width:100%; max-width:680px; max-height:85vh; display:flex; flex-direction:column; background:#0e121e; border:1px solid rgba(249,115,22,0.4); border-radius:18px; box-shadow:0 30px 90px rgba(0,0,0,0.9); overflow:hidden;">
            <!-- Cabecera -->
            <div style="padding:1.2rem 1.6rem; border-bottom:1px solid rgba(249,115,22,0.15); display:flex; justify-content:space-between; align-items:center; background:rgba(249,115,22,0.06);">
                <div style="display:flex; align-items:center; gap:10px;">
                    <span style="font-size:1.6rem;">🌀</span>
                    <div>
                        <h3 style="color:#f97316; font-size:1.1rem; margin:0; letter-spacing:0.04em;">MODIFICAR PARÁMETRO: ${skName.toUpperCase()}</h3>
                        <div style="font-size:0.72rem; color:#aaa;">Elegí qué atributo de la habilidad querés alterar con este talento</div>
                    </div>
                </div>
                <button onclick="closeSkillParamPickerModal()" style="background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); color:#aaa; cursor:pointer; width:32px; height:32px; border-radius:8px; font-size:1rem; display:flex; align-items:center; justify-content:center; transition:all 0.15s;" onmouseover="this.style.color='#fff'; this.style.borderColor='rgba(255,255,255,0.3)'" onmouseout="this.style.color='#aaa'; this.style.borderColor='rgba(255,255,255,0.1)'">✕</button>
            </div>

            <!-- Contenido -->
            <div style="flex:1; overflow-y:auto; padding:1.4rem 1.6rem;">
                ${itemsHtml}
            </div>
        </div>
    </div>`;

    const existing = document.getElementById('skill-param-picker-overlay');
    if (existing) existing.remove();
    document.body.insertAdjacentHTML('beforeend', modalHtml);
};

window.closeSkillParamPickerModal = function() {
    const el = document.getElementById('skill-param-picker-overlay');
    if (el) el.remove();
};

window.addSkillParamToTalent = function(talentIdx, skId, attrKey, defaultVal, isFlat) {
    const cfg = (typeof config !== 'undefined' ? config : (window.config || {})) || {};
    const t = cfg.talentsConfig?.talents?.[talentIdx];
    if (!t) return;
    if (!t.effects) t.effects = {};
    if (!t.effectsMeta) t.effectsMeta = {};

    const fullKey = `skill:${skId}:${attrKey}`;
    t.effects[fullKey] = defaultVal;
    t.effectsMeta[fullKey] = { flat: !!isFlat };

    closeSkillParamPickerModal();
    renderTalentCreator();
};

window.deleteTalentSkillGroup = function(talentIdx, skId) {
    const cfg = (typeof config !== 'undefined' ? config : (window.config || {})) || {};
    const t = cfg.talentsConfig?.talents?.[talentIdx];
    if (!t || !t.effects) return;

    const prefix = `skill:${skId}:`;
    Object.keys(t.effects).forEach(key => {
        if (key.startsWith(prefix)) {
            delete t.effects[key];
            if (t.effectsMeta && t.effectsMeta[key]) {
                delete t.effectsMeta[key];
            }
        }
    });

    renderTalentCreator();
};

// ═══════════════════════════════════════════════════════════
// TOGGLE FLAT / PERCENTUAL POR EFECTO
// ═══════════════════════════════════════════════════════════
window.toggleEffectFlat = function(talentIdx, key) {
    const t = config.talentsConfig.talents[talentIdx];
    if (!t.effectsMeta) t.effectsMeta = {};
    if (!t.effectsMeta[key]) t.effectsMeta[key] = { flat: false };
    const wasFlat = !!t.effectsMeta[key].flat;
    t.effectsMeta[key].flat = !wasFlat;
    if (t.effects && t.effects[key] !== undefined) {
        t.effects[key] = wasFlat ? (t.effects[key] / 100) : (t.effects[key] * 100);
    }
    renderTalentCreator();
};

// ═══════════════════════════════════════════════════════════
// FUNCIONES CRUD DE EFECTOS
// ═══════════════════════════════════════════════════════════
window.addTalentEffect = function(talentIdx) {
    window.openEffectPickerModal(talentIdx);
};

window.updateTalentEffectKey = function(talentIdx, oldKey, newKey) {
    const t = config.talentsConfig.talents[talentIdx];
    if (t.effects[newKey] !== undefined) return;
    const val = t.effects[oldKey];
    delete t.effects[oldKey];
    t.effects[newKey] = val;
    if (t.effectsMeta) {
        if (t.effectsMeta[oldKey]) { t.effectsMeta[newKey] = t.effectsMeta[oldKey]; delete t.effectsMeta[oldKey]; }
    }
    renderTalentCreator();
};

window.deleteTalentEffect = function(talentIdx, key) {
    const t = config.talentsConfig.talents[talentIdx];
    delete t.effects[key];
    if (t.effectsMeta && t.effectsMeta[key]) delete t.effectsMeta[key];
    renderTalentCreator();
};

window.renderTalentMapper = function(connectingMousePos = null) {
    const canvas = document.getElementById('talent-mapper-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');

    // Inicializar canvas y listeners del mapper si aún no están listos
    if (!canvas._talentMapperInitialized && typeof initTalentMapper === 'function') {
        initTalentMapper();
        return;
    }

    // Sincronizar dimensiones con resolución HiDPI / Retina
    const { w, h, dpr } = (typeof syncTalentCanvasSize === 'function') 
        ? syncTalentCanvasSize() 
        : { w: canvas.width, h: canvas.height, dpr: 1 };

    // Resetear transformada a píxeles lógicos con escala de alta definición
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const talentZoom = (typeof window.talentZoom !== 'undefined') ? window.talentZoom : (typeof window['talentZoom'] !== 'undefined' ? window['talentZoom'] : 1.0);
    const talentPanOffset = (typeof window.talentPanOffset !== 'undefined') ? window.talentPanOffset : (typeof window['talentPanOffset'] !== 'undefined' ? window['talentPanOffset'] : { x: 0, y: 0 });

    // Limpiar canvas
    ctx.clearRect(0, 0, w, h);

    // Helper: world to screen conversion (en coordenadas lógicas)
    const worldToScreen = (wx, wy) => ({
        x: wx * talentZoom + talentPanOffset.x,
        y: wy * talentZoom + talentPanOffset.y
    });

    // ─── REJILLA TÁCTICA SCI-FI ANCLADA AL MUNDO ───
    const minorStep = 40;
    const majorStep = 200;
    const minWorldX = -talentPanOffset.x / talentZoom;
    const maxWorldX = (w - talentPanOffset.x) / talentZoom;
    const minWorldY = -talentPanOffset.y / talentZoom;
    const maxWorldY = (h - talentPanOffset.y) / talentZoom;

    // Cuadrícula menor (se atenúa suavemente al alejar la cámara)
    if (talentZoom > 0.35) {
        const minorAlpha = Math.min(0.06, (talentZoom - 0.35) * 0.12);
        ctx.strokeStyle = `rgba(0, 210, 255, ${minorAlpha})`;
        ctx.lineWidth = 1;
        ctx.beginPath();
        const startX = Math.floor(minWorldX / minorStep) * minorStep;
        for (let wx = startX; wx <= maxWorldX; wx += minorStep) {
            const sx = Math.round(wx * talentZoom + talentPanOffset.x);
            ctx.moveTo(sx, 0);
            ctx.lineTo(sx, h);
        }
        const startY = Math.floor(minWorldY / minorStep) * minorStep;
        for (let wy = startY; wy <= maxWorldY; wy += minorStep) {
            const sy = Math.round(wy * talentZoom + talentPanOffset.y);
            ctx.moveTo(0, sy);
            ctx.lineTo(w, sy);
        }
        ctx.stroke();
    }

    // Cuadrícula mayor (siempre nítida y sutil)
    ctx.strokeStyle = 'rgba(0, 210, 255, 0.12)';
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    const startMajorX = Math.floor(minWorldX / majorStep) * majorStep;
    for (let wx = startMajorX; wx <= maxWorldX; wx += majorStep) {
        const sx = Math.round(wx * talentZoom + talentPanOffset.x);
        ctx.moveTo(sx, 0);
        ctx.lineTo(sx, h);
    }
    const startMajorY = Math.floor(minWorldY / majorStep) * majorStep;
    for (let wy = startMajorY; wy <= maxWorldY; wy += majorStep) {
        const sy = Math.round(wy * talentZoom + talentPanOffset.y);
        ctx.moveTo(0, sy);
        ctx.lineTo(w, sy);
    }
    ctx.stroke();

    // Ejes cartesianos de origen (0, 0)
    const axisX = Math.round(talentPanOffset.x);
    const axisY = Math.round(talentPanOffset.y);
    ctx.strokeStyle = 'rgba(0, 210, 255, 0.25)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    if (axisX >= 0 && axisX <= w) {
        ctx.moveTo(axisX, 0);
        ctx.lineTo(axisX, h);
    }
    if (axisY >= 0 && axisY <= h) {
        ctx.moveTo(0, axisY);
        ctx.lineTo(w, axisY);
    }
    ctx.stroke();

    // Datos del mapper
    const connections = config.talentsConfig.connections || [];
    const nodes = config.talentsConfig.nodes || {};
    const talents = config.talentsConfig.talents || [];

    // ═══ Bounds del árbol + Centro visual (centro siempre en 0,0) ═══
    const ctr = worldToScreen(0, 0);
    const treeNodes = Object.values(nodes);

    // Bounds solo si hay nodos
    if (treeNodes.length > 0) {
        let bMinX = 0, bMinY = 0, bMaxX = 0, bMaxY = 0;
        for (const p of treeNodes) {
            bMinX = Math.min(bMinX, p.x); bMinY = Math.min(bMinY, p.y);
            bMaxX = Math.max(bMaxX, p.x); bMaxY = Math.max(bMaxY, p.y);
        }

        const PAD = 200;
        const tl = worldToScreen(bMinX - PAD, bMinY - PAD);
        const br = worldToScreen(bMaxX + PAD, bMaxY + PAD);

        ctx.strokeStyle = 'rgba(0, 210, 255, 0.12)';
        ctx.lineWidth = 1;
        ctx.setLineDash([8, 6]);
        ctx.strokeRect(tl.x, tl.y, br.x - tl.x, br.y - tl.y);
        ctx.setLineDash([]);
    }

    // Centro visual siempre visible en (0,0)
    const MARK = 18;
    ctx.strokeStyle = 'rgba(255, 215, 0, 0.45)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(ctr.x - MARK, ctr.y);
    ctx.lineTo(ctr.x + MARK, ctr.y);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(ctr.x, ctr.y - MARK);
    ctx.lineTo(ctr.x, ctr.y + MARK);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(ctr.x, ctr.y, MARK * 0.6, 0, Math.PI * 2);
    ctx.stroke();
    ctx.fillStyle = 'rgba(255, 215, 0, 0.6)';
    ctx.beginPath();
    ctx.arc(ctr.x, ctr.y, 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.font = '9px Outfit, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillStyle = 'rgba(255, 215, 0, 0.5)';
    ctx.fillText('CENTRO (0,0)', ctr.x, ctr.y - MARK * 0.6 - 4);

    // Conexiones de talentos (Estilo conductos de energía estelar)
    connections.forEach(conn => {
        const fromNode = nodes[conn.from];
        const toNode = nodes[conn.to];
        if (!fromNode || !toNode) return;

        const start = worldToScreen(fromNode.x, fromNode.y);
        const end = worldToScreen(toNode.x, toNode.y);

        const fromTalent = talents.find(t => t.id === conn.from);
        const toTalent = talents.find(t => t.id === conn.to);
        const col1 = fromTalent ? (getCategoryColor(fromTalent.category) || '#00d2ff') : '#00d2ff';
        const col2 = toTalent ? (getCategoryColor(toTalent.category) || '#00d2ff') : '#00d2ff';

        const lineW = Math.max(2, Math.min(5, 3 * talentZoom));

        ctx.save();
        const grad = ctx.createLinearGradient(start.x, start.y, end.x, end.y);
        grad.addColorStop(0, col1);
        grad.addColorStop(1, col2);

        // Resplandor exterior
        ctx.strokeStyle = grad;
        ctx.lineWidth = lineW;
        ctx.shadowColor = col1;
        ctx.shadowBlur = Math.max(4, 10 * talentZoom);
        ctx.beginPath();
        ctx.moveTo(start.x, start.y);
        ctx.lineTo(end.x, end.y);
        ctx.stroke();

        // Núcleo brillante de plasma blanco
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.45)';
        ctx.lineWidth = Math.max(1, lineW * 0.35);
        ctx.shadowBlur = 0;
        ctx.stroke();
        ctx.restore();
    });

    // Dibujar previsualización de conexión en progreso
    if (connectStartNodeId && connectingMousePos && nodes[connectStartNodeId]) {
        const startNode = nodes[connectStartNodeId];
        const start = worldToScreen(startNode.x, startNode.y);

        ctx.strokeStyle = 'rgba(255, 215, 0, 0.8)';
        ctx.lineWidth = 2;
        ctx.setLineDash([5, 5]);
        ctx.beginPath();
        ctx.moveTo(start.x, start.y);
        ctx.lineTo(connectingMousePos.x, connectingMousePos.y);
        ctx.stroke();
        ctx.setLineDash([]);
    }

    // Dibujar Nodos
    ctx.shadowBlur = 0;

    const searchTerm = talentMapperSearchTerm || '';

    for (const [id, pos] of Object.entries(nodes)) {
        const t = talents.find(x => x.id === id);
        if (!t) continue;

        const screen = worldToScreen(pos.x, pos.y);
        const nodeType = pos.nodeType || 'small';
        const typeInfo = NODE_TYPES[nodeType] || NODE_TYPES.small;
        // Tamaños con mínimo para que no desaparezcan al zoom out
        const radius = Math.max(typeInfo.radius * talentZoom, typeInfo.radius * 0.35);
        const iconSize = Math.max(Math.round(parseInt(typeInfo.iconSize) * talentZoom), Math.round(parseInt(typeInfo.iconSize) * 0.35));
        const labelSize = Math.max(Math.round(parseInt(typeInfo.labelSize) * talentZoom), 8);

        // Aplicar filtro de búsqueda
        if (searchTerm && !t.name.toLowerCase().includes(searchTerm) && !t.id.toLowerCase().includes(searchTerm)) {
            ctx.globalAlpha = 0.2;
            ctx.fillStyle = '#1a1a2e';
            ctx.beginPath();
            ctx.arc(screen.x, screen.y, radius * 0.6, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalAlpha = 1.0;
            continue;
        }

        // Colores dinámicos por rama/categoría
        const catColor = (typeof getCategoryColor === 'function') ? (getCategoryColor(t.category) || '#00d2ff') : '#00d2ff';
        const catColorDark = (typeof darkenHexColor === 'function') ? darkenHexColor(catColor, 0.35) : '#005a7a';

        const isSelected = selectedTalentNodeId === id;
        const isHovered = talentMapperHoveredNode === id;
        const time = Date.now() / 1000;

        // ═══════════════════════════════════════════════════════
        // SMALL NODE - Círculo simple, minimalista
        // ═══════════════════════════════════════════════════════
        if (nodeType === 'small') {
            // Glow sutil
            if (isSelected || isHovered) {
                ctx.shadowColor = catColor;
                ctx.shadowBlur = 12 * (isSelected ? 1.5 : 1);
            }

            // Borde exterior
            ctx.strokeStyle = isSelected ? '#ffffff' : catColor;
            ctx.lineWidth = typeInfo.borderWidth;
            ctx.fillStyle = '#060d1a';
            ctx.beginPath();
            ctx.arc(screen.x, screen.y, radius, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            ctx.shadowBlur = 0;

            // Línea decorativa sutil (anillo interior)
            ctx.strokeStyle = 'rgba(255,255,255,0.06)';
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.arc(screen.x, screen.y, radius - 4 * talentZoom, 0, Math.PI * 2);
            ctx.stroke();

            // Icono
            ctx.font = `${iconSize}px Arial`;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(t.icon || '🌳', screen.x, screen.y);
        }

        // ═══════════════════════════════════════════════════════
        // NOTABLE NODE - Hexágono con gradiente y brillo
        // ═══════════════════════════════════════════════════════
        else if (nodeType === 'notable') {
            const glowPulse = 0.7 + Math.sin(time * 2) * 0.3;

            // Glow exterior animado
            if (isSelected || isHovered) {
                ctx.shadowColor = catColor;
                ctx.shadowBlur = 22 * (isSelected ? 1.5 : 1);
            } else {
                ctx.shadowColor = catColor;
                ctx.shadowBlur = 8 * glowPulse;
            }

            // Borde hexagonal exterior
            ctx.strokeStyle = isSelected ? '#ffffff' : catColor;
            ctx.lineWidth = typeInfo.borderWidth;
            ctx.beginPath();
            for (let i = 0; i < 6; i++) {
                const angle = (Math.PI / 3) * i - Math.PI / 6;
                const hx = screen.x + radius * Math.cos(angle);
                const hy = screen.y + radius * Math.sin(angle);
                i === 0 ? ctx.moveTo(hx, hy) : ctx.lineTo(hx, hy);
            }
            ctx.closePath();

            // Relleno con gradiente radial
            const gradBg = ctx.createRadialGradient(screen.x, screen.y - radius * 0.3, 0, screen.x, screen.y, radius);
            gradBg.addColorStop(0, '#0f2035');
            gradBg.addColorStop(1, '#060d1a');
            ctx.fillStyle = gradBg;
            ctx.fill();
            ctx.stroke();
            ctx.shadowBlur = 0;

            // Borde interior decorativo
            ctx.strokeStyle = 'rgba(255,255,255,0.08)';
            ctx.lineWidth = 1;
            ctx.beginPath();
            for (let i = 0; i < 6; i++) {
                const angle = (Math.PI / 3) * i - Math.PI / 6;
                const hx = screen.x + (radius - 5 * talentZoom) * Math.cos(angle);
                const hy = screen.y + (radius - 5 * talentZoom) * Math.sin(angle);
                i === 0 ? ctx.moveTo(hx, hy) : ctx.lineTo(hx, hy);
            }
            ctx.closePath();
            ctx.stroke();

            // Líneas de esquina decorativas (peak marks)
            ctx.strokeStyle = catColor;
            ctx.lineWidth = 1.5;
            ctx.globalAlpha = 0.4;
            for (let i = 0; i < 6; i++) {
                const angle = (Math.PI / 3) * i - Math.PI / 6;
                const innerR = radius - 3 * talentZoom;
                const outerR = radius + 4 * talentZoom;
                ctx.beginPath();
                ctx.moveTo(screen.x + innerR * Math.cos(angle), screen.y + innerR * Math.sin(angle));
                ctx.lineTo(screen.x + outerR * Math.cos(angle), screen.y + outerR * Math.sin(angle));
                ctx.stroke();
            }
            ctx.globalAlpha = 1.0;

            // Icono
            ctx.font = `${iconSize}px Arial`;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(t.icon || '🌳', screen.x, screen.y);
        }

        // ═══════════════════════════════════════════════════════
        // KEYSTONE NODE - Escudo ornamental con aura animada
        // ═══════════════════════════════════════════════════════
        else if (nodeType === 'keystone') {
            const glowPulse = 0.6 + Math.sin(time * 1.5) * 0.4;
            const rotateAngle = time * 0.3;

            // Aura exterior animada (anillo rotatorio)
            ctx.save();
            ctx.translate(screen.x, screen.y);
            ctx.rotate(rotateAngle);
            ctx.strokeStyle = catColor;
            ctx.lineWidth = 1.5;
            ctx.globalAlpha = 0.2 * glowPulse;
            ctx.beginPath();
            for (let i = 0; i < 12; i++) {
                const a = (Math.PI / 6) * i;
                const r1 = radius + 12 * talentZoom;
                const r2 = radius + 16 * talentZoom;
                ctx.moveTo(r1 * Math.cos(a), r1 * Math.sin(a));
                ctx.lineTo(r2 * Math.cos(a), r2 * Math.sin(a));
            }
            ctx.stroke();
            ctx.globalAlpha = 1.0;
            ctx.restore();

            // Anillo exterior decorativo
            ctx.strokeStyle = 'rgba(255,215,0,0.2)';
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.arc(screen.x, screen.y, radius + 10 * talentZoom, 0, Math.PI * 2);
            ctx.stroke();

            // Glow
            if (isSelected || isHovered) {
                ctx.shadowColor = catColor;
                ctx.shadowBlur = 30 * (isSelected ? 1.5 : 1);
            } else {
                ctx.shadowColor = '#ffd700';
                ctx.shadowBlur = 14 * glowPulse;
            }

            // Borde principal - forma de escudo octogonal
            const outerR = radius;
            const innerR = radius * 0.82;
            ctx.beginPath();
            for (let i = 0; i < 8; i++) {
                const aOuter = (Math.PI / 4) * i - Math.PI / 8;
                const aInner = aOuter + Math.PI / 8;
                const ox = screen.x + outerR * Math.cos(aOuter);
                const oy = screen.y + outerR * Math.sin(aOuter);
                const ix = screen.x + innerR * Math.cos(aInner);
                const iy = screen.y + innerR * Math.sin(aInner);
                i === 0 ? ctx.moveTo(ox, oy) : ctx.lineTo(ox, oy);
                ctx.lineTo(ix, iy);
            }
            ctx.closePath();

            // Relleno con gradiente premium
            const gradKeystone = ctx.createRadialGradient(screen.x, screen.y - radius * 0.4, 0, screen.x, screen.y, radius);
            gradKeystone.addColorStop(0, '#1a2840');
            gradKeystone.addColorStop(0.5, '#0d1a2d');
            gradKeystone.addColorStop(1, '#050a14');
            ctx.fillStyle = gradKeystone;
            ctx.fill();

            // Borde dorado/colored
            const gradBorder = ctx.createLinearGradient(screen.x - radius, screen.y - radius, screen.x + radius, screen.y + radius);
            gradBorder.addColorStop(0, catColor);
            gradBorder.addColorStop(0.5, '#ffd700');
            gradBorder.addColorStop(1, catColor);
            ctx.strokeStyle = gradBorder;
            ctx.lineWidth = typeInfo.borderWidth + 1;
            ctx.stroke();
            ctx.shadowBlur = 0;

            // Borde interior brillante
            ctx.strokeStyle = 'rgba(255,215,0,0.15)';
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.arc(screen.x, screen.y, radius - 6 * talentZoom, 0, Math.PI * 2);
            ctx.stroke();

            // Brillo superior (simula reflejo de cristal)
            const gradShine = ctx.createLinearGradient(screen.x, screen.y - radius, screen.x, screen.y - radius * 0.3);
            gradShine.addColorStop(0, 'rgba(255,255,255,0.12)');
            gradShine.addColorStop(1, 'rgba(255,255,255,0)');
            ctx.fillStyle = gradShine;
            ctx.beginPath();
            ctx.arc(screen.x, screen.y, radius - 2 * talentZoom, -Math.PI * 0.8, -Math.PI * 0.2);
            ctx.lineTo(screen.x + (radius - 2 * talentZoom) * Math.cos(-Math.PI * 0.2), screen.y + (radius - 2 * talentZoom) * Math.sin(-Math.PI * 0.2));
            ctx.arc(screen.x, screen.y, radius * 0.4, -Math.PI * 0.2, -Math.PI * 0.8, true);
            ctx.closePath();
            ctx.fill();

            // Esquinas decorativas (diamantes pequeños)
            ctx.fillStyle = catColor;
            ctx.globalAlpha = 0.6 * glowPulse;
            for (let i = 0; i < 4; i++) {
                const a = (Math.PI / 2) * i + Math.PI / 4;
                const dx = screen.x + (radius + 6 * talentZoom) * Math.cos(a);
                const dy = screen.y + (radius + 6 * talentZoom) * Math.sin(a);
                ctx.save();
                ctx.translate(dx, dy);
                ctx.rotate(Math.PI / 4);
                ctx.fillRect(-2.5 * talentZoom, -2.5 * talentZoom, 5 * talentZoom, 5 * talentZoom);
                ctx.restore();
            }
            ctx.globalAlpha = 1.0;

            // Icono
            ctx.font = `${iconSize}px Arial`;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(t.icon || '🌳', screen.x, screen.y);
        }

        ctx.shadowBlur = 0;

        // Nombre del talento abajo (con sombra para nitidez cristalina)
        if (talentZoom > 0.28) {
            ctx.save();
            ctx.font = `bold ${labelSize}px Outfit, -apple-system, sans-serif`;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'top';
            ctx.fillStyle = 'rgba(0, 0, 0, 0.9)';
            ctx.fillText(t.name, screen.x + 1, screen.y + radius + 8 * talentZoom + 1);
            ctx.fillStyle = isSelected ? '#ffffff' : (isHovered ? '#00ffff' : 'rgba(240, 248, 255, 0.9)');
            ctx.fillText(t.name, screen.x, screen.y + radius + 8 * talentZoom);
            ctx.restore();
        }
    }

    // Actualizar estadísticas de ramas
    updateBranchStats();

    // Renderizar listado de talentos en el panel lateral (agrupados por rama, mapeados primero, ordenados por tamaño)
    const unplacedList = document.getElementById('talent-mapper-unplaced-list');
    if (unplacedList) {
        unplacedList.innerHTML = '';
        const cats = (typeof getCategories === 'function') ? getCategories() : [];
        const allTalents = talents.filter(t => {
            if (searchTerm && !t.name.toLowerCase().includes(searchTerm) && !t.id.toLowerCase().includes(searchTerm)) return false;
            return true;
        });

        // Recolectar ramas en orden
        const catIds = [...new Set([...cats.map(c => c.id), ...allTalents.map(t => t.category)])];

        catIds.forEach(catId => {
            const catObj = cats.find(c => c.id === catId) || { id: catId, name: catId.toUpperCase(), color: '#00d2ff', emoji: '📁' };
            const catColor = catObj.color || '#00d2ff';
            const catEmoji = catObj.emoji || '📁';
            const catName = catObj.name || catId;

            const branchTalents = allTalents.filter(t => t.category === catId);
            if (branchTalents.length === 0) return;

            // Ordenar: primero los ya mapeados, luego no mapeados, ambos por tamaño (keystone > notable > small)
            const sortedBranch = (typeof window.sortTalentsMappedAndSize === 'function')
                ? window.sortTalentsMappedAndSize(branchTalents, nodes)
                : branchTalents;

            const mappedCount = sortedBranch.filter(t => !!nodes[t.id]).length;

            // Encabezado de rama
            const groupHeader = document.createElement('div');
            groupHeader.style.cssText = `padding: 6px 10px; margin-top: 10px; margin-bottom: 4px; border-radius: 6px; background: ${catColor}15; border: 1px solid ${catColor}35; display: flex; justify-content: space-between; align-items: center;`;
            groupHeader.innerHTML = `
                <span style="font-weight: bold; color: ${catColor}; font-size: 0.78rem;">${catEmoji} ${catName.toUpperCase()}</span>
                <span style="font-size: 0.68rem; color: #aaa;">${mappedCount}/${sortedBranch.length} mapeados</span>
            `;
            unplacedList.appendChild(groupHeader);

            sortedBranch.forEach(t => {
                const isPlaced = !!nodes[t.id];
                const nd = nodes[t.id] || {};
                const nodeType = nd.nodeType || t.nodeType || 'small';
                const typeLabel = nodeType === 'keystone' ? '🔴 Clave' : (nodeType === 'notable' ? '🟡 Notable' : '🟢 Pequeño');

                const item = document.createElement('div');
                item.className = 'card';
                item.dataset.talentId = t.id;
                item.style.padding = '8px 10px';
                item.style.margin = '0';
                item.style.display = 'flex';
                item.style.alignItems = 'center';
                item.style.justifyContent = 'space-between';
                item.style.border = isPlaced ? `1px solid ${catColor}40` : '1px dashed rgba(255,255,255,0.15)';
                item.style.background = isPlaced ? 'rgba(255,255,255,0.035)' : 'rgba(255,255,255,0.015)';
                item.style.borderRadius = '6px';
                item.style.cursor = isPlaced ? 'pointer' : 'grab';

                if (!isPlaced) {
                    item.draggable = true;
                    item.ondragstart = (ev) => {
                        ev.dataTransfer.setData('text/plain', t.id);
                        ev.dataTransfer.effectAllowed = 'copy';
                    };
                    item.ondblclick = () => placeTalentOnMap(t.id);
                } else {
                    item.onclick = () => {
                        selectedTalentNodeId = t.id;
                        if (typeof showTalentNodeEditor === 'function') showTalentNodeEditor(t.id);
                        if (nodes[t.id] && canvas) {
                            const { w, h } = (typeof syncTalentCanvasSize === 'function') ? syncTalentCanvasSize() : { w: 800, h: 600 };
                            talentPanOffset.x = w / 2 - nodes[t.id].x * talentZoom;
                            talentPanOffset.y = h / 2 - nodes[t.id].y * talentZoom;
                            clampPanOffset();
                        }
                        renderTalentMapper();
                    };
                }

                item.onmouseenter = () => { item.style.background = 'rgba(255,255,255,0.08)'; item.style.borderColor = catColor; };
                item.onmouseleave = () => { item.style.background = isPlaced ? 'rgba(255,255,255,0.035)' : 'rgba(255,255,255,0.015)'; item.style.borderColor = isPlaced ? `${catColor}40` : 'rgba(255,255,255,0.15)'; };

                const actionBtn = isPlaced
                    ? `<button class="btn btn-secondary" style="padding: 4px 8px; font-size: 0.68rem; margin: 0; border-color: ${catColor}60; color: ${catColor};" onclick="event.stopPropagation(); selectedTalentNodeId='${t.id}'; if(typeof showTalentNodeEditor==='function') showTalentNodeEditor('${t.id}'); renderTalentMapper();">🔍 Ver</button>`
                    : `<button class="btn btn-primary" style="padding: 4px 8px; font-size: 0.68rem; margin: 0;" onclick="event.stopPropagation(); placeTalentOnMap('${t.id}')">+ Colocar</button>`;

                const statusTag = isPlaced
                    ? `<span style="font-size: 0.65rem; color: #10b981; font-weight: bold;">📍 Mapeado</span>`
                    : `<span style="font-size: 0.65rem; color: #ef4444; font-weight: bold;">⚠️ Sin Mapear</span>`;

                item.innerHTML = `
                    <div style="display:flex; gap:8px; align-items:center; flex: 1; min-width: 0;">
                        <span style="font-size: 1.4rem; flex-shrink: 0;">${t.icon || '🌳'}</span>
                        <div style="flex: 1; min-width: 0;">
                            <div style="font-weight: bold; font-size: 0.82rem; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${t.name}</div>
                            <div style="font-size: 0.68rem; color: #aaa; display: flex; gap: 6px; align-items: center;">
                                <span>${typeLabel}</span>
                                <span>•</span>
                                ${statusTag}
                            </div>
                        </div>
                    </div>
                    ${actionBtn}
                `;
                unplacedList.appendChild(item);
            });
        });

        if (unplacedList.children.length === 0) {
            unplacedList.innerHTML = '<div style="color:var(--text-dim); text-align:center; padding:2rem; font-size:0.85rem;">No se encontraron talentos.</div>';
        }
    }
};

// ─── TOGLE ACTIVAR ───
window.toggleTimeRestrictions = function(mapId, enabled) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId]) return;
    config.mapsConfig[mapId].timeRestrictionsEnabled = enabled;
    if (enabled && !config.mapsConfig[mapId].allowedHours) {
        config.mapsConfig[mapId].allowedHours = [];
    }
    saveConfig();
    renderMapDetail();
};

// ─── HELPERS DE DÍAS ───
window._toggleNewAllDays = function() {
    const allCb = document.getElementById('new-day-all');
    const isChecked = allCb.checked;
    [0,1,2,3,4,5,6].forEach(i => {
        const cb = document.getElementById('new-day-' + i);
        if (cb) cb.checked = isChecked;
    });
};

window._updateGroupDays = function(gIdx) {
    const dayCbs = [0,1,2,3,4,5,6].map(i => document.querySelector(`.edit-grp-day-${gIdx}[value="${i}"]`));
    const allCb = document.querySelector(`.edit-grp-all-${gIdx}`);
    const allChecked = dayCbs.every(cb => cb && cb.checked);
    if (allCb) allCb.checked = allChecked;
};

window._toggleGroupAllDays = function(gIdx) {
    const allCb = document.querySelector(`.edit-grp-all-${gIdx}`);
    const isChecked = allCb.checked;
    [0,1,2,3,4,5,6].forEach(i => {
        const cb = document.querySelector(`.edit-grp-day-${gIdx}[value="${i}"]`);
        if (cb) cb.checked = isChecked;
    });
};

window._getNewGroupDays = function() {
    const dayCbs = [0,1,2,3,4,5,6].map(i => document.getElementById('new-day-' + i));
    const allCb = document.getElementById('new-day-all');
    if (!dayCbs.every(Boolean)) return [0,1,2,3,4,5,6];
    const checked = dayCbs.filter(cb => cb.checked).map(cb => parseInt(cb.value));
    if (checked.length === 7 || (allCb && allCb.checked)) return [0,1,2,3,4,5,6];
    return checked;
};

window._getEditGroupDays = function(gIdx) {
    const dayCbs = [0,1,2,3,4,5,6].map(i => document.querySelector(`.edit-grp-day-${gIdx}[value="${i}"]`));
    if (!dayCbs.every(Boolean)) return [0,1,2,3,4,5,6];
    const checked = dayCbs.filter(cb => cb.checked).map(cb => parseInt(cb.value));
    const allCb = document.querySelector(`.edit-grp-all-${gIdx}`);
    if (checked.length === 7 || (allCb && allCb.checked)) return [0,1,2,3,4,5,6];
    return checked;
};

// ─── AÑADIR GRUPO NUEVO ───
window.addScheduleGroup = function(mapId) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId]) return;
    const start = document.getElementById('new-range-start').value;
    const end = document.getElementById('new-range-end').value;
    if (!start || !end) {
        showToast("ERROR: Completá Inicio y Fin del horario.");
        return;
    }
    const days = window._getNewGroupDays();
    if (days.length === 0) {
        showToast("ERROR: Seleccioná al menos un día.");
        return;
    }
    if (!config.mapsConfig[mapId].allowedHours) {
        config.mapsConfig[mapId].allowedHours = [];
    }
    config.mapsConfig[mapId].allowedHours.push({ days, hours: [{ start, end }] });
    saveConfig();
    renderMapDetail();
};

// ─── EDITAR GRUPO ───
window.editScheduleGroup = function(mapId, gIdx) {
    window._editingGroupIndex = gIdx;
    renderMapDetail();
};

window.cancelScheduleGroupEdit = function() {
    window._editingGroupIndex = -1;
    renderMapDetail();
};

window.saveScheduleGroup = function(mapId, gIdx) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId] || !config.mapsConfig[mapId].allowedHours) return;
    
    const days = window._getEditGroupDays(gIdx);
    if (days.length === 0) {
        showToast("ERROR: Seleccioná al menos un día.");
        return;
    }
    
    const group = config.mapsConfig[mapId].allowedHours[gIdx];
    const hours = (group.hours || [{ start: "00:00", end: "00:00" }]).map((hr, hIdx) => {
        const startEl = document.getElementById(`edit-hr-start-${gIdx}-${hIdx}`);
        const endEl = document.getElementById(`edit-hr-end-${gIdx}-${hIdx}`);
        if (startEl && endEl) {
            return { start: startEl.value, end: endEl.value };
        }
        return hr;
    });
    
    config.mapsConfig[mapId].allowedHours[gIdx] = { days, hours };
    window._editingGroupIndex = -1;
    saveConfig();
    renderMapDetail();
};

// ─── AÑADIR HORARIO A GRUPO EN EDICIÓN ───
window.addHourToGroup = function(mapId, gIdx) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId] || !config.mapsConfig[mapId].allowedHours) return;
    const startEl = document.getElementById(`edit-new-hr-start-${gIdx}`);
    const endEl = document.getElementById(`edit-new-hr-end-${gIdx}`);
    if (!startEl || !endEl) return;
    const start = startEl.value;
    const end = endEl.value;
    if (!start || !end) {
        showToast("ERROR: Completá Inicio y Fin del nuevo horario.");
        return;
    }
    if (!config.mapsConfig[mapId].allowedHours[gIdx].hours) {
        config.mapsConfig[mapId].allowedHours[gIdx].hours = [];
    }
    config.mapsConfig[mapId].allowedHours[gIdx].hours.push({ start, end });
    // Limpiar campos después de añadir
    startEl.value = '';
    endEl.value = '';
    saveConfig();
    renderMapDetail();
};

// ─── ELIMINAR HORARIO DE GRUPO ───
window.removeGroupHour = function(mapId, gIdx, hIdx) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId] || !config.mapsConfig[mapId].allowedHours) return;
    const group = config.mapsConfig[mapId].allowedHours[gIdx];
    if (!group || !group.hours) return;
    group.hours.splice(hIdx, 1);
    if (group.hours.length === 0) {
        group.hours = [{ start: "00:00", end: "00:00" }];
    }
    saveConfig();
    renderMapDetail();
};

// ─── ELIMINAR GRUPO COMPLETO ───
window.removeScheduleGroup = function(mapId, gIdx) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId] || !config.mapsConfig[mapId].allowedHours) return;
    config.mapsConfig[mapId].allowedHours.splice(gIdx, 1);
    saveConfig();
    renderMapDetail();
};

// ═══════════════════════════════════════════════════════════════════════════════
// SISTEMA DE CLASIFICACIÓN / RANKING
// ═══════════════════════════════════════════════════════════════════════════════
