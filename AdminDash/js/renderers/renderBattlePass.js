// AdminDash/js/renderers/renderBattlePass.js
function renderBattlePass() {
    if (!config.battlePassConfig) {
        const niveles = [];
        for (let i = 0; i < 50; i++) {
            niveles.push({
                level: i + 1,
                expRequired: (i + 1) * 2000,
                freeReward: null,
                vipReward: null
            });
        }
        config.battlePassConfig = {
            enabled: true,
            seasonName: "Tempada 1: Alborada Galáctica",
            seasonDurationDays: 30,
            maxLevel: 50,
            vipCostHubs: 50000,
            vipCostOhcu: 200,
            xpSources: {
                killExp: 50,
                bossKillExp: 200,
                questExp: 100,
                extractionExp: 500,
                dailyBonusExp: 1000
            },
            levels: niveles
        };
    }

    const bp = config.battlePassConfig;

    const container = document.getElementById('battlepass-config-container');
    if (!container) return;

    container.innerHTML = `
        <div class="card">
            <h4 style="color:var(--accent); margin-bottom:1rem;">⚙️ CONFIGURACIÓN GENERAL</h4>
            <div class="form-grid">
                <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;">
                    <input type="checkbox" id="bp-enabled" ${bp.enabled ? 'checked' : ''} onchange="config.battlePassConfig.enabled = this.checked">
                    <label for="bp-enabled" style="margin:0; cursor:pointer;">Pase de Batalla Activado</label>
                </div>
                <div class="field full"><label>Nombre de la Temporada</label><input type="text" value="${bp.seasonName}" onchange="config.battlePassConfig.seasonName = this.value"></div>
                <div class="field"><label>Duración (días)</label><input type="number" value="${bp.seasonDurationDays}" onchange="config.battlePassConfig.seasonDurationDays = parseInt(this.value)"></div>
                <div class="field"><label>Nivel Máximo</label><input type="number" value="${bp.maxLevel}" onchange="config.battlePassConfig.maxLevel = parseInt(this.value)"></div>
            </div>
        </div>
        <div class="card">
            <h4 style="color:var(--primary); margin-bottom:1rem;">👑 COSTO VIP</h4>
            <div class="form-grid">
                <div class="field"><label>Precio Hubs</label><input type="number" value="${bp.vipCostHubs}" onchange="config.battlePassConfig.vipCostHubs = parseInt(this.value)"></div>
                <div class="field"><label>Precio Ohcu</label><input type="number" value="${bp.vipCostOhcu}" onchange="config.battlePassConfig.vipCostOhcu = parseInt(this.value)"></div>
            </div>
            <h4 style="color:var(--accent); margin-top:2rem; margin-bottom:1rem;">📈 FUENTES DE EXP</h4>
            <div class="form-grid">
                <div class="field"><label>EXP por Kill Normal</label><input type="number" value="${bp.xpSources.killExp}" onchange="config.battlePassConfig.xpSources.killExp = parseInt(this.value)"></div>
                <div class="field"><label>EXP por Boss Kill</label><input type="number" value="${bp.xpSources.bossKillExp}" onchange="config.battlePassConfig.xpSources.bossKillExp = parseInt(this.value)"></div>
                <div class="field"><label>EXP por Misión</label><input type="number" value="${bp.xpSources.questExp}" onchange="config.battlePassConfig.xpSources.questExp = parseInt(this.value)"></div>
                <div class="field"><label>EXP por Extracción</label><input type="number" value="${bp.xpSources.extractionExp}" onchange="config.battlePassConfig.xpSources.extractionExp = parseInt(this.value)"></div>
                <div class="field"><label>EXP Diaria (Bonus)</label><input type="number" value="${bp.xpSources.dailyBonusExp}" onchange="config.battlePassConfig.xpSources.dailyBonusExp = parseInt(this.value)"></div>
            </div>
        </div>
    `;

    // Renderizar niveles
    const levelsContainer = document.getElementById('battlepass-levels-container');
    if (!levelsContainer) return;
    levelsContainer.innerHTML = '';

    const headerCard = document.createElement('div');
    headerCard.className = 'card';
    headerCard.style.width = '100%';
    headerCard.style.marginBottom = '1.5rem';
    headerCard.innerHTML = `
        <h3 style="color: var(--accent); margin-bottom: 1rem; display: flex; align-items: center; gap: 10px;">
            🎯 NIVELES DEL PASE DE BATALLA
            <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem;" onclick="addBattlePassLevel()">+ AGREGAR NIVEL</button>
            <button class="btn btn-secondary" style="padding: 4px 12px; font-size: 0.7rem; background:#ef4444; border-color:#ef4444;" onclick="regenerateBattlePassLevels()">🔄 REGENERAR</button>
        </h3>
        <p style="font-size:0.85rem; color:#aaa; line-height:1.4;">
            Configurá las recompensas de cada nivel del Pase de Batalla. Cada nivel tiene una recompensa <strong style="color:var(--primary);">GRATUITA</strong> 
            y una <strong style="color:var(--accent);">VIP</strong>. Hacé clic en "EDITAR RECOMPENSA" para configurar items, hubs, ohcu o exp.
        </p>
    `;
    levelsContainer.appendChild(headerCard);

    const levelsGrid = document.createElement('div');
    levelsGrid.style.display = 'grid';
    levelsGrid.style.gridTemplateColumns = 'repeat(auto-fill, minmax(300px, 1fr))';
    levelsGrid.style.gap = '1rem';
    levelsContainer.appendChild(levelsGrid);

    const levels = bp.levels || [];
    levels.forEach((lvl, idx) => {
        const card = document.createElement('div');
        card.className = 'card';
        card.style.position = 'relative';
        card.style.borderLeft = '3px solid ' + (lvl.freeReward || lvl.vipReward ? 'var(--accent)' : '#333');

        const freeLabel = lvl.freeReward ? formatRewardPreview(lvl.freeReward) : 'Sin recompensa';
        const vipLabel = lvl.vipReward ? formatRewardPreview(lvl.vipReward) : 'Sin recompensa';

        card.innerHTML = `
            <div style="position:absolute; top:8px; right:8px; display:flex; gap:6px;">
                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.9rem;" onclick="removeBattlePassLevel(${idx})" title="Eliminar nivel">✕</button>
            </div>
            <div class="card-tag" style="background:rgba(6,182,212,0.15); color:var(--accent);">NIVEL ${lvl.level}</div>
            <div class="field full" style="margin-top:0.8rem;">
                <label>EXP Requerida</label>
                <input type="number" value="${lvl.expRequired}" onchange="config.battlePassConfig.levels[${idx}].expRequired = parseInt(this.value)">
            </div>
            <div style="margin-top:1rem; padding-top:0.8rem; border-top:1px solid rgba(255,255,255,0.05);">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
                    <span style="color:var(--primary); font-size:0.8rem; font-weight:bold;">🆓 GRATUITO</span>
                    <button class="btn btn-primary" style="padding:2px 8px; font-size:0.6rem;" onclick="editBattlePassReward(${idx}, 'free')">EDITAR</button>
                </div>
                <div style="font-size:0.75rem; color:#aaa; background:rgba(0,0,0,0.2); padding:6px; border-radius:4px; min-height:30px;">
                    ${freeLabel}
                </div>
            </div>
            <div style="margin-top:0.8rem; padding-top:0.8rem; border-top:1px solid rgba(255,255,255,0.05);">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
                    <span style="color:var(--accent); font-size:0.8rem; font-weight:bold;">👑 VIP</span>
                    <button class="btn btn-primary" style="padding:2px 8px; font-size:0.6rem;" onclick="editBattlePassReward(${idx}, 'vip')">EDITAR</button>
                </div>
                <div style="font-size:0.75rem; color:#aaa; background:rgba(0,0,0,0.2); padding:6px; border-radius:4px; min-height:30px;">
                    ${vipLabel}
                </div>
            </div>
        `;
        levelsGrid.appendChild(card);
    });
}

