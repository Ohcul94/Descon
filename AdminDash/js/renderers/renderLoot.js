// AdminDash/js/renderers/renderLoot.js
function renderLootConfig() {
    updateLootSidebar();
    if (!config || !config.lootConfig) return;
    
    const rangeInput = document.getElementById('loot-interact-range');
    const expInput = document.getElementById('loot-expiration-ms');
    const authCheck = document.getElementById('loot-server-auth');
    const pvpCheck = document.getElementById('loot-pvp-drop');
    
    if (rangeInput) rangeInput.value = config.lootConfig.interactRange || 400;
    if (expInput) expInput.value = config.lootConfig.expirationMs || 300000;
    if (authCheck) authCheck.checked = config.lootConfig.serverAuthoritative !== false;
    if (pvpCheck) pvpCheck.checked = !!config.lootConfig.pvpDropEnabled;

    // Resumen visual de tablas de botín por enemigo
    const summaryGrid = document.getElementById('loot-summary-grid');
    if (!summaryGrid) return;
    summaryGrid.innerHTML = '';

    if (!config.enemyModels) return;

    const sortedIds = Object.keys(config.enemyModels).sort((a, b) => parseInt(a) - parseInt(b));
    let totalEnemiesWithDrops = 0;

    sortedIds.forEach(enemyId => {
        const en = config.enemyModels[enemyId];
        if (!en) return;

        const dropCount = (en.lootDrops && en.lootDrops.length) || 0;
        const isBoss = parseInt(enemyId) >= 100;
        const accentColor = isBoss ? 'var(--accent)' : 'var(--success)';
        const typeLabel = isBoss ? '💀 BOSS' : '👾 REGULAR';

        if (dropCount > 0) totalEnemiesWithDrops++;

        const card = document.createElement('div');
        card.style.cssText = `
            background: rgba(255,255,255,0.02); 
            border: 1px solid rgba(255,255,255,0.06); 
            border-radius: 10px; 
            padding: 1rem 1.2rem; 
            cursor: pointer; 
            transition: all 0.25s;
            display: flex;
            justify-content: space-between;
            align-items: center;
        `;
        card.onmouseenter = function() { 
            this.style.borderColor = 'rgba(6,182,212,0.35)'; 
            this.style.background = 'rgba(6,182,212,0.05)'; 
            this.style.transform = 'translateY(-2px)'; 
        };
        card.onmouseleave = function() { 
            this.style.borderColor = 'rgba(255,255,255,0.06)'; 
            this.style.background = 'rgba(255,255,255,0.02)'; 
            this.style.transform = 'translateY(0)'; 
        };
        card.onclick = () => selectLootEnemy(enemyId);

        card.innerHTML = `
            <div>
                <span style="font-size: 0.6rem; color: ${accentColor}; font-weight: bold;">${typeLabel}</span>
                <div style="font-size: 0.95rem; color: #fff; font-weight: 600; margin-top: 2px;">${en.name || 'Enemigo ' + enemyId}</div>
                <span style="font-size: 0.7rem; color: var(--text-dim);">#ID ${enemyId}</span>
            </div>
            <div style="text-align: center;">
                <div style="font-size: 1.5rem; font-weight: bold; color: ${dropCount > 0 ? accentColor : 'var(--text-dim)'};">${dropCount}</div>
                <div style="font-size: 0.55rem; color: var(--text-dim); text-transform: uppercase;">Drops</div>
            </div>
        `;
        summaryGrid.appendChild(card);
    });
}


function updateLootSidebar() {
    const enemyList = document.getElementById('sidebar-loot-enemies-list');
    const bossList = document.getElementById('sidebar-loot-bosses-list');
    if (!enemyList || !bossList) return;

    enemyList.innerHTML = '';
    bossList.innerHTML = '';

    if (!config || !config.enemyModels) return;

    // Preservar el estado cerrado/abierto de las carpetas de botín
    const closedFolders = new Set();
    document.querySelectorAll('.folder-content').forEach(el => {
        if (el.id && !el.classList.contains('show')) {
            closedFolders.add(el.id);
        }
    });

    const sortedIds = Object.keys(config.enemyModels).sort((a, b) => parseInt(a) - parseInt(b));
    const baseSelectedId = selectedLootEnemyId ? selectedLootEnemyId.split('-')[0] : '';
    const tiers = [
        { suffix: '', label: 'Base (x1)' },
        { suffix: '-A', label: 'Tier A (x2)' },
        { suffix: '-B', label: 'Tier B (x3)' },
        { suffix: '-C', label: 'Tier C (x4)' },
        { suffix: '-D', label: 'Tier D (x5)' }
    ];

    sortedIds.forEach(id => {
        if (id.includes('-')) return; // Omitir variantes en la iteración principal del sidebar
        
        const en = config.enemyModels[id];
        if (!en) return;

        const isBoss = parseInt(id) >= 100;

        if (!isBoss) {
            const isCurrentOpen = baseSelectedId === id && !closedFolders.has(`subfolder-loot-enemy-${id}`);
            
            // Contenedor del grupo de botín
            const groupContainer = document.createElement('div');
            groupContainer.className = 'enemy-group';
            groupContainer.style.display = 'flex';
            groupContainer.style.flexDirection = 'column';

            // Enlace del Enemigo Base (Carpeta)
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
                toggleFolder(`subfolder-loot-enemy-${id}`, e);
                selectLootEnemy(id);
            };
            groupContainer.appendChild(parentLink);

            // Sub-carpeta colapsable para variantes de botín
            const subContainer = document.createElement('div');
            subContainer.id = `subfolder-loot-enemy-${id}`;
            subContainer.className = 'folder-content ' + (isCurrentOpen ? 'show' : '');
            subContainer.style.paddingLeft = '1rem';
            subContainer.style.borderLeft = '1px solid #333';
            subContainer.style.marginLeft = '0.5rem';

            tiers.forEach(t => {
                const subId = `${id}${t.suffix}`;
                const subEn = config.enemyModels[subId];
                if (!subEn) return;
                
                const isSubActive = selectedLootEnemyId === subId;
                const subDropCount = (subEn.lootDrops && subEn.lootDrops.length) || 0;

                const subLink = document.createElement('div');
                subLink.className = 'nav-link sub ' + (isSubActive ? 'active' : '');
                subLink.style.display = 'flex';
                subLink.style.justifyContent = 'space-between';
                subLink.style.alignItems = 'center';
                subLink.style.cursor = 'pointer';
                subLink.innerHTML = `
                    <span>👾 ${t.label}</span>
                    <span style="font-size: 0.55rem; opacity: 0.5; background: rgba(255,255,255,0.05); padding: 1px 4px; border-radius: 3px;">${subDropCount} drops</span>
                `;
                
                subLink.onclick = (e) => {
                    e.stopPropagation();
                    selectLootEnemy(subId);
                };

                subContainer.appendChild(subLink);
            });

            groupContainer.appendChild(subContainer);
            enemyList.appendChild(groupContainer);
        } else {
            // Bosses
            const dropCount = (en.lootDrops && en.lootDrops.length) || 0;
            const isActive = selectedLootEnemyId === id;
            const link = document.createElement('div');
            link.className = 'nav-link sub ' + (isActive ? 'active' : '');
            link.style.cursor = 'pointer';
            link.style.display = 'flex';
            link.style.justifyContent = 'space-between';
            link.style.alignItems = 'center';
            link.innerHTML = `
                <span>💀 ${en.name || 'Boss '+id}</span>
                <span style="font-size: 0.6rem; opacity: 0.5; background: rgba(255,255,255,0.05); padding: 2px 6px; border-radius: 4px;">${dropCount} drops</span>
            `;
            link.onclick = () => selectLootEnemy(id);
            bossList.appendChild(link);
        }
    });
}

