import pathlib
p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
txt = p.read_text(encoding="utf-8")

old_attack = """            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Nombre Público</label><input type="text" value="${m.label}" onchange="config.mechanicsLib['${type}'].label = this.value; renderAll();"></div><div class="field full" style="margin-top:0.5rem;"><label>Descripción</label><input type="text" value="${m.desc || ''}" onchange="config.mechanicsLib['${type}'].desc = this.value"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => fieldLabels[fl] || fl).join(' • ')}</div>`;"""

new_attack = """            const mechSoundWeb = resolveAssetWebUrl(m.sound || '');
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
                    <div class="field"><label>Volumen (dB)</label><input type="number" step="1" value="${m.soundVolumeDb !== undefined ? m.soundVolumeDb : 0}" onchange="config.mechanicsLib['${type}'].soundVolumeDb = parseFloat(this.value) || 0"></div>
                    <div class="field"><label>Dist Max (px)</label><input type="number" step="50" value="${m.soundMaxDist || 1200}" onchange="config.mechanicsLib['${type}'].soundMaxDist = parseInt(this.value) || 1200"></div>
                </div>
            </div>
            <div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => fieldLabels[fl] || fl).join(' • ')}</div>`;"""

if old_attack in txt:
    txt = txt.replace(old_attack, new_attack)
    print("patched attack")
else:
    print("attack not found")

old_def = """            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Nombre Público</label><input type="text" value="${m.label}" onchange="config.defenseLib['${type}'].label = this.value; renderAll();"></div><div class="field full" style="margin-top:0.5rem;"><label>Descripción</label><input type="text" value="${m.desc || ''}" onchange="config.defenseLib['${type}'].desc = this.value"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => fieldLabels[fl] || fl).join(' • ')}</div>`;"""

# defense appears twice? attack is first, defense second. Use replace once for defense after attack patched
if old_def in txt:
    new_def = """            const defSoundWeb = resolveAssetWebUrl(m.sound || '');
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
                    <div class="field"><label>Volumen (dB)</label><input type="number" step="1" value="${m.soundVolumeDb !== undefined ? m.soundVolumeDb : 0}" onchange="config.defenseLib['${type}'].soundVolumeDb = parseFloat(this.value) || 0"></div>
                    <div class="field"><label>Dist Max (px)</label><input type="number" step="50" value="${m.soundMaxDist || 800}" onchange="config.defenseLib['${type}'].soundMaxDist = parseInt(this.value) || 800"></div>
                </div>
            </div>
            <div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => fieldLabels[fl] || fl).join(' • ')}</div>`;"""
    txt = txt.replace(old_def, new_def, 1)
    print("patched defense")
else:
    print("defense not found")

p.write_text(txt, encoding="utf-8")
print("done")