function formatRewardPreview(reward) {
    if (!reward) return '<span style="color:#555;">Vacío</span>';
    const parts = [];
    if (reward.hubs) parts.push(`💰 ${reward.hubs} Hubs`);
    if (reward.ohcu) parts.push(`💎 ${reward.ohcu} Ohcu`);
    if (reward.exp) parts.push(`📈 ${reward.exp} EXP`);
    if (reward.itemName) parts.push(`📦 ${reward.itemName}${reward.itemAmount ? ' x' + reward.itemAmount : ''}`);
    if (reward.shipId) parts.push(`🚀 Nave ID: ${reward.shipId}`);
    if (reward.isPremium) parts.push('👑 VIP Gratis');
    return parts.length > 0 ? parts.join(' | ') : '<span style="color:#555;">Vacío</span>';
}

function addBattlePassLevel() {
    if (!config.battlePassConfig) config.battlePassConfig = {};
    if (!config.battlePassConfig.levels) config.battlePassConfig.levels = [];
    const lastLvl = config.battlePassConfig.levels.length > 0
        ? config.battlePassConfig.levels[config.battlePassConfig.levels.length - 1]
        : { level: 0, expRequired: 0 };
    config.battlePassConfig.levels.push({
        level: lastLvl.level + 1,
        expRequired: lastLvl.expRequired + 2000,
        freeReward: null,
        vipReward: null
    });
    renderBattlePass();
}

