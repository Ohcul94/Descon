// AdminDash/js/renderers.js
// Orquestador Principal de Renderizado del Admin Dashboard (Modularizado)

window.resolveAssetWebUrl = function(iconPath) {
    if (!iconPath) return '';
    let path = iconPath;
    const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';
    if (path.includes('res://assets/')) {
        return path.replace('res://assets/', activeURL + '/assets/');
    }
    let idx = path.indexOf('assets/');
    if (idx !== -1) {
        return activeURL + '/' + path.substring(idx);
    }
    return path;
};

function refreshCurrentTab() {
    if(!config || Object.keys(config).length === 0) return;
    const active = document.querySelector('.view.active');
    if(!active) return;
    const tabId = active.id.replace('view-', '');
    const renderMap = {
        'ships': renderShips, 'enemies': renderEnemies, 'ammo': renderAmmo, 'weapons': renderWeapons, 
        'shields': renderShields, 'engines': renderEngines, 'skills': renderSkills, 
        'mechanics': renderMechanicsLib, 'maps': renderMaps, 'users': renderRegisteredUsers,
        'pilot': renderPilot,
        'modes': renderModes,
        'loot': renderLootConfig,
        'enemy-loot': renderEnemyLootDetail,
        'crafting-recipes': renderCrafting,
        'crafting-materials': renderCrafting,
        'crafting-categories': renderCrafting,
        'housing': renderHousing,
        'quests': renderQuests,
        'battlepass': renderBattlePass,
        'talent-creator': renderTalentCreator,
        'talent-mapper': renderTalentMapper,
        'market': renderMarket,
        'sessions': () => (currentSessionSubTab === 'online' ? renderOnlinePlayers() : renderSessions()),
        'ranking': renderRanking,
        'bugreports': renderBugReports
    };
    if(renderMap[tabId]) renderMap[tabId]();
}

function renderAll() {
    if(!config || Object.keys(config).length === 0) return;
    renderShips(); renderEnemies(); renderSkills(); renderMechanicsLib();
    renderMaps(); renderAmmo(); renderWeapons(); renderShields(); renderEngines();
    renderPilot();
    renderModes();
    renderLootConfig();
    renderCrafting();
    renderHousing();
    renderQuests();
    renderBattlePass();
    renderRanking();
    renderMarket();
}

function updateSidebar() {
    const enemyList = document.getElementById('sidebar-enemies-list');
    const bossList = document.getElementById('sidebar-bosses-list');
    const mapList = document.getElementById('sidebar-maps-list');
    if(!enemyList || !bossList || !mapList) return;
    
    // Preservar el estado cerrado/abierto de las carpetas al re-renderizar
    const closedFolders = new Set();
    document.querySelectorAll('.folder-content').forEach(el => {
        if (el.id && !el.classList.contains('show')) {
            closedFolders.add(el.id);
        }
    });

    const searchTerm = (document.getElementById('sidebar-search')?.value || '').toLowerCase();
    enemyList.innerHTML = ''; bossList.innerHTML = ''; mapList.innerHTML = '';

    // Mapas
    for(let id in config.mapsConfig) {
        const m = config.mapsConfig[id];
        if(searchTerm && !m.name.toLowerCase().includes(searchTerm)) continue;
        const link = document.createElement('div');
        link.className = 'nav-link sub ' + (selectedMapId === id ? 'active' : '');
        link.innerHTML = `<span style="color:${m.color}">■</span> ${m.name}`;
        link.onclick = () => selectMap(id);
        mapList.appendChild(link);
    }

    // Enemigos
    const baseSelectedId = selectedEnemyId ? selectedEnemyId.split('-')[0] : '';
    const tiers = [
        { suffix: '', label: 'Base (x1)' },
        { suffix: '-A', label: 'Tier A (x2)' },
        { suffix: '-B', label: 'Tier B (x3)' },
        { suffix: '-C', label: 'Tier C (x4)' },
        { suffix: '-D', label: 'Tier D (x5)' }
    ];

    for(let id in config.enemyModels) {
        if (id.includes('-')) continue; // Ocultar variantes sub-tier de la iteración principal
        
        const en = config.enemyModels[id];
        const matches = en.name.toLowerCase().includes(searchTerm) || id.includes(searchTerm);
        if (!matches) continue;

        if (parseInt(id) < 100) {
            const isCurrentOpen = baseSelectedId === id && !closedFolders.has(`subfolder-enemy-${id}`);
            
            // Contenedor de grupo
            const groupContainer = document.createElement('div');
            groupContainer.className = 'enemy-group';
            groupContainer.style.display = 'flex';
            groupContainer.style.flexDirection = 'column';

            // Enlace del Enemigo Base (Carpeta de nivel medio)
            const parentLink = document.createElement('div');
            parentLink.className = 'nav-link sub ' + (isCurrentOpen ? 'active' : '');
            parentLink.style.display = 'flex';
            parentLink.style.justifyContent = 'space-between';
            parentLink.style.alignItems = 'center';
            parentLink.style.cursor = 'pointer';
            
            parentLink.innerHTML = `
                <span>👾 ${en.name || 'Enemigo '+id}</span>
                <span class="chevron" style="font-size: 0.65rem; transition: transform 0.2s;">${isCurrentOpen ? '▼' : '▶'}</span>
            `;

            parentLink.onclick = (e) => {
                toggleFolder(`subfolder-enemy-${id}`, e);
                selectEnemy(id);
            };
            groupContainer.appendChild(parentLink);

            // Sub-carpeta colapsable con misma estética que subfolder-ammo
            const subContainer = document.createElement('div');
            subContainer.id = `subfolder-enemy-${id}`;
            subContainer.className = 'folder-content ' + (isCurrentOpen ? 'show' : '');
            subContainer.style.paddingLeft = '1rem';
            subContainer.style.borderLeft = '1px solid #333';
            subContainer.style.marginLeft = '0.5rem';

            tiers.forEach(t => {
                const subId = `${id}${t.suffix}`;
                const isSubActive = selectedEnemyId === subId;

                const subLink = document.createElement('div');
                subLink.className = 'nav-link sub ' + (isSubActive ? 'active' : '');
                subLink.innerText = `👾 ${t.label}`;
                subLink.style.cursor = 'pointer';
                
                subLink.onclick = (e) => {
                    e.stopPropagation();
                    selectEnemy(subId);
                };

                subContainer.appendChild(subLink);
            });

            groupContainer.appendChild(subContainer);
            enemyList.appendChild(groupContainer);
        } else {
            // Bosses
            const link = document.createElement('div');
            link.className = 'nav-link sub ' + (selectedEnemyId === id ? 'active' : '');
            link.innerText = `💀 ${en.name || 'Boss '+id}`;
            link.onclick = () => selectEnemy(id);
            bossList.appendChild(link);
        }
    }
}