function renderEnemyLootDetail() {
    updateLootSidebar();
    const container = document.getElementById('enemy-loot-detail-container');
    if (!container) return;

    const enemyId = selectedLootEnemyId;
    if (!enemyId || !config.enemyModels[enemyId]) {
        container.innerHTML = '<div style="color: var(--text-dim); text-align: center; padding: 4rem;">Seleccioná un enemigo del sidebar para configurar su botín.</div>';
        return;
    }

    const en = config.enemyModels[enemyId];
    if (!en.lootDrops) en.lootDrops = [];

    const isBoss = parseInt(enemyId) >= 100;
    const badgeColor = isBoss ? 'var(--accent)' : 'var(--success)';
    const badgeText = isBoss ? 'BOSS' : 'REGULAR';

    const totalChance = en.lootDrops.reduce((sum, ld) => sum + (ld.chance || 0), 0);
    const avgDrops = totalChance.toFixed(2);

    container.innerHTML = `
        <div class="card" style="width: 100%; margin-bottom: 2rem; border-left: 4px solid ${badgeColor};">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
                <div>
                    <span style="background: ${badgeColor}20; color: ${badgeColor}; padding: 3px 10px; border-radius: 6px; font-size: 0.7rem; font-weight: bold; margin-right: 12px;">${badgeText}</span>
                    <strong style="font-size: 1.4rem; color: #fff;">${en.name}</strong>
                    <span style="color: var(--text-dim); font-size: 0.85rem; margin-left: 8px;">(#ID ${enemyId})</span>
                </div>
                <div style="display: flex; gap: 1rem; align-items: center;">
                    <div style="text-align: center; background: rgba(255,255,255,0.03); padding: 8px 16px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.05);">
                        <div style="font-size: 0.6rem; color: var(--text-dim); text-transform: uppercase;">Items Configurados</div>
                        <div style="font-size: 1.3rem; font-weight: bold; color: var(--accent);">${en.lootDrops.length}</div>
                    </div>
                    <div style="text-align: center; background: rgba(255,255,255,0.03); padding: 8px 16px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.05);">
                        <div style="font-size: 0.6rem; color: var(--text-dim); text-transform: uppercase;">Drops Promedio</div>
                        <div style="font-size: 1.3rem; font-weight: bold; color: var(--primary);"><select id="asset-picker-select" size="12" style="flex:1; overflow-y:auto; padding:8px 12px; width:100%; background:rgba(255,255,255,0.02); color:white; border:1px solid rgba(255,255,255,0.1); border-radius:8px;">
                <!-- Options will be filled dynamically -->
            </select></div>
                </div>
            </div>

            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem; padding-top: 1rem; border-top: 1px solid rgba(255,255,255,0.05);">
                <label style="color: var(--accent); font-size: 0.75rem; font-weight: bold;">🎁 TABLA DE RECOMPENSAS</label>
                <button class="btn btn-primary" style="padding: 6px 16px; font-size: 0.75rem; background: var(--accent); border-color: var(--accent);" onclick="addLootDropFromComponent('${enemyId}', 'enemy-loot-detail-container')">+ AGREGAR RECOMPENSA</button>
            </div>

            <div id="enemy-loot-drops-list" style="display: grid; grid-template-columns: 1fr; gap: 12px;">
                <!-- Rendered dynamically by component -->
            </div>
        </div>
    `;
    window.renderLootTableComponent(enemyId, 'enemy-loot-drops-list');
}

// ==========================================
// MÓDULO DE CRAFTEO Y CREACIÓN (ADMIN DASH)
// ==========================================

// Grupos colapsados por el admin (persisten entre renders dentro de la sesión)
const CRAFTING_COLLAPSE_KEY = 'adminDash_craftingCollapsed';
let collapsedCraftingGroups = new Set();
try {
    const stored = JSON.parse(localStorage.getItem(CRAFTING_COLLAPSE_KEY) || '[]');
    if (Array.isArray(stored)) collapsedCraftingGroups = new Set(stored);
} catch (e) { /* estado corrupto: se ignora */ }
function saveCollapsedCraftingGroups() {
    try { localStorage.setItem(CRAFTING_COLLAPSE_KEY, JSON.stringify(Array.from(collapsedCraftingGroups))); } catch (e) { /* sin almacenamiento */ }
}