function removeBattlePassLevel(idx) {
    if (!config.battlePassConfig || !config.battlePassConfig.levels) return;
    config.battlePassConfig.levels.splice(idx, 1);
    renderBattlePass();
}

function regenerateBattlePassLevels() {
    if (!config.battlePassConfig) return;
    const maxLevel = config.battlePassConfig.maxLevel || 50;
    const niveles = [];
    for (let i = 0; i < maxLevel; i++) {
        niveles.push({
            level: i + 1,
            expRequired: (i + 1) * 2000,
            freeReward: null,
            vipReward: null
        });
    }
    config.battlePassConfig.levels = niveles;
    renderBattlePass();
}

function editBattlePassReward(levelIdx, track) {
    const bp = config.battlePassConfig;
    if (!bp || !bp.levels || !bp.levels[levelIdx]) return;

    const rewardKey = track === 'free' ? 'freeReward' : 'vipReward';
    const current = bp.levels[levelIdx][rewardKey] || {};

    const overlay = document.createElement('div');
    overlay.style.cssText = 'position:fixed; inset:0; background:rgba(0,0,0,0.85); backdrop-filter:blur(8px); z-index:100000; display:flex; align-items:center; justify-content:center; padding:2rem;';
    overlay.id = 'bp-reward-overlay';

    const card = document.createElement('div');
    card.className = 'card';
    card.style.cssText = 'max-width:500px; width:100%; padding:2rem;';

    card.innerHTML = `
        <h3 style="color:var(--accent); margin-bottom:1.5rem;">🎁 EDITAR RECOMPENSA ${track === 'free' ? 'GRATUITA' : 'VIP'} - NIVEL ${bp.levels[levelIdx].level}</h3>
        <div class="form-grid">
            <div class="field"><label>Hubs</label><input type="number" id="bp-reward-hubs" value="${current.hubs || 0}"></div>
            <div class="field"><label>Ohcu</label><input type="number" id="bp-reward-ohcu" value="${current.ohcu || 0}"></div>
            <div class="field"><label>EXP</label><input type="number" id="bp-reward-exp" value="${current.exp || 0}"></div>
            <div class="field full"><label>Nombre del Ítem</label><input type="text" id="bp-reward-item-name" value="${current.itemName || ''}" placeholder="Ej: laser_01"></div>
            <div class="field"><label>Cantidad del Ítem</label><input type="number" id="bp-reward-item-amount" value="${current.itemAmount || 1}"></div>
            <div class="field"><label>ID de Nave</label><input type="number" id="bp-reward-ship-id" value="${current.shipId || 0}" placeholder="0 = ninguna"></div>
            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;">
                <input type="checkbox" id="bp-reward-is-premium" ${current.isPremium ? 'checked' : ''}>
                <label for="bp-reward-is-premium" style="margin:0; cursor:pointer;">Desbloquear VIP (solo para recompensa gratuita)</label>
            </div>
        </div>
        <div style="display:flex; gap:15px; margin-top:2rem; justify-content:flex-end;">
            <button class="btn btn-secondary" onclick="closeBattlePassRewardEditor()">CANCELAR</button>
            <button class="btn btn-primary" onclick="saveBattlePassReward(${levelIdx}, '${track}')">GUARDAR</button>
        </div>
    `;

    overlay.appendChild(card);
    document.body.appendChild(overlay);
}

