import pathlib, re

p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
t = p.read_text(encoding="utf-8")

# 1. Fix mech override (line 39) - replace span + slider with input number + slider synced
old_mech_override = """        <div style="display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:0.4rem;">
            <div class="field"><label>Volumen <span id="mech-override-vol-${enemyId}-${listName}-${idx}" style="color:var(--accent);">${mech.soundVolumePercent !== undefined ? mech.soundVolumePercent : (lib ? lib.soundVolumePercent : 50)}%</span></label><input type="range" min="0" max="100" value="${mech.soundVolumePercent !== undefined ? mech.soundVolumePercent : (lib ? lib.soundVolumePercent : 50)}" oninput="config.enemyModels['${enemyId}'][listName][${idx}].soundVolumePercent = parseFloat(this.value); var l=document.getElementById(''mech-override-vol-${enemyId}-${listName}-${idx}''); if(l) l.innerText=this.value+''%'';"></div>"""

new_mech_override = """        <div style="display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:0.4rem;">
            <div class="field"><label>Volumen <input type="number" id="mech-override-vol-input-${enemyId}-${listName}-${idx}" min="0" max="100" value="${mech.soundVolumePercent !== undefined ? mech.soundVolumePercent : (lib ? lib.soundVolumePercent : 50)}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid #a855f7; color:#a855f7; font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.enemyModels[''${enemyId}''][listName][${idx}].soundVolumePercent=v; let s=document.getElementById(''mech-override-vol-slider-${enemyId}-${listName}-${idx}''); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.enemyModels[''${enemyId}''][listName][${idx}].soundVolumePercent=v; let s=document.getElementById(''mech-override-vol-slider-${enemyId}-${listName}-${idx}''); if(s) s.value=v;"> %</label><input type="range" id="mech-override-vol-slider-${enemyId}-${listName}-${idx}" min="0" max="100" value="${mech.soundVolumePercent !== undefined ? mech.soundVolumePercent : (lib ? lib.soundVolumePercent : 50)}" oninput="config.enemyModels[''${enemyId}''][listName][${idx}].soundVolumePercent=parseFloat(this.value); let i=document.getElementById(''mech-override-vol-input-${enemyId}-${listName}-${idx}''); if(i) i.value=this.value;"></div>"""

if old_mech_override in t:
    t = t.replace(old_mech_override, new_mech_override)
    print("fixed mech override")