window.renderCrafting = function() {
    // Inicializar secciones si no existen
    if (!config.shopItems) config.shopItems = {};
    if (!config.shopItems.resources) {
        config.shopItems.resources = [
            { id: "mat_iron", name: "Mineral de Hierro", desc: "Material básico para fundiciones espaciales.", prices: { hubs: 100, ohcu: 0 }, icon: "res://assets/Materiales/Hierro.png", color: "#9ca3af", type: "resource", tags: [] },
            { id: "mat_copper", name: "Mineral de Cobre", desc: "Utilizado para componentes electrónicos.", prices: { hubs: 200, ohcu: 0 }, icon: "res://assets/Materiales/Cobre.png", color: "#b45309", type: "resource", tags: [] },
            { id: "mat_plasma", name: "Núcleo de Plasma", desc: "Esencia energética altamente inestable.", prices: { hubs: 1000, ohcu: 5 }, icon: "res://assets/Materiales/Plasma.png", color: "#06b6d4", type: "resource", tags: [] },
            { id: "mat_darkmatter", name: "Materia Oscura", desc: "Elemento exótico usado para tecnologías avanzadas.", prices: { hubs: 5000, ohcu: 25 }, icon: "res://assets/Materiales/MateriaOscura.png", color: "#d946ef", type: "resource", tags: [] }
        ];
    }
    if (!config.craftingRecipes) {
        config.craftingRecipes = [];
    }
    if (!config.craftingCategories) {
        config.craftingCategories = [
            { id: "mapas", name: "Mapas", icon: "🗺️", color: "#00d2ff" },
            { id: "armas", name: "Armas", icon: "⚔️", color: "#ff4655" }
        ];
    }

    const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';

    function resolveAssetWebUrl(iconPath) {
        if (!iconPath) return '';
        let path = iconPath.replace(/\\/g, '/');
        if (path.includes('res://assets/')) {
            return path.replace('res://assets/', activeURL + '/assets/');
        }
        let idx = path.indexOf('assets/');
        if (idx !== -1) {
            return activeURL + '/' + path.substring(idx);
        }
        return iconPath;
    }

    function getCraftingCat(catId) {
        return (config.craftingCategories || []).find(c => c.id === catId);
    }

    function craftingTagsHTML(tags, isResource, idx) {
        if (!config.craftingCategories || config.craftingCategories.length === 0) {
            return '<span style="color:#666; font-size:0.7rem;">Sin categorías creadas — ve a la pestaña 🏷️ Categorías para crear grupos.</span>';
        }
        const fn = isResource ? 'toggleResourceTag' : 'toggleRecipeTag';
        return config.craftingCategories.map(cat => {
            const active = (tags || []).includes(cat.id);
            return `<button type="button" onclick="${fn}(${idx}, '${cat.id}')" style="padding:4px 10px; border-radius:20px; font-size:0.7rem; cursor:pointer; ${active
                ? `background:${cat.color || '#00d2ff'}33; border:1px solid ${cat.color || '#00d2ff'}; color:${cat.color || '#00d2ff'}; font-weight:bold;`
                : 'background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.12); color:#999;'}">${cat.icon || '🏷️'} ${cat.name}${active ? ' ✓' : ''}</button>`;
        }).join('');
    }

    function craftingGroupHeaderHTML(cat, count) {
        if (cat) {
            return `<div class="crafting-group-header" onclick="toggleCraftingGroup(this)" title="Click para colapsar / expandir" style="display:flex; align-items:center; gap:10px; padding:0.75rem 1rem; border-radius:8px; background:rgba(0,210,255,0.04); border:1px solid ${cat.color || '#00d2ff'}55; margin-bottom:2px; position:sticky; top:0; z-index:5; cursor:pointer; user-select:none;">
                <span class="chevron" style="font-size:0.65rem; color:#888; width:14px; text-align:center;">▼</span>
                <span style="font-size:1.1rem;">${cat.icon || '🏷️'}</span>
                <span style="font-weight:bold; color:${cat.color || '#00d2ff'}; letter-spacing:1px; font-size:0.85rem;">${(cat.name || 'Categoría').toUpperCase()}</span>
                <span style="color:#666; font-size:0.7rem;">(${count})</span>
            </div>`;
        }
        return `<div class="crafting-group-header" onclick="toggleCraftingGroup(this)" title="Click para colapsar / expandir" style="display:flex; align-items:center; gap:10px; padding:0.75rem 1rem; border-radius:8px; background:rgba(255,255,255,0.02); border:1px dashed rgba(255,255,255,0.12); margin-bottom:2px; cursor:pointer; user-select:none;">
            <span class="chevron" style="font-size:0.65rem; color:#888; width:14px; text-align:center;">▼</span>
            <span style="font-weight:bold; color:#888; letter-spacing:1px; font-size:0.85rem;">SIN CATEGORÍA</span>
            <span style="color:#666; font-size:0.7rem;">(${count})</span>
        </div>`;
    }

    function appendCraftingGroup(listEl, g, gap) {
        if (g.cards.length === 0) return;
        const cat = getCraftingCat(g.tagId);
        const key = g.tagId || 'untagged';

        const wrap = document.createElement('div');
        wrap.style.display = 'flex';
        wrap.style.flexDirection = 'column';
        wrap.style.gap = gap;

        const header = document.createElement('div');
        header.innerHTML = craftingGroupHeaderHTML(cat, g.cards.length);
        const headerEl = header.firstChild;
        headerEl.dataset.groupKey = key;
        wrap.appendChild(headerEl);

        const cardsWrap = document.createElement('div');
        cardsWrap.className = 'crafting-group-cards';
        cardsWrap.style.display = 'flex';
        cardsWrap.style.flexDirection = 'column';
        cardsWrap.style.gap = gap;
        g.cards.forEach(c => cardsWrap.appendChild(c));
        wrap.appendChild(cardsWrap);

        if (collapsedCraftingGroups.has(key)) {
            cardsWrap.style.display = 'none';
            const chev = headerEl.querySelector('.chevron');
            if (chev) chev.innerText = '▶';
            headerEl.style.opacity = '0.5';
        }

        listEl.appendChild(wrap);
    }

    // --- RENDERIZAR CATEGORÍAS ---
    const catsList = document.getElementById('crafting-categories-list');
    if (catsList) {
        catsList.innerHTML = '';
        if (!config.craftingCategories.length) {
            const emptyMsg = document.createElement('div');
            emptyMsg.style.color = '#888';
            emptyMsg.style.fontStyle = 'italic';
            emptyMsg.style.padding = '1rem';
            emptyMsg.innerText = 'No hay categorías todavía. Hacé clic en "+ AGREGAR CATEGORÍA" para crear la primera (ej: Mapas, Armas, Estilos...).';
            catsList.appendChild(emptyMsg);
        }
        config.craftingCategories.forEach((cat, idx) => {
            const div = document.createElement('div');
            div.style.background = 'rgba(255,255,255,0.02)';
            div.style.padding = '1rem 1.25rem';
            div.style.borderRadius = '10px';
            div.style.border = '1px solid ' + (cat.color || '#ffffff') + '44';
            div.style.display = 'flex';
            div.style.alignItems = 'center';
            div.style.gap = '15px';
            div.style.flexWrap = 'wrap';
            div.style.position = 'relative';
            div.innerHTML = `
                <div class="field" style="width: 60px; margin:0; flex-shrink:0;"><label>Icono</label><input type="text" value="${cat.icon || '🏷️'}" style="text-align:center; font-size:1.1rem;" onchange="config.craftingCategories[${idx}].icon = this.value || '🏷️'"></div>
                <div class="field" style="flex:1; min-width:150px; margin:0;"><label>Nombre de la Categoría</label><input type="text" value="${cat.name || ''}" onchange="config.craftingCategories[${idx}].name = this.value; renderCrafting();"></div>
                <div class="field" style="width: 110px; margin:0; flex-shrink:0;"><label>ID única</label><input type="text" value="${cat.id || ''}" onchange="config.craftingCategories[${idx}].id = this.value;"></div>
                <div class="field" style="width: 50px; margin:0; flex-shrink:0;"><label>Color</label><input type="color" value="${cat.color || '#00d2ff'}" style="height:38px; width:100%; padding:0; border:none; background:none; cursor:pointer;" onchange="config.craftingCategories[${idx}].color = this.value;"></div>
                <button class="btn" style="padding:6px 10px; font-size:0.7rem; cursor:pointer;" title="Subir (va primero)" onclick="moveCraftingCategory(${idx}, -1)">↑</button>
                <button class="btn" style="padding:6px 10px; font-size:0.7rem; cursor:pointer;" title="Bajar" onclick="moveCraftingCategory(${idx}, 1)">↓</button>
                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:16px;" title="Eliminar categoría" onclick="removeCraftingCategory(${idx})">✕</button>
            `;
            catsList.appendChild(div);
        });
    }

    // --- RENDERIZAR MATERIALES (AGRUPADOS POR CATEGORÍA) ---
    const resourcesList = document.getElementById('crafting-resources-list');
    if (resourcesList) {
        resourcesList.innerHTML = '';

        function buildResourceCard(res, idx) {
            const div = document.createElement('div');
            div.style.background = 'rgba(255,255,255,0.02)';
            div.style.padding = '1.5rem';
            div.style.borderRadius = '10px';
            div.style.border = '1px solid rgba(255,255,255,0.05)';
            div.style.position = 'relative';

            const resIconWeb = resolveAssetWebUrl(res.icon);
            const previewImgHTML = resIconWeb ? `<img src="${resIconWeb}" style="width:130px; height:130px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.15); background: rgba(0,0,0,0.3); display: block;" onerror="this.style.display='none';">` : `<div style="width:130px; height:130px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.75rem;">Sin Icono</div>`;

            div.innerHTML = `
                <button style="position:absolute; top:8px; right:8px; background:none; border:none; color:#ff4444; cursor:pointer; font-size:16px;" onclick="removeCraftingResource(${idx})">✕</button>
                <div style="display: flex; gap: 20px; align-items: flex-start;">
                    <!-- Preview Image -->
                    <div style="flex-shrink: 0; display: flex; align-items: center; justify-content: center;">
                        ${previewImgHTML}
                    </div>
                    
                    <!-- Form Fields -->
                    <div style="flex-grow: 1; display: flex; flex-direction: column; gap: 10px;">
                        <div class="form-grid" style="grid-template-columns: 1fr 1.5fr; gap:10px; display: grid;">
                            <div class="field"><label>ID de Recurso</label><input type="text" value="${res.id}" onchange="config.shopItems.resources[${idx}].id = this.value; renderCrafting();"></div>
                            <div class="field"><label>Nombre del Material</label><input type="text" value="${res.name}" onchange="config.shopItems.resources[${idx}].name = this.value; renderCrafting();"></div>
                        </div>
                        <div class="field" style="width: 100%;"><label>Descripción</label><input type="text" value="${res.desc || ''}" style="width: 100%;" onchange="config.shopItems.resources[${idx}].desc = this.value;"></div>
                        <div class="field" style="width: 100%;"><label>Icono (Asset del Servidor)</label>
                            <div style="display: flex; gap: 10px; align-items: center; width: 100%;">
                                <div style="flex-grow:1; background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.08); border-radius:6px; padding:8px 12px; font-family:'JetBrains Mono'; font-size:0.75rem; color:${res.icon ? 'var(--primary)' : 'rgba(255,255,255,0.25)'}; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${res.icon || '-- Sin asset asignado --'}</div>
                                <button class="btn btn-primary" style="padding:8px 15px; font-size:0.75rem; flex-shrink:0; background:var(--accent); border-color:var(--accent); white-space:nowrap;" onclick="openAssetPicker(${idx}, 'resource')">🖼 SELECCIONAR ASSET</button>
                            </div>
                        </div>
                        
                        <div style="display: flex; gap: 15px; align-items: center; width: 100%;">
                            <div class="field" style="width: 70px; margin:0; flex-shrink: 0;"><label>Escala</label><input type="number" step="0.1" min="0.1" value="${res.iconScale || 1.0}" style="width: 100%;" onchange="config.shopItems.resources[${idx}].iconScale = parseFloat(this.value) || 1.0;"></div>
                            <div class="field" style="width: 50px; margin:0; flex-shrink: 0;"><label>Color</label><input type="color" value="${res.color || '#ffffff'}" style="height:38px; width:100%; padding:0; border:none; background:none; cursor:pointer;" onchange="config.shopItems.resources[${idx}].color = this.value;"></div>
                            <div class="field" style="width: 90px; margin:0; flex-shrink: 0;"><label>Límite Stack</label><input type="number" min="1" value="${res.maxStack || 1}" onchange="config.shopItems.resources[${idx}].maxStack = parseInt(this.value) || 1;"></div>
                            <div class="field" style="width: 110px; margin:0; flex-shrink: 0;"><label>Precio (Hubs)</label><input type="number" max="9999999" value="${res.prices ? (res.prices.hubs || 0) : 0}" oninput="if(this.value.length > 7) this.value = this.value.slice(0, 7);" onchange="if(!config.shopItems.resources[${idx}].prices) config.shopItems.resources[${idx}].prices = {hubs:0, ohcu:0}; config.shopItems.resources[${idx}].prices.hubs = parseInt(this.value) || 0;"></div>
                            <div class="field" style="width: 110px; margin:0; flex-shrink: 0;"><label>Precio (Ohcu)</label><input type="number" max="9999999" value="${res.prices ? (res.prices.ohcu || 0) : 0}" oninput="if(this.value.length > 7) this.value = this.value.slice(0, 7);" onchange="if(!config.shopItems.resources[${idx}].prices) config.shopItems.resources[${idx}].prices = {hubs:0, ohcu:0}; config.shopItems.resources[${idx}].prices.ohcu = parseInt(this.value) || 0;"></div>
                            <div class="field" style="margin:0; flex-shrink: 0;"><label>No Comerciable</label><input type="checkbox" ${res.soulbound ? 'checked' : ''} onchange="config.shopItems.resources[${idx}].soulbound = this.checked;"></div>
                        </div>

                        <div style="margin-top: 10px; padding-top: 10px; border-top: 1px solid rgba(255,255,255,0.05); width: 100%;">
                            <label style="color:var(--accent); font-size: 0.75rem; font-weight:bold; display:block; margin-bottom:8px;">🏷️ CATEGORÍAS (TOGGLE)</label>
                            <div style="display:flex; flex-wrap:wrap; gap:6px;">${craftingTagsHTML(res.tags, true, idx)}</div>
                        </div>
                    </div>
                </div>
            `;
            return div;
        }

        const resourceGroups = [];
        config.craftingCategories.forEach(c => resourceGroups.push({ tagId: c.id, cards: [] }));
        const untaggedResources = { tagId: null, cards: [] };
        resourceGroups.push(untaggedResources);

        config.shopItems.resources.forEach((res, idx) => {
            const card = buildResourceCard(res, idx);
            const tags = res.tags || [];
            let placed = false;
            for (const g of resourceGroups) {
                if (g.tagId !== null && tags.includes(g.tagId)) {
                    g.cards.push(card);
                    placed = true;
                    break;
                }
            }
            if (!placed) untaggedResources.cards.push(card);
        });

        resourceGroups.forEach(g => appendCraftingGroup(resourcesList, g, '15px'));
    }

    // --- OBTENER TODOS LOS ÍTEMS DEL JUEGO PARA EL SELECTOR ---
    const allGameItems = [];
    if (config.shipModels) {
        config.shipModels.forEach(s => {
            if (s.hidden) return;
            allGameItems.push({ id: String(s.id), name: `[NAVE] ${s.name}`, category: 'ships' });
        });
    }
    if (config.shopItems) {
        if (config.shopItems.weapons) {
            config.shopItems.weapons.forEach(w => allGameItems.push({ id: w.id, name: `[ARMA] ${w.name}`, category: 'weapons' }));
        }
        if (config.shopItems.shields) {
            config.shopItems.shields.forEach(s => allGameItems.push({ id: s.id, name: `[ESCUDO] ${s.name}`, category: 'shields' }));
        }
        if (config.shopItems.engines) {
            config.shopItems.engines.forEach(e => allGameItems.push({ id: e.id, name: `[MOTOR] ${e.name}`, category: 'engines' }));
        }
        if (config.shopItems.extras) {
            config.shopItems.extras.forEach(x => allGameItems.push({ id: x.id, name: `[EXTRA] ${x.name}`, category: 'extras' }));
        }
        if (config.shopItems.ammo) {
            for (let sub in config.shopItems.ammo) {
                config.shopItems.ammo[sub].forEach(a => allGameItems.push({ id: a.id, name: `[MUNI] ${sub.toUpperCase()} - ${a.name}`, category: 'ammo' }));
            }
        }
        if (config.shopItems.resources) {
            config.shopItems.resources.forEach(r => allGameItems.push({ id: r.id, name: `[RECURSO] ${r.name}`, category: 'resources' }));
        }
        if (config.shopItems.spheres) {
            config.shopItems.spheres.forEach(s => allGameItems.push({ id: s.id, name: `[ESFERA] ${s.name}`, category: 'spheres' }));
        }
    }

    // --- RENDERIZAR RECETAS (AGRUPADAS POR CATEGORÍA) ---
    const recipesList = document.getElementById('crafting-recipes-list');
    if (recipesList) {
        recipesList.innerHTML = '';

        function buildRecipeCard(recipe, idx) {
            const div = document.createElement('div');
            div.style.background = 'rgba(255,255,255,0.02)';
            div.style.padding = '1.5rem';
            div.style.borderRadius = '12px';
            div.style.border = '1px solid rgba(255,255,255,0.05)';
            div.style.position = 'relative';

            // Construir select de item resultante
            const selectOptions = allGameItems.map(item => {
                const isSelected = (recipe.resultItemId === item.id && recipe.resultCategory === item.category);
                return `<option value="${item.category}:${item.id}" ${isSelected ? 'selected' : ''}>${item.name}</option>`;
            }).join('');

            // Ingredientes
            const ingredientsHTML = (recipe.ingredients || []).map((ing, ingIdx) => {
                const matSelectOptions = config.shopItems.resources.map(r => {
                    return `<option value="${r.id}" ${ing.itemId === r.id ? 'selected' : ''}>${r.name} (${r.id})</option>`;
                }).join('');

                return `
                    <div style="display: flex; gap: 10px; align-items: center; margin-bottom: 8px;">
                        <select style="background: #0f172a; border: 1px solid rgba(255,255,255,0.1); color: white; padding: 6px 10px; border-radius: 6px; flex: 2;" onchange="updateCraftingRecipeIngredientItem(${idx}, ${ingIdx}, this.value)">
                            <option value="">-- Seleccionar Material --</option>
                            ${matSelectOptions}
                        </select>
                        <input type="number" min="1" value="${ing.amount}" style="background: #0f172a; border: 1px solid rgba(255,255,255,0.1); color: white; padding: 6px 10px; border-radius: 6px; width: 80px; text-align: center;" onchange="updateCraftingRecipeIngredientQty(${idx}, ${ingIdx}, this.value)">
                        <button style="background: rgba(255,68,68,0.1); border: 1px solid rgba(255,68,68,0.2); color: #ff4444; border-radius: 6px; padding: 6px 12px; cursor: pointer;" onclick="removeCraftingRecipeIngredient(${idx}, ${ingIdx})">✕</button>
                    </div>
                `;
            }).join('');

            let resultIcon = '';
            if (recipe.resultCategory === 'ships') {
                const s = config.shipModels?.find(ship => String(ship.id) === String(recipe.resultItemId));
                resultIcon = s ? s.icon : '';
            } else if (recipe.resultCategory === 'ammo') {
                for (let sub in config.shopItems?.ammo || {}) {
                    const a = config.shopItems.ammo[sub].find(item => item.id === recipe.resultItemId);
                    if (a) { resultIcon = a.icon; break; }
                }
            } else {
                const list = config.shopItems?.[recipe.resultCategory] || [];
                const it = list.find(item => item.id === recipe.resultItemId);
                resultIcon = it ? it.icon : '';
            }
            // Usar icono propio de la receta si existe, sino el del item resultante
            const recipeOwnIcon = recipe.icon || '';
            const recipeDisplayIcon = recipeOwnIcon || resultIcon;
            const recipeIconWeb = resolveAssetWebUrl(recipeDisplayIcon);
            const recipePreviewImgHTML = recipeIconWeb ? `<img src="${recipeIconWeb}" style="width:110px; height:110px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.15); background: rgba(0,0,0,0.3); display: block;" onerror="this.style.display='none';">` : `<div style="width:110px; height:110px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.75rem;">Sin Icono</div>`;

            div.innerHTML = `
                <button style="position:absolute; top:12px; right:12px; background:none; border:none; color:#ff4444; cursor:pointer; font-size:18px;" onclick="removeCraftingRecipe(${idx})">✕ ELIMINAR RECETA</button>
                <div style="display: flex; gap: 20px; align-items: flex-start;">
                    <!-- Preview Image + Asset Picker para la receta -->
                    <div style="flex-shrink: 0; display: flex; flex-direction:column; align-items: center; justify-content: center; gap:8px;">
                        ${recipePreviewImgHTML}
                        <button class="btn" style="padding:5px 10px; font-size:0.65rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.2); color:var(--primary); white-space:nowrap; cursor:pointer; border-radius:6px; width:110px;" onclick="openAssetPicker(${idx}, 'recipe')">🖼 ICONO RECETA</button>
                        ${recipeOwnIcon ? `<button style="padding:3px 8px; font-size:0.6rem; background:none; border:1px solid rgba(255,68,68,0.3); color:#ff6b6b; border-radius:4px; cursor:pointer; width:110px;" onclick="config.craftingRecipes[${idx}].icon=''; renderCrafting();">✕ Quitar icono</button>` : ''}
                    </div>
                    
                    <!-- Form Fields -->
                    <div style="flex-grow: 1; display: flex; flex-direction: column; gap: 10px;">
                        <div class="form-grid" style="grid-template-columns: 1fr 1.5fr 50px; gap:15px; display: grid;">
                            <div class="field"><label>ID Única de Receta</label><input type="text" value="${recipe.id}" onchange="config.craftingRecipes[${idx}].id = this.value;"></div>
                            <div class="field"><label>Nombre Visual de la Receta</label><input type="text" value="${recipe.name}" onchange="config.craftingRecipes[${idx}].name = this.value;"></div>
                            <div class="field" style="width: 50px; margin:0; flex-shrink: 0;"><label>Color</label><input type="color" value="${recipe.color || '#ffffff'}" style="height:38px; width:100%; padding:0; border:none; background:none; cursor:pointer;" onchange="config.craftingRecipes[${idx}].color = this.value;"></div>
                        </div>
                        <div class="field" style="width:100%;"><label>Descripción de Receta</label><input type="text" value="${recipe.desc || ''}" style="width:100%;" onchange="config.craftingRecipes[${idx}].desc = this.value;"></div>
                        
                        <div class="form-grid" style="grid-template-columns: 2fr 1fr; gap:15px; display: grid; align-items:center;">
                            <div class="field">
                                <label>Objeto Resultante a Fabricar</label>
                                <select style="background: #0f172a; border: 1px solid rgba(255,255,255,0.1); color: white; font-weight: bold; cursor: pointer; width: 100%; border-radius: 6px; padding: 8px 10px; font-size: 0.85rem;" onchange="updateCraftingRecipeResultItem(${idx}, this.value); renderCrafting();">
                                    <option value="">-- Seleccionar Objeto del Juego --</option>
                                    ${selectOptions}
                                </select>
                            </div>
                            <div class="field"><label>Cantidad Fabricada</label><input type="number" min="1" value="${recipe.resultAmount || 1}" onchange="config.craftingRecipes[${idx}].resultAmount = parseInt(this.value)"></div>
                        </div>

                         <div style="display: flex; gap: 15px; align-items: center; width: 100%;">
                            <div class="field" style="width: 70px; margin:0; flex-shrink: 0;"><label>Escala</label><input type="number" step="0.1" min="0.1" value="${recipe.iconScale || 1.0}" style="width:100%;" onchange="config.craftingRecipes[${idx}].iconScale = parseFloat(this.value) || 1.0;"></div>
                            <div class="field" style="width: 90px; margin:0; flex-shrink: 0;"><label>Límite Stack</label><input type="number" min="1" value="${recipe.maxStack || 1}" onchange="config.craftingRecipes[${idx}].maxStack = parseInt(this.value) || 1;"></div>
                            <div class="field" style="flex-grow:1; margin:0;"><label>Costo de Hubs (qty)</label><input type="number" value="${recipe.costHubs || 0}" onchange="config.craftingRecipes[${idx}].costHubs = parseInt(this.value)"></div>
                            <div class="field" style="flex-grow:1; margin:0;"><label>Costo de Ohcu (qty)</label><input type="number" value="${recipe.costOhcu || 0}" onchange="config.craftingRecipes[${idx}].costOhcu = parseInt(this.value)"></div>
                        </div>

                        <div style="margin-top: 10px; padding-top: 10px; border-top: 1px solid rgba(255,255,255,0.05); width: 100%;">
                            <label style="color:var(--accent); font-size: 0.75rem; font-weight:bold; display:block; margin-bottom:8px;">🏷️ CATEGORÍAS (TOGGLE)</label>
                            <div style="display:flex; flex-wrap:wrap; gap:6px;">${craftingTagsHTML(recipe.tags, false, idx)}</div>
                        </div>

                        <div style="margin-top: 15px; padding-top: 10px; border-top: 1px solid rgba(255,255,255,0.05); width: 100%;">
                            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
                                <label style="color:var(--accent); font-size: 0.75rem; font-weight:bold;">⚙️ INGREDIENTES REQUERIDOS</label>
                                <button class="btn btn-primary" style="padding: 2px 8px; font-size: 0.65rem;" onclick="addCraftingRecipeIngredient(${idx})">+ AGREGAR INGREDIENTE</button>
                            </div>
                            <div id="recipe-ingredients-${idx}">
                                ${ingredientsHTML}
                            </div>
                        </div>
                    </div>
                </div>
            `;
            return div;
        }

        const recipeGroups = [];
        config.craftingCategories.forEach(c => recipeGroups.push({ tagId: c.id, cards: [] }));
        const untaggedRecipes = { tagId: null, cards: [] };
        recipeGroups.push(untaggedRecipes);

        config.craftingRecipes.forEach((recipe, idx) => {
            const card = buildRecipeCard(recipe, idx);
            const tags = recipe.tags || [];
            let placed = false;
            for (const g of recipeGroups) {
                if (g.tagId !== null && tags.includes(g.tagId)) {
                    g.cards.push(card);
                    placed = true;
                    break;
                }
            }
            if (!placed) untaggedRecipes.cards.push(card);
        });

        recipeGroups.forEach(g => appendCraftingGroup(recipesList, g, '1.5rem'));
    }
};