function saveBattlePassReward(levelIdx, track) {
    const rewardKey = track === 'free' ? 'freeReward' : 'vipReward';
    const hubs = parseInt(document.getElementById('bp-reward-hubs').value) || 0;
    const ohcu = parseInt(document.getElementById('bp-reward-ohcu').value) || 0;
    const exp = parseInt(document.getElementById('bp-reward-exp').value) || 0;
    const itemName = document.getElementById('bp-reward-item-name').value.trim();
    const itemAmount = parseInt(document.getElementById('bp-reward-item-amount').value) || 1;
    const shipId = parseInt(document.getElementById('bp-reward-ship-id').value) || 0;
    const isPremium = document.getElementById('bp-reward-is-premium').checked;

    const reward = {};
    if (hubs > 0) reward.hubs = hubs;
    if (ohcu > 0) reward.ohcu = ohcu;
    if (exp > 0) reward.exp = exp;
    if (itemName) { reward.itemName = itemName; reward.itemAmount = itemAmount; }
    if (shipId > 0) reward.shipId = shipId;
    if (isPremium) reward.isPremium = true;

    config.battlePassConfig.levels[levelIdx][rewardKey] = Object.keys(reward).length > 0 ? reward : null;
    closeBattlePassRewardEditor();
    renderBattlePass();
}

function closeBattlePassRewardEditor() {
    const overlay = document.getElementById('bp-reward-overlay');
    if (overlay) overlay.remove();
}

const HUD_ELEMENTS_CONFIG = {
    "CenterStats":           { name: "🧬 STATS (CenterStats)", x: 1063,  y: 21,  w: 250, h: 140 },
    "ChatUI":                { name: "💬 CHAT (ChatUI)", x: 12,    y: 545, w: 320, h: 200 },
    "RadarWindow":           { name: "🛰️ RADAR (RadarWindow)", x: 1066,  y: 564, w: 220, h: 220 },
    "SkillsContainer":       { name: "🔥 SKILLS (SkillsContainer)", x: 101,   y: 684, w: 575, h: 65 },
    "PartyHUD":              { name: "👥 PARTY (PartyHUD)", x: 10,    y: 120, w: 220, h: 200 },
    "ControlBar":            { name: "⚙️ MENÚS (ControlBar)", x: 10,    y: 745, w: 340, h: 45 },
    "StatusEffects":         { name: "✨ ESTADOS (StatusEffects)", x: 390,   y: 620, w: 500, h: 55 },
    "CamTouchPadContainer":  { name: "🎥 CÁMARA (CamTouchPad)", x: 1060,  y: 250, w: 190, h: 230 },
    "TargetFrame":           { name: "🎯 ENEMIGO (TargetFrame)", x: 540,  y: 80,  w: 200, h: 65 },
    "CombatMeter":           { name: "⚔️ COMBAT (CombatMeter)", x: 940,  y: 180, w: 340, h: 220 },
    "TopLeft":               { name: "📈 DIAGNÓSTICOS (TopLeft)", x: 10,    y: 10,  w: 180, h: 120 }
};