else:
    print("mech override not found exact - trying fuzzy")
    # fallback: replace via regex
    t = re.sub(r''<div class="field"><label>Volumen <span id="mech-override-vol-.*?</div>'', new_mech_override, t, flags=re.DOTALL)
    print("fuzzy done")

# Helper to replace generic volumen blocks
# 2. Ammo
t = t.replace(
    """                    <div class="field"><label>Volumen <span id="ammo-vol-label-${type}-${i}" style="color:var(--accent);">${item.soundVolumePercent !== undefined ? item.soundVolumePercent : 50}%</span></label><input type="range" min="0" max="100" value="${item.soundVolumePercent !== undefined ? item.soundVolumePercent : 50}" oninput="config.shopItems.ammo[''${type}''][${i}].soundVolumePercent = parseFloat(this.value); var l=document.getElementById(''ammo-vol-label-${type}-${i}''); if(l) l.innerText=this.value+''%'';"></div>""",
    """                    <div class="field"><label>Volumen <input type="number" id="ammo-vol-input-${type}-${i}" min="0" max="100" value="${item.soundVolumePercent !== undefined ? item.soundVolumePercent : 50}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.shopItems.ammo[''${type}''][${i}].soundVolumePercent=v; let s=document.getElementById(''ammo-vol-slider-${type}-${i}''); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.shopItems.ammo[''${type}''][${i}].soundVolumePercent=v; let s=document.getElementById(''ammo-vol-slider-${type}-${i}''); if(s) s.value=v;"> %</label><input type="range" id="ammo-vol-slider-${type}-${i}" min="0" max="100" value="${item.soundVolumePercent !== undefined ? item.soundVolumePercent : 50}" oninput="config.shopItems.ammo[''${type}''][${i}].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById(''ammo-vol-input-${type}-${i}''); if(inp) inp.value=this.value;"></div>"""
)
print("ammo fixed", "ammo-vol-input" in t)

# 3. MechanicsLib
t = t.replace(
    """                    <div class="field"><label>Volumen <span id="mech-vol-label-${type}" style="color:var(--accent);">${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}%</span></label><input type="range" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" oninput="config.mechanicsLib[''${type}''].soundVolumePercent = parseFloat(this.value); var l=document.getElementById(''mech-vol-label-${type}''); if(l) l.innerText=this.value+''%'';"></div>""",
    """                    <div class="field"><label>Volumen <input type="number" id="mech-vol-input-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.mechanicsLib[''${type}''].soundVolumePercent=v; let s=document.getElementById(''mech-vol-slider-${type}''); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.mechanicsLib[''${type}''].soundVolumePercent=v; let s=document.getElementById(''mech-vol-slider-${type}''); if(s) s.value=v;"> %</label><input type="range" id="mech-vol-slider-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" oninput="config.mechanicsLib[''${type}''].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById(''mech-vol-input-${type}''); if(inp) inp.value=this.value;"></div>"""
)
print("mech lib fixed", "mech-vol-input" in t)

# 4. Defense
t = t.replace(
    """                    <div class="field"><label>Volumen <span id="def-vol-label-${type}" style="color:var(--accent);">${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}%</span></label><input type="range" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" oninput="config.defenseLib[''${type}''].soundVolumePercent = parseFloat(this.value); var l=document.getElementById(''def-vol-label-${type}''); if(l) l.innerText=this.value+''%'';"></div>""",
    """                    <div class="field"><label>Volumen <input type="number" id="def-vol-input-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.defenseLib[''${type}''].soundVolumePercent=v; let s=document.getElementById(''def-vol-slider-${type}''); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.defenseLib[''${type}''].soundVolumePercent=v; let s=document.getElementById(''def-vol-slider-${type}''); if(s) s.value=v;"> %</label><input type="range" id="def-vol-slider-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" oninput="config.defenseLib[''${type}''].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById(''def-vol-input-${type}''); if(inp) inp.value=this.value;"></div>"""
)
print("def fixed", "def-vol-input" in t)

# 5. Movement
t = t.replace(
    """                    <div class="field"><label>Volumen <span id="mov-vol-label-${type}" style="color:var(--accent);">${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}%</span></label><input type="range" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" oninput="config.movementLib[''${type}''].soundVolumePercent = parseFloat(this.value); var l=document.getElementById(''mov-vol-label-${type}''); if(l) l.innerText=this.value+''%'';"></div>""",
    """                    <div class="field"><label>Volumen <input type="number" id="mov-vol-input-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.movementLib[''${type}''].soundVolumePercent=v; let s=document.getElementById(''mov-vol-slider-${type}''); if(s) s.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.movementLib[''${type}''].soundVolumePercent=v; let s=document.getElementById(''mov-vol-slider-${type}''); if(s) s.value=v;"> %</label><input type="range" id="mov-vol-slider-${type}" min="0" max="100" value="${m.soundVolumePercent !== undefined ? m.soundVolumePercent : 50}" oninput="config.movementLib[''${type}''].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById(''mov-vol-input-${type}''); if(inp) inp.value=this.value;"></div>"""
)
print("mov fixed", "mov-vol-input" in t)

# 6. Skills - need special handling for name with spaces - keep id sanitized
old_skill = """                    <div class="field"><label>Volumen <span id="skill-vol-label-${name}" style="color:var(--accent);">${s.soundVolumePercent !== undefined ? s.soundVolumePercent : (s.soundVolume || 50)}%</span></label><input type="range" min="0" max="100" value="${s.soundVolumePercent !== undefined ? s.soundVolumePercent : (s.soundVolume || 50)}" oninput="config.skillsData[''${name}''].soundVolumePercent = parseFloat(this.value); var l=document.getElementById(''skill-vol-label-${name}''); if(l) l.innerText=this.value+''%'';"></div>"""
new_skill = """                    <div class="field"><label>Volumen <input type="number" id="skill-vol-input-${name.replace(/[^a-zA-Z0-9]/g,''_'')}" min="0" max="100" value="${s.soundVolumePercent !== undefined ? s.soundVolumePercent : (s.soundVolume || 50)}" style="width:55px; display:inline-block; background:rgba(0,0,0,0.35); border:1px solid var(--accent); color:var(--accent); font-size:0.65rem; padding:2px 4px; border-radius:4px; text-align:center;" oninput="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.skillsData[''${name}''].soundVolumePercent=v; let s2=document.getElementById(''skill-vol-slider-${name.replace(/[^a-zA-Z0-9]/g,''_'')}''); if(s2) s2.value=v;" onchange="let v=Math.max(0,Math.min(100,parseInt(this.value)||0)); this.value=v; config.skillsData[''${name}''].soundVolumePercent=v; let s2=document.getElementById(''skill-vol-slider-${name.replace(/[^a-zA-Z0-9]/g,''_'')}''); if(s2) s2.value=v;"> %</label><input type="range" id="skill-vol-slider-${name.replace(/[^a-zA-Z0-9]/g,''_'')}" min="0" max="100" value="${s.soundVolumePercent !== undefined ? s.soundVolumePercent : (s.soundVolume || 50)}" oninput="config.skillsData[''${name}''].soundVolumePercent=parseFloat(this.value); let inp=document.getElementById(''skill-vol-input-${name.replace(/[^a-zA-Z0-9]/g,''_'')}''); if(inp) inp.value=this.value;"></div>"""

if old_skill in t:
    t = t.replace(old_skill, new_skill)
    print("skill fixed exact")
else:
    print("skill not found exact - search")
    print("skill present?", "skill-vol-label" in t)

p.write_text(t, encoding="utf-8")
print("done total")