window.addCraftingResource = function() {
    const newId = "mat_new_" + Math.random().toString(36).substr(2, 5);
    config.shopItems.resources.push({
        id: newId,
        name: "Nuevo Material",
        desc: "Descripción del nuevo material.",
        prices: { hubs: 100, ohcu: 0 },
        icon: "res://assets/Materiales/Hierro.png",
        color: "#ffffff",
        type: "resource",
        tags: []
    });
    renderCrafting();
};

window.removeCraftingResource = function(idx) {
    if (confirm("¿Estás seguro de eliminar este material? Esto podría afectar las recetas que lo utilicen.")) {
        config.shopItems.resources.splice(idx, 1);
        renderCrafting();
    }
};

window.addCraftingRecipe = function() {
    const newId = "recipe_new_" + Math.random().toString(36).substr(2, 5);
    config.craftingRecipes.push({
        id: newId,
        name: "Nueva Receta",
        desc: "Descripción de la nueva receta.",
        resultItemId: "",
        resultCategory: "weapons",
        resultAmount: 1,
        costHubs: 1000,
        costOhcu: 0,
        ingredients: [],
        tags: []
    });
    renderCrafting();
};

window.removeCraftingRecipe = function(idx) {
    if (confirm("¿Deseas eliminar esta receta de crafteo?")) {
        config.craftingRecipes.splice(idx, 1);
        renderCrafting();
    }
};

