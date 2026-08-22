import pathlib
p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
txt = p.read_text(encoding="utf-8")
old = """            const ml = { speed:"Velocidad", stopDist:"Frenado", idealDist:"Rango", orbitRadius:"Órbita", chargeCooldown: "Dash", activationHP: "Activación HP (%)", explosionDamage: "Daño Explosión", duration: "Duración", explodeOnDeath: "Auto-Detonar" };
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Nombre Público</label><input type="text" value="${m.label}" onchange="config.movementLib['${type}'].label = this.value; renderAll();"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => ml[fl] || fl).join(' • ')}</div>`;"""
new = """            const ml = { speed:"Velocidad", stopDist:"Frenado", idealDist:"Rango", orbitRadius:"Órbita", chargeCooldown: "Dash", activationHP: "Activación HP (%)", explosionDamage: "Daño Explosión", duration: "Duración", explodeOnDeath: "Auto-Detonar" };
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
                    <div class="field"><label>Volumen (dB)</label><input type="number" step="1" value="${m.soundVolumeDb !== undefined ? m.soundVolumeDb : 0}" onchange="config.movementLib['${type}'].soundVolumeDb = parseFloat(this.value) || 0"></div>
                    <div class="field"><label>Dist Max (px)</label><input type="number" step="50" value="${m.soundMaxDist || 800}" onchange="config.movementLib['${type}'].soundMaxDist = parseInt(this.value) || 800"></div>
                </div>
            </div>
            <div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => ml[fl] || fl).join(' • ')}</div>`;"""
# find the exact substring - need to match encoding
if old in txt:
    txt = txt.replace(old, new)
    p.write_text(txt, encoding="utf-8")
    print("patched movement")
else:
    print("not found movement")
    # try to show relevant snippet
    idx = txt.find('MOVEMENT_LIB')
    import re
    print(txt[idx: idx+500])
