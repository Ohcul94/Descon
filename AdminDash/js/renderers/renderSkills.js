// AdminDash/js/renderers/renderSkills.js
function renderSkills() {
    const grid = document.getElementById('skills-grid'); grid.innerHTML = '';
    const f = getFilter();
    for(let name in config.skillsData) {
        const s = config.skillsData[name];
        
        // v1.9.2: Filtrar por Esfera seleccionada
        if (s.type !== currentSkillTab) continue;

        if (f && !name.toLowerCase().includes(f) && !JSON.stringify(s).toLowerCase().includes(f)) continue;
        const card = document.createElement('div'); card.className = 'card';
        if(!s.targetFilters) s.targetFilters = { allies: true, enemies: false, bosses: false, players: true, clan: false };
        if(s.targetFilters.clan === undefined) s.targetFilters.clan = false;

        // Ícono actual
        const skillIconWeb = resolveAssetWebUrl(s.icon || '');
        const iconPreviewHtml = skillIconWeb
            ? `<img src="${skillIconWeb}" style="width:72px; height:72px; object-fit:contain; border-radius:10px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:72px; height:72px; border:1px dashed rgba(255,255,255,0.15); border-radius:10px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.7rem; text-align:center; padding:4px;">Sin Ícono</div>`;

        card.innerHTML = `
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <!-- Columna ícono -->
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${iconPreviewHtml}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload('${name}', 'skill_icon')">🖼️ ÍCONO</button>
                    ${s.icon ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="config.skillsData['${name}'].icon=''; renderSkills();">✕ Quitar</button>` : ''}
                </div>
                <!-- Columna nombre + tipo -->
                <div style="flex-grow:1;">
                    <div class="field" style="margin-bottom:0.5rem;"><label>Protocolo (ID Interno)</label><input type="text" value="${name}" style="color:var(--accent); font-weight:bold; background:transparent; border:none;" readonly></div>
                    <div class="field full" style="margin-bottom:0.5rem;"><label>Nombre Público</label><input type="text" value="${s.name || name}" onchange="config.skillsData['${name}'].name = this.value; renderAll();"></div>
                    <div class="field full"><label>Descripción</label><input type="text" value="${s.desc || ''}" onchange="config.skillsData['${name}'].desc = this.value"></div>
                </div>
            </div>
            <div class="form-grid">
                <div class="field"><label>Tipo</label><select onchange="config.skillsData['${name}'].type = this.value"><option value="Defensa" ${s.type==='Defensa'?'selected':''}>Defensa</option><option value="Curación" ${s.type==='Curación'?'selected':''}>Curación</option><option value="Ataque" ${s.type==='Ataque'?'selected':''}>Ataque</option><option value="Utilidad" ${s.type==='Utilidad'?'selected':''}>Utilidad</option></select></div>
                <div class="field"><label>Cooldown (ms)</label><input type="number" value="${s.cd}" onchange="config.skillsData['${name}'].cd = parseInt(this.value)"></div>
                <div class="field"><label>Casteo (ms)</label><input type="number" min="0" max="5000" step="50" value="${s.castTimeMs || 0}" onchange="config.skillsData['${name}'].castTimeMs = parseInt(this.value) || 0"></div>
                <div class="field"><label>Puntos (pts)</label><input type="number" value="${s.amount || 0}" onchange="config.skillsData['${name}'].amount = parseInt(this.value)"></div>
                <div class="field"><label>Rango (px)</label><input type="number" value="${s.range || 0}" onchange="config.skillsData['${name}'].range = parseInt(this.value)"></div>
                ${s.duration !== undefined ? `<div class="field"><label>Duración (ms)</label><input type="number" value="${s.duration}" onchange="config.skillsData['${name}'].duration = parseInt(this.value)"></div>` : ''}
                ${s.radius !== undefined ? `<div class="field"><label>Radio/Área (px)</label><input type="number" value="${s.radius}" onchange="config.skillsData['${name}'].radius = parseInt(this.value)"></div>` : ''}
                ${s.speed !== undefined ? `<div class="field"><label>Velocidad (px/s)</label><input type="number" value="${s.speed}" onchange="config.skillsData['${name}'].speed = parseInt(this.value)"></div>` : ''}
                ${s.width !== undefined ? `<div class="field"><label>Ancho (px)</label><input type="number" value="${s.width}" onchange="config.skillsData['${name}'].width = parseInt(this.value)"></div>` : ''}
                ${s.breakRange !== undefined ? `<div class="field"><label>Rango de Ruptura (px)</label><input type="number" value="${s.breakRange}" onchange="config.skillsData['${name}'].breakRange = parseInt(this.value)"></div>` : ''}
                ${s.tickInterval !== undefined ? `<div class="field"><label>Intervalo Tick (ms)</label><input type="number" value="${s.tickInterval}" onchange="config.skillsData['${name}'].tickInterval = parseInt(this.value)"></div>` : ''}
                ${s.pulse_interval !== undefined ? `<div class="field"><label>Intervalo Pulso (ms)</label><input type="number" value="${s.pulse_interval}" onchange="config.skillsData['${name}'].pulse_interval = parseInt(this.value)"></div>` : ''}
                ${s.heal_amount !== undefined ? `<div class="field"><label>Sanación Onda</label><input type="number" value="${s.heal_amount}" onchange="config.skillsData['${name}'].heal_amount = parseInt(this.value)"></div>` : ''}
                ${s.taunt_duration !== undefined ? `<div class="field"><label>Duración Provocación (ms)</label><input type="number" value="${s.taunt_duration}" onchange="config.skillsData['${name}'].taunt_duration = parseInt(this.value)"></div>` : ''}
                ${s.revive_hp_pct !== undefined ? `<div class="field"><label>Vida al Revivir (%)</label><input type="number" value="${s.revive_hp_pct}" onchange="config.skillsData['${name}'].revive_hp_pct = parseInt(this.value)"></div>` : ''}
                ${s.revive_shield_pct !== undefined ? `<div class="field"><label>Escudo al Revivir (%)</label><input type="number" value="${s.revive_shield_pct}" onchange="config.skillsData['${name}'].revive_shield_pct = parseInt(this.value)"></div>` : ''}
            </div>
            <div style="margin-top: 1.5rem; padding-top: 1rem; border-top: 1px solid rgba(255,255,255,0.05); background: rgba(0,0,0,0.1); border-radius: 8px; padding: 12px;">
                <label style="color:var(--accent); font-size: 0.6rem; font-weight:bold; display:flex; align-items:center; gap:5px; margin-bottom:1rem; letter-spacing: 1px; opacity: 0.8;">
                    <span style="font-size:10px;">🎯</span> PROTOCOLOS DE FILTRADO
                </label>
                <div style="display:grid; grid-template-columns: 1fr 1fr; gap: 12px;">
                    <div style="display:flex; align-items:center; gap:8px; cursor:pointer;" onclick="this.querySelector('input').click()">
                        <input type="checkbox" style="width:14px; height:14px; cursor:pointer; accent-color:var(--accent);" ${s.targetFilters.allies?'checked':''} onchange="config.skillsData['${name}'].targetFilters.allies = this.checked" onclick="event.stopPropagation()">
                        <span style="font-size:0.75rem; color:rgba(255,255,255,0.7); font-weight:500;">Aliados</span>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px; cursor:pointer;" onclick="this.querySelector('input').click()">
                        <input type="checkbox" style="width:14px; height:14px; cursor:pointer; accent-color:var(--accent);" ${s.targetFilters.enemies?'checked':''} onchange="config.skillsData['${name}'].targetFilters.enemies = this.checked" onclick="event.stopPropagation()">
                        <span style="font-size:0.75rem; color:rgba(255,255,255,0.7); font-weight:500;">Enemigos</span>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px; cursor:pointer;" onclick="this.querySelector('input').click()">
                        <input type="checkbox" style="width:14px; height:14px; cursor:pointer; accent-color:var(--accent);" ${s.targetFilters.bosses?'checked':''} onchange="config.skillsData['${name}'].targetFilters.bosses = this.checked" onclick="event.stopPropagation()">
                        <span style="font-size:0.75rem; color:rgba(255,255,255,0.7); font-weight:500;">Bosses</span>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px; cursor:pointer;" onclick="this.querySelector('input').click()">
                        <input type="checkbox" style="width:14px; height:14px; cursor:pointer; accent-color:var(--accent);" ${s.targetFilters.players?'checked':''} onchange="config.skillsData['${name}'].targetFilters.players = this.checked" onclick="event.stopPropagation()">
                        <span style="font-size:0.75rem; color:rgba(255,255,255,0.7); font-weight:500;">Jugadores</span>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px; cursor:pointer;" onclick="this.querySelector('input').click()">
                        <input type="checkbox" style="width:14px; height:14px; cursor:pointer; accent-color:var(--accent);" ${s.targetFilters.clan?'checked':''} onchange="config.skillsData['${name}'].targetFilters.clan = this.checked" onclick="event.stopPropagation()">
                        <span style="font-size:0.75rem; color:rgba(255,255,255,0.7); font-weight:500;">Gente del Clan</span>
                    </div>
                </div>
            </div>
            <div style="margin-top:1rem; padding:1rem; background:rgba(168,85,247,0.06); border:1px solid rgba(168,85,247,0.2); border-radius:8px;">
                <label style="color:#a855f7; font-size:0.65rem; font-weight:bold; letter-spacing:1px; display:flex; align-items:center; gap:6px;">SONIDO DE HABILIDAD (assets/Sonidos/Habilidades/)</label>
                <div style="display:flex; gap:8px; align-items:center; margin-top:0.6rem; flex-wrap:wrap;">
                    <input type="text" placeholder="res://assets/Sonidos/Habilidades/ej.ogg" value="${s.sound || ''}" style="flex:1; min-width:200px; font-size:0.7rem;" onchange="config.skillsData['${name}'].sound = this.value; renderSkills();">
                    <button class="btn" style="padding:6px 10px; font-size:0.65rem; background:rgba(168,85,247,0.12); border:1px solid rgba(168,85,247,0.3); color:#a855f7;" onclick="triggerAssetUpload('${name}', 'skill_sound')">SONIDO</button>
                    ${s.sound ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060;" onclick="config.skillsData['${name}'].sound=''; renderSkills();">Quitar</button><audio controls preload="none" src="${resolveAssetWebUrl(s.sound)}" style="height:28px; width:140px;"></audio>` : ''}
                </div>
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:8px; margin-top:0.6rem;">
                    <div class="field"><label>Volumen <input type="number" id="skill-vol-input-${name.replace(/[^a-zA-Z0-9]/g,'_')}" min="0" max="100" value="${s.soundVolumePercent !== undefined ? s.soundVolumePercent : (s.soundVolume || 50)}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.skillsData['${name}'].soundVolumePercent=v; let s2=document.getElementById('skill-vol-slider-${name.replace(/[^a-zA-Z0-9]/g,'_')}'); if(s2) s2.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.skillsData['${name}'].soundVolumePercent=v; let s2=document.getElementById('skill-vol-slider-${name.replace(/[^a-zA-Z0-9]/g,'_')}'); if(s2) s2.value=v;"> %</label><input type="range" id="skill-vol-slider-${name.replace(/[^a-zA-Z0-9]/g,'_')}" min="0" max="100" value="${s.soundVolumePercent !== undefined ? s.soundVolumePercent : (s.soundVolume || 50)}" oninput="config.skillsData['${name}'].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById('skill-vol-input-${name.replace(/[^a-zA-Z0-9]/g,'_')}'); if(inp) inp.value=this.value;"></div>
                    <div class="field"><label>Distancia Max (px)</label><input type="number" step="50" value="${s.soundMaxDist || 1400}" onchange="config.skillsData['${name}'].soundMaxDist = parseInt(this.value) || 1400"></div>
                </div>
            </div>
            ${requirementsSectionHtml('req_skill_' + reqSectionIdSanitize(name), `config.skillsData["${name.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"]`)}
        `;
        grid.appendChild(card);
    }
}
let lastSessionsData = [];
let lastOnlineData = [];