window.addCraftingRecipeIngredient = function(recipeIdx) {
    if (!config.craftingRecipes[recipeIdx].ingredients) {
        config.craftingRecipes[recipeIdx].ingredients = [];
    }
    config.craftingRecipes[recipeIdx].ingredients.push({
        itemId: "",
        amount: 1
    });
    renderCrafting();
};

window.removeCraftingRecipeIngredient = function(recipeIdx, ingIdx) {
    config.craftingRecipes[recipeIdx].ingredients.splice(ingIdx, 1);
    renderCrafting();
};

window.updateCraftingRecipeIngredientItem = function(recipeIdx, ingIdx, value) {
    config.craftingRecipes[recipeIdx].ingredients[ingIdx].itemId = value;
};

window.updateCraftingRecipeIngredientQty = function(recipeIdx, ingIdx, value) {
    config.craftingRecipes[recipeIdx].ingredients[ingIdx].amount = parseInt(value) || 1;
};

window.updateCraftingRecipeResultItem = function(recipeIdx, value) {
    if (!value) {
        config.craftingRecipes[recipeIdx].resultCategory = "weapons";
        config.craftingRecipes[recipeIdx].resultItemId = "";
        return;
    }
    const [category, id] = value.split(':');
    config.craftingRecipes[recipeIdx].resultCategory = category;
    config.craftingRecipes[recipeIdx].resultItemId = id;
};

// --- HANDLERS DE CATEGORÍAS DE CRAFTEO ---

window.addCraftingCategory = function() {
    if (!config.craftingCategories) config.craftingCategories = [];
    config.craftingCategories.push({
        id: "cat_" + Math.random().toString(36).substr(2, 5),
        name: "Nueva Categoría",
        icon: "🏷️",
        color: "#00d2ff"
    });
    renderCrafting();
};

window.removeCraftingCategory = function(idx) {
    const cat = config.craftingCategories && config.craftingCategories[idx];
    if (!cat) return;
    if (!confirm(`¿Eliminar la categoría "${cat.name}"?\nLos materiales y recetas que la usen quedarán sin categoría.`)) return;
    const catId = cat.id;
    config.craftingCategories.splice(idx, 1);
    (config.shopItems?.resources || []).forEach(r => {
        if (r.tags) r.tags = r.tags.filter(t => t !== catId);
    });
    (config.craftingRecipes || []).forEach(rc => {
        if (rc.tags) rc.tags = rc.tags.filter(t => t !== catId);
    });
    renderCrafting();
};