function initWebHUDDesigner() {
    const canvas = document.getElementById('web-hud-canvas');
    if (!canvas) return;
 
    if (!config.pilotConfig.defaultLayout) {
        // Inicializar con los defaults idénticos a los de fábrica de Godot
        config.pilotConfig.defaultLayout = {
            "TopLeft":         { "x": 10,    "y": 10,    "scale": 0.5, "alpha": 1.0 },
            "PartyHUD":        { "x": 10,    "y": 120,   "scale": 0.5, "alpha": 1.0 },
            "ControlBar":      { "x": 10,    "y": 745,   "scale": 0.5, "alpha": 1.0, "rows": 2 },
            "StatusEffects":   { "x": 390,   "y": 620,   "scale": 0.5, "alpha": 1.0 },
            "CamTouchPadContainer":  { "x": 1060,  "y": 250,   "scale": 0.5, "alpha": 1.0 },
            "TargetFrame":     { "x": 540,   "y": 80,    "scale": 0.5, "alpha": 1.0 },
            "CombatMeter":     { "x": 940,   "y": 180,   "scale": 0.5, "alpha": 1.0 }
        };
    } else {
        if (!config.pilotConfig.defaultLayout["TargetFrame"]) {
            config.pilotConfig.defaultLayout["TargetFrame"] = { "x": 540, "y": 80, "scale": 0.5, "alpha": 1.0 };
        }
        if (!config.pilotConfig.defaultLayout["CombatMeter"]) {
            config.pilotConfig.defaultLayout["CombatMeter"] = { "x": 940, "y": 180, "scale": 0.5, "alpha": 1.0 };
        }
    }

    const layout = config.pilotConfig.defaultLayout;
    
    // Sincronizar el selector de filas de la barra de menús
    const rowsSel = document.getElementById('web-hud-controlbar-rows');
    if (rowsSel) {
        const currentRows = (layout["ControlBar"] && layout["ControlBar"].rows) || 2;
        rowsSel.value = currentRows;
    }

    canvas.innerHTML = `
        <div class="hud-canvas-axis-h"></div>
        <div class="hud-canvas-axis-v"></div>
    `; // Limpiar y meter ejes centrales

    // Dibujar cada elemento en el lienzo
    Object.keys(HUD_ELEMENTS_CONFIG).forEach(winId => {
        const spec = JSON.parse(JSON.stringify(HUD_ELEMENTS_CONFIG[winId]));
        const state = layout[winId] || { x: spec.x, y: spec.y };
        
        // Convertir coordenadas del plano de 1280x800 al canvas de 640x400 (Escala 0.5)
        const webX = state.x / 2.0;
        const webY = state.y / 2.0;
        const webW = spec.w / 2.0;
        const webH = spec.h / 2.0;

        const el = document.createElement('div');
        el.className = 'hud-element';
        el.id = `web-hud-${winId}`;
        el.innerText = spec.name;
        el.style.width = `${webW}px`;
        el.style.height = `${webH}px`;
        el.style.left = `${webX}px`;
        el.style.top = `${webY}px`;

        // Lógica premium de arrastre Drag & Drop en JS
        el.addEventListener('mousedown', (e) => {
            e.preventDefault();
            const startX = e.clientX;
            const startY = e.clientY;
            const elemLeft = el.offsetLeft;
            const elemTop = el.offsetTop;

            const onMouseMove = (moveEvent) => {
                let dx = moveEvent.clientX - startX;
                let dy = moveEvent.clientY - startY;

                let newLeft = elemLeft + dx;
                let newTop = elemTop + dy;

                // Limitar el movimiento estrictamente dentro del canvas (640x400)
                const maxLeft = 640 - webW;
                const maxTop = 400 - webH;

                newLeft = Math.max(0, Math.min(newLeft, maxLeft));
                newTop = Math.max(0, Math.min(newTop, maxTop));

                el.style.left = `${newLeft}px`;
                el.style.top = `${newTop}px`;

                // Guardar la coordenada escalada de vuelta a la base de 1280x800 en memoria
                if (!layout[winId]) layout[winId] = { scale: 0.5, alpha: 1.0 };
                
                if (winId === "SkillsContainer") {
                    const oldX = layout[winId].x !== undefined ? layout[winId].x : spec.x;
                    const oldY = layout[winId].y !== undefined ? layout[winId].y : spec.y;
                    const newX = Math.round(newLeft * 2.0);
                    const newY = Math.round(newTop * 2.0);
                    const dx = newX - oldX;
                    const dy = newY - oldY;

                    const slots = ["LaserSlot", "MissileSlot", "MineSlot", "Sphere1Slot", "Sphere2Slot", "Sphere3Slot", "Sphere4Slot"];
                    slots.forEach(slotId => {
                        if (!layout[slotId]) {
                            const defaultSlots = {
                                "LaserSlot":       { "x": 364.5, "y": 714 },
                                "MissileSlot":     { "x": 449.5, "y": 714 },
                                "MineSlot":        { "x": 534.5, "y": 714 },
                                "Sphere1Slot":     { "x": 619.5, "y": 714 },
                                "Sphere2Slot":     { "x": 704.5, "y": 714 },
                                "Sphere3Slot":     { "x": 789.5, "y": 714 },
                                "Sphere4Slot":     { "x": 874.5, "y": 714 }
                            };
                            layout[slotId] = { 
                                x: defaultSlots[slotId].x, 
                                y: defaultSlots[slotId].y, 
                                scale: 0.5, 
                                alpha: 1.0 
                            };
                        }
                        layout[slotId].x = Math.round(layout[slotId].x + dx);
                        layout[slotId].y = Math.round(layout[slotId].y + dy);
                    });
                }
                
                layout[winId].x = Math.round(newLeft * 2.0);
                layout[winId].y = Math.round(newTop * 2.0);
            };

            const onMouseUp = () => {
                document.removeEventListener('mousemove', onMouseMove);
                document.removeEventListener('mouseup', onMouseUp);
            };

            document.addEventListener('mousemove', onMouseMove);
            document.addEventListener('mouseup', onMouseUp);
        });

        canvas.appendChild(el);
    });
}

window.updateWebHUDControlBarRows = function(val) {
    const rows = parseInt(val) || 2;
    if (!config.pilotConfig.defaultLayout) config.pilotConfig.defaultLayout = {};
    if (!config.pilotConfig.defaultLayout["ControlBar"]) config.pilotConfig.defaultLayout["ControlBar"] = { scale: 0.5, alpha: 1.0 };
    config.pilotConfig.defaultLayout["ControlBar"].rows = rows;
    
    // Actualizar tamaño de la caja en el canvas
    const el = document.getElementById('web-hud-ControlBar');
    if (el) {
        // Escala 0.5
        const w = (rows === 2 ? 260 : 420) / 2.0;
        const h = (rows === 2 ? 85 : 45) / 2.0;
        el.style.width = `${w}px`;
        el.style.height = `${h}px`;
    }
};