window.moveCraftingCategory = function(idx, dir) {
    const list = config.craftingCategories;
    const target = idx + dir;
    if (!list || target < 0 || target >= list.length) return;
    const tmp = list[idx];
    list[idx] = list[target];
    list[target] = tmp;
    renderCrafting();
};

window.toggleResourceTag = function(idx, tagId) {
    const res = config.shopItems && config.shopItems.resources && config.shopItems.resources[idx];
    if (!res) return;
    if (!res.tags) res.tags = [];
    const pos = res.tags.indexOf(tagId);
    if (pos >= 0) res.tags.splice(pos, 1);
    else res.tags.push(tagId);
    renderCrafting();
};

window.toggleRecipeTag = function(idx, tagId) {
    const recipe = config.craftingRecipes && config.craftingRecipes[idx];
    if (!recipe) return;
    if (!recipe.tags) recipe.tags = [];
    const pos = recipe.tags.indexOf(tagId);
    if (pos >= 0) recipe.tags.splice(pos, 1);
    else recipe.tags.push(tagId);
    renderCrafting();
};

window.toggleCraftingGroup = function(headerEl) {
    const wrap = headerEl.parentElement;
    const cards = wrap.querySelector('.crafting-group-cards');
    if (!cards) return;
    const key = headerEl.dataset.groupKey || 'untagged';
    const collapsed = cards.style.display === 'none';
    cards.style.display = collapsed ? 'flex' : 'none';
    if (collapsed) collapsedCraftingGroups.delete(key);
    else collapsedCraftingGroups.add(key);
    saveCollapsedCraftingGroups();
    const chev = headerEl.querySelector('.chevron');
    if (chev) chev.innerText = collapsed ? '▼' : '▶';
    headerEl.style.opacity = collapsed ? '1' : '0.5';
};

function formatBytes(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatDuration(ms) {
    const totalSecs = Math.floor(ms / 1000);
    const hrs = Math.floor(totalSecs / 3600);
    const mins = Math.floor((totalSecs % 3600) / 60);
    const secs = totalSecs % 60;
    
    let parts = [];
    if (hrs > 0) parts.push(`${hrs}h`);
    if (mins > 0 || hrs > 0) parts.push(`${mins}m`);
    parts.push(`${secs}s`);
    return parts.join(' ');
}

window.renderPerformance = function(data) {
    const perf = data.performance || {};
    const container = document.getElementById('perf-aaa-container');
    if (!container) return;

    // Helper para sparklines SVG autoescalables
    function generateSparkline(history, color) {
        if (!history || history.length === 0) {
            return `<svg viewBox="0 0 100 30" width="100%" height="30"><text x="50%" y="50%" text-anchor="middle" fill="#555" font-size="8">Sin datos</text></svg>`;
        }
        const max = Math.max(...history) || 1;
        const min = Math.min(...history) || 0;
        const range = max - min || 1;
        const width = 100;
        const height = 30;
        const points = history.map((val, idx) => {
            const x = (idx / (history.length - 1)) * width;
            const y = height - ((val - min) / range) * (height - 4) - 2;
            return `${x.toFixed(1)},${y.toFixed(1)}`;
        }).join(' ');
        
        return `
            <svg viewBox="0 0 100 30" width="100%" height="35" style="overflow:visible;">
                <polyline fill="none" stroke="${color}" stroke-width="1.5" points="${points}" />
                <circle cx="100" cy="${(height - ((history[history.length - 1] - min) / range) * (height - 4) - 2).toFixed(1)}" r="2" fill="${color}" />
            </svg>
        `;
    }

    // 1. Análisis de Alertas Automáticas
    let alerts = [];
    
    // Alerta CPU
    if (perf.cpuUsage >= 70) {
        alerts.push({
            type: 'danger',
            icon: '🔥',
            title: 'USO CRÍTICO DE CPU',
            desc: `La CPU del servidor está en ${perf.cpuUsage}%. Reducí la cantidad de entidades activas.`
        });
    } else if (perf.cpuUsage >= 55) {
        alerts.push({
            type: 'warning',
            icon: '⚠️',
            title: 'CPU ELEVADA',
            desc: `Uso de CPU en ${perf.cpuUsage}%. Monitorear de cerca.`
        });
    }

    // Alerta Latencia de Tick
    const p99 = perf.p99TickTime || 0;
    if (p99 >= 33) {
        alerts.push({
            type: 'danger',
            icon: '⏱️',
            title: 'TICK P99 CRÍTICO (STUTTERS)',
            desc: `El percentil 99 de ticks está en ${p99.toFixed(1)} ms. El juego está experimentando tirones graves de físicas/colisiones.`
        });
    } else if (p99 >= 20) {
        alerts.push({
            type: 'warning',
            icon: '⏳',
            title: 'TICK P99 ELEVADO',
            desc: `Latencia P99 en ${p99.toFixed(1)} ms. Posible sobrecarga leve en el bucle principal.`
        });
    }

    // Alerta PPS de Entrada
    const ppsIn = perf.ppsIn || 0;
    if (ppsIn >= 8000) {
        alerts.push({
            type: 'danger',
            icon: '📡',
            title: 'SATURACIÓN DE RED (PPS IN CRÍTICO)',
            desc: `Recibiendo ${ppsIn.toLocaleString()} paquetes/seg. Posible ataque de denegación de servicio o exploit de spam de red.`
        });
    }

    // Alerta Fuga de Memoria (Detección de tendencia creciente en RSS)
    let memoryLeakAlert = false;
    let memLeakGrowth = 0;
    if (perf.rssHistory && perf.rssHistory.length >= 20) {
        const history = perf.rssHistory;
        const len = history.length;
        const initialSamples = history.slice(0, 5);
        const finalSamples = history.slice(len - 5);
        const avgInitial = initialSamples.reduce((a, b) => a + b, 0) / initialSamples.length;
        const avgFinal = finalSamples.reduce((a, b) => a + b, 0) / finalSamples.length;
        if (avgInitial > 0 && avgFinal > avgInitial) {
            memLeakGrowth = ((avgFinal - avgInitial) / avgInitial) * 100;
            if (memLeakGrowth >= 20) {
                memoryLeakAlert = true;
                alerts.push({
                    type: 'danger',
                    icon: '🧠',
                    title: 'FUGA DE MEMORIA DETECTADA (LEAK)',
                    desc: `El uso de RAM RSS ha crecido un +${memLeakGrowth.toFixed(1)}% en las últimas muestras. Posible fuga a largo plazo.`
                });
            }
        }
    }

    // Renderizado del HTML
    let html = '';

    // SECCIÓN 1: PANEL DE ALERTAS
    if (alerts.length > 0) {
        html += `
            <div class="perf-section-title" style="margin: 0 0 1rem 0; color: #ff5555; font-size: 0.9rem; font-weight: bold; letter-spacing: 1px; display: flex; align-items: center; gap: 8px;">
                🔔 ANÁLISIS DE ALERTAS EN TIEMPO REAL
            </div>
            <div style="display: flex; flex-direction: column; gap: 10px; margin-bottom: 2rem;">
        `;
        alerts.forEach(alert => {
            const borderCol = alert.type === 'danger' ? '#ef4444' : '#f59e0b';
            const bgCol = alert.type === 'danger' ? 'rgba(239, 68, 68, 0.05)' : 'rgba(245, 158, 11, 0.05)';
            const titleCol = alert.type === 'danger' ? '#f87171' : '#fbbf24';
            html += `
                <div style="border-left: 4px solid ${borderCol}; background: ${bgCol}; padding: 1rem; border-radius: 4px 8px 8px 4px; display: flex; align-items: flex-start; gap: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);">
                    <div style="font-size: 1.4rem; line-height: 1;">${alert.icon}</div>
                    <div style="flex: 1;">
                        <h4 style="margin: 0 0 4px 0; color: ${titleCol}; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.5px; font-weight: 700;">${alert.title}</h4>
                        <p style="margin: 0; font-size: 0.8rem; color: #ccc; line-height: 1.4;">${alert.desc}</p>
                    </div>
                </div>
            `;
        });
        html += `</div>`;
    } else {
        html += `
            <div style="border-left: 4px solid #10b981; background: rgba(16, 185, 129, 0.03); padding: 0.75rem 1rem; border-radius: 4px 8px 8px 4px; display: flex; align-items: center; gap: 10px; margin-bottom: 2rem; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
                <div style="color: #10b981; font-size: 1.1rem;">✅</div>
                <div style="color: #a7f3d0; font-size: 0.8rem; font-weight: 600;">SISTEMA ESTABLE: Todas las métricas de red, CPU, RAM y latencia están dentro del rango operativo seguro.</div>
            </div>
        `;
    }

    // SECCIÓN 2: TARJETAS GENERALES Y DETALLES DEL PROCESO
    const uptimeStr = formatDuration(data.uptimeMs || 0);
    html += `
        <div class="perf-section-title" style="margin: 0 0 1rem 0; color: var(--accent); font-size: 0.9rem; font-weight: bold; letter-spacing: 1px;">
            📊 TELEMETRÍA GENERAL DEL PROCESO
        </div>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1.5rem; margin-bottom: 2rem;">
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:var(--primary); font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">PILOTOS ONLINE</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${data.playersCount !== undefined ? data.playersCount : '--'}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Jugadores en mapas / lobby</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#ef4444; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">ENEMIGOS ACTIVOS</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${data.enemiesCount !== undefined ? data.enemiesCount : '--'}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">IAs simuladas por AIManager</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#eab308; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">ÁREAS ACTIVAS</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${data.activeAreas !== undefined ? data.activeAreas : '--'}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Grillas AOI cargadas</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#3bff31; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">UPTIME DE INSTANCIA</h4>
                <div style="font-size:1.2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff; height: 2.2rem; display: flex; align-items: center;">${uptimeStr}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Tiempo desde el último inicio</p>
            </div>
        </div>
    `;

    // SECCIÓN 3: TICK TIMES (P99, P50, Avg, Max)
    const p99Val = perf.p99TickTime || 0;
    const p50Val = perf.p50TickTime || 0;
    const avgVal = perf.avgTickTime || 0;
    const maxVal = perf.maxTickTime || 0;

    const p99Color = p99Val >= 33 ? '#ef4444' : (p99Val >= 20 ? '#fbbf24' : '#10b981');
    const p50Color = p50Val >= 16 ? '#ef4444' : (p50Val >= 10 ? '#fbbf24' : '#10b981');
    const avgColor = avgVal >= 16 ? '#ef4444' : (avgVal >= 10 ? '#fbbf24' : '#10b981');

    html += `
        <div class="perf-section-title" style="margin: 0 0 1rem 0; color: var(--accent); font-size: 0.9rem; font-weight: bold; letter-spacing: 1px;">
            ⏱️ ANÁLISIS DE CICLOS DE JUEGO (TICK LATENCY)
        </div>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1.5rem; margin-bottom: 2rem;">
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:${p99Color}; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Percentil 99 (P99)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:${p99Color};">${p99Val.toFixed(1)} ms</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Peor escenario de latencia</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:${p50Color}; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Mediana (P50)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:${p50Color};">${p50Val.toFixed(1)} ms</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Valor típico del Loop</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:${avgColor}; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Promedio (Avg)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:${avgColor};">${avgVal.toFixed(1)} ms</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Promedio móvil ponderado</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#a855f7; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Pico Histórico (Max)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${maxVal.toFixed(1)} ms</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Mayor pico de procesamiento</p>
            </div>
        </div>
    `;

    // SECCIÓN 4: MÉTRICAS DE RED EN TIEMPO REAL
    const incomingPps = perf.ppsIn || 0;
    const outgoingPps = perf.ppsOut || 0;
    const incomingBytes = formatBytes(perf.network?.totalBytesReceived || 0);
    const outgoingBytes = formatBytes(perf.network?.totalBytesSent || 0);

    html += `
        <div class="perf-section-title" style="margin: 0 0 1rem 0; color: var(--accent); font-size: 0.9rem; font-weight: bold; letter-spacing: 1px;">
            📡 TELEMETRÍA DE RED (BANDWIDTH & PACKETS)
        </div>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1.5rem; margin-bottom: 2rem;">
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:var(--primary); font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Paquetes Entrantes (PPS In)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${incomingPps.toLocaleString()} <span style="font-size: 0.9rem; opacity: 0.7;">pkts/s</span></div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Tasa de entrada actual</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#f43f5e; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Paquetes Salientes (PPS Out)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${outgoingPps.toLocaleString()} <span style="font-size: 0.9rem; opacity: 0.7;">pkts/s</span></div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Tasa de salida actual</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#3bff31; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Total Tráfico Recibido</h4>
                <div style="font-size:1.8rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff; height: 2.2rem; display: flex; align-items: center;">⬇️ ${incomingBytes}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Acumulado de bajada (Ingreso)</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#3bff31; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Total Tráfico Enviado</h4>
                <div style="font-size:1.8rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff; height: 2.2rem; display: flex; align-items: center;">⬆️ ${outgoingBytes}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Acumulado de subida (Egreso)</p>
            </div>
        </div>
    `;

    // SECCIÓN 5: CPU Y MEMORIA (SPARKLINES HISTÓRICOS)
    const rssVal = perf.memoryUsage?.rss || 0;
    const heapVal = perf.memoryUsage?.heapUsed || 0;
    const heapTot = perf.memoryUsage?.heapTotal || 0;
    const cpuPct = perf.cpuUsage || 0;

    html += `
        <div class="perf-section-title" style="margin: 0 0 1rem 0; color: var(--accent); font-size: 0.9rem; font-weight: bold; letter-spacing: 1px;">
            💻 RENDIMIENTO DE RECURSOS DEL SISTEMA
        </div>
        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 1.5rem; margin-bottom: 2rem;">
            <!-- Uso de CPU -->
            <div class="card" style="background: rgba(0,210,255,0.02); border: 1px solid rgba(0,210,255,0.12); padding: 1.5rem; display: flex; flex-direction: column; justify-content: space-between;">
                <div>
                    <h4 style="margin:0 0 10px 0; color:var(--primary); font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">USO DE CPU DEL PROCESO</h4>
                    <div style="font-size:2.5rem; font-weight:800; font-family:'JetBrains Mono'; color:#fff; margin-bottom: 1rem;">${cpuPct}%</div>
                </div>
                <div>
                    <div style="width: 100%; height: 8px; background: rgba(255,255,255,0.05); border-radius: 4px; overflow: hidden; margin-bottom: 6px;">
                        <div style="width: ${cpuPct}%; height: 100%; background: ${cpuPct >= 70 ? 'var(--danger)' : (cpuPct >= 50 ? 'var(--warning)' : 'var(--primary)')}; border-radius: 4px; transition: width 0.3s ease;"></div>
                    </div>
                    <p style="margin:0; font-size:0.7rem; opacity:0.6;">Carga actual sobre el núcleo asignado</p>
                </div>
            </div>

            <!-- Historial de Memoria con Sparklines SVG -->
            <div class="card" style="background: rgba(0,210,255,0.02); border: 1px solid rgba(0,210,255,0.12); padding: 1.5rem;">
                <h4 style="margin:0 0 15px 0; color:var(--accent); font-size:0.75rem; text-transform:uppercase; letter-spacing:1px; display: flex; justify-content: space-between;">
                    <span>📈 HISTORIAL Y TENDENCIA DE MEMORIA</span>
                    <span style="font-family: 'JetBrains Mono'; font-weight: normal; color: #aaa; text-transform: none;">Últimos 120s (Muestras de 2s)</span>
                </h4>
                
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
                    <!-- RSS Sparkline -->
                    <div style="background: rgba(0,0,0,0.15); padding: 10px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.02);">
                        <div style="display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 5px;">
                            <span style="font-size: 0.75rem; font-weight: bold; color: #60a5fa;">RAM RSS (Física)</span>
                            <span style="font-family: 'JetBrains Mono'; font-size: 0.85rem; font-weight: bold; color: #fff;">${rssVal.toFixed(1)} MB</span>
                        </div>
                        <div style="margin-top: 5px; min-height: 40px;">
                            ${generateSparkline(perf.rssHistory, '#60a5fa')}
                        </div>
                        <p style="margin: 5px 0 0 0; font-size: 0.65rem; opacity: 0.5; text-align: right;">rss footprint</p>
                    </div>

                    <!-- Heap Sparkline -->
                    <div style="background: rgba(0,0,0,0.15); padding: 10px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.02);">
                        <div style="display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 5px;">
                            <span style="font-size: 0.75rem; font-weight: bold; color: #f472b6;">V8 Heap (JS)</span>
                            <span style="font-family: 'JetBrains Mono'; font-size: 0.85rem; font-weight: bold; color: #fff;">${heapVal.toFixed(1)} / ${heapTot.toFixed(1)} MB</span>
                        </div>
                        <div style="margin-top: 5px; min-height: 40px;">
                            ${generateSparkline(perf.heapHistory, '#f472b6')}
                        </div>
                        <p style="margin: 5px 0 0 0; font-size: 0.65rem; opacity: 0.5; text-align: right;">heap usage</p>
                    </div>
                </div>
            </div>
        </div>
    `;

    // SECCIÓN 6: AUDITORÍA DE ANCHO DE BANDA POR PILOTO
    html += `
        <div class="card" style="width: 100%; padding: 0; overflow: hidden; margin-top: 1rem; border: 1px solid rgba(255,255,255,0.05); background: rgba(0,0,0,0.2);">
            <div style="padding: 1.5rem; border-bottom: 1px solid rgba(255,255,255,0.05); display:flex; justify-content:space-between; align-items:center;">
                <h3 style="margin:0; color:var(--primary); font-size: 0.95rem; font-weight: bold;">🕵️ AUDITORÍA DE ANCHO DE BANDA DETALLADA POR PILOTO</h3>
                <span style="font-size:0.8rem; color:#aaa; font-style: italic;">Consumo de red granular y estimación por hora</span>
            </div>
            <table style="width: 100%; border-collapse: collapse; font-size: 0.9rem; text-align: left;">
                <thead style="background: rgba(255,255,255,0.03); border-bottom: 1px solid rgba(255,255,255,0.05);">
                    <tr>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Piloto</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Dirección IP</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Zona</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Uptime Conexión</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Datos Recibidos</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Datos Enviados</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Paquetes (Rx / Tx)</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Latencia</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Consumo Est. / Hora</th>
                    </tr>
                </thead>
                <tbody>
    `;

    const f = getFilter();
    let shownPlayersCount = 0;

    if (!data.playerStats || data.playerStats.length === 0) {
        html += `
            <tr>
                <td colspan="9" style="padding:3rem; text-align:center; color:#666; font-style:italic;">No hay pilotos en órbita en este momento.</td>
            </tr>
        `;
    } else {
        data.playerStats.forEach(p => {
            if (f && !p.username.toLowerCase().includes(f) && !p.ip.includes(f)) return;
            shownPlayersCount++;

            const timeOnline = formatDuration(p.durationMs);
            const recBytes = formatBytes(p.bytesReceived);
            const sentBytes = formatBytes(p.bytesSent);
            const estPerHour = formatBytes(p.totalPerHour || 0);

            const latColor = p.latency < 80 ? '#10b981' : (p.latency < 180 ? '#fbbf24' : '#ef4444');
            const zoneLabel = p.zone !== undefined ? p.zone : 'Desconocida';

            html += `
                <tr style="border-bottom: 1px solid rgba(255,255,255,0.03); transition: background 0.2s;" onmouseover="this.style.background='rgba(255,255,255,0.02)'" onmouseout="this.style.background='transparent'">
                    <td style="padding: 1rem 1.2rem; font-weight: bold; color: var(--primary); font-family: 'JetBrains Mono';">${p.username.toUpperCase()}</td>
                    <td style="padding: 1rem 1.2rem; font-family: 'JetBrains Mono'; opacity: 0.7; font-size: 0.8rem;">${p.ip}</td>
                    <td style="padding: 1rem 1.2rem; font-size: 0.85rem;"><span class="card-tag" style="position:static; background:rgba(234,179,8,0.1); color:#fbbf24; font-size:0.75rem; border: 1px solid rgba(234,179,8,0.25);">${zoneLabel}</span></td>
                    <td style="padding: 1rem 1.2rem; font-size: 0.85rem;">${timeOnline}</td>
                    <td style="padding: 1rem 1.2rem; color: #a5f3fc; font-family: 'JetBrains Mono'; font-size: 0.85rem;">${recBytes}</td>
                    <td style="padding: 1rem 1.2rem; color: #fed7aa; font-family: 'JetBrains Mono'; font-size: 0.85rem;">${sentBytes}</td>
                    <td style="padding: 1rem 1.2rem; font-family: 'JetBrains Mono'; font-size: 0.8rem; opacity: 0.8;">
                        <span style="color: #60a5fa;">⬇️ ${(p.pktReceived || 0).toLocaleString()}</span> / 
                        <span style="color: #f472b6;">⬆️ ${(p.pktSent || 0).toLocaleString()}</span>
                    </td>
                    <td style="padding: 1rem 1.2rem; font-weight: bold; color: ${latColor}; font-family: 'JetBrains Mono'; font-size: 0.85rem;">${p.latency}ms</td>
                    <td style="padding: 1rem 1.2rem; font-weight: bold; color: #3bff31; font-family: 'JetBrains Mono'; font-size: 0.85rem;">${estPerHour}/h</td>
                </tr>
            `;
        });

        if (shownPlayersCount === 0) {
            html += `
                <tr>
                    <td colspan="9" style="padding:3rem; text-align:center; color:#666; font-style:italic;">Ningún piloto coincide con el filtro: "${f}"</td>
                </tr>
            `;
        }
    }

    html += `
                </tbody>
            </table>
        </div>
    `;

    container.innerHTML = html;
};

// ==========================================
// FUNCIONES AUXILIARES DEL MODO ARENA
// ==========================================

window.addArenaMap = function(mapId) {
    if (!mapId) return;
    const idInt = parseInt(mapId);
    if (!config.gameModes.arenas) {
        config.gameModes.arenas = { enabled: true, maps: [], minPlayers: 2 };
    }
    if (!config.gameModes.arenas.maps) config.gameModes.arenas.maps = [];
    if (!config.gameModes.arenas.maps.includes(idInt)) {
        config.gameModes.arenas.maps.push(idInt);
        if (!config.gameModes.arenas.mapConfigs) config.gameModes.arenas.mapConfigs = {};
        config.gameModes.arenas.mapConfigs[idInt] = {
            width: 10000,
            height: 10000,
            nexusRed: { x: 2000, y: 5000, hp: 10000, shield: 5000 },
            nexusBlue: { x: 8000, y: 5000, hp: 10000, shield: 5000 },
            pillars: []
        };
        activeArenaMapId = idInt;
        activeArenaPillarIndex = null;
        renderModes();
    }
};

window.selectArenaMap = function(mapId) {
    activeArenaMapId = mapId ? parseInt(mapId) : null;
    activeArenaPillarIndex = null;
    renderModes();
};

window.addArenaPillar = function() {
    if (!activeArenaMapId) return;
    const mapCfg = config.gameModes.arenas.mapConfigs[activeArenaMapId];
    if (!mapCfg) return;
    if (!mapCfg.pillars) mapCfg.pillars = [];
    
    const newPillar = {
        name: `Pilar ${mapCfg.pillars.length + 1}`,
        team: 'red',
        x: Math.round(mapCfg.width / 2),
        y: Math.round(mapCfg.height / 2),
        damage: 150,
        range: 600,
        ammoType: 'laser',
        attackType: 'fast',
        hp: 3000,
        shield: 1500
    };
    mapCfg.pillars.push(newPillar);
    activeArenaPillarIndex = mapCfg.pillars.length - 1;
    renderModes();
};

window.removeArenaPillar = function(idx) {
    if (!activeArenaMapId) return;
    const mapCfg = config.gameModes.arenas.mapConfigs[activeArenaMapId];
    if (!mapCfg || !mapCfg.pillars) return;
    mapCfg.pillars.splice(idx, 1);
    activeArenaPillarIndex = null;
    renderModes();
};

window.selectArenaPillar = function(idx) {
    activeArenaPillarIndex = idx;
    renderModes();
};

window.addArenaSpawn = function() {
    if (!activeArenaMapId) return;
    const mapCfg = config.gameModes.arenas.mapConfigs[activeArenaMapId];
    if (!mapCfg) return;
    if (!mapCfg.spawns) mapCfg.spawns = [];
    
    const newSpawn = {
        name: `Spawn ${mapCfg.spawns.length + 1}`,
        team: 'red',
        x: Math.round(mapCfg.width / 2),
        y: Math.round(mapCfg.height / 2),
        radius: 200
    };
    mapCfg.spawns.push(newSpawn);
    activeArenaSpawnIndex = mapCfg.spawns.length - 1;
    renderModes();
};

window.removeArenaSpawn = function(idx) {
    if (!activeArenaMapId) return;
    const mapCfg = config.gameModes.arenas.mapConfigs[activeArenaMapId];
    if (!mapCfg || !mapCfg.spawns) return;
    mapCfg.spawns.splice(idx, 1);
    activeArenaSpawnIndex = null;
    renderModes();
};

window.selectArenaSpawn = function(idx) {
    activeArenaSpawnIndex = idx;
    renderModes();
};
